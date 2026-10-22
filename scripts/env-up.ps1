# Starts the whole local SDLC environment with one command:
#   MongoDB -> SonarQube -> auth token (-> optionally copied into a generated project)
#
# Usage:
#   .\scripts\env-up.ps1
#   .\scripts\env-up.ps1 -ProjectPath projects\springboot-sdlc-demo
#   .\scripts\env-up.ps1 -SkipToken

[CmdletBinding()]
param(
    [string]$SonarUrl = "http://localhost:9000",
    [string]$Database = "",
    [int]$DbPort = 0,
    [string]$DbHost = "",
    [int]$MongoPort = 27017,
    [int]$MaxWaitSeconds = 240,
    [string]$ProjectPath = "",
    [switch]$SkipMongo,
    [switch]$SkipDb,
    [switch]$SkipSonar,
    [switch]$SkipToken
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path $scriptDir -Parent
$tokenFile = Join-Path $repoRoot "sonar-token.txt"

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
if (-not $DbHost) { $DbHost = Get-ConfigValue "databaseHost" "localhost" }
if ($SkipMongo) { $SkipDb = $true }


function Test-TcpPort {
    param([string]$ComputerName = "localhost", [int]$Port)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $ok = $client.ConnectAsync($ComputerName, $Port).Wait(1000)
        $client.Close()
        return $ok
    } catch { return $false }
}

function Get-SonarStatus {
    param([string]$Url)
    try { return (Invoke-RestMethod "$Url/api/system/status" -TimeoutSec 5 -ErrorAction Stop).status }
    catch { return $null }
}

function Start-InOwnWindow {
    param([string]$ScriptPath, [string]$Title, [string]$LogPath)
    Write-Host "    launching $Title in a separate window..." -ForegroundColor Gray
    $startArgs = @{
        FilePath     = "pwsh"
        ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"")
        WindowStyle  = "Minimized"
        PassThru     = $true
    }
    # Without this the window just vanishes on a startup crash and takes the reason with it.
    if ($LogPath) {
        New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
        $startArgs.RedirectStandardOutput = $LogPath
        $startArgs.RedirectStandardError = "$LogPath.err"
    }
    return Start-Process @startArgs
}

