# ==============================================================================
# PROJECT RECON - read-only snapshot of an existing (brownfield) project
# Run from the project root: .\tools\recon.ps1   ->   recon-report.json
# Builds and runs tests, but changes no source files.
# ==============================================================================
Param(
    [string]$MavenSettings = $env:MAVEN_SETTINGS,
    [switch]$SkipBuild,
    [int]$TopClasses = 10
)

$ErrorActionPreference = "Continue"
$reportFile = "recon-report.json"

$report = [ordered]@{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    project   = (Split-Path (Get-Location) -Leaf)
    build     = [ordered]@{ tool = $null; wrapper = $false; multiModule = $false; modules = @() }
    versions  = [ordered]@{ javaDeclared = $null; javaRuntime = $null; mavenRuntime = $null; springBoot = $null }
    plugins   = [ordered]@{ jacoco = $false; jacocoCheck = $false; dependencyCheck = $false }
    sonar     = [ordered]@{ propertiesFile = $false; projectKey = $null }
    source    = [ordered]@{ mainFiles = 0; testFiles = 0; largestClasses = @(); classesWithoutTest = @() }
    results   = [ordered]@{ compiles = $null; testsRan = $false; tests = $null; failingTests = @(); coverage = $null }
    errors    = @()
    warnings  = @()
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "            PROJECT RECON               " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Save-Report {
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportFile -Encoding UTF8
    Write-Host "`nReport: $reportFile" -ForegroundColor Yellow
}

# --- Build tool ---------------------------------------------------------------
if (Test-Path "pom.xml") {
    $report.build.tool = "maven"
} elseif ((Test-Path "build.gradle") -or (Test-Path "build.gradle.kts")) {
    $report.build.tool = "gradle"
    $report.errors += "Gradle project detected - not supported yet (Maven only). No build was run."
    Write-Host "[RECON] Gradle project - not supported yet" -ForegroundColor Red
    Save-Report
    exit 2
} else {
    $report.errors += "No pom.xml or build.gradle in $(Get-Location) - run recon from the project root."
    Write-Host "[RECON] No build file found" -ForegroundColor Red
    Save-Report
    exit 2
}
$report.build.wrapper = Test-Path "mvnw.cmd"

# --- pom.xml ------------------------------------------------------------------
[xml]$pom = Get-Content "pom.xml" -Raw
function Get-PomNodes([string]$path) {
    # local-name() ignores the Maven namespace
    $xpath = ($path -split '/' | ForEach-Object { "*[local-name()='$_']" }) -join '/'
    return $pom.SelectNodes("/$xpath")
}
function Get-PomText([string]$path) {
    $node = Get-PomNodes $path | Select-Object -First 1
    if ($node) { return $node.InnerText.Trim() }
    return $null
}

$modules = @(Get-PomNodes "project/modules/module" | ForEach-Object { $_.InnerText.Trim() })
if ($modules.Count -gt 0) {
    $report.build.multiModule = $true
    $report.build.modules = $modules
    $report.warnings += "Multi-module project ($($modules.Count) modules). sdlc.ps1 reads reports from the root target/ only - metrics may be incomplete."
}

foreach ($p in @("project/properties/java.version", "project/properties/maven.compiler.release", "project/properties/maven.compiler.source")) {
    $v = Get-PomText $p
    if ($v) { $report.versions.javaDeclared = $v; break }
}
if ((Get-PomText "project/parent/artifactId") -eq "spring-boot-starter-parent") {
    $report.versions.springBoot = Get-PomText "project/parent/version"
} else {
    $bom = Get-PomNodes "project/dependencyManagement/dependencies/dependency" |
        Where-Object { $_.SelectSingleNode("*[local-name()='artifactId']").InnerText -eq "spring-boot-dependencies" } |
        Select-Object -First 1
    if ($bom) { $report.versions.springBoot = $bom.SelectSingleNode("*[local-name()='version']").InnerText.Trim() }
}

if (Test-Path (Join-Path $PSScriptRoot "use-java.ps1")) { & (Join-Path $PSScriptRoot "use-java.ps1") -Quiet }
$javaOut = (& java -version 2>&1 | ForEach-Object { "$_" }) -join "`n"
if ($javaOut -match 'version "([^"]+)"') { $report.versions.javaRuntime = $matches[1] }
if (-not (Test-Path "mvnw.cmd")) {
    $mvnOut = (& mvn -v 2>&1 | ForEach-Object { "$_" }) -join "`n"
    if ($mvnOut -match 'Apache Maven (\S+)') { $report.versions.mavenRuntime = $matches[1] }
}

$pomRaw = Get-Content "pom.xml" -Raw
$report.plugins.jacoco = $pomRaw -match "jacoco-maven-plugin"
$report.plugins.jacocoCheck = $report.plugins.jacoco -and ($pomRaw -match "<goal>\s*check\s*</goal>")
$report.plugins.dependencyCheck = $pomRaw -match "dependency-check-maven"

if (Test-Path "sonar-project.properties") {
    $report.sonar.propertiesFile = $true
    $keyLine = Get-Content "sonar-project.properties" | Where-Object { $_ -match "^\s*sonar\.projectKey\s*=" } | Select-Object -First 1
    if ($keyLine) { $report.sonar.projectKey = ($keyLine -split "=", 2)[1].Trim() }
}

# --- Source statistics --------------------------------------------------------
$mainFiles = @(Get-ChildItem -Path . -Recurse -File -Filter *.java -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]src[\\/]main[\\/]java[\\/]' })
$testFiles = @(Get-ChildItem -Path . -Recurse -File -Filter *.java -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]src[\\/]test[\\/]java[\\/]' })
$report.source.mainFiles = $mainFiles.Count
$report.source.testFiles = $testFiles.Count

$root = (Get-Location).Path
$report.source.largestClasses = @($mainFiles | ForEach-Object {
        [ordered]@{ file = $_.FullName.Substring($root.Length + 1); lines = @(Get-Content $_.FullName).Count }
    } | Sort-Object { $_.lines } -Descending | Select-Object -First $TopClasses)

$testNames = @{}
foreach ($t in $testFiles) { $testNames[$t.BaseName] = $true }
$report.source.classesWithoutTest = @($mainFiles | Where-Object {
        $n = $_.BaseName
        -not ($testNames["${n}Test"] -or $testNames["${n}Tests"] -or $testNames["${n}IT"])
    } | ForEach-Object { $_.FullName.Substring($root.Length + 1) })

Write-Host "  Build tool:   maven (wrapper: $($report.build.wrapper))" -ForegroundColor Gray
Write-Host "  Java:         declared $($report.versions.javaDeclared), runtime $($report.versions.javaRuntime)" -ForegroundColor Gray
Write-Host "  Maven:        $(if ($report.build.wrapper) { 'wrapper' } else { $report.versions.mavenRuntime })" -ForegroundColor Gray
Write-Host "  Spring Boot:  $($report.versions.springBoot)" -ForegroundColor Gray
Write-Host "  Sources:      $($mainFiles.Count) main, $($testFiles.Count) test, $($report.source.classesWithoutTest.Count) main classes without a test" -ForegroundColor Gray
Write-Host "  JaCoCo:       $($report.plugins.jacoco) (check rule: $($report.plugins.jacocoCheck))" -ForegroundColor Gray

# --- Build and tests ----------------------------------------------------------
if ($SkipBuild) {
    Save-Report
    exit 0
}

$mvn = if ($report.build.wrapper) { ".\mvnw.cmd" } else { "mvn" }
if (-not $report.build.wrapper -and -not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    $report.errors += "No mvnw.cmd in the project and no mvn on PATH - cannot build."
    Save-Report
    exit 2
}
$mvnArgs = @()
if ($MavenSettings -and (Test-Path $MavenSettings)) { $mvnArgs = @("-s", (Resolve-Path $MavenSettings).Path) }

Write-Host "`n[RECON] Compiling (main + test)..." -ForegroundColor Yellow
$out = & $mvn @mvnArgs -B clean test-compile 2>&1
$report.results.compiles = ($LASTEXITCODE -eq 0)
if (-not $report.results.compiles) {
    Write-Host "[RECON] Compilation FAILED" -ForegroundColor Red
    $report.errors += "Compilation failed:`n" + (($out | Select-Object -Last 40) -join "`n")
    Save-Report
    exit 0
}
Write-Host "[RECON] Compilation OK" -ForegroundColor Green

# failure.ignore: recon must see every failing test, not stop at the first failing module
Write-Host "[RECON] Running tests..." -ForegroundColor Yellow
$goals = @("test", "-Dmaven.test.failure.ignore=true")
if ($report.plugins.jacoco) { $goals += "org.jacoco:jacoco-maven-plugin:report" }
$out = & $mvn @mvnArgs -B @goals 2>&1
if ($LASTEXITCODE -ne 0) {
    $report.errors += "Test run did not complete:`n" + (($out | Select-Object -Last 40) -join "`n")
}

$suites = @(Get-ChildItem -Path . -Recurse -File -Filter "TEST-*.xml" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]target[\\/]surefire-reports[\\/]' })
if ($suites.Count -gt 0) {
    $report.results.testsRan = $true
    $total = 0; $failed = 0; $errorsCount = 0; $skipped = 0
    foreach ($s in $suites) {
        try {
            [xml]$x = Get-Content $s.FullName -Raw
            $total += [int]$x.testsuite.tests; $failed += [int]$x.testsuite.failures
            $errorsCount += [int]$x.testsuite.errors; $skipped += [int]$x.testsuite.skipped
            foreach ($tc in @($x.testsuite.SelectNodes("testcase"))) {
                if ($tc.SelectSingleNode("failure") -or $tc.SelectSingleNode("error")) { $report.results.failingTests += "$($tc.classname)#$($tc.name)" }
            }
        } catch {
            $report.warnings += "Could not parse $($s.Name)"
        }
    }
    $report.results.tests = [ordered]@{
        total = $total; passed = ($total - $failed - $errorsCount - $skipped)
        failed = $failed; errors = $errorsCount; skipped = $skipped
    }
    Write-Host "  Tests: $total total, $failed failed, $errorsCount errors, $skipped skipped" -ForegroundColor Gray
} else {
    Write-Host "  No test reports found" -ForegroundColor DarkYellow
}

if (Test-Path "target/site/jacoco/jacoco.xml") {
    [xml]$j = Get-Content "target/site/jacoco/jacoco.xml" -Raw
    $cov = [ordered]@{ line = $null; branch = $null }
    foreach ($c in $j.report.counter) {
        $sum = [int]$c.missed + [int]$c.covered
        if ($sum -gt 0 -and $c.type -eq "LINE") { $cov.line = [math]::Round([int]$c.covered / $sum * 100, 1) }
        if ($sum -gt 0 -and $c.type -eq "BRANCH") { $cov.branch = [math]::Round([int]$c.covered / $sum * 100, 1) }
    }
    $report.results.coverage = $cov
    Write-Host "  Coverage: $($cov.line)% lines, $($cov.branch)% branches" -ForegroundColor Gray
} elseif ($report.plugins.jacoco) {
    $report.warnings += "JaCoCo is configured but no target/site/jacoco/jacoco.xml was produced."
}

Save-Report
exit 0
