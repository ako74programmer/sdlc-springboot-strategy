# ==============================================================================
# LOCAL SDLC PIPELINE - Quality & Security Gates
#   .\tools\sdlc.ps1                 all gates, writes sdlc-report.json
#   .\tools\sdlc.ps1 -CheckReport    does sdlc-report.json describe the current code? (exit 0 = yes)
# ==============================================================================
Param(
    [switch]$SkipSonar,
    [switch]$SkipOwasp,
    [switch]$SkipXray,
    [switch]$CheckReport,
    [string]$MavenSettings = $env:MAVEN_SETTINGS,
    [string]$SonarPluginVersion = "5.8.0.7211"
)

$ErrorActionPreference = "Continue"
$reportFile = "sdlc-report.json"

# Empty = Maven resolves artifacts with its default ~/.m2/settings.xml
$mvnSettingsArgs = @()
if ($MavenSettings) {
    if (Test-Path $MavenSettings) {
        $mvnSettingsArgs = @("-s", (Resolve-Path $MavenSettings).Path)
        Write-Host "Maven settings: $((Resolve-Path $MavenSettings).Path)" -ForegroundColor Gray
    } else {
        Write-Host "Warning: Maven settings file not found: $MavenSettings (using Maven default)" -ForegroundColor DarkYellow
    }
}
$gateStatus = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    status    = "PASSED"
    gates     = @{}
    metrics   = @{
        tests    = @{ total = 0; passed = 0; failed = 0; skipped = 0; errors = 0 }
        coverage = @{ line = $null; branch = $null }
    }
    errors    = @()
    warnings  = @()
}

# Tree hash of tracked + untracked files (ignored ones excluded), built in a temporary index
function Get-WorkTreeHash {
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $tmpIndex = Join-Path ([IO.Path]::GetTempPath()) "sdlc-index-$PID"
    $previous = $env:GIT_INDEX_FILE
    try {
        $env:GIT_INDEX_FILE = $tmpIndex
        git add -A 2>$null
        return (git write-tree 2>$null)
    } finally {
        $env:GIT_INDEX_FILE = $previous
        Remove-Item $tmpIndex -ErrorAction SilentlyContinue
    }
}

if ($CheckReport) {
    if (-not (Test-Path $reportFile)) { Write-Host "No $reportFile - run .\tools\sdlc.ps1" -ForegroundColor Red; exit 1 }
    $recorded = (Get-Content $reportFile -Raw | ConvertFrom-Json).workTreeHash
    $now = Get-WorkTreeHash
    if ($recorded -and $recorded -eq $now) {
        Write-Host "$reportFile matches the current code ($now)" -ForegroundColor Green
        exit 0
    }
    Write-Host "$reportFile does NOT match the current code (report: $recorded, now: $now) - run .\tools\sdlc.ps1 again" -ForegroundColor Red
    exit 1
}
$gateStatus.workTreeHash = Get-WorkTreeHash

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "          LOCAL SDLC PIPELINE           " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Helper function to log gate results
function Execute-Gate {
    param(
        [string]$GateName,
        [scriptblock]$Command
    )
    Write-Host "`n[RUNNING GATE] $GateName..." -ForegroundColor Yellow
    
    $output = & $Command 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "[GATE PASS] $GateName" -ForegroundColor Green
        $script:gateStatus.gates[$GateName] = "PASS"
        return @{ Success = $true; Output = ($output -join "`n") }
    } else {
        Write-Host "[GATE FAIL] $GateName" -ForegroundColor Red
        $script:gateStatus.gates[$GateName] = "FAIL"
        $script:gateStatus.status = "FAILED"
        
        # Capture tail error lines
        $errorLines = ($output | Select-Object -Last 30) -join "`n"
        $script:gateStatus.errors += @{
            gate    = $GateName
            summary = "Command returned non-zero exit code ($exitCode)"
            details = $errorLines
        }
        return @{ Success = $false; Output = ($output -join "`n") }
    }
}

