# ==============================================================================
# SPRING BOOT TEMPLATE GENERATOR USING SPRING INITIALIZR API
# ==============================================================================
Param(
    [string]$ConfigFile = "config/project-config.yaml",
    # Empty = projectsDir from config/scenario-config.yaml (default "projects")
    [string]$OutputDir = "",
    [string]$MavenSettings = $env:MAVEN_SETTINGS,
    # Allows replacing an existing folder that this generator did not create
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot "scripts\config-loader.ps1")
$templateDir = "templates/greenfield"
$generatedMarker = ".sdlc-generated"

if (-not $OutputDir) {
    $OutputDir = "projects"
    $scenarioConfig = "config/scenario-config.yaml"
    if (Test-Path $scenarioConfig) {
        $line = Get-Content $scenarioConfig | Where-Object { $_ -match '^\s*projectsDir\s*:' } | Select-Object -First 1
        if ($line -match ':\s*"?([^"#]+?)"?\s*(#.*)?$') { $OutputDir = $matches[1].Trim() }
    }
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Spring Boot SDLC Project Template Generator    " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Verify Config File
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found at: $ConfigFile"
}

Write-Host "[1/7] Reading configuration from $ConfigFile..." -ForegroundColor Yellow
$config = Read-FactoryConfig $ConfigFile
$configValues = $config.Values
$configLines = Get-Content $ConfigFile
Write-Host "    Local override: $(if ($config.LocalLoaded) { $config.LocalFile } else { 'none' })" -ForegroundColor Gray

# Project settings
$type        = Get-ConfigValue $configValues "type" "maven-project"
$language    = Get-ConfigValue $configValues "language" "java"
$bootVersion = Get-ConfigValue $configValues "bootVersion" ""
$groupId     = Get-ConfigValue $configValues "groupId" "com.example.sdlc"
$artifactId  = Get-ConfigValue $configValues "artifactId" "springboot-sdlc-demo"
$name        = Get-ConfigValue $configValues "name" "springboot-sdlc-demo"
$description = Get-ConfigValue $configValues "description" "Spring Boot Service with SDLC"
$packageName = Get-ConfigValue $configValues "packageName" "com.example.sdlc.demo"
$packaging   = Get-ConfigValue $configValues "packaging" "jar"
$javaVersion = Get-ConfigValue $configValues "javaVersion" "21"

# SDLC settings
$enableSonarQube = Get-ConfigValue $configValues "enableSonarQube" "true"
$enableOwaspCheck = Get-ConfigValue $configValues "enableOwaspCheck" "true"
$sonarHostUrl    = Get-ConfigValue $configValues "sonarHostUrl" "http://localhost:9000"
$owaspFailOnCvss = Get-ConfigValue $configValues "owaspFailOnCvss" "7.0"
$owaspFailOnError = Get-ConfigValue $configValues "owaspFailOnError" "true"
$enableXray      = Get-ConfigValue $configValues "enableXray" "false"
$xrayUrl         = Get-ConfigValue $configValues "xrayUrl" ""
$xrayWatches     = Get-ConfigValue $configValues "xrayWatches" ""
$xrayInsecureTls = Get-ConfigValue $configValues "xrayInsecureTls" "false"
# JaCoCo must understand the class file version produced by javaVersion (0.8.15 covers Java 25)
$jacocoVersion   = Get-ConfigValue $configValues "jacocoVersion" "0.8.15"

# Maven settings.xml (CLI parameter wins over config; empty = Maven default ~/.m2/settings.xml)
if (-not $MavenSettings) { $MavenSettings = Get-ConfigValue $configValues "settingsFile" "" }
$mvnSettingsArgs = @()
if ($MavenSettings) {
    if (Test-Path $MavenSettings) {
        $MavenSettings = (Resolve-Path $MavenSettings).Path
        $mvnSettingsArgs = @("-s", $MavenSettings)
    } else {
        Write-Host "    Warning: Maven settings file not found: $MavenSettings (falling back to Maven default)" -ForegroundColor DarkYellow
        $MavenSettings = ""
    }
}

# Extract dependencies array
$deps = @()
$inDeps = $false
foreach ($line in $configLines) {
    $lineTrim = $line.Trim()
    if ($lineTrim -match "^dependencies\s*:") {
        $inDeps = $true
        continue
    }
    if ($inDeps) {
        if ($lineTrim -match "^-\s*(.*)") {
            $depVal = $matches[1].Trim()
            if ($depVal -match "^([^#]+)") {
                $depVal = $matches[1].Trim()
            }
            if ($depVal) { $deps += $depVal }
        } elseif ($lineTrim -match "^\w+:") {
            $inDeps = $false
        }
    }
}

