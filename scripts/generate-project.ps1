# ==============================================================================
# SPRING BOOT TEMPLATE GENERATOR USING SPRING INITIALIZR API
# ==============================================================================
Param(
    [string]$ConfigFile = "config/project-config.yaml",
    [string]$OutputDir = "generated-projects"
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Spring Boot SDLC Project Template Generator    " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Verify Config File
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found at: $ConfigFile"
}

Write-Host "[1/7] Reading configuration from $ConfigFile..." -ForegroundColor Yellow
$configContent = Get-Content $ConfigFile -Raw

# Simple robust regex parser for project-config.yaml
function Get-YamlValue([string]$key, [string]$default = "") {
    if ($configContent -match "$key\s*:\s*[`"']?(.*?)[`"']?\s*(?:#.*)?$") {
        $val = $matches[1].Trim()
        if ($val -match "^([^#]+)") {
            $val = $matches[1].Trim()
        }
        return $val
    }
    return $default
}

# Project settings
$type        = Get-YamlValue "type" "maven-project"
$language    = Get-YamlValue "language" "java"
$bootVersion = Get-YamlValue "bootVersion" ""
$groupId     = Get-YamlValue "groupId" "com.example.sdlc"
$artifactId  = Get-YamlValue "artifactId" "springboot-sdlc-demo"
$name        = Get-YamlValue "name" "springboot-sdlc-demo"
$description = Get-YamlValue "description" "Spring Boot Service with SDLC"
$packageName = Get-YamlValue "packageName" "com.example.sdlc.demo"
$packaging   = Get-YamlValue "packaging" "jar"
$javaVersion = Get-YamlValue "javaVersion" "21"

# SDLC settings
$enableSonarQube = Get-YamlValue "enableSonarQube" "true"
$enableOwaspCheck = Get-YamlValue "enableOwaspCheck" "true"
$sonarHostUrl    = Get-YamlValue "sonarHostUrl" "http://localhost:9000"
$owaspFailOnCvss = Get-YamlValue "owaspFailOnCvss" "7.0"

# Extract dependencies array
$deps = @()
$inDeps = $false
foreach ($line in ($configContent -split "`n")) {
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
    $deps = @("web", "data-jpa", "actuator", "validation", "lombok", "h2")
}
$depsJoined = $deps -join ","

Write-Host "    ArtifactId:       $artifactId" -ForegroundColor Gray
Write-Host "    GroupId:          $groupId" -ForegroundColor Gray
Write-Host "    Java Version:     $javaVersion" -ForegroundColor Gray
Write-Host "    Dependencies:     $depsJoined" -ForegroundColor Gray
Write-Host "    SonarQube:        $enableSonarQube ($sonarHostUrl)" -ForegroundColor Gray
Write-Host "    OWASP Check:      $enableOwaspCheck (CVSS >= $owaspFailOnCvss)" -ForegroundColor Gray

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
    Remove-Item $targetPath -Recurse -Force
}
New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $OutputDir -Force
Remove-Item $tempZip -Force

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
				<version>0.8.12</version>
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
				</configuration>
			</plugin>
"@
    }

    # Insert plugins inside <plugins> block
    if ($pomXml.Contains("</plugins>")) {
        $pomXml = $pomXml.Replace("</plugins>", "$sdlcPlugins`n`t`t</plugins>")
        Set-Content -Path $pomFile -Value $pomXml -Encoding UTF8
        Write-Host "    JaCoCo plugin added (with 60% coverage threshold)" -ForegroundColor Green
        if ($enableOwaspCheck -eq "true") {
            Write-Host "    OWASP Dependency-Check plugin added (CVSS >= $owaspFailOnCvss)" -ForegroundColor Green
        }
    }
}

# 5. Copy Local SDLC Infrastructure Files
Write-Host "`n[5/7] Injecting SDLC Tools, SonarQube & Agent Rules..." -ForegroundColor Yellow