# Helper: Parse Surefire test results from XML reports
function Parse-TestResults {
    $surefireDir = "target/surefire-reports"
    if (-not (Test-Path $surefireDir)) { return }
    
    $totalTests = 0; $totalFailed = 0; $totalErrors = 0; $totalSkipped = 0
    
    Get-ChildItem -Path $surefireDir -Filter "TEST-*.xml" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            [xml]$xml = Get-Content $_.FullName
            $suite = $xml.testsuite
            $totalTests   += [int]$suite.tests
            $totalFailed  += [int]$suite.failures
            $totalErrors  += [int]$suite.errors
            $totalSkipped += [int]$suite.skipped
        } catch {}
    }
    
    $script:gateStatus.metrics.tests = @{
        total   = $totalTests
        passed  = ($totalTests - $totalFailed - $totalErrors - $totalSkipped)
        failed  = $totalFailed
        errors  = $totalErrors
        skipped = $totalSkipped
    }
    
    Write-Host "    Tests: $totalTests total, $($totalTests - $totalFailed - $totalErrors - $totalSkipped) passed, $totalFailed failed, $totalErrors errors, $totalSkipped skipped" -ForegroundColor Gray
}

# Helper: Parse JaCoCo coverage report
function Parse-Coverage {
    $jacocoFile = "target/site/jacoco/jacoco.xml"
    if (-not (Test-Path $jacocoFile)) { return }
    
    try {
        [xml]$xml = Get-Content $jacocoFile
        foreach ($counter in $xml.report.counter) {
            if ($counter.type -eq "LINE") {
                $missed  = [int]$counter.missed
                $covered = [int]$counter.covered
                $total   = $missed + $covered
                if ($total -gt 0) {
                    $pct = [math]::Round(($covered / $total) * 100, 1)
                    $script:gateStatus.metrics.coverage.line = $pct
                    Write-Host "    Line Coverage: $pct%" -ForegroundColor Gray
                }
            }
            if ($counter.type -eq "BRANCH") {
                $missed  = [int]$counter.missed
                $covered = [int]$counter.covered
                $total   = $missed + $covered
                if ($total -gt 0) {
                    $pct = [math]::Round(($covered / $total) * 100, 1)
                    $script:gateStatus.metrics.coverage.branch = $pct
                    Write-Host "    Branch Coverage: $pct%" -ForegroundColor Gray
                }
            }
        }
    } catch {
        Write-Host "    Warning: Could not parse JaCoCo report" -ForegroundColor DarkYellow
    }
}

# Helper: Resolve SonarQube token (no hardcoded fallback); returns token + where it came from
function Get-SonarToken {
    if ($env:SONAR_TOKEN) {
        return @{ Token = $env:SONAR_TOKEN; Source = "environment variable SONAR_TOKEN" }
    }
    if (Test-Path "sonar-token.txt") {
        $token = (Get-Content "sonar-token.txt" -Raw).Trim()
        if ($token) { return @{ Token = $token; Source = "sonar-token.txt" } }
    }
    return $null
}

# Helper: Verify the token is accepted by this SonarQube server before launching Maven
function Test-SonarToken {
    param([string]$SonarUrl, [string]$Token)

    try {
        $resp = Invoke-RestMethod -Uri "$SonarUrl/api/authentication/validate" -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop
        return [bool]$resp.valid
    } catch {
        return $false
    }
}

# Helper: Read a single property from sonar-project.properties
function Get-SonarProperty {
    param([string]$Name, [string]$Default = $null)

    if (-not (Test-Path "sonar-project.properties")) { return $Default }
    $pattern = "^\s*$([regex]::Escape($Name))\s*=\s*(.+)$"
    foreach ($line in (Get-Content "sonar-project.properties")) {
        if ($line -match $pattern) { return $matches[1].Trim() }
    }
    return $Default
}

