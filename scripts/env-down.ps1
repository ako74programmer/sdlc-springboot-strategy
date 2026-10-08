# Stops the local SDLC environment started by env-up.ps1: SonarQube (web + ES + CE) and MongoDB.
#
# Usage:
#   .\scripts\env-down.ps1
#   .\scripts\env-down.ps1 -SkipMongo

[CmdletBinding()]
param(
    [int]$MongoPort = 27017,
    [switch]$SkipMongo,
    [switch]$SkipSonar
)

$ErrorActionPreference = "Continue"

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
# 2. MongoDB
# ---------------------------------------------------------------
Write-Host "`n[2/3] MongoDB" -ForegroundColor Yellow
if ($SkipMongo) {
    Write-Host "    SKIPPED (-SkipMongo)" -ForegroundColor DarkGray
} else {
    Stop-ProcessTree -Processes (Get-Process -Name mongod -ErrorAction SilentlyContinue) -Label "mongod"
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
foreach ($check in @(@{ Name = "SonarQube"; Port = 9000 }, @{ Name = "SonarQube ES"; Port = 9001 }, @{ Name = "MongoDB"; Port = $MongoPort })) {
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
