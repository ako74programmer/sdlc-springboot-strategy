# ==============================================================================
# SINGLE ENTRY POINT FOR A BATTLE SCENARIO
#   greenfield -> scripts/generate-project.ps1 (unchanged behaviour)
#   any other  -> scripts/attach-project.ps1 on <projectsDir>/<Project>
#
# Usage:
#   .\scripts\start-scenario.ps1                                   (values from config/scenario-config.yaml)
#   .\scripts\start-scenario.ps1 -Scenario greenfield
#   .\scripts\start-scenario.ps1 -Scenario bugfix -Project my-legacy-app
#   .\scripts\start-scenario.ps1 -Scenario feature -RepoUrl https://gitlab.../group/app.git   (fetch-project.ps1 -> attach-project.ps1)
#   .\scripts\start-scenario.ps1 -Fresh                            (delete the project folder and clone again, asks first)
#   .\scripts\start-scenario.ps1 -NewTask                          (next task on an attached project: archive old task files, refresh tools)
#   .\scripts\start-scenario.ps1 -Scenario remediation -NewTask   (fix what the last review found; the review report is archived and becomes the input)
# ==============================================================================
Param(
    [string]$Scenario,
    [string]$Project,
    [string]$RepoUrl,
    [string]$ScenarioConfig = "config/scenario-config.yaml",
    [switch]$Fresh,
    [switch]$NewTask
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$scenarios = @("greenfield", "buildfix", "bugfix", "sonarfix", "vulnfix", "refactor", "feature", "tests", "migration", "review", "remediation")

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
if (-not $RepoUrl) { $RepoUrl = Get-ScenarioValue "scenarioRepoUrl" }
if (-not $Project -and $RepoUrl) { $Project = [IO.Path]::GetFileNameWithoutExtension($RepoUrl.TrimEnd('/')) }

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
        if ($RepoUrl) {
            & (Join-Path $PSScriptRoot "fetch-project.ps1") -RepoUrl $RepoUrl -Project $Project -ScenarioConfig $ScenarioConfig -Fresh:$Fresh
        }
        & (Join-Path $PSScriptRoot "attach-project.ps1") -Project $Project -Scenario $Scenario -NewTask:$NewTask
    }
} finally {
    Pop-Location
}