# Helper: Check SonarQube Quality Gate status via API
function Check-SonarQualityGate {
    param([string]$SonarUrl, [string]$Token)

    $projectKey = Get-SonarProperty "sonar.projectKey"
    if (-not $projectKey) {
        Write-Host "    Warning: sonar.projectKey not found in sonar-project.properties" -ForegroundColor DarkYellow
        return $null
    }
    
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }

    # api/ce/component only shows the last finished task; this run's task id is in the scanner's report-task.txt
    $reportTask = "target/sonar/report-task.txt"
    $ceTaskId = $null
    if (Test-Path $reportTask) {
        $line = Get-Content $reportTask | Where-Object { $_ -match '^ceTaskId=' } | Select-Object -First 1
        if ($line) { $ceTaskId = ($line -split '=', 2)[1].Trim() }
    }
    if (-not $ceTaskId) {
        Write-Host "    Warning: no ceTaskId in $reportTask - Quality Gate cannot be tied to this analysis" -ForegroundColor DarkYellow
        $script:gateStatus.warnings += "SonarQube: no ceTaskId in $reportTask; Quality Gate not checked"
        return $null
    }

    Write-Host "    Waiting for SonarQube analysis task $ceTaskId..." -ForegroundColor Gray
    $maxWait = 180
    $elapsed = 0
    $analysisId = $null
    do {
        try {
            $task = (Invoke-RestMethod -Uri "$SonarUrl/api/ce/task?id=$ceTaskId" -Headers $headers -ErrorAction Stop).task
            if ($task.status -eq "SUCCESS") { $analysisId = $task.analysisId; break }
            if ($task.status -in @("FAILED", "CANCELED")) {
                Write-Host "    SonarQube analysis task $($task.status)" -ForegroundColor Red
                return "ERROR"
            }
        } catch {
            # Task not visible yet, keep waiting
        }
        Start-Sleep 3
        $elapsed += 3
    } while ($elapsed -lt $maxWait)

    if (-not $analysisId) {
        Write-Host "    Warning: analysis task $ceTaskId not finished after ${maxWait}s" -ForegroundColor DarkYellow
        $script:gateStatus.warnings += "SonarQube: analysis task $ceTaskId not finished after ${maxWait}s; Quality Gate unknown"
        return $null
    }

    # Query Quality Gate status of exactly this analysis
    try {
        $qgUrl = "$SonarUrl/api/qualitygates/project_status?analysisId=$analysisId"
        $qgResponse = Invoke-RestMethod -Uri $qgUrl -Headers $headers -ErrorAction Stop
        $qgStatus = $qgResponse.projectStatus.status
        if ($qgStatus -eq "NONE") {
            Write-Host "    Quality Gate: NONE (no gate assigned to the project)" -ForegroundColor DarkYellow
            $script:gateStatus.warnings += "SonarQube: Quality Gate status NONE (no gate assigned to the project)"
            return $null
        }
        
        Write-Host "    Quality Gate: $qgStatus" -ForegroundColor $(if ($qgStatus -eq "OK") { "Green" } else { "Red" })
        
        # Collect failed conditions
        if ($qgStatus -ne "OK" -and $qgResponse.projectStatus.conditions) {
            foreach ($condition in $qgResponse.projectStatus.conditions) {
                if ($condition.status -ne "OK") {
                    $script:gateStatus.errors += @{
                        gate    = "SonarQube-QualityGate"
                        summary = "Condition failed: $($condition.metricKey)"
                        details = "Actual: $($condition.actualValue), Threshold: $($condition.errorThreshold)"
                    }
                }
            }
        }
        
        return $qgStatus
    } catch {
        Write-Host "    Warning: Could not query Quality Gate API: $_" -ForegroundColor DarkYellow
        return $null
    }
}

# ============================================
# GATE 1: Compilation
# ============================================
$compileResult = Execute-Gate -GateName "Compilation" -Command {
    .\mvnw.cmd @mvnSettingsArgs clean compile
}

# ============================================
# GATE 2: Unit & Integration Tests
# ============================================
if ($compileResult.Success) {
    $testResult = Execute-Gate -GateName "Tests" -Command {
        .\mvnw.cmd @mvnSettingsArgs verify
    }
    Parse-TestResults
    Parse-Coverage
} else {
    $script:gateStatus.gates["Tests"] = "SKIPPED"
}

