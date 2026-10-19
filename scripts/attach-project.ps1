# ==============================================================================
# ATTACH AN EXISTING PROJECT (brownfield) TO THE LOCAL SDLC TOOLING
# Works on a folder the user downloaded into <projectsDir>/<Project>.
# Never clones, never deletes, never calls generate-project.ps1, never overwrites existing files
# (except -NewTask: refreshes tools/agents from templates and moves the previous task's files to sdlc-history/).
#
# Usage:
#   .\scripts\attach-project.ps1 -Project my-legacy-app
#   .\scripts\attach-project.ps1 -Project my-legacy-app -NoBranch -SkipRecon
#   .\scripts\attach-project.ps1 -Project my-legacy-app -Scenario migration -NewTask   (next task on an attached project)
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
    [switch]$SkipRecon,
    [switch]$NewTask
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
if (-not $Scenario) { $Scenario = $scenarioCfg["scenarioType"] }

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

# Copies one file only when the target does not exist yet (-Overwrite: always, for tool and agent updates)
function Add-ProjectFile([string]$source, [string]$relativeTarget, [switch]$Overwrite) {
    $target = Join-Path $projectPath $relativeTarget
    if ((Test-Path $target) -and -not $Overwrite) {
        $skipped.Add($relativeTarget)
        return
    }
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item $source -Destination $target -Force
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
if ($NewTask) {
    # The orchestrator must start from a clean slate: its own baseline, analysis and plan
    $history = Join-Path $projectPath ("sdlc-history\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    $taskFiles = @("task.md", "analysis.md", "plan.md", "security-review.md", "recon-report.json", "sdlc-baseline.json",
        "sdlc-report.json", "sdlc-repro.json", "sdlc-cost.json", "sdlc-run.log")
    $moved = @($taskFiles | Where-Object { Test-Path (Join-Path $projectPath $_) })
    if ($moved.Count -gt 0) {
        New-Item -ItemType Directory -Path $history -Force | Out-Null
        foreach ($f in $moved) { Move-Item (Join-Path $projectPath $f) $history }
        Write-Host "`n    -NewTask: previous task files moved to $history ($($moved -join ', '))" -ForegroundColor Green
    }
}
Write-Host "`n[2/6] SDLC tools and agents ($(if ($NewTask) { 'refreshed from templates' } else { 'missing files only' }))" -ForegroundColor Yellow
Add-ProjectFile (Join-Path $templates "sdlc.ps1") "tools\sdlc.ps1" -Overwrite:$NewTask
Add-ProjectFile (Join-Path $templates "recon.ps1") "tools\recon.ps1" -Overwrite:$NewTask
Add-ProjectFile (Join-Path $templates "use-java.ps1") "tools\use-java.ps1" -Overwrite:$NewTask
Add-ProjectFile (Join-Path $repoRoot "templates\shared\copilot-quota.ps1") "tools\copilot-quota.ps1" -Overwrite:$NewTask
foreach ($agent in Get-ChildItem (Join-Path $templates "agents") -File) {
    Add-ProjectFile $agent.FullName ".github\agents\$($agent.Name)" -Overwrite:$NewTask
}
Add-ProjectFile (Join-Path $templates "copilot-instructions.md") ".github\copilot-instructions.md" -Overwrite:$NewTask
# Jira/Confluence read-only, so the orchestrator can fetch the task text
Add-ProjectFile (Join-Path $templates "mcp.json") ".vscode\mcp.json"

if ($projectCfg["enableXray"] -eq "true" -and $projectCfg["xrayUrl"]) {
    Add-ProjectFile (Join-Path $templates "jfrog-scan.ps1") "tools\jfrog-scan.ps1" -Overwrite:$NewTask
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
Write-Host "`n[3/6] Maven and Java" -ForegroundColor Yellow
# Same Maven as the CI builder image; a different one hides CI-only failures
$mavenHome = ""
$mavenVersion = $projectCfg["mavenVersion"]
$mavensDir = $projectCfg["mavensDir"]
if ($mavenVersion -and $mavensDir) {
    $candidate = Join-Path $mavensDir "apache-maven-$mavenVersion"
    if (-not (Test-Path (Join-Path $candidate "bin\mvn.cmd")) -and (Test-Path $mavensDir) -and (Get-Command mvn -ErrorAction SilentlyContinue)) {
        Write-Host "    Maven $mavenVersion not in $mavensDir - downloading org.apache.maven:apache-maven:${mavenVersion}:zip:bin" -ForegroundColor Gray
        $download = Join-Path ([IO.Path]::GetTempPath()) "sdlc-maven-$mavenVersion"
        $dlSettings = @(if ($MavenSettings) { "-s", (Resolve-Path $MavenSettings).Path })
        # mvn writes JVM notices to stderr; they must not stop this script
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & mvn -B -q @dlSettings "org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy" `
            "-Dartifact=org.apache.maven:apache-maven:${mavenVersion}:zip:bin" "-DoutputDirectory=$download" 2>&1 | Out-Host
        $ErrorActionPreference = $previousEap
        $zip = Join-Path $download "apache-maven-$mavenVersion-bin.zip"
        if (Test-Path $zip) {
            Expand-Archive -Path $zip -DestinationPath $mavensDir -Force
        }
        Remove-Item $download -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path (Join-Path $candidate "bin\mvn.cmd")) {
        $mavenHome = (Resolve-Path $candidate).Path
        Write-Host "    Maven $mavenVersion`: $mavenHome" -ForegroundColor Green
    } else {
        Write-Host "    Maven $mavenVersion not available in $mavensDir (download failed or mavensDir missing) - tools use mvn from PATH" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "    mavenVersion/mavensDir not set - tools use mvn from PATH" -ForegroundColor DarkYellow
}
if (Test-Path (Join-Path $projectPath "mvnw.cmd")) {
    Write-Host "    Maven Wrapper present - it decides the Maven version" -ForegroundColor Green
} elseif ($mavenHome) {
    Write-Host "    No Maven Wrapper - tools use $mavenHome" -ForegroundColor Green
} elseif (Get-Command mvn -ErrorAction SilentlyContinue) {
    Write-Host "    No Maven Wrapper - tools use mvn from PATH" -ForegroundColor Green
} else {
    Write-Host "    No Maven Wrapper and no mvn on PATH - tools/sdlc.ps1 will not run. Install Maven." -ForegroundColor Red
}

# A newer JDK than the project's breaks builds (e.g. JDK 23+ no longer runs Lombok implicitly)
function Get-JavaMajor([string]$version) {
    if ($version -match '^1\.(\d+)') { return [int]$matches[1] }
    if ($version -match '^(\d+)') { return [int]$matches[1] }
    return $null
}
$javaHome = ""
[xml]$pomForJava = [IO.File]::ReadAllText((Join-Path $projectPath "pom.xml"))
$javaDeclared = $null
foreach ($prop in @("java.version", "maven.compiler.release", "maven.compiler.source")) {
    $node = $pomForJava.SelectSingleNode("/*[local-name()='project']/*[local-name()='properties']/*[local-name()='$prop']")
    if ($node -and $node.InnerText.Trim()) { $javaDeclared = $node.InnerText.Trim(); break }
}
$javaMajor = Get-JavaMajor $javaDeclared
# A migration builds on the target JDK; a newer JDK also compiles the old release level
if ($Scenario -eq "migration" -and $scenarioCfg["migrationJavaVersion"]) {
    $javaMajor = Get-JavaMajor $scenarioCfg["migrationJavaVersion"]
}
$jdksDir = $projectCfg["jdksDir"]
if (-not $javaMajor) {
    Write-Host "    Java version not declared in pom.xml - tools use java from PATH" -ForegroundColor DarkYellow
} elseif (-not $jdksDir -or -not (Test-Path $jdksDir)) {
    Write-Host "    Project needs Java $javaMajor; jdksDir not set or missing - tools use java from PATH" -ForegroundColor DarkYellow
} else {
    $candidates = @(Get-Item $jdksDir) + @(Get-ChildItem $jdksDir -Directory | Sort-Object Name -Descending)
    foreach ($dir in $candidates) {
        $release = Join-Path $dir.FullName "release"
        if ((Test-Path $release) -and (Test-Path (Join-Path $dir.FullName "bin\java.exe")) -and
            (Get-Content $release -Raw) -match 'JAVA_VERSION="([^"]+)"' -and (Get-JavaMajor $matches[1]) -eq $javaMajor) {
            $javaHome = $dir.FullName
            break
        }
    }
    if ($javaHome) {
        Write-Host "    Java $javaMajor ($(if ($Scenario -eq 'migration' -and $scenarioCfg['migrationJavaVersion']) { 'migration target' } else { 'from pom.xml' })): $javaHome" -ForegroundColor Green
    } else {
        Write-Host "    No JDK $javaMajor in $jdksDir - tools use java from PATH" -ForegroundColor DarkYellow
    }
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
    javaHome              = $javaHome
    mavenHome             = $mavenHome
    diffGuardMaxFiles     = Get-CfgNumber "diffGuardMaxFiles" 15
    diffGuardMaxLines     = Get-CfgNumber "diffGuardMaxLines" 400
    diffGuardMode         = $(if ($scenarioCfg["diffGuardMode"]) { $scenarioCfg["diffGuardMode"] } else { "warn" })
    coverageTolerance     = Get-CfgNumber "coverageTolerance" 0.0
    sonarMaxOpenIssues    = $(if ($Scenario -eq "sonarfix") { 0 } else { -1 })
    maxFixIterations      = Get-CfgNumber "maxFixIterations" 5
    maxOfficialCiAttempts = Get-CfgNumber "maxOfficialCiAttempts" 2
    sameGateStopAfter     = Get-CfgNumber "sameGateStopAfter" 3
}
if ($Scenario -eq "migration") {
    $sdlcSettings.migrationBootVersion = $scenarioCfg["migrationBootVersion"]
    $sdlcSettings.migrationJavaVersion = $scenarioCfg["migrationJavaVersion"]
}
$sdlcSettings | ConvertTo-Json | Set-Content -Path (Join-Path $projectPath "sdlc-settings.json") -Encoding UTF8
Write-Host "    sdlc-settings.json written (scenario: $(if ($Scenario) { $Scenario } else { 'not set' }))" -ForegroundColor Green
$manifestFile = Join-Path $projectPath "sdlc-attach.json"
$manifestAdded = New-Object System.Collections.Generic.List[string]
foreach ($a in $added) { $manifestAdded.Add($a) }
$previous = $null
# Re-attaching must not forget what an earlier attach added
if (Test-Path $manifestFile) {
    $previous = Get-Content $manifestFile -Raw | ConvertFrom-Json
    foreach ($a in @($previous.added)) { if ($a -and -not $manifestAdded.Contains($a)) { $manifestAdded.Add($a) } }
}
$manifest = [ordered]@{
    attachedAt  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    project     = $Project
    added       = @($manifestAdded)
    skipped     = @($skipped)
    pomModified = ($pomModified -or [bool]$previous.pomModified)
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -Path $manifestFile -Encoding UTF8

if ($isGit) {
    Push-Location $projectPath
    try {
        $excludeFile = git rev-parse --git-path info/exclude
        New-Item -ItemType Directory -Path (Split-Path $excludeFile -Parent) -Force | Out-Null
        $existing = @(if (Test-Path $excludeFile) { Get-Content $excludeFile })
        $wanted = @($added) + @("sdlc-attach.json", "sdlc-settings.json", "sdlc-report.json", "sdlc-baseline.json", "sdlc-repro.json", "sdlc-cost.json",
            "recon-report.json", "sdlc-run.log", "task.md", "analysis.md", "plan.md", "security-review.md", "*.token", "sonar-token.txt", "sdlc-history/")
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
