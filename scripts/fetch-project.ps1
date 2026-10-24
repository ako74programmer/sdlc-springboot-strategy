# ==============================================================================
# DOWNLOAD AN EXISTING PROJECT (brownfield) INTO <projectsDir>/<Project>
# Brownfield counterpart of generate-project.ps1: only gets the code, attach-project.ps1 adds the tooling.
# An existing folder is never touched unless -Fresh is given (asks for confirmation, deletes local changes).
#
# Usage:
#   .\scripts\fetch-project.ps1 -RepoUrl https://gitlab.centrala.bzwbk/group/app.git
#   .\scripts\fetch-project.ps1 -RepoUrl <url> -Project my-app -Ref develop
#   .\scripts\fetch-project.ps1 -RepoUrl <url> -Fresh
# ==============================================================================
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
Param(
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [string]$Project,
    [string]$ProjectsDir,
    [string]$Ref,
    [string]$ScenarioConfig = "config/scenario-config.yaml",
    [switch]$Fresh
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot "scripts\config-loader.ps1")

if ($RepoUrl -match '://[^/]*@') {
    Write-Error "RepoUrl must not contain credentials. Git Credential Manager provides them."
}
if (-not $Project) { $Project = [IO.Path]::GetFileNameWithoutExtension($RepoUrl.TrimEnd('/')) }
if ($Project -notmatch '^[A-Za-z0-9._-]+$' -or $Project -match '^\.+$') {
    Write-Error "Invalid project folder name '$Project'."
}

if (-not $ProjectsDir) {
    $scenarioValues = (Read-FactoryConfig (Join-Path $repoRoot $ScenarioConfig)).Values
    $ProjectsDir = Get-ConfigValue $scenarioValues "projectsDir" "projects"
}
$projectsPath = Join-Path $repoRoot $ProjectsDir
$target = Join-Path $projectsPath $Project

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "        Fetch existing project                    " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Repository: $RepoUrl" -ForegroundColor Gray
Write-Host "Target:     $target" -ForegroundColor Gray

if (Test-Path $target) {
    if (-not $Fresh) {
        Write-Host "Folder exists - not cloning again (use -Fresh to replace it)" -ForegroundColor Gray
        return
    }
    $dirty = $false
    if (Test-Path (Join-Path $target ".git")) {
        $dirty = [bool](git -C $target status --porcelain)
    }
    $what = if ($dirty) { "$target (HAS UNCOMMITTED CHANGES)" } else { $target }
    if (-not $PSCmdlet.ShouldProcess($what, "Delete folder and clone again")) {
        Write-Host "Cancelled - folder left unchanged" -ForegroundColor DarkYellow
        return
    }
    Remove-Item $target -Recurse -Force
}

New-Item -ItemType Directory -Path $projectsPath -Force | Out-Null
$cloneArgs = @("clone")
if ($Ref) { $cloneArgs += @("--branch", $Ref) }
$cloneArgs += @($RepoUrl, $target)
git @cloneArgs
if ($LASTEXITCODE -ne 0) { Write-Error "git clone $RepoUrl failed" }

if (-not (Test-Path (Join-Path $target "pom.xml"))) {
    Write-Host "WARNING: no pom.xml in the repository root - attach-project.ps1 supports Maven projects only" -ForegroundColor DarkYellow
}
Write-Host "Cloned into $target" -ForegroundColor Green
Write-Host "Next: .\scripts\attach-project.ps1 -Project $Project -Scenario <type>" -ForegroundColor Gray