# ============================================
# GATE 3: Vulnerability Scan (OWASP Dependency Check)
# ============================================
# The gate exists only when the generator added the plugin to pom.xml (enableOwaspCheck)
if ((-not $SkipOwasp) -and (Select-String -Path "pom.xml" -Pattern "dependency-check-maven" -Quiet)) {
    Execute-Gate -GateName "VulnerabilityCheck" -Command {
        # failBuildOnCVSS and failOnError come from the dependency-check plugin config in pom.xml
        .\mvnw.cmd @mvnSettingsArgs org.owasp:dependency-check-maven:check "-DautoUpdate=true"
    } | Out-Null
    if (-not (Test-Path "target/dependency-check-report.json")) {
        Write-Host "    WARNING: no dependency-check report produced - VulnerabilityCheck result is not meaningful" -ForegroundColor DarkYellow
        $script:gateStatus.warnings += "VulnerabilityCheck produced no dependency-check report (NVD update failed?); do not treat PASS as a clean scan"
    }
} else {
    $script:gateStatus.gates["VulnerabilityCheck"] = "SKIPPED"
}

# ============================================
# GATE 4: JFrog Xray Scan (corporate policy, zero findings allowed)
# Enabled by the presence of jfrog-xray.properties; needs the jar built by the Tests gate.
# ============================================
if ((-not $SkipXray) -and (Test-Path "jfrog-xray.properties")) {
    if ($testResult -and $testResult.Success) {
        $xrayResult = Execute-Gate -GateName "XrayScan" -Command {
            & "$PSScriptRoot\jfrog-scan.ps1" *>&1
        }
        if (-not $xrayResult.Success -and (Test-Path "target/xray-findings.json")) {
            # One error per finding so the quality-fixer agent gets exact component, CVE and fix version
            $script:gateStatus.errors = @($script:gateStatus.errors | Where-Object { $_.gate -ne "XrayScan" })
            foreach ($f in @(Get-Content "target/xray-findings.json" -Raw | ConvertFrom-Json)) {
                $fix = if (@($f.fixedVersions).Count) { @($f.fixedVersions) -join " " } else { "no fix available" }
                $script:gateStatus.errors += @{
                    gate    = "XrayScan"
                    summary = "[$($f.severity)] $($f.component) $(@($f.cves) -join ',')"
                    details = "Fixed in: $fix. $($f.summary)"
                }
            }
        }
    } else {
        $script:gateStatus.gates["XrayScan"] = "SKIPPED"
    }
} else {
    $script:gateStatus.gates["XrayScan"] = "SKIPPED"
}

