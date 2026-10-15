# ==============================================================================
# SWITCH THE CURRENT POWERSHELL SESSION TO THE PROJECT'S JDK
#   .\tools\use-java.ps1                      javaHome from sdlc-settings.json
#   .\tools\use-java.ps1 -JavaHome D:\Java\jdk-21
# Environment variables are process-wide, so the switch stays for the rest of the terminal session.
# tools\sdlc.ps1 and tools\recon.ps1 call it themselves; run it before using mvn by hand.
# ==============================================================================
Param(
    [string]$JavaHome,
    [switch]$Quiet
)

$settingsFile = Join-Path (Split-Path $PSScriptRoot -Parent) "sdlc-settings.json"
if (-not $JavaHome -and (Test-Path $settingsFile)) {
    $JavaHome = (Get-Content $settingsFile -Raw | ConvertFrom-Json).javaHome
}
if (-not $JavaHome) {
    if (-not $Quiet) { Write-Host "No javaHome in sdlc-settings.json - keeping JAVA_HOME=$env:JAVA_HOME" -ForegroundColor DarkYellow }
    return
}
if (-not (Test-Path (Join-Path $JavaHome "bin\java.exe"))) {
    Write-Host "javaHome has no bin\java.exe: $JavaHome - keeping JAVA_HOME=$env:JAVA_HOME" -ForegroundColor Red
    return
}

$bin = Join-Path $JavaHome "bin"
$env:JAVA_HOME = $JavaHome
$env:Path = (@($bin) + @($env:Path -split ';' | Where-Object { $_ -and $_ -ne $bin })) -join ';'

if ($Quiet) {
    Write-Host "Java: $JavaHome" -ForegroundColor Gray
} else {
    Write-Host "JAVA_HOME = $JavaHome" -ForegroundColor Green
    & java -version 2>&1 | ForEach-Object { "$_" }
}