# A freshly killed SonarQube keeps locking temp/ and the ES data dir; starting too
# soon makes the launcher die before it opens sonar.log, leaving no trace at all.
function Wait-SonarShutdown {
    param([int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $reported = $false
    while ((Get-Date) -lt $deadline) {
        $leftovers = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'sonarqube' })
        if ($leftovers.Count -eq 0 -and -not (Test-TcpPort -Port 9001)) { return $true }
        if (-not $reported) {
            Write-Host "    waiting for the previous instance to release its files..." -ForegroundColor Gray
            $reported = $true
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "          SDLC ENVIRONMENT UP           " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ---------------------------------------------------------------
# 1. Database ($Database)
# ---------------------------------------------------------------
$dbType = $Database.ToLower()
Write-Host "`n[1/3] Database: $dbType $(if ($DbPort) { "(port $DbPort)" })" -ForegroundColor Yellow

if ($SkipDb -or $dbType -in @("none", "", "h2")) {
    Write-Host "    SKIPPED (database: $(if ($dbType) { $dbType } else { 'none' }))" -ForegroundColor DarkGray
} elseif ($dbType -in @("mongodb", "mongo")) {
    if (Test-TcpPort -ComputerName $DbHost -Port $DbPort) {
        Write-Host "    MongoDB already running on ${DbHost}:${DbPort}" -ForegroundColor Green
    } else {
        Start-InOwnWindow -ScriptPath (Join-Path $scriptDir "start-mongo.ps1") -Title "MongoDB" | Out-Null
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline -and -not (Test-TcpPort -ComputerName $DbHost -Port $DbPort)) { Start-Sleep -Seconds 2 }
        if (Test-TcpPort -ComputerName $DbHost -Port $DbPort) {
            Write-Host "    MongoDB started on ${DbHost}:${DbPort}" -ForegroundColor Green
        } else {
            Write-Error "MongoDB did not open port $DbPort within 60s. Check the MongoDB window."
        }
    }
} elseif ($dbType -in @("postgresql", "postgres", "db2")) {
    if (Test-TcpPort -ComputerName $DbHost -Port $DbPort) {
        Write-Host "    $Database already running and listening on ${DbHost}:${DbPort}" -ForegroundColor Green
    } else {
        $customStart = Join-Path $scriptDir "start-$dbType.ps1"
        if (Test-Path $customStart) {
            Write-Host "    launching $customStart..." -ForegroundColor Gray
            & $customStart
        } else {
            Write-Host "    WARNING: $Database is not listening on ${DbHost}:${DbPort}." -ForegroundColor DarkYellow
            Write-Host "    Start your $Database instance (service or container) on port $DbPort before running database tests." -ForegroundColor Gray
        }
    }
} else {
    Write-Host "    Unknown database type '$Database' - skipping" -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------
# 2. SonarQube
# ---------------------------------------------------------------
Write-Host "`n[2/3] SonarQube ($SonarUrl)" -ForegroundColor Yellow
if ($SkipSonar) {
    Write-Host "    SKIPPED (-SkipSonar)" -ForegroundColor DarkGray
} else {
    $status = Get-SonarStatus -Url $SonarUrl
    if ($status -eq "UP") {
        Write-Host "    already running" -ForegroundColor Green
    } else {
        $launcher = $null
        $launcherLog = Join-Path $repoRoot "logs\sonarqube-launcher.log"
        if (-not $status) {
            if (-not (Wait-SonarShutdown)) {
                Write-Error "A previous SonarQube instance is still holding its files. Run .\scripts\env-down.ps1 and retry."
            }
            $launcher = Start-InOwnWindow -ScriptPath (Join-Path $scriptDir "start-sonarqube.ps1") -Title "SonarQube" -LogPath $launcherLog
        }
        Write-Host "    waiting for status UP (max ${MaxWaitSeconds}s)..." -ForegroundColor Gray
        $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
        while ((Get-Date) -lt $deadline) {
            $status = Get-SonarStatus -Url $SonarUrl
            if ($status -eq "UP") { break }
            if ($launcher -and $launcher.HasExited) {
                Write-Host "    launcher died (exit $($launcher.ExitCode)); last lines:" -ForegroundColor Red
                Get-Content $launcherLog -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
                Write-Error "SonarQube launcher exited before the server came up. Full log: $launcherLog"
            }
            Start-Sleep -Seconds 5
        }
        if ($status -eq "UP") {
            Write-Host "    started" -ForegroundColor Green
        } else {
            Write-Error "SonarQube is not UP after ${MaxWaitSeconds}s (last status: '$status'). Log: $launcherLog"
        }
    }
}

# ---------------------------------------------------------------
# 3. Auth token
# ---------------------------------------------------------------
Write-Host "`n[3/3] SonarQube token" -ForegroundColor Yellow
if ($SkipToken -or $SkipSonar) {
    Write-Host "    SKIPPED" -ForegroundColor DarkGray
} else {
    $tokenValid = $false
    if (Test-Path $tokenFile) {
        $existing = (Get-Content $tokenFile -Raw).Trim()
        try {
            $tokenValid = (Invoke-RestMethod "$SonarUrl/api/authentication/validate" `
                -Headers @{ Authorization = "Bearer $existing" } -TimeoutSec 10 -ErrorAction Stop).valid
        } catch { $tokenValid = $false }
    }

    if ($tokenValid) {
        Write-Host "    existing sonar-token.txt accepted by this server" -ForegroundColor Green
    } else {
        Write-Host "    no valid token - generating a new one..." -ForegroundColor Gray
        & (Join-Path $scriptDir "setup-sonar-token.ps1") -SonarUrl $SonarUrl -OutputFile $tokenFile
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tokenFile)) {
            Write-Host "    Could not generate a token automatically." -ForegroundColor Yellow
            Write-Host "    Set the admin password first, then re-run this script:" -ForegroundColor Yellow
            Write-Host '      $env:SONAR_ADMIN_PASSWORD = Read-Host "SonarQube admin password" -AsSecureString | ConvertFrom-SecureString -AsPlainText' -ForegroundColor Gray
        }
    }

    # A SONAR_TOKEN from another server always wins over the file and returns HTTP 401.
    if ($env:SONAR_TOKEN) {
        try {
            $envValid = (Invoke-RestMethod "$SonarUrl/api/authentication/validate" `
                -Headers @{ Authorization = "Bearer $env:SONAR_TOKEN" } -TimeoutSec 10 -ErrorAction Stop).valid
        } catch { $envValid = $false }
        if (-not $envValid) {
            Write-Host "    WARNING: `$env:SONAR_TOKEN is set but rejected by $SonarUrl." -ForegroundColor Red
            Write-Host "    It takes precedence over sonar-token.txt - clear it with: `$env:SONAR_TOKEN = `$null" -ForegroundColor Yellow
        }
    }

    if ($ProjectPath -and (Test-Path $ProjectPath) -and (Test-Path $tokenFile)) {
        Copy-Item $tokenFile (Join-Path $ProjectPath "sonar-token.txt") -Force
        Write-Host "    token copied to $ProjectPath" -ForegroundColor Green
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ENVIRONMENT READY                     " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
if ($dbType -notin @("none", "", "h2") -and -not $SkipDb) {
    Write-Host "  Database:  $Database (${DbHost}:${DbPort})"
} else {
    Write-Host "  Database:  none / in-memory"
}
Write-Host "  SonarQube: $SonarUrl"
Write-Host "`n  Next: cd <project> ; .\tools\sdlc.ps1"
Write-Host "  Stop:  .\scripts\env-down.ps1`n"