if ($deps.Count -eq 0) {
    $deps = @("web", "data-mongodb", "actuator", "validation", "lombok")
}
$depsJoined = $deps -join ","

Write-Host "    ArtifactId:       $artifactId" -ForegroundColor Gray
Write-Host "    GroupId:          $groupId" -ForegroundColor Gray
Write-Host "    Java Version:     $javaVersion" -ForegroundColor Gray
Write-Host "    Dependencies:     $depsJoined" -ForegroundColor Gray
Write-Host "    SonarQube:        $enableSonarQube ($sonarHostUrl)" -ForegroundColor Gray
Write-Host "    OWASP Check:      $enableOwaspCheck (CVSS >= $owaspFailOnCvss, failOnError: $owaspFailOnError)" -ForegroundColor Gray
Write-Host "    JFrog Xray:       $enableXray$(if ($enableXray -eq 'true') { " ($xrayUrl, watches: $xrayWatches)" })" -ForegroundColor Gray
Write-Host "    Maven settings:   $(if ($MavenSettings) { $MavenSettings } else { 'Maven default (~/.m2/settings.xml)' })" -ForegroundColor Gray

# 2. Call Spring Initializr REST API
$bootVersionParam = if ($bootVersion -and $bootVersion -ne "latest") { "&bootVersion=$bootVersion" } else { "" }
$apiUrl = "https://start.spring.io/starter.zip?type=$type&language=$language$bootVersionParam&baseDir=$artifactId&groupId=$groupId&artifactId=$artifactId&name=$name&description=$([uri]::EscapeDataString($description))&packageName=$packageName&packaging=$packaging&javaVersion=$javaVersion&dependencies=$depsJoined"

$tempZip = Join-Path $env:TEMP "$artifactId-starter.zip"
Write-Host "`n[2/7] Querying Spring Initializr REST API..." -ForegroundColor Yellow

Write-Host "    API URL: $apiUrl" -ForegroundColor Gray
Invoke-WebRequest -Uri $apiUrl -OutFile $tempZip -UserAgent "curl/7.68.0"

if (-not (Test-Path $tempZip)) {
    Write-Error "Failed to download starter archive from Spring Initializr."
}

# 3. Unpack Starter Archive
$targetPath = Join-Path $OutputDir $artifactId
Write-Host "`n[3/7] Unpacking template to: $targetPath..." -ForegroundColor Yellow

if (Test-Path $targetPath) {
    # Projects share one folder with downloaded code; only our own output may be replaced silently
    if (-not (Test-Path (Join-Path $targetPath $generatedMarker)) -and -not $Force) {
        Remove-Item $tempZip -Force
        Write-Error "$targetPath exists and was not created by this generator (no $generatedMarker). Nothing was deleted. Change artifactId, remove the folder yourself, or re-run with -Force."
    }
    # Agents' work lives on sdlc-work; regenerating must not silently throw it away
    if ((Test-Path (Join-Path $targetPath ".git")) -and -not $Force) {
        $dirty = git -C $targetPath status --porcelain 2>$null
        $ahead = git -C $targetPath rev-list --count main..sdlc-work 2>$null
        if ($dirty -or ([int]$ahead -gt 0)) {
            Remove-Item $tempZip -Force
            Write-Error "$targetPath has work in git (uncommitted changes or commits on sdlc-work). Nothing was deleted. Push or save it, change artifactId, or re-run with -Force."
        }
    }
    Remove-Item $targetPath -Recurse -Force
}
New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $OutputDir -Force
Remove-Item $tempZip -Force
Set-Content -Path (Join-Path $targetPath $generatedMarker) -Value "Created by scripts/generate-project.ps1 - regenerating replaces this folder." -Encoding UTF8

# 4. Enrich pom.xml with JaCoCo and OWASP Dependency Check plugins
Write-Host "`n[4/7] Injecting SDLC Maven Plugins (JaCoCo, OWASP)..." -ForegroundColor Yellow
$pomFile = Join-Path $targetPath "pom.xml"

