# ==============================================================================
# LOCAL SDLC PIPELINE (brownfield) - Quality & Security Gates
#   .\tools\sdlc.ps1 -Baseline           record the starting state (sdlc-baseline.json)
#   .\tools\sdlc.ps1                     gates + Regression/TestIntegrity/DiffGuard against the baseline
#                                        (+ TestMigration when sdlc-settings.json scenario is "tests", MigrationGuard for "migration",
#                                         TestCount and SonarQube-Issues for "sonarfix")
#   .\tools\sdlc.ps1 -ReproTest Cls#m     also prove a bug: the test must be red first, green after the fix
#   .\tools\sdlc.ps1 -CheckReport        does sdlc-report.json describe the current code? (exit 0 = yes)
# ==============================================================================
Param(
    [switch]$SkipSonar,
    [switch]$SkipOwasp,
    [switch]$SkipXray,
    [switch]$Baseline,
    [switch]$CheckReport,
    [string]$ReproTest,
    [string]$MavenSettings = $env:MAVEN_SETTINGS,
    [string]$SonarPluginVersion = "5.8.0.7211"
)

$ErrorActionPreference = "Continue"
$reportFile = "sdlc-report.json"
$baselineFile = "sdlc-baseline.json"
$reproFile = "sdlc-repro.json"
# Downloaded projects do not always ship the Maven Wrapper
$mvn = if (Test-Path "mvnw.cmd") { ".\mvnw.cmd" } else { "mvn" }

# Written by attach-project.ps1; defaults apply when the file is missing
$settings = @{
    scenario           = ""
    mavenSettings      = ""
    diffGuardMaxFiles  = 15
    diffGuardMaxLines  = 400
    diffGuardMode      = "warn"
    coverageTolerance  = 0.0
    sonarMaxOpenIssues = -1
}
if (Test-Path "sdlc-settings.json") {
    foreach ($p in (Get-Content "sdlc-settings.json" -Raw | ConvertFrom-Json).PSObject.Properties) { $settings[$p.Name] = $p.Value }
}
if (-not $MavenSettings) { $MavenSettings = $settings.mavenSettings }
if (Test-Path (Join-Path $PSScriptRoot "use-java.ps1")) { & (Join-Path $PSScriptRoot "use-java.ps1") -Quiet }

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
    scenario  = $settings.scenario
    gates     = @{}
    metrics   = @{
        tests    = @{ total = 0; passed = 0; failed = 0; skipped = 0; errors = 0 }
        coverage = @{ line = $null; branch = $null }
        sonar    = @{ openIssues = $null; hotspotsToReview = $null }
    }
    baseline  = $null
    delta     = $null
    errors    = @()
    warnings  = @()
}
# "package.Class#method" -> passed | failed | skipped
$testCases = @{}

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

# sonarfix is judged by SonarQube data: a baseline without the open issue keys would make Regression and SonarQube-Issues meaningless
if ($Baseline -and $SkipSonar -and $settings.scenario -eq "sonarfix") {
    Write-Host "[BASELINE] Not recorded: -SkipSonar is not allowed for a sonarfix baseline. Start SonarQube (..\..\scripts\env-up.ps1) and run .\tools\sdlc.ps1 -Baseline" -ForegroundColor Red
    exit 1
}

# Taken before the build: files the build rewrites (e.g. springdoc output) must not end up in the baseline snapshot
$preBuildGitBase = $null
if ($Baseline) {
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $preBuildGitBase = git stash create 2>$null
        if (-not $preBuildGitBase) { $preBuildGitBase = git rev-parse HEAD 2>$null }
    }
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

