# ==============================================================================
# SINGLE ENTRY POINT FOR A BATTLE SCENARIO
#   greenfield -> scripts/generate-project.ps1 (unchanged behaviour)
#   any other  -> scripts/attach-project.ps1 on <projectsDir>/<Project>
#
# Usage:
#   .\scripts\start-scenario.ps1                                   (values from config/scenario-config.yaml)
#   .\scripts\start-scenario.ps1 -Scenario greenfield
#   .\scripts\start-scenario.ps1 -Scenario bugfix -Project my-legacy-app
# ==============================================================================
Param(
    [string]$Scenario,
    [string]$Project,
    [string]$ScenarioConfig = "config/scenario-config.yaml"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$scenarios = @("greenfield", "buildfix", "bugfix", "sonarfix", "vulnfix", "refactor", "feature", "tests", "migration", "review")

function Get-ScenarioValue([string]$key) {
    $file = Join-Path $repoRoot $ScenarioConfig
    if (-not (Test-Path $file)) { return "" }
    foreach ($line in Get-Content $file) {
        if ($line -match "^\s*$([regex]::Escape($key))\s*:\s*(.*)$") {
            $raw = $matches[1].Trim()
            if ($raw -match '^"([^"]*)"') { return $matches[1] }
            return ($raw -split '#')[0].Trim()
        }
    }
    return ""
}

if (-not $Scenario) { $Scenario = Get-ScenarioValue "scenarioType" }
if (-not $Scenario) { $Scenario = "greenfield" }
if (-not $Project) { $Project = Get-ScenarioValue "scenarioProject" }

if ($scenarios -notcontains $Scenario) {
    Write-Error "Unknown scenario '$Scenario'. Allowed: $($scenarios -join ', ')"
}

Write-Host "Scenario: $Scenario" -ForegroundColor Cyan

# Both scripts resolve their paths relative to the repository root
Push-Location $repoRoot
try {
    if ($Scenario -eq "greenfield") {
        & (Join-Path $PSScriptRoot "generate-project.ps1")
    } else {
        if (-not $Project) {
            Write-Error "Scenario '$Scenario' needs -Project <folder in projects/> (or scenarioProject in $ScenarioConfig)."
        }
        & (Join-Path $PSScriptRoot "attach-project.ps1") -Project $Project -Scenario $Scenario
    }
} finally {
    Pop-Location
}