if (Test-Path $pomFile) {
    $pomXml = Get-Content $pomFile -Raw

    $sdlcPlugins = @"
			<!-- JaCoCo Code Coverage Plugin -->
			<plugin>
				<groupId>org.jacoco</groupId>
				<artifactId>jacoco-maven-plugin</artifactId>
				<version>$jacocoVersion</version>
				<executions>
					<execution>
						<goals>
							<goal>prepare-agent</goal>
						</goals>
					</execution>
					<execution>
						<id>report</id>
						<phase>prepare-package</phase>
						<goals>
							<goal>report</goal>
						</goals>
					</execution>
					<execution>
						<id>check</id>
						<goals>
							<goal>check</goal>
						</goals>
						<configuration>
							<rules>
								<rule>
									<element>BUNDLE</element>
									<limits>
										<limit>
											<counter>LINE</counter>
											<value>COVEREDRATIO</value>
											<minimum>0.60</minimum>
										</limit>
									</limits>
								</rule>
							</rules>
						</configuration>
					</execution>
				</executions>
			</plugin>
"@

    # Conditionally add OWASP plugin
    if ($enableOwaspCheck -eq "true") {
        $sdlcPlugins += @"

			<!-- OWASP Dependency-Check Plugin -->
			<plugin>
				<groupId>org.owasp</groupId>
				<artifactId>dependency-check-maven</artifactId>
				<version>9.0.9</version>
				<configuration>
					<format>ALL</format>
					<failBuildOnCVSS>$owaspFailOnCvss</failBuildOnCVSS>
					<failOnError>$owaspFailOnError</failOnError>
				</configuration>
			</plugin>
"@
    }

    # Insert plugins inside <plugins> block
    if ($pomXml.Contains("</plugins>")) {
        $pomXml = $pomXml.Replace("</plugins>", "$sdlcPlugins`n`t`t</plugins>")
        Set-Content -Path $pomFile -Value $pomXml -Encoding UTF8
        Write-Host "    JaCoCo plugin added (version $jacocoVersion, 60% coverage threshold)" -ForegroundColor Green
        if ($enableOwaspCheck -eq "true") {
            Write-Host "    OWASP Dependency-Check plugin added (CVSS >= $owaspFailOnCvss)" -ForegroundColor Green
        }
    }
}

# 5. Copy Local SDLC Infrastructure Files
Write-Host "`n[5/7] Injecting SDLC Tools, SonarQube & Agent Rules..." -ForegroundColor Yellow

# Copy tools/sdlc.ps1
$toolsDir = Join-Path $targetPath "tools"
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
$sdlcScriptSource = "$templateDir/sdlc.ps1"
if (Test-Path $sdlcScriptSource) {
    Copy-Item $sdlcScriptSource -Destination (Join-Path $toolsDir "sdlc.ps1") -Force
    Write-Host "    Copied tools/sdlc.ps1" -ForegroundColor Green
}
Copy-Item "templates/shared/copilot-quota.ps1" -Destination (Join-Path $toolsDir "copilot-quota.ps1") -Force
Write-Host "    Copied tools/copilot-quota.ps1" -ForegroundColor Green
if (Test-Path "templates/brownfield/load-secrets.ps1") {
    Copy-Item "templates/brownfield/load-secrets.ps1" -Destination (Join-Path $toolsDir "load-secrets.ps1") -Force
    Write-Host "    Copied tools/load-secrets.ps1" -ForegroundColor Green
}
if (Test-Path "templates/brownfield/run-local.ps1") {
    Copy-Item "templates/brownfield/run-local.ps1" -Destination (Join-Path $toolsDir "run-local.ps1") -Force
    Write-Host "    Copied tools/run-local.ps1" -ForegroundColor Green
}

# JFrog Xray gate: tools/jfrog-scan.ps1 + jfrog-xray.properties (its presence enables the gate)
if ($enableXray -eq "true") {
    if (-not $xrayUrl) { Write-Error "enableXray is true but xrayUrl is empty in $ConfigFile" }
    Copy-Item "$templateDir/jfrog-scan.ps1" -Destination (Join-Path $toolsDir "jfrog-scan.ps1") -Force
    $xrayProps = "url=$xrayUrl`nwatches=$xrayWatches`ninsecureTls=$xrayInsecureTls`n"
    Set-Content -Path (Join-Path $targetPath "jfrog-xray.properties") -Value $xrayProps -Encoding UTF8 -NoNewline
    Write-Host "    Copied tools/jfrog-scan.ps1, generated jfrog-xray.properties" -ForegroundColor Green

    if (Test-Path "jfrog.token") {
        Copy-Item "jfrog.token" -Destination (Join-Path $targetPath "jfrog.token") -Force
        Write-Host "    Copied jfrog.token" -ForegroundColor Green
    }
} else {
    Write-Host "    JFrog Xray disabled in config - skipping Xray gate" -ForegroundColor DarkYellow
}