# Helper: Parse Surefire test results (all modules), including per-test outcome
function Parse-TestResults {
    $suites = @(Get-ChildItem -Path . -Recurse -File -Filter "TEST-*.xml" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]target[\\/]surefire-reports[\\/]' })
    if ($suites.Count -eq 0) { return }

    $totalTests = 0; $totalFailed = 0; $totalErrors = 0; $totalSkipped = 0

    foreach ($file in $suites) {
        try {
            [xml]$xml = Get-Content $file.FullName -Raw
            $suite = $xml.testsuite
            $totalTests   += [int]$suite.tests
            $totalFailed  += [int]$suite.failures
            $totalErrors  += [int]$suite.errors
            $totalSkipped += [int]$suite.skipped
            foreach ($tc in @($suite.SelectNodes("testcase"))) {
                $state = if ($tc.SelectSingleNode("failure") -or $tc.SelectSingleNode("error")) { "failed" }
                         elseif ($tc.SelectSingleNode("skipped")) { "skipped" }
                         else { "passed" }
                $script:testCases["$($tc.classname)#$($tc.name)"] = $state
            }
        } catch {
            $script:gateStatus.warnings += "Could not parse $($file.Name)"
        }
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
        $script:gateStatus.warnings += "SonarQube: no ceTaskId in $reportTask; Quality Gate and open issues not checked"
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
        $script:gateStatus.warnings += "SonarQube: analysis task $ceTaskId not finished after ${maxWait}s; Quality Gate and open issues unknown"
        return $null
    }
    $script:sonarAnalysisDone = $true

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
    & $mvn @mvnSettingsArgs clean compile
}

# ============================================
# GATE 2: Unit & Integration Tests
# ============================================
if ($compileResult.Success) {
    # Baseline: failing legacy tests must not stop the JaCoCo report (bound to verify)
    $testArgs = @()
    if ($Baseline) { $testArgs = @("-Dmaven.test.failure.ignore=true") }
    $testResult = Execute-Gate -GateName "Tests" -Command {
        & $mvn @mvnSettingsArgs verify @testArgs
    }
    Parse-TestResults
    Parse-Coverage
    $t = $script:gateStatus.metrics.tests
    if ($Baseline -and ($t.failed + $t.errors) -gt 0) {
        $script:gateStatus.gates["Tests"] = "FAIL"
        $script:gateStatus.status = "FAILED"
    }
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
        & $mvn @mvnSettingsArgs org.owasp:dependency-check-maven:check "-DautoUpdate=true"
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
                & $mvn @mvnSettingsArgs "org.sonarsource.scanner.maven:sonar-maven-plugin:${SonarPluginVersion}:sonar" $sonarProperties
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

            # Open issues: needed for the baseline/Regression and for sonarfix scenarios (QG checks new code only)
            if (-not $script:sonarAnalysisDone) {
                Write-Host "    Open issues not read: this run's analysis was not confirmed" -ForegroundColor DarkYellow
            } else { try {
                $projectKey = [uri]::EscapeDataString((Get-SonarProperty "sonar.projectKey"))
                $issueList = @()
                $page = 1
                do {
                    $issues = Invoke-RestMethod -Uri "$sonarUrl/api/issues/search?componentKeys=$projectKey&resolved=false&ps=500&p=$page" `
                        -Headers @{ Authorization = "Bearer $sonarToken" } -ErrorAction Stop
                    $issueList += @($issues.issues)
                    $page++
                } while ($issueList.Count -lt [int]$issues.total -and @($issues.issues).Count -gt 0)
                $script:sonarIssues = $issueList
                $script:gateStatus.metrics.sonar.openIssues = [int]$issues.total
                Write-Host "    Open issues: $($issues.total)" -ForegroundColor Gray
                # Hotspots are not part of any gate; recorded so agents report them without querying SonarQube themselves
                try {
                    $hotspots = Invoke-RestMethod -Uri "$sonarUrl/api/hotspots/search?project=$projectKey&status=TO_REVIEW&ps=1" `
                        -Headers @{ Authorization = "Bearer $sonarToken" } -ErrorAction Stop
                    $script:gateStatus.metrics.sonar.hotspotsToReview = [int]$hotspots.paging.total
                    Write-Host "    Security hotspots to review: $($hotspots.paging.total)" -ForegroundColor Gray
                } catch {
                    $script:gateStatus.warnings += "Could not read SonarQube security hotspots: $_"
                }

                if ([int]$settings.sonarMaxOpenIssues -ge 0) {
                    if ([int]$issues.total -gt [int]$settings.sonarMaxOpenIssues) {
                        $script:gateStatus.gates["SonarQube-Issues"] = "FAIL"
                        $script:gateStatus.status = "FAILED"
                        Write-Host "[GATE FAIL] SonarQube-Issues ($($issues.total) > $($settings.sonarMaxOpenIssues))" -ForegroundColor Red
                        foreach ($i in $issueList) {
                            $script:gateStatus.errors += @{
                                gate    = "SonarQube-Issues"
                                summary = "[$($i.severity) $($i.type)] $($i.rule)"
                                details = "$($i.component -replace '^[^:]*:[^:]*:', ''):$($i.line) $($i.message)"
                            }
                        }
                    } else {
                        $script:gateStatus.gates["SonarQube-Issues"] = "PASS"
                        Write-Host "[GATE PASS] SonarQube-Issues" -ForegroundColor Green
                    }
                }
            } catch {
                Write-Host "    Warning: could not read open issues: $_" -ForegroundColor DarkYellow
                $script:gateStatus.warnings += "Could not read SonarQube open issues: $_"
            } }
        }
    }
} else {
    $script:gateStatus.gates["SonarQube"] = "SKIPPED"
}

