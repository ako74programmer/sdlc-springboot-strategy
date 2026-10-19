# ==============================================================================
# SWITCH THE CURRENT POWERSHELL SESSION TO THE PROJECT'S JDK AND MAVEN
#   .\tools\use-java.ps1                      javaHome and mavenHome from sdlc-settings.json
#   .\tools\use-java.ps1 -JavaHome D:\Java\jdk-21 -MavenHome D:\Tools\apache-maven-3.9.16
# Environment variables are process-wide, so the switch stays for the rest of the terminal session.
# tools\sdlc.ps1 and tools\recon.ps1 call it themselves; run it before using mvn by hand.
# ==============================================================================
Param(
    [string]$JavaHome,
    [string]$MavenHome,
    [switch]$Quiet
)

$settingsFile = Join-Path (Split-Path $PSScriptRoot -Parent) "sdlc-settings.json"
$settings = if (Test-Path $settingsFile) { Get-Content $settingsFile -Raw | ConvertFrom-Json } else { $null }
if (-not $JavaHome -and $settings) { $JavaHome = $settings.javaHome }
if (-not $MavenHome -and $settings) { $MavenHome = $settings.mavenHome }

function Set-PathFirst([string]$bin) {
    $env:Path = (@($bin) + @($env:Path -split ';' | Where-Object { $_ -and $_ -ne $bin })) -join ';'
}

if (-not $JavaHome) {
    if (-not $Quiet) { Write-Host "No javaHome in sdlc-settings.json - keeping JAVA_HOME=$env:JAVA_HOME" -ForegroundColor DarkYellow }
} elseif (-not (Test-Path (Join-Path $JavaHome "bin\java.exe"))) {
    Write-Host "javaHome has no bin\java.exe: $JavaHome - keeping JAVA_HOME=$env:JAVA_HOME" -ForegroundColor Red
} else {
    $env:JAVA_HOME = $JavaHome
    Set-PathFirst (Join-Path $JavaHome "bin")
    if ($Quiet) {
        Write-Host "Java: $JavaHome" -ForegroundColor Gray
    } else {
        Write-Host "JAVA_HOME = $JavaHome" -ForegroundColor Green
        & java -version 2>&1 | ForEach-Object { "$_" }
    }
}

if (-not $MavenHome) {
    if (-not $Quiet) { Write-Host "No mavenHome in sdlc-settings.json - keeping mvn from PATH" -ForegroundColor DarkYellow }
} elseif (-not (Test-Path (Join-Path $MavenHome "bin\mvn.cmd"))) {
    Write-Host "mavenHome has no bin\mvn.cmd: $MavenHome - keeping mvn from PATH" -ForegroundColor Red
} else {
    $env:MAVEN_HOME = $MavenHome
    Set-PathFirst (Join-Path $MavenHome "bin")
    if ($Quiet) {
        Write-Host "Maven: $MavenHome" -ForegroundColor Gray
    } else {
        Write-Host "MAVEN_HOME = $MavenHome" -ForegroundColor Green
    }
}