# ============================================
# GATE 5: SonarQube Analysis + Quality Gate
# ============================================
if (-not $SkipSonar) {
    $sonarUrl = Get-SonarProperty "sonar.host.url" "http://localhost:9000"
    $tokenInfo = Get-SonarToken
    Write-Host "`n    SonarQube host: $sonarUrl" -ForegroundColor Gray

    if (-not $tokenInfo) {
        Write-Host "`n[GATE FAIL] SonarQube" -ForegroundColor Red
        Write-Host "    ERROR: No SonarQube token found." -ForegroundColor Red
        Write-Host "    Set SONAR_TOKEN environment variable or run:" -ForegroundColor Yellow
        Write-Host "    .\scripts\setup-sonar-token.ps1" -ForegroundColor Yellow
        $script:gateStatus.gates["SonarQube"] = "FAIL"
        $script:gateStatus.status = "FAILED"
        $script:gateStatus.errors += @{
            gate    = "SonarQube"
            summary = "No authentication token available"
            details = "Set SONAR_TOKEN env var or create sonar-token.txt via setup-sonar-token.ps1"
        }
    } elseif (-not (Test-SonarToken -SonarUrl $sonarUrl -Token $tokenInfo.Token)) {
        Write-Host "`n[GATE FAIL] SonarQube" -ForegroundColor Red
        Write-Host "    ERROR: $sonarUrl rejected the token from $($tokenInfo.Source)." -ForegroundColor Red
        Write-Host "    A token is bound to one server - a token for another SonarQube will always return 401." -ForegroundColor Yellow
        Write-Host "    Fix: clear the stale value (`$env:SONAR_TOKEN = `$null) and run .\scripts\setup-sonar-token.ps1" -ForegroundColor Yellow
        $script:gateStatus.gates["SonarQube"] = "FAIL"
        $script:gateStatus.status = "FAILED"
        $script:gateStatus.errors += @{
            gate    = "SonarQube"
            summary = "Token rejected by $sonarUrl (HTTP 401)"
            details = "Token source: $($tokenInfo.Source). Generate a token on this server via setup-sonar-token.ps1 or the SonarQube UI (My Account > Security)."
        }
    } else {
        $sonarToken = $tokenInfo.Token
        $scanResult = Execute-Gate -GateName "SonarQube" -Command {
            $sonarProperties = @()
            if (Test-Path "sonar-project.properties") {
                foreach ($line in (Get-Content "sonar-project.properties")) {
                    if ($line -match "^\s*([^#][^=]*)\s*=\s*(.*)\s*$") {
                        $propertyName = $matches[1].Trim()
                        $propertyValue = $matches[2].Trim()
                        if ($propertyName -ne "sonar.token") {
                            $sonarProperties += "-D$propertyName=$propertyValue"
                        }
                    }
                }
            }
            # The scanner reads SONAR_TOKEN itself; keeps the token out of the process command line
            $previousSonarToken = $env:SONAR_TOKEN
            $env:SONAR_TOKEN = $sonarToken
            try {
                & .\mvnw.cmd @mvnSettingsArgs "org.sonarsource.scanner.maven:sonar-maven-plugin:${SonarPluginVersion}:sonar" $sonarProperties
            } finally {
                $env:SONAR_TOKEN = $previousSonarToken
            }
        }
        
        # Even if sonar:sonar returned 0, check the actual Quality Gate status
        if ($scanResult.Success) {
            $qgStatus = Check-SonarQualityGate -SonarUrl $sonarUrl -Token $sonarToken
            if ($qgStatus -and $qgStatus -ne "OK") {
                $script:gateStatus.gates["SonarQube-QualityGate"] = "FAIL"
                $script:gateStatus.status = "FAILED"
                Write-Host "[GATE FAIL] SonarQube Quality Gate" -ForegroundColor Red
            } elseif ($qgStatus -eq "OK") {
                $script:gateStatus.gates["SonarQube-QualityGate"] = "PASS"
                Write-Host "[GATE PASS] SonarQube Quality Gate" -ForegroundColor Green
            } else {
                $script:gateStatus.gates["SonarQube-QualityGate"] = "UNKNOWN"
                Write-Host "[GATE WARN] SonarQube Quality Gate status could not be determined" -ForegroundColor DarkYellow
            }
        }
    }
} else {
    $script:gateStatus.gates["SonarQube"] = "SKIPPED"
}

# ============================================
# Output Summary
# ============================================
$script:gateStatus | ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding UTF8

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          GATE SUMMARY                  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($gate in $script:gateStatus.gates.GetEnumerator()) {
    $color = switch ($gate.Value) {
        "PASS"    { "Green" }
        "FAIL"    { "Red" }
        "SKIPPED" { "DarkYellow" }
        default   { "Gray" }
    }
    $icon = switch ($gate.Value) {
        "PASS"    { "[OK]  " }
        "FAIL"    { "[FAIL]" }
        "SKIPPED" { "[SKIP]" }
        default   { "[????]" }
    }
    Write-Host "  $icon $($gate.Key)" -ForegroundColor $color
}

$testMetrics = $script:gateStatus.metrics.tests
if ($testMetrics.total -gt 0) {
    Write-Host "`n  Tests: $($testMetrics.total) total | $($testMetrics.passed) passed | $($testMetrics.failed) failed | $($testMetrics.skipped) skipped" -ForegroundColor Gray
}
$covLine = $script:gateStatus.metrics.coverage.line
if ($covLine) {
    Write-Host "  Coverage: $covLine% lines" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($script:gateStatus.status -eq "PASSED") {
    Write-Host "  RESULT: ALL GATES PASSED              " -ForegroundColor Green
} else {
    Write-Host "  RESULT: PIPELINE FAILED               " -ForegroundColor Red
    Write-Host "  Report: $reportFile                    " -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan

if ($script:gateStatus.status -eq "PASSED") {
    exit 0
} else {
    exit 1
}