# sonarfix: a run without confirmed open issues (skipped, Sonar down, analysis not confirmed) is never PASSED
if ($settings.scenario -eq "sonarfix" -and -not $Baseline -and -not $script:gateStatus.gates.ContainsKey("SonarQube-Issues")) {
    $script:gateStatus.gates["SonarQube-Issues"] = "FAIL"
    $script:gateStatus.status = "FAILED"
    $script:gateStatus.errors += @{
        gate    = "SonarQube-Issues"
        summary = "Open SonarQube issues not read in a sonarfix scenario"
        details = "SonarQube gate: $($script:gateStatus.gates['SonarQube']). Start SonarQube (..\..\scripts\env-up.ps1) and run .\tools\sdlc.ps1 without -SkipSonar"
    }
    Write-Host "[GATE FAIL] SonarQube-Issues (open issues not read)" -ForegroundColor Red
}

# ============================================
# Baseline facts (shared by -Baseline and the comparison gates)
# ============================================
function Get-RelativePath([string]$fullName) {
    return $fullName.Substring((Get-Location).Path.Length + 1).Replace('\', '/')
}

# Per test file: test method names, @Disabled count, assertion count - used to detect weakened tests
function Get-TestFileFacts {
    $facts = @{}
    $files = Get-ChildItem -Path . -Recurse -File -Include *.java, *.kt, *.groovy -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]src[\\/]test[\\/]' -and $_.FullName -notmatch '[\\/]target[\\/]' }
    foreach ($f in $files) {
        $lines = @(Get-Content $f.FullName)
        $methods = @()
        $pending = $false
        foreach ($l in $lines) {
            # Spock feature method: def "does something"()
            if ($l -match '^\s*def\s+(["''])(.+?)\1\s*\(') { $methods += $matches[2]; $pending = $false; continue }
            if ($l -match '^\s*@(Test|ParameterizedTest|RepeatedTest|TestFactory|TestTemplate)\b') { $pending = $true; continue }
            if ($pending -and $l -notmatch '^\s*@' -and $l -match '\b(\w+)\s*\(') { $methods += $matches[1]; $pending = $false }
        }
        $text = $lines -join "`n"
        $facts[(Get-RelativePath $f.FullName)] = [ordered]@{
            methods  = $methods
            disabled = ([regex]::Matches($text, '@(?:[\w.]+\.)?(Disabled\w*|Ignore)\b')).Count
            asserts  = ([regex]::Matches($text, '\b(assert\w*|verify\w*|expect\w*|andExpect|fail)\s*\(')).Count
        }
    }
    return $facts
}

function Get-SuppressionCount {
    $count = 0
    $files = Get-ChildItem -Path . -Recurse -File -Include *.java, *.kt -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]src[\\/]' -and $_.FullName -notmatch '[\\/]target[\\/]' }
    foreach ($f in $files) {
        $count += ([regex]::Matches("$(Get-Content $f.FullName -Raw)", 'NOSONAR|@SuppressWarnings')).Count
    }
    return $count
}

function Get-FileHashOrNull([string]$path) {
    if (Test-Path $path) { return (Get-FileHash $path -Algorithm SHA256).Hash }
    return $null
}

