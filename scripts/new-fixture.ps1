# ==============================================================================
# CREATE A TRAINING PROJECT FROM A TEST SCENARIO (tests/scenarios, see its README.md)
# Generates the fixed base (tests/scenarios/fixture-config.yaml), strips our tooling so it looks
# like downloaded code, overlays tests/scenarios/_base and tests/scenarios/<Name>, commits it as a fresh git repo.
# tests/scenarios/<Name>/expected.md (task text + answer) is NOT copied into the project.
#
# Usage:
#   .\scripts\new-fixture.ps1 -Name b2-failing-test
#   .\scripts\new-fixture.ps1 -Name b2-failing-test -ProjectsDir scratch\projects
# ==============================================================================
Param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$ProjectsDir,
    [string]$ProjectName
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot "scripts\config-loader.ps1")
$fixturesDir = Join-Path $repoRoot "tests\scenarios"
$fixtureDir = Join-Path $fixturesDir $Name

if (-not (Test-Path $fixtureDir)) {
    $available = (Get-ChildItem $fixturesDir -Directory | Where-Object Name -ne "_base").Name -join ", "
    Write-Error "Scenario '$Name' not found in tests\scenarios. Available: $available"
}

$scenarioValues = (Read-FactoryConfig (Join-Path $repoRoot "config\scenario-config.yaml")).Values
$projectValues = (Read-FactoryConfig (Join-Path $repoRoot "config\project-config.yaml")).Values

if (-not $ProjectsDir) { $ProjectsDir = Get-ConfigValue $scenarioValues "projectsDir" "" }
if (-not $ProjectsDir) { $ProjectsDir = "projects" }
if (-not $ProjectName) { $ProjectName = $Name }
$target = Join-Path (Join-Path $repoRoot $ProjectsDir) $ProjectName
if (Test-Path $target) {
    Write-Error "$target already exists - remove it yourself or pass -ProjectName."
}

$mavenSettings = Get-ConfigValue $projectValues "settingsFile" ""
$tmp = Join-Path $repoRoot ("scratch\fixture-" + [guid]::NewGuid().ToString("N").Substring(0, 8))

Push-Location $repoRoot
try {
    Write-Host "[1/4] Generating base project..." -ForegroundColor Yellow
    $genArgs = @{ ConfigFile = "tests/scenarios/fixture-config.yaml"; OutputDir = $tmp }
    if ($mavenSettings) { $genArgs.MavenSettings = $mavenSettings }
    & (Join-Path $PSScriptRoot "generate-project.ps1") @genArgs *> $null
    $src = Join-Path $tmp "shop-service"
    if (-not (Test-Path (Join-Path $src "pom.xml"))) { Write-Error "Base generation failed (no pom.xml in $src)" }

    Write-Host "[2/4] Stripping SDLC tooling (downloaded code does not have it)..." -ForegroundColor Yellow
    foreach ($item in @("tools", ".github", ".githooks", "target", "sonar-project.properties", "jfrog-xray.properties", "jfrog.token", "sonar-token.txt", "HELP.md", ".sdlc-generated")) {
        $p = Join-Path $src $item
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    }
    $pomFile = Join-Path $src "pom.xml"
    $pom = [IO.File]::ReadAllText($pomFile)
    $pom = [regex]::Replace($pom, "(?s)\s*<!-- JaCoCo Code Coverage Plugin -->.*?</plugin>", "")
    [IO.File]::WriteAllText($pomFile, $pom, (New-Object System.Text.UTF8Encoding($false)))

    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item $src $target -Recurse

    Write-Host "[3/4] Applying fixture '$Name'..." -ForegroundColor Yellow
    foreach ($overlay in @((Join-Path $fixturesDir "_base\overlay"), (Join-Path $fixtureDir "overlay"))) {
        if (Test-Path $overlay) { Copy-Item (Join-Path $overlay "*") $target -Recurse -Force }
    }
    $apply = Join-Path $fixtureDir "apply.ps1"
    if (Test-Path $apply) { & $apply -ProjectPath $target }
} finally {
    Pop-Location
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
}

Write-Host "[4/4] Initial commit..." -ForegroundColor Yellow
Push-Location $target
try {
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git init -q
    git add -A 2>$null
    git -c user.name="fixture" -c user.email="fixture@local" commit -q -m "Initial import ($Name)"
    $ErrorActionPreference = $previousEap
} finally {
    Pop-Location
}

Write-Host "`nFixture ready: $target" -ForegroundColor Green
Write-Host "Task text and acceptance criteria: tests\scenarios\$Name\expected.md (do not give the answer section to the agents)" -ForegroundColor Gray
Write-Host "Next: .\scripts\attach-project.ps1 -Project $ProjectName -ProjectsDir $ProjectsDir -Scenario <type from expected.md>" -ForegroundColor Gray