# Secrets must never be committed (Initializr's .gitignore does not know them)
$gitignore = Join-Path $targetPath ".gitignore"
if (Test-Path $gitignore) {
    $ignored = Get-Content $gitignore
    $missing = @("sonar-token.txt", "*.token", ".env", "secrets.local.env") | Where-Object { $ignored -notcontains $_ }
    if ($missing) {
        Add-Content -Path $gitignore -Value ((@("") + $missing) -join "`n")
        Write-Host "    .gitignore: added $($missing -join ', ')" -ForegroundColor Green
    }
}

# Generate sonar-project.properties from the template
if ($enableSonarQube -eq "true") {
    $sonarTemplate = "$templateDir/sonar-project.properties"
    if (Test-Path $sonarTemplate) {
        $sonarProjectKey = "${groupId}:${artifactId}"
        Write-Host "    Generating sonar-project.properties (projectKey=$sonarProjectKey)..." -ForegroundColor Green
        $sonarProps = (Get-Content $sonarTemplate -Raw).
            Replace("{{groupId}}", $groupId).
            Replace("{{artifactId}}", $artifactId).
            Replace("{{name}}", $name).
            Replace("{{sonarHostUrl}}", $sonarHostUrl)
        Set-Content -Path (Join-Path $targetPath "sonar-project.properties") -Value $sonarProps -Encoding UTF8
    } else {
        Write-Host "    Warning: $sonarTemplate not found - skipping sonar-project.properties" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "    SonarQube disabled in config - skipping sonar-project.properties" -ForegroundColor DarkYellow
}

# Copy sonar-token.txt if exists
if (Test-Path "sonar-token.txt") {
    Copy-Item "sonar-token.txt" -Destination (Join-Path $targetPath "sonar-token.txt") -Force
    Write-Host "    Copied sonar-token.txt" -ForegroundColor Green
}

# Copy .github directory (Copilot rules & agent configs)
$githubSource = "$templateDir/.github"
if (Test-Path $githubSource) {
    Copy-Item $githubSource -Destination (Join-Path $targetPath ".github") -Recurse -Force
    Write-Host "    Copied .github/ (copilot-instructions, agents, workflows)" -ForegroundColor Green

    # Without the OWASP plugin in pom.xml the CI step would fail; drop it and renumber the gates
    if ($enableOwaspCheck -ne "true") {
        $workflow = Join-Path $targetPath ".github/workflows/sdlc.yml"
        $yml = Get-Content $workflow -Raw
        $yml = [regex]::Replace($yml, "(?ms)^      # Gate \d+: OWASP Dependency Check\r?\n.*?dependency-check-maven:check[^\r\n]*\r?\n\r?\n", "")
        $labels = [regex]::Matches($yml, "\[GATE \d+/\d+\]").Count
        $n = 0
        $yml = [regex]::Replace($yml, "\[GATE \d+/\d+\]", { $script:n++; "[GATE $script:n/$labels]" })
        Set-Content -Path $workflow -Value $yml -Encoding UTF8 -NoNewline
        Write-Host "    OWASP disabled - removed its step from CI workflow" -ForegroundColor DarkYellow
    }
}

# 6. Create pre-commit hook
Write-Host "`n[6/7] Setting up Git repository and pre-commit hook..." -ForegroundColor Yellow
$hooksDir = Join-Path $targetPath ".githooks"
New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null

$preCommitHook = @'
#!/bin/sh
# SDLC Pre-Commit Hook
# Runs compilation and tests before allowing commit.
# SonarQube/OWASP/Xray are skipped for speed (run them manually or in CI).

echo "Running SDLC pre-commit checks..."

if command -v pwsh &> /dev/null; then
    pwsh -File ./tools/sdlc.ps1 -SkipSonar -SkipOwasp -SkipXray
elif command -v powershell &> /dev/null; then
    powershell -File ./tools/sdlc.ps1 -SkipSonar -SkipOwasp -SkipXray
else
    echo "PowerShell not found. Running Maven directly..."
    ./mvnw clean verify -q
fi

STATUS=$?
if [ $STATUS -ne 0 ]; then
    echo ""
    echo "========================================="
    echo "  COMMIT BLOCKED: SDLC gates failed     "
    echo "  Fix the issues and try again.          "
    echo "========================================="
    exit 1
fi
'@

Set-Content -Path (Join-Path $hooksDir "pre-commit") -Value $preCommitHook -Encoding UTF8 -NoNewline

# Create setup script for enabling hooks
$hooksSetup = @'
# Run this once to enable SDLC pre-commit hooks
git config core.hooksPath .githooks
Write-Host "Git hooks enabled. Commits will be validated by SDLC pipeline." -ForegroundColor Green
'@
Set-Content -Path (Join-Path $toolsDir "enable-hooks.ps1") -Value $hooksSetup -Encoding UTF8

Write-Host "    Created .githooks/pre-commit" -ForegroundColor Green
Write-Host "    Created tools/enable-hooks.ps1 (run once to activate)" -ForegroundColor Green

# Every project is versioned: main = generated starting point, sdlc-work = where the agents change code
Push-Location $targetPath
try {
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git init -q -b main
    if ($LASTEXITCODE -ne 0) { Write-Error "git init failed in $targetPath" }
    $localFiles = @(".sdlc-generated", "sdlc-report.json", "sdlc-run.log", "sdlc-cost.json", "plan.md", "security-review.md", "task.md")
    Add-Content -Path ".git/info/exclude" -Value ((@("", "# added by generate-project.ps1") + ($localFiles | ForEach-Object { "/$_" })) -join "`n")
    git add -A 2>$null
    $secrets = @(git diff --cached --name-only | Where-Object { $_ -match '(^|/)(sonar-token\.txt|[^/]*\.token|\.env)$' })
    if ($secrets.Count -gt 0) {
        git reset -q
        Write-Error "Secrets would be committed: $($secrets -join ', '). Check .gitignore in $targetPath."
    }
    git commit -q -m "Initial project from generate-project.ps1 ($artifactId, Spring Boot $bootVersion)"
    if ($LASTEXITCODE -eq 0) {
        git checkout -q -b sdlc-work
        Write-Host "    Git repository: initial commit on main, working branch sdlc-work" -ForegroundColor Green
    } else {
        Write-Host "    WARNING: initial commit failed (git user.name / user.email not set?). Run in $targetPath`: git commit -m 'Initial project'; git checkout -b sdlc-work" -ForegroundColor DarkYellow
    }
    $ErrorActionPreference = $previousEap
} finally {
    Pop-Location
}

# 7. Smoke Test (optional compile verification)
Write-Host "`n[7/7] Smoke test - verifying generated project compiles..." -ForegroundColor Yellow
$originalLocation = Get-Location
try {
    Set-Location $targetPath
    $smokeOutput = & .\mvnw.cmd @mvnSettingsArgs clean compile 2>&1
    $smokeExit = $LASTEXITCODE
    if ($smokeExit -eq 0) {
        Write-Host "    Smoke test PASSED - project compiles successfully" -ForegroundColor Green
    } else {
        Write-Host "    Smoke test FAILED - generated project does not compile!" -ForegroundColor Red
        Write-Host "    Review the pom.xml modifications." -ForegroundColor Yellow
        $smokeOutput | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    }
} catch {
    Write-Host "    Smoke test skipped (Maven Wrapper not available yet): $_" -ForegroundColor DarkYellow
} finally {
    Set-Location $originalLocation
}

# Final Summary
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "   SUCCESS: Project Template Generated!           " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Location: $targetPath"
Write-Host ""
Write-Host "Generated structure:" -ForegroundColor Gray
Write-Host "  $artifactId/"
Write-Host "  +-- .github/agents/       (6 AI agents: sdlc-orchestrator, planner, developer, test-engineer, security-reviewer, quality-fixer)"
Write-Host "  +-- .github/workflows/    (CI pipeline mirroring local SDLC)"
Write-Host "  +-- .githooks/            (pre-commit quality gate)"
Write-Host "  +-- tools/sdlc.ps1        (local SDLC pipeline)"
Write-Host "  +-- sonar-project.properties"
Write-Host "  +-- pom.xml               (enriched with JaCoCo + OWASP)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. .\scripts\env-up.ps1 -ProjectPath $targetPath   (Database + SonarQube + token)"
Write-Host "  2. cd $targetPath"
Write-Host "  3. .\tools\sdlc.ps1                   (run local SDLC gates)"
Write-Host "  4. .\tools\enable-hooks.ps1            (enable pre-commit hooks)"
Write-Host ""
Write-Host "  Shut the environment down with: .\scripts\env-down.ps1"