function Test-GitRepo {
    $null = git rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Add-GateError([string]$gate, [string]$summary, [string]$details) {
    $script:gateStatus.errors += @{ gate = $gate; summary = $summary; details = $details }
}

function Set-Gate([string]$gate, [bool]$ok) {
    $script:gateStatus.gates[$gate] = if ($ok) { "PASS" } else { "FAIL" }
    if (-not $ok) { $script:gateStatus.status = "FAILED" }
    Write-Host "$(if ($ok) { '[GATE PASS]' } else { '[GATE FAIL]' }) $gate" -ForegroundColor $(if ($ok) { "Green" } else { "Red" })
}

if ($Baseline) {
    # ============================================
    # -Baseline: record the starting point; failing legacy tests are recorded, not judged
    # ============================================
    if ($settings.scenario -eq "sonarfix" -and $null -eq $script:sonarIssues) {
        Write-Host "`n[BASELINE] Not recorded: SonarQube open issues were not read (SonarQube: $($script:gateStatus.gates['SonarQube'])). Start SonarQube (..\..\scripts\env-up.ps1) and run .\tools\sdlc.ps1 -Baseline again" -ForegroundColor Red
        exit 1
    }
    $gitBase = $preBuildGitBase
    if ($gitBase) {
        # stash create snapshots tracked changes (e.g. JaCoCo added by attach) without touching the working tree
        git update-ref refs/sdlc/baseline $gitBase 2>$null
    }
    $baselineData = [ordered]@{
        createdAt           = $script:gateStatus.timestamp
        gitBase             = $gitBase
        compiles            = ($script:gateStatus.gates["Compilation"] -eq "PASS")
        tests               = $script:gateStatus.metrics.tests
        cases               = $testCases
        coverage            = $script:gateStatus.metrics.coverage
        sonarOpenIssues     = $script:gateStatus.metrics.sonar.openIssues
        sonarHotspotsToReview = $script:gateStatus.metrics.sonar.hotspotsToReview
        sonarIssueKeys      = $(if ($null -ne $script:sonarIssues) { , @($script:sonarIssues | ForEach-Object { $_.key }) } else { $null })
        testFiles           = Get-TestFileFacts
        suppressions        = Get-SuppressionCount
        sonarPropertiesHash = Get-FileHashOrNull "sonar-project.properties"
    }
    $baselineData | ConvertTo-Json -Depth 6 | Set-Content -Path $baselineFile -Encoding UTF8
    if (Test-Path $reproFile) { Remove-Item $reproFile }
    $failingNow = @($testCases.GetEnumerator() | Where-Object { $_.Value -eq "failed" }).Count
    Write-Host "`n[BASELINE] Recorded $baselineFile (git: $(if ($gitBase) { $gitBase.Substring(0, 8) } else { 'n/a' }), tests: $($testCases.Count), failing: $failingNow, coverage: $($script:gateStatus.metrics.coverage.line), sonar issues: $($script:gateStatus.metrics.sonar.openIssues))" -ForegroundColor Cyan
    $script:gateStatus.baseline = @{ recorded = $true; file = $baselineFile }
} elseif (Test-Path $baselineFile) {
    $base = Get-Content $baselineFile -Raw | ConvertFrom-Json
    $baseCases = @{}
    if ($base.cases) { foreach ($p in $base.cases.PSObject.Properties) { $baseCases[$p.Name] = $p.Value } }
    $script:gateStatus.baseline = @{ recorded = $true; createdAt = $base.createdAt; gitBase = $base.gitBase }

    # ============================================
    # GATE: Regression - nothing that worked before may break
    # ============================================
    if ($script:gateStatus.gates["Tests"] -in @("PASS", "FAIL")) {
        $ok = $true
        foreach ($name in $baseCases.Keys) {
            if ($baseCases[$name] -eq "passed" -and $testCases.ContainsKey($name) -and $testCases[$name] -ne "passed") {
                $ok = $false
                Add-GateError "Regression" "Test passed in baseline, now $($testCases[$name])" $name
            }
        }
        $covNow = $script:gateStatus.metrics.coverage.line
        $covBase = $base.coverage.line
        if ($null -ne $covNow -and $null -ne $covBase -and [double]$covNow -lt ([double]$covBase - [double]$settings.coverageTolerance)) {
            $ok = $false
            Add-GateError "Regression" "Line coverage dropped" "Baseline: $covBase%, now: $covNow%"
        }
        $sonarNow = $script:gateStatus.metrics.sonar.openIssues
        if ($null -ne $script:sonarIssues -and $null -ne $base.sonarIssueKeys) {
            # Issue keys survive Sonar's issue tracking, so only issues absent from the baseline count as new
            $known = @{}
            foreach ($k in @($base.sonarIssueKeys)) { $known[$k] = $true }
            # In a platform migration the new Java level / library annotations activate rules on untouched code;
            # only issues on lines changed by this task block, the rest is reported for a separate sonarfix task
            $changedLines = $null
            if ($settings.scenario -eq "migration" -and $base.gitBase -and (Test-GitRepo)) {
                $changedLines = @{}
                $file = $null
                foreach ($dl in @(git diff -U0 $base.gitBase -- src 2>$null)) {
                    if ($dl -match '^\+\+\+ b/(.+)$') { $file = $Matches[1]; $changedLines[$file] = @() }
                    elseif ($file -and $dl -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@') {
                        $start = [int]$Matches[1]; $len = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
                        if ($len -gt 0) { $changedLines[$file] += , @($start, ($start + $len - 1)) }
                    }
                }
                foreach ($f in @(git ls-files --others --exclude-standard -- src 2>$null)) { $changedLines[$f] = @(, @(1, [int]::MaxValue)) }
            }
            foreach ($i in @($script:sonarIssues | Where-Object { -not $known.ContainsKey($_.key) })) {
                $path = $i.component -replace '^[^:]*:[^:]*:', ''
                $where = "${path}:$($i.line) $($i.message)"
                $onChangedLine = $true
                if ($null -ne $changedLines) {
                    $onChangedLine = $false
                    if ($changedLines.ContainsKey($path) -and $i.line) {
                        foreach ($r in $changedLines[$path]) { if ([int]$i.line -ge $r[0] -and [int]$i.line -le $r[1]) { $onChangedLine = $true; break } }
                    }
                }
                if ($onChangedLine) {
                    $ok = $false
                    Add-GateError "Regression" "New SonarQube issue [$($i.severity) $($i.type)] $($i.rule)" $where
                } else {
                    $script:gateStatus.warnings += "Regression: SonarQube issue on unchanged code after the platform upgrade (not blocking; fix in a sonarfix task) [$($i.severity) $($i.type)] $($i.rule) $where"
                }
            }
        } elseif ($null -ne $sonarNow -and $null -ne $base.sonarOpenIssues -and [int]$sonarNow -gt [int]$base.sonarOpenIssues) {
            $ok = $false
            Add-GateError "Regression" "More open SonarQube issues than in baseline" "Baseline: $($base.sonarOpenIssues), now: $sonarNow"
        }
        Set-Gate "Regression" $ok
    } else {
        $script:gateStatus.gates["Regression"] = "SKIPPED"
    }

    # ============================================
    # GATE: TestIntegrity - tests must not be deleted, disabled or weakened; no new suppressions
    # ============================================
    $ok = $true
    # In a test migration (and when sonarfix merges tests into parameterized ones) methods are replaced;
    # TestMigration / TestCount then guard the number of executed tests
    $migration = ($settings.scenario -eq "tests")
    $testsReplaceable = ($settings.scenario -in @("tests", "sonarfix"))
    $nowFacts = Get-TestFileFacts
    if ($base.testFiles) {
        foreach ($p in $base.testFiles.PSObject.Properties) {
            $file = $p.Name; $was = $p.Value
            if (-not $nowFacts.ContainsKey($file)) {
                if (@($was.methods).Count -gt 0) {
                    if ($testsReplaceable) {
                        $script:gateStatus.warnings += "TestIntegrity: test file replaced (guarded by the test count gate): $file ($(@($was.methods).Count) tests)"
                    } else {
                        $ok = $false
                        Add-GateError "TestIntegrity" "Test file deleted" "$file ($(@($was.methods).Count) tests)"
                    }
                }
                continue
            }
            $now = $nowFacts[$file]
            $missing = @(@($was.methods) | Where-Object { @($now.methods) -notcontains $_ })
            if ($missing.Count -gt 0) {
                if ($testsReplaceable) {
                    $script:gateStatus.warnings += "TestIntegrity: test methods replaced (guarded by the test count gate): ${file}: $($missing -join ', ')"
                } else {
                    $ok = $false
                    Add-GateError "TestIntegrity" "Test methods removed or renamed" "${file}: $($missing -join ', ')"
                }
            }
            if ($now.disabled -gt $was.disabled) {
                $ok = $false
                Add-GateError "TestIntegrity" "Tests disabled" "${file}: @Disabled/@Ignore $($was.disabled) -> $($now.disabled)"
            }
            if ($now.asserts -lt $was.asserts) {
                if ($settings.scenario -eq "sonarfix" -and $missing.Count -gt 0) {
                    $script:gateStatus.warnings += "TestIntegrity: fewer assertions after merging tests (guarded by TestCount): ${file}: $($was.asserts) -> $($now.asserts)"
                } else {
                    $ok = $false
                    Add-GateError "TestIntegrity" "Fewer assertions than in baseline" "${file}: $($was.asserts) -> $($now.asserts)"
                }
            }
        }
    }
    $suppressNow = Get-SuppressionCount
    if ($suppressNow -gt [int]$base.suppressions) {
        $ok = $false
        Add-GateError "TestIntegrity" "New NOSONAR/@SuppressWarnings" "Baseline: $($base.suppressions), now: $suppressNow"
    }
    if ((Get-FileHashOrNull "sonar-project.properties") -ne $base.sonarPropertiesHash) {
        $ok = $false
        Add-GateError "TestIntegrity" "sonar-project.properties changed" "Analysis scope or exclusions must not change to silence findings"
    }
    Set-Gate "TestIntegrity" $ok

    # ============================================
    # GATE: DiffGuard - size of the change against the baseline snapshot
    # ============================================
    $changed = $null
    if ($base.gitBase -and (Test-GitRepo)) {
        $changed = @{}
        foreach ($line in @(git diff --numstat $base.gitBase 2>$null)) {
            $parts = $line -split "`t"
            if ($parts.Count -ge 3) {
                $n = 0
                if ($parts[0] -match '^\d+$') { $n += [int]$parts[0] }
                if ($parts[1] -match '^\d+$') { $n += [int]$parts[1] }
                $changed[$parts[2]] = $n
            }
        }
        foreach ($f in @(git ls-files --others --exclude-standard 2>$null)) {
            if ($f -match '^(sdlc-|recon-report)' -or -not (Test-Path $f -PathType Leaf)) { continue }
            $changed[$f] = @(Get-Content $f -ErrorAction SilentlyContinue).Count
        }
        $fileCount = $changed.Count
        $lineCount = ($changed.Values | Measure-Object -Sum).Sum
        if (-not $lineCount) { $lineCount = 0 }
        $script:gateStatus.metrics.diff = @{ files = $fileCount; lines = $lineCount; changed = @($changed.Keys | Sort-Object) }
        Write-Host "`n    Diff vs baseline: $fileCount files, $lineCount lines" -ForegroundColor Gray

        if ($changed.ContainsKey("pom.xml")) {
            $script:gateStatus.warnings += "DiffGuard: pom.xml changed - expected for vulnfix/migration/buildfix, suspicious otherwise"
        }
        $testsTouched = @($changed.Keys | Where-Object { $_ -match '(^|/)src/test/' -and (Test-Path $_) -and $base.testFiles.PSObject.Properties.Name -contains $_ })
        if ($testsTouched.Count -gt 0) {
            $script:gateStatus.warnings += "DiffGuard: existing test files modified: $($testsTouched -join ', ')"
        }

        $tooBig = ($fileCount -gt [int]$settings.diffGuardMaxFiles) -or ($lineCount -gt [int]$settings.diffGuardMaxLines)
        if ($tooBig) {
            $msg = "Change is larger than the limit: $fileCount files (max $($settings.diffGuardMaxFiles)), $lineCount lines (max $($settings.diffGuardMaxLines))"
            if ($settings.diffGuardMode -eq "fail") {
                Add-GateError "DiffGuard" "Change too large" $msg
                Set-Gate "DiffGuard" $false
            } else {
                $script:gateStatus.warnings += "DiffGuard: $msg"
                Set-Gate "DiffGuard" $true
            }
        } else {
            Set-Gate "DiffGuard" $true
        }
    } else {
        $script:gateStatus.gates["DiffGuard"] = "SKIPPED"
    }

    # ============================================
    # GATE: TestMigration (scenario "tests") / MigrationGuard (scenario "migration")
    # Tests may be replaced or adapted, never reduced
    # ============================================
    $platformMigration = ($settings.scenario -eq "migration")
    $sonarfix = ($settings.scenario -eq "sonarfix")
    if ($migration -or $platformMigration -or $sonarfix) {
        $gate = if ($migration) { "TestMigration" } elseif ($platformMigration) { "MigrationGuard" } else { "TestCount" }
        $ok = $true
        # Spock reports an unrolled feature once more as a container: "<feature>" next to "<feature> [..]", or with unresolved #placeholders
        $byClass = @{}
        foreach ($k in $baseCases.Keys) {
            $parts = $k -split '#', 2
            if (-not $byClass.ContainsKey($parts[0])) { $byClass[$parts[0]] = New-Object System.Collections.Generic.List[string] }
            $byClass[$parts[0]].Add($parts[1])
        }
        $containers = @($baseCases.Keys | Where-Object {
                $parts = $_ -split '#', 2
                $m = $parts[1]
                ($m -match '#[A-Za-z_]\w*') -or @($byClass[$parts[0]] | Where-Object { $_ -ne $m -and $_.StartsWith("$m [") }).Count -gt 0
            })
        $baseTotal = [int]$base.tests.total - $containers.Count
        $basePassed = [int]$base.tests.passed - @($containers | Where-Object { $baseCases[$_] -eq "passed" }).Count
        if ($script:gateStatus.gates["Tests"] -in @("PASS", "FAIL")) {
            $nowTests = $script:gateStatus.metrics.tests
            $note = if ($containers.Count) { " ($($containers.Count) Spock container entries not counted)" } else { "" }
            if ([int]$nowTests.total -lt $baseTotal) {
                $ok = $false
                Add-GateError $gate "Fewer executed tests than in baseline" "Baseline: $baseTotal$note, now: $($nowTests.total)"
            }
            if ([int]$nowTests.passed -lt $basePassed) {
                $ok = $false
                Add-GateError $gate "Fewer passing tests than in baseline" "Baseline: $basePassed$note, now: $($nowTests.passed)"
            }
        } else {
            $ok = $false
            Add-GateError $gate "Tests did not run" "Test count cannot be compared with the baseline"
        }
        if ($migration) {
            if ($null -ne $changed) {
                $prodChanged = @($changed.Keys | Where-Object { $_ -match '(^|/)src/main/' } | Sort-Object)
                if ($prodChanged.Count -gt 0) {
                    $ok = $false
                    Add-GateError $gate "Production code changed in a tests scenario" ($prodChanged -join ', ')
                }
            } else {
                $script:gateStatus.warnings += "TestMigration: no git baseline - src/main changes not checked"
            }
        } elseif ($platformMigration) {
            # The migration is done only when pom.xml declares the target versions
            [xml]$pomNow = Get-Content "pom.xml" -Raw
            $pomValue = { param($path) $n = $pomNow.SelectSingleNode("/" + (($path -split '/' | ForEach-Object { "*[local-name()='$_']" }) -join '/')); if ($n) { $n.InnerText.Trim() } }
            $bootNow = & $pomValue "project/parent/version"
            $javaNow = & $pomValue "project/properties/java.version"
            if (-not $javaNow) { $javaNow = & $pomValue "project/properties/maven.compiler.release" }
            if ($settings.migrationBootVersion -and $bootNow -ne $settings.migrationBootVersion) {
                $ok = $false
                Add-GateError $gate "Spring Boot version is not the migration target" "pom.xml parent: $bootNow, target: $($settings.migrationBootVersion)"
            }
            if ($settings.migrationJavaVersion -and $javaNow -ne "$($settings.migrationJavaVersion)") {
                $ok = $false
                Add-GateError $gate "Java version is not the migration target" "pom.xml: $javaNow, target: $($settings.migrationJavaVersion)"
            }
        }
        Set-Gate $gate $ok
    }

    $script:gateStatus.delta = @{
        testsPassed     = $script:gateStatus.metrics.tests.passed - [int]$base.tests.passed
        coverageLine    = if ($null -ne $script:gateStatus.metrics.coverage.line -and $null -ne $base.coverage.line) { [math]::Round([double]$script:gateStatus.metrics.coverage.line - [double]$base.coverage.line, 1) } else { $null }
        sonarOpenIssues = if ($null -ne $script:gateStatus.metrics.sonar.openIssues -and $null -ne $base.sonarOpenIssues) { [int]$script:gateStatus.metrics.sonar.openIssues - [int]$base.sonarOpenIssues } else { $null }
    }
} else {
    Write-Host "`n    No $baselineFile - Regression/TestIntegrity/DiffGuard skipped. Run .\tools\sdlc.ps1 -Baseline before changing code." -ForegroundColor DarkYellow
    $script:gateStatus.warnings += "No baseline recorded - Regression, TestIntegrity and DiffGuard were skipped"
    foreach ($g in @("Regression", "TestIntegrity", "DiffGuard")) { $script:gateStatus.gates[$g] = "SKIPPED" }
    if ($settings.scenario -eq "tests") { $script:gateStatus.gates["TestMigration"] = "SKIPPED" }
    if ($settings.scenario -eq "migration") { $script:gateStatus.gates["MigrationGuard"] = "SKIPPED" }
    if ($settings.scenario -eq "sonarfix") { $script:gateStatus.gates["TestCount"] = "SKIPPED" }
}

# ============================================
# GATE: ReproTest - a bug fix is proven by a test that was red before and is green now
# ============================================
if ($ReproTest -and -not $Baseline) {
    $match = @($testCases.Keys | Where-Object { $_ -eq $ReproTest -or $_.EndsWith(".$ReproTest") })
    if ($match.Count -ne 1) {
        Add-GateError "ReproTest" "Reproduction test not found (or ambiguous)" "'$ReproTest' matched $($match.Count) executed tests. Use Class#method or package.Class#method."
        Set-Gate "ReproTest" $false
    } else {
        $id = $match[0]
        $state = $testCases[$id]
        $red = $false
        if (Test-Path $reproFile) {
            $rec = Get-Content $reproFile -Raw | ConvertFrom-Json
            $red = ($rec.test -eq $id -and $rec.red)
        }
        if (-not $red -and (Test-Path $baselineFile)) {
            $bc = (Get-Content $baselineFile -Raw | ConvertFrom-Json).cases
            if ($bc -and $bc.PSObject.Properties.Name -contains $id -and $bc.$id -eq "failed") { $red = $true }
        }

        if (-not $red) {
            if ($state -eq "failed") {
                @{ test = $id; red = $true; recordedAt = $script:gateStatus.timestamp } | ConvertTo-Json | Set-Content $reproFile -Encoding UTF8
                Add-GateError "ReproTest" "Bug reproduced - test is red as expected; now fix the production code" $id
                $script:gateStatus.gates["ReproTest"] = "RED-RECORDED"
                $script:gateStatus.status = "FAILED"
                Write-Host "[GATE RED ] ReproTest recorded red: $id" -ForegroundColor Yellow
            } else {
                Add-GateError "ReproTest" "Test does not reproduce the bug - it was never red" "$id is $state; a reproduction test must fail before the fix"
                Set-Gate "ReproTest" $false
            }
        } else {
            if ($state -ne "passed") { Add-GateError "ReproTest" "Bug not fixed - reproduction test still $state" $id }
            Set-Gate "ReproTest" ($state -eq "passed")
        }
    }
}

# ============================================
# Output Summary
# ============================================
$script:gateStatus | ConvertTo-Json -Depth 6 | Set-Content -Path $reportFile -Encoding UTF8

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          GATE SUMMARY                  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($gate in $script:gateStatus.gates.GetEnumerator()) {
    $color = switch ($gate.Value) {
        "PASS"    { "Green" }
        "FAIL"    { "Red" }
        "SKIPPED" { "DarkYellow" }
        "RED-RECORDED" { "Yellow" }
        default   { "Gray" }
    }
    $icon = switch ($gate.Value) {
        "PASS"    { "[OK]  " }
        "FAIL"    { "[FAIL]" }
        "SKIPPED" { "[SKIP]" }
        "RED-RECORDED" { "[RED] " }
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
if ($Baseline) {
    Write-Host "  BASELINE RECORDED: $baselineFile       " -ForegroundColor Cyan
    Write-Host "  (gate failures above describe the starting state)" -ForegroundColor Gray
} elseif ($script:gateStatus.status -eq "PASSED") {
    Write-Host "  RESULT: ALL GATES PASSED              " -ForegroundColor Green
} else {
    Write-Host "  RESULT: PIPELINE FAILED               " -ForegroundColor Red
    Write-Host "  Report: $reportFile                    " -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan

if ($Baseline -or $script:gateStatus.status -eq "PASSED") {
    exit 0
} else {
    exit 1
}
