# ==============================================================================
# ATTACH AN EXISTING PROJECT (brownfield) TO THE LOCAL SDLC TOOLING
# Works on a folder the user downloaded into <projectsDir>/<Project>.
# Never clones, never deletes, never calls generate-project.ps1, never overwrites existing files.
#
# Usage:
#   .\scripts\attach-project.ps1 -Project my-legacy-app
#   .\scripts\attach-project.ps1 -Project my-legacy-app -NoBranch -SkipRecon
# ==============================================================================
Param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$ProjectsDir,
    [string]$Scenario,
    [string]$ScenarioConfig = "config/scenario-config.yaml",
    [string]$ProjectConfig = "config/project-config.yaml",
    [string]$Branch = "sdlc-work",
    [string]$MavenSettings = $env:MAVEN_SETTINGS,
    [switch]$NoBranch,
    [switch]$NoJacoco,
    [switch]$SkipRecon
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$templates = Join-Path $repoRoot "templates\brownfield"

function Read-FlatYaml([string]$file) {
    $values = @{}
    if (-not (Test-Path $file)) { return $values }
    foreach ($line in Get-Content $file) {
        if ($line -match '^\s*([A-Za-z][\w]*)\s*:\s*(.*)$') {
            $key = $matches[1]
            $raw = $matches[2].Trim()
            if ($raw -match '^"([^"]*)"') { $val = $matches[1] }
            elseif ($raw -match "^'([^']*)'") { $val = $matches[1] }
            else { $val = ($raw -split '#')[0].Trim() }
            # First occurrence wins, same as generate-project.ps1
            if (-not $values.ContainsKey($key)) { $values[$key] = $val }
        }
    }
    return $values
}

$scenarioCfg = Read-FlatYaml (Join-Path $repoRoot $ScenarioConfig)
$projectCfg = Read-FlatYaml (Join-Path $repoRoot $ProjectConfig)

$projectsDir = if ($ProjectsDir) { $ProjectsDir } elseif ($scenarioCfg["projectsDir"]) { $scenarioCfg["projectsDir"] } else { "projects" }
$projectPath = Join-Path (Join-Path $repoRoot $projectsDir) $Project

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "        Attach existing project to SDLC           " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Project: $projectPath" -ForegroundColor Gray

if (-not (Test-Path $projectPath)) {
    Write-Error "Project folder not found: $projectPath. Download the code into $projectsDir\$Project first."
}
if (-not (Test-Path (Join-Path $projectPath "pom.xml"))) {
    Write-Error "No pom.xml in $projectPath. Only Maven projects are supported (recon reports Gradle projects)."
}

if (-not $MavenSettings) { $MavenSettings = $projectCfg["settingsFile"] }
if ($MavenSettings -and -not (Test-Path $MavenSettings)) {
    Write-Host "    Warning: Maven settings file not found: $MavenSettings (using Maven default)" -ForegroundColor DarkYellow
    $MavenSettings = ""
}

$added = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]
$pomModified = $false

