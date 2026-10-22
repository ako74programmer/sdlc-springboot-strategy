# Stops the local SDLC environment started by env-up.ps1: SonarQube (web + ES + CE) and MongoDB.
#
# Usage:
#   .\scripts\env-down.ps1
#   .\scripts\env-down.ps1 -SkipMongo

[CmdletBinding()]
param(
    [string]$Database = "",
    [int]$DbPort = 0,
    [int]$MongoPort = 27017,
    [switch]$SkipMongo,
    [switch]$SkipDb,
    [switch]$SkipSonar
)

$ErrorActionPreference = "Continue"
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path $scriptDir -Parent

function Get-ConfigValue([string]$key, [string]$default = "") {
    $cfgFile = Join-Path $repoRoot "config\project-config.yaml"
    if (Test-Path $cfgFile) {
        foreach ($line in Get-Content $cfgFile) {
            if ($line -match "^\s*$([regex]::Escape($key))\s*:\s*(.*)$") {
                return ($matches[1] -split '#')[0].Trim().Trim('"').Trim("'")
            }
        }
    }
    return $default
}

$cfgDb = Get-ConfigValue "databaseType" "mongodb"
if (-not $Database) { $Database = $cfgDb }
if (-not $DbPort -or $DbPort -eq 0) {
    if ($Database.ToLower() -eq $cfgDb.ToLower()) {
        $cfgPort = Get-ConfigValue "databasePort" ""
        if ($cfgPort -match '^\d+$') { $DbPort = [int]$cfgPort }
    }
    if (-not $DbPort -or $DbPort -eq 0) {
        $DbPort = switch ($Database.ToLower()) {
            "mongodb"    { 27017 }
            "mongo"      { 27017 }
            "postgresql" { 5432 }
            "postgres"   { 5432 }
            "db2"        { 50000 }
            default      { 0 }
        }
    }
}
if ($SkipMongo) { $SkipDb = $true }


function Stop-ProcessTree {
    param([System.Diagnostics.Process[]]$Processes, [string]$Label)
    if (-not $Processes) {
        Write-Host "    not running" -ForegroundColor DarkGray
        return
    }
    foreach ($p in $Processes) {
        try {
            Write-Host "    stopping $Label PID $($p.Id)..." -ForegroundColor Gray
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
        } catch {
            Write-Host "    could not stop PID $($p.Id): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "         SDLC ENVIRONMENT DOWN          " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ---------------------------------------------------------------
# 1. SonarQube - web, compute engine and the bundled Elasticsearch
# ---------------------------------------------------------------
Write-Host "`n[1/3] SonarQube" -ForegroundColor Yellow
if ($SkipSonar) {
    Write-Host "    SKIPPED (-SkipSonar)" -ForegroundColor DarkGray
} else {
    $sonarPids = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'sonarqube' } |
        Select-Object -ExpandProperty ProcessId
    $sonarProcs = $sonarPids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
    Stop-ProcessTree -Processes $sonarProcs -Label "SonarQube java"

    # StartSonar.bat itself runs in a cmd host that survives the java kill
    $batHosts = Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'StartSonar' } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if ($batHosts) { Stop-ProcessTree -Processes $batHosts -Label "StartSonar.bat host" }
}

# ---------------------------------------------------------------
# 2. Database
# ---------------------------------------------------------------
$dbLabel = if ($Database) { $Database } else { "none" }
Write-Host "`n[2/3] Database ($dbLabel)" -ForegroundColor Yellow
if ($SkipDb -or $Database -in @('none', '', 'h2')) {
    Write-Host "    SKIPPED (no database managed or -SkipDb)" -ForegroundColor DarkGray
} elseif ($Database -in @('mongodb', 'mongo')) {
    Stop-ProcessTree -Processes (Get-Process -Name mongod -ErrorAction SilentlyContinue) -Label "mongod"
} else {
    Write-Host "    External database '$Database' is not stopped automatically by this script." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------
# 3. Verify ports are released
# ---------------------------------------------------------------
Write-Host "`n[3/3] Verification" -ForegroundColor Yellow

function Test-PortOpen {
    param([int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    $open = $false
    try { $open = $client.ConnectAsync("localhost", $Port).Wait(1000) } catch { }
    $client.Close()
    return $open
}

# env-up must not start before the ports and file locks are actually released.
$checks = [System.Collections.Generic.List[object]]::new()
if (-not $SkipSonar) {
    $checks.Add(@{ Name = "SonarQube"; Port = 9000 })
    $checks.Add(@{ Name = "SonarQube ES"; Port = 9001 })
}
if (-not $SkipDb -and $Database -in @('mongodb', 'mongo') -and $DbPort -gt 0) {
    $checks.Add(@{ Name = "MongoDB"; Port = $DbPort })
}

foreach ($check in $checks) {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and (Test-PortOpen -Port $check.Port)) { Start-Sleep -Seconds 2 }
    if (Test-PortOpen -Port $check.Port) {
        Write-Host "    $($check.Name) still listening on $($check.Port)" -ForegroundColor Yellow
    } else {
        Write-Host "    $($check.Name) port $($check.Port) free" -ForegroundColor Green
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ENVIRONMENT STOPPED                   " -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