# Copy Docker Compose
$dockerComposeSource = "docker/docker-compose.yml"
if (Test-Path $dockerComposeSource) {
    Copy-Item $dockerComposeSource -Destination (Join-Path $targetPath "docker-compose.yml") -Force
    Write-Host "    Copied docker-compose.yml" -ForegroundColor Green
}

# Copy tools/sdlc.ps1
$toolsDir = Join-Path $targetPath "tools"
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
$sdlcScriptSource = "templates/sdlc.ps1"
if (Test-Path $sdlcScriptSource) {
    Copy-Item $sdlcScriptSource -Destination (Join-Path $toolsDir "sdlc.ps1") -Force
    Write-Host "    Copied tools/sdlc.ps1" -ForegroundColor Green
}

# Generate parametrized sonar-project.properties
Write-Host "    Generating sonar-project.properties (projectKey=$artifactId)..." -ForegroundColor Green
$sonarProps = @"
# SonarQube Project Configuration (auto-generated)
sonar.projectKey=$artifactId
sonar.projectName=$name
sonar.host.url=$sonarHostUrl
sonar.sourceEncoding=UTF-8
sonar.sources=src/main/java
sonar.tests=src/test/java
sonar.java.binaries=target/classes
sonar.java.test.binaries=target/test-classes
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
"@
Set-Content -Path (Join-Path $targetPath "sonar-project.properties") -Value $sonarProps -Encoding UTF8

# Copy sonar-token.txt if exists
if (Test-Path "sonar-token.txt") {
    Copy-Item "sonar-token.txt" -Destination (Join-Path $targetPath "sonar-token.txt") -Force
    Write-Host "    Copied sonar-token.txt" -ForegroundColor Green
}

# Copy .github directory (Copilot rules & agent configs)
$githubSource = "templates/.github"
if (Test-Path $githubSource) {
    Copy-Item $githubSource -Destination (Join-Path $targetPath ".github") -Recurse -Force
    Write-Host "    Copied .github/ (copilot-instructions, agents, workflows)" -ForegroundColor Green
}

# 6. Create pre-commit hook
Write-Host "`n[6/7] Setting up Git pre-commit hook..." -ForegroundColor Yellow
$hooksDir = Join-Path $targetPath ".githooks"
New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null

$preCommitHook = @'
#!/bin/sh
# SDLC Pre-Commit Hook
# Runs compilation and tests before allowing commit.
# SonarQube/OWASP are skipped for speed (run them manually or in CI).

echo "Running SDLC pre-commit checks..."

if command -v pwsh &> /dev/null; then
    pwsh -File ./tools/sdlc.ps1 -SkipSonar -SkipOwasp
elif command -v powershell &> /dev/null; then
    powershell -File ./tools/sdlc.ps1 -SkipSonar -SkipOwasp
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

# 7. Smoke Test (optional compile verification)
Write-Host "`n[7/7] Smoke test - verifying generated project compiles..." -ForegroundColor Yellow
$originalLocation = Get-Location
try {
    Set-Location $targetPath
    $smokeOutput = & .\mvnw.cmd clean compile 2>&1
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
Write-Host "  +-- .github/agents/       (5 AI agents: planner, developer, test-engineer, security-reviewer, quality-fixer)"
Write-Host "  +-- .github/workflows/    (CI pipeline mirroring local SDLC)"
Write-Host "  +-- .githooks/            (pre-commit quality gate)"
Write-Host "  +-- tools/sdlc.ps1        (local SDLC pipeline)"
Write-Host "  +-- docker-compose.yml    (SonarQube + PostgreSQL)"
Write-Host "  +-- sonar-project.properties"
Write-Host "  +-- pom.xml               (enriched with JaCoCo + OWASP)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. cd $targetPath"
Write-Host "  2. docker-compose up -d                (start local SonarQube)"
Write-Host "  3. ..\..\scripts\setup-sonar-token.ps1 (generate auth token - waits for SonarQube)"
Write-Host "  4. .\tools\sdlc.ps1                   (run local SDLC gates)"
Write-Host "  5. .\tools\enable-hooks.ps1            (enable pre-commit hooks)"