# Copies one file only when the target does not exist yet
function Add-ProjectFile([string]$source, [string]$relativeTarget) {
    $target = Join-Path $projectPath $relativeTarget
    if (Test-Path $target) {
        $skipped.Add($relativeTarget)
        return
    }
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item $source -Destination $target
    $added.Add($relativeTarget.Replace('\', '/'))
}

# --- 1. Git working branch ----------------------------------------------------
Write-Host "`n[1/6] Git" -ForegroundColor Yellow
Push-Location $projectPath
try {
    $isGit = $false
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) { $isGit = $true }

    if (-not $isGit) {
        Write-Host "    Not a git repository - no branch, no exclude list (tokens copied below stay untracked only by convention)" -ForegroundColor DarkYellow
    } elseif ($NoBranch) {
        Write-Host "    -NoBranch: staying on $(git rev-parse --abbrev-ref HEAD)" -ForegroundColor Gray
    } else {
        $current = git rev-parse --abbrev-ref HEAD
        if ($current -eq $Branch) {
            Write-Host "    Already on $Branch" -ForegroundColor Green
        } elseif (git status --porcelain) {
            Write-Host "    Uncommitted changes present - not switching branches (still on $current)" -ForegroundColor DarkYellow
        } else {
            git show-ref --verify --quiet "refs/heads/$Branch"
            if ($LASTEXITCODE -eq 0) { git checkout -q $Branch } else { git checkout -q -b $Branch }
            if ($LASTEXITCODE -ne 0) { Write-Error "git checkout $Branch failed" }
            Write-Host "    Working branch: $Branch (from $current)" -ForegroundColor Green
        }
    }
} finally {
    Pop-Location
}

# --- 2. Tools, agents, instructions -------------------------------------------
Write-Host "`n[2/6] SDLC tools and agents (missing files only)" -ForegroundColor Yellow
Add-ProjectFile (Join-Path $templates "sdlc.ps1") "tools\sdlc.ps1"
Add-ProjectFile (Join-Path $templates "recon.ps1") "tools\recon.ps1"
Add-ProjectFile (Join-Path $repoRoot "templates\shared\copilot-quota.ps1") "tools\copilot-quota.ps1"
foreach ($agent in Get-ChildItem (Join-Path $templates "agents") -File) {
    Add-ProjectFile $agent.FullName ".github\agents\$($agent.Name)"
}
Add-ProjectFile (Join-Path $templates "copilot-instructions.md") ".github\copilot-instructions.md"
# Jira/Confluence read-only, so the orchestrator can fetch the task text
Add-ProjectFile (Join-Path $templates "mcp.json") ".vscode\mcp.json"

if ($projectCfg["enableXray"] -eq "true" -and $projectCfg["xrayUrl"]) {
    Add-ProjectFile (Join-Path $templates "jfrog-scan.ps1") "tools\jfrog-scan.ps1"
    $xrayProps = Join-Path $projectPath "jfrog-xray.properties"
    if (-not (Test-Path $xrayProps)) {
        $content = "url=$($projectCfg['xrayUrl'])`nwatches=$($projectCfg['xrayWatches'])`ninsecureTls=$($projectCfg['xrayInsecureTls'])`n"
        Set-Content -Path $xrayProps -Value $content -Encoding UTF8 -NoNewline
        $added.Add("jfrog-xray.properties")
    } else {
        $skipped.Add("jfrog-xray.properties")
    }
}
foreach ($secret in @("jfrog.token", "sonar-token.txt")) {
    $src = Join-Path $repoRoot $secret
    if (Test-Path $src) { Add-ProjectFile $src $secret }
}

# --- 3. Maven (brownfield sdlc.ps1 falls back to mvn when there is no wrapper) ---
Write-Host "`n[3/6] Maven" -ForegroundColor Yellow
if (Test-Path (Join-Path $projectPath "mvnw.cmd")) {
    Write-Host "    Maven Wrapper present" -ForegroundColor Green
} elseif (Get-Command mvn -ErrorAction SilentlyContinue) {
    Write-Host "    No Maven Wrapper - tools use mvn from PATH" -ForegroundColor Green
} else {
    Write-Host "    No Maven Wrapper and no mvn on PATH - tools/sdlc.ps1 will not run. Install Maven." -ForegroundColor Red
}

# --- 4. JaCoCo (measurement only) ----------------------------------------------
Write-Host "`n[4/6] JaCoCo" -ForegroundColor Yellow
$pomFile = Join-Path $projectPath "pom.xml"
$pomBytes = [IO.File]::ReadAllBytes($pomFile)
$hasBom = $pomBytes.Length -ge 3 -and $pomBytes[0] -eq 0xEF -and $pomBytes[1] -eq 0xBB -and $pomBytes[2] -eq 0xBF
$pom = [IO.File]::ReadAllText($pomFile)

if ($pom -match "jacoco-maven-plugin") {
    Write-Host "    Already configured - pom.xml unchanged" -ForegroundColor Green
} elseif ($NoJacoco) {
    Write-Host "    -NoJacoco: skipped, coverage will not be measured" -ForegroundColor DarkYellow
} else {
    $jacocoVersion = if ($projectCfg["jacocoVersion"]) { $projectCfg["jacocoVersion"] } else { "0.8.15" }
    $nl = if ($pom.Contains("`r`n")) { "`r`n" } else { "`n" }
    # No <check> rule: legacy code with low coverage must still build so a baseline can be recorded
    $plugin = @(
        "<plugin>",
        "`t<groupId>org.jacoco</groupId>",
        "`t<artifactId>jacoco-maven-plugin</artifactId>",
        "`t<version>$jacocoVersion</version>",
        "`t<executions>",
        "`t`t<execution>",
        "`t`t`t<goals><goal>prepare-agent</goal></goals>",
        "`t`t</execution>",
        "`t`t<execution>",
        "`t`t`t<id>report</id>",
        "`t`t`t<phase>verify</phase>",
        "`t`t`t<goals><goal>report</goal></goals>",
        "`t`t</execution>",
        "`t</executions>",
        "</plugin>"
    )
    function Format-Block([string[]]$lines, [string]$indent) {
        return ($lines | ForEach-Object { "$indent$_" }) -join $nl
    }

    # <plugins> also appears in pluginManagement, profiles and reporting - those are not the main build
    $excluded = @()
    foreach ($tag in @("pluginManagement", "profiles", "reporting")) {
        foreach ($m in [regex]::Matches($pom, "(?s)<$tag>.*?</$tag>")) { $excluded += , @($m.Index, ($m.Index + $m.Length)) }
    }
    function Test-Outside([int]$pos) {
        foreach ($r in $excluded) { if ($pos -ge $r[0] -and $pos -lt $r[1]) { return $false } }
        return $true
    }

    $pluginsClose = [regex]::Matches($pom, "</plugins>") | Where-Object { Test-Outside $_.Index } | Select-Object -First 1
    $buildClose = [regex]::Matches($pom, "</build>") | Where-Object { Test-Outside $_.Index } | Select-Object -First 1

    if ($pluginsClose) {
        $insert = (Format-Block (@("<!-- added by attach-project.ps1: coverage measurement only -->") + $plugin) "`t`t`t") + $nl + "`t`t"
        $pom = $pom.Insert($pluginsClose.Index, $insert)
    } elseif ($buildClose) {
        $block = @("<plugins>") + ($plugin | ForEach-Object { "`t$_" }) + @("</plugins>")
        $pom = $pom.Insert($buildClose.Index, (Format-Block $block "`t`t") + $nl + "`t")
    } else {
        $block = @("<build>", "`t<plugins>") + ($plugin | ForEach-Object { "`t`t$_" }) + @("`t</plugins>", "</build>")
        $projectClose = $pom.LastIndexOf("</project>")
        $pom = $pom.Insert($projectClose, (Format-Block $block "`t") + $nl)
    }

    try {
        $null = [xml]$pom
    } catch {
        Write-Error "JaCoCo insertion produced invalid XML - pom.xml left unchanged. $_"
    }
    [IO.File]::WriteAllText($pomFile, $pom, (New-Object System.Text.UTF8Encoding($hasBom)))
    $pomModified = $true
    Write-Host "    Added jacoco-maven-plugin $jacocoVersion (prepare-agent + report, no coverage rule)" -ForegroundColor Green
    Write-Host "    NOTE: pom.xml is a tracked file - this change shows up in the project diff" -ForegroundColor DarkYellow
}

# --- 5. sonar-project.properties ----------------------------------------------
Write-Host "`n[5/6] SonarQube configuration" -ForegroundColor Yellow
$sonarFile = Join-Path $projectPath "sonar-project.properties"
if (Test-Path $sonarFile) {
    $skipped.Add("sonar-project.properties")
    Write-Host "    Present - left unchanged" -ForegroundColor Green
} else {
    [xml]$pomXml = [IO.File]::ReadAllText($pomFile)
    function Get-PomValue([string]$path) {
        $xpath = "/" + (($path -split '/' | ForEach-Object { "*[local-name()='$_']" }) -join '/')
        $node = $pomXml.SelectSingleNode($xpath)
        if ($node) { return $node.InnerText.Trim() }
        return $null
    }
    $groupId = Get-PomValue "project/groupId"
    if (-not $groupId) { $groupId = Get-PomValue "project/parent/groupId" }
    $artifactId = Get-PomValue "project/artifactId"
    $name = Get-PomValue "project/name"
    if (-not $name) { $name = $artifactId }
    $sonarHostUrl = if ($projectCfg["sonarHostUrl"]) { $projectCfg["sonarHostUrl"] } else { "http://localhost:9000" }

    $props = (Get-Content (Join-Path $templates "sonar-project.properties") -Raw).
        Replace("{{groupId}}", $groupId).
        Replace("{{artifactId}}", $artifactId).
        Replace("{{name}}", $name).
        Replace("{{sonarHostUrl}}", $sonarHostUrl)
    Set-Content -Path $sonarFile -Value $props -Encoding UTF8
    $added.Add("sonar-project.properties")
    Write-Host "    Generated (projectKey=${groupId}:${artifactId}, host=$sonarHostUrl)" -ForegroundColor Green
    if ($pomXml.SelectSingleNode("/*[local-name()='project']/*[local-name()='modules']")) {
        Write-Host "    WARNING: multi-module project - sonar.sources=src/main/java will not match; adjust sonar-project.properties" -ForegroundColor DarkYellow
    }
}

# --- 6. Keep our files out of the project's git history -----------------------
Write-Host "`n[6/6] Settings and git exclude list" -ForegroundColor Yellow
if (-not $Scenario) { $Scenario = $scenarioCfg["scenarioType"] }
function Get-CfgNumber([string]$key, $default) {
    if ($scenarioCfg[$key] -match '^-?\d+$') { return [int]$scenarioCfg[$key] }
    if ($scenarioCfg[$key] -match '^-?\d+\.\d+$') { return [double]$scenarioCfg[$key] }
    return $default
}
# Read by tools/sdlc.ps1 and the orchestrator; the project cannot see config/ of this repository
$sdlcSettings = [ordered]@{
    scenario              = $Scenario
    mavenSettings         = $(if ($MavenSettings) { (Resolve-Path $MavenSettings).Path } else { "" })
    diffGuardMaxFiles     = Get-CfgNumber "diffGuardMaxFiles" 15
    diffGuardMaxLines     = Get-CfgNumber "diffGuardMaxLines" 400
    diffGuardMode         = $(if ($scenarioCfg["diffGuardMode"]) { $scenarioCfg["diffGuardMode"] } else { "warn" })
    coverageTolerance     = Get-CfgNumber "coverageTolerance" 0.0
    sonarMaxOpenIssues    = $(if ($Scenario -eq "sonarfix") { 0 } else { -1 })
    maxFixIterations      = Get-CfgNumber "maxFixIterations" 5
    maxOfficialCiAttempts = Get-CfgNumber "maxOfficialCiAttempts" 2
    sameGateStopAfter     = Get-CfgNumber "sameGateStopAfter" 3
}
$sdlcSettings | ConvertTo-Json | Set-Content -Path (Join-Path $projectPath "sdlc-settings.json") -Encoding UTF8
Write-Host "    sdlc-settings.json written (scenario: $(if ($Scenario) { $Scenario } else { 'not set' }))" -ForegroundColor Green
$manifest = [ordered]@{
    attachedAt  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    project     = $Project
    added       = @($added)
    skipped     = @($skipped)
    pomModified = $pomModified
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $projectPath "sdlc-attach.json") -Encoding UTF8

if ($isGit) {
    Push-Location $projectPath
    try {
        $excludeFile = git rev-parse --git-path info/exclude
        New-Item -ItemType Directory -Path (Split-Path $excludeFile -Parent) -Force | Out-Null
        $existing = @(if (Test-Path $excludeFile) { Get-Content $excludeFile })
        $wanted = @($added) + @("sdlc-attach.json", "sdlc-settings.json", "sdlc-report.json", "sdlc-baseline.json", "sdlc-repro.json", "sdlc-cost.json",
            "recon-report.json", "sdlc-run.log", "task.md", "analysis.md", "plan.md", "security-review.md", "*.token", "sonar-token.txt")
        $missing = @($wanted | Select-Object -Unique | ForEach-Object { "/" + $_.TrimStart('/') } |
            Where-Object { $existing -notcontains $_ })
        if ($missing.Count -gt 0) {
            Add-Content -Path $excludeFile -Value ((@("", "# added by sdlc attach-project.ps1") + $missing) -join "`n")
        }
        Write-Host "    $($missing.Count) entries added to $excludeFile" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

Write-Host "`n    Added:   $(if ($added.Count) { $added -join ', ' } else { '-' })" -ForegroundColor Gray
Write-Host "    Skipped (already existed): $(if ($skipped.Count) { $skipped -join ', ' } else { '-' })" -ForegroundColor Gray
Write-Host "    pom.xml modified: $pomModified" -ForegroundColor Gray

# --- Recon --------------------------------------------------------------------
if (-not $SkipRecon) {
    Push-Location $projectPath
    try {
        & .\tools\recon.ps1 -MavenSettings $MavenSettings
    } finally {
        Pop-Location
    }
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. .\scripts\env-up.ps1 -ProjectPath $projectsDir\$Project   (MongoDB + SonarQube + token)"
Write-Host "  2. Open the folder $projectsDir\$Project in a NEW VS Code window (agents and .vscode/mcp.json load from the project root)"
Write-Host "  3. Ctrl+Shift+P > 'MCP: List Servers' > erste-intranet-mcp > Start Server (trust it once; needed for Jira/Confluence tasks)"
Write-Host "  4. In chat pick @sdlc-orchestrator and paste the task or the Jira link"
