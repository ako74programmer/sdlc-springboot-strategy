# ==============================================================================
# LOCAL SDLC PIPELINE - Quality & Security Gates
# ==============================================================================
Param(
    [switch]$SkipSonar,
    [switch]$SkipOwasp,
    [string]$MavenSettings = $env:MAVEN_SETTINGS
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
}

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

# Helper: Resolve SonarQube token (no hardcoded fallback)
function Get-SonarToken {
    if ($env:SONAR_TOKEN) {
        return $env:SONAR_TOKEN
    }
    if (Test-Path "sonar-token.txt") {
        $token = (Get-Content "sonar-token.txt" -Raw).Trim()
        if ($token) { return $token }
    }
    return $null
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
    
    # Wait for SonarQube to process the analysis (async processing)
    Write-Host "    Waiting for SonarQube analysis to complete..." -ForegroundColor Gray
    $maxWait = 60
    $elapsed = 0
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    
    do {
        Start-Sleep 5
        $elapsed += 5
        try {
            $ceUrl = "$SonarUrl/api/ce/component?component=$projectKey"
            $ceResponse = Invoke-RestMethod -Uri $ceUrl -Headers $headers -ErrorAction Stop
            $currentTask = $ceResponse.current
            if ($null -eq $currentTask) { break }
            if ($currentTask.status -eq "SUCCESS") { break }
            if ($currentTask.status -eq "FAILED") {
                Write-Host "    SonarQube analysis task FAILED" -ForegroundColor Red
                return "ERROR"
            }
        } catch {
            # API not ready yet, keep waiting
        }
    } while ($elapsed -lt $maxWait)
    
    # Query Quality Gate status
    try {
        $qgUrl = "$SonarUrl/api/qualitygates/project_status?projectKey=$projectKey"
        $qgResponse = Invoke-RestMethod -Uri $qgUrl -Headers $headers -ErrorAction Stop
        $qgStatus = $qgResponse.projectStatus.status
        
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
if (-not $SkipOwasp) {
    Execute-Gate -GateName "VulnerabilityCheck" -Command {
        .\mvnw.cmd @mvnSettingsArgs org.owasp:dependency-check-maven:check "-DfailBuildOnCVSS=7.0" "-DautoUpdate=true" "-DfailOnError=false"
    } | Out-Null
} else {
    $script:gateStatus.gates["VulnerabilityCheck"] = "SKIPPED"
}

# ============================================
# GATE 4: SonarQube Analysis + Quality Gate
# ============================================
if (-not $SkipSonar) {
    $sonarToken = Get-SonarToken
    if (-not $sonarToken) {
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
    } else {
        $sonarUrl = Get-SonarProperty "sonar.host.url" "http://localhost:9000"
        Write-Host "    SonarQube host: $sonarUrl" -ForegroundColor Gray
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
            $sonarProperties += "-Dsonar.token=$sonarToken"
            & .\mvnw.cmd @mvnSettingsArgs "org.sonarsource.scanner.maven:sonar-maven-plugin:sonar" $sonarProperties
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
