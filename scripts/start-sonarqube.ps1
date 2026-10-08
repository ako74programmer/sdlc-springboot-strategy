# PowerShell script to start SonarQube server for the Bitwa na kody project
# ---------------------------------------------------------------
# This script launches the SonarQube Community server using the
# unpacked distribution located in the project folder.
# SonarQube runs by default on port 9000 (http://localhost:9000).
# The server is started in the foreground, so the script will keep
# running until stopped (Ctrl+C).
#
# Default credentials:
#   Login:    admin
#   Password: admin
#
# Usage:
#   pwsh -File .\scripts\start-sonarqube.ps1
#
# To stop SonarQube externally you can run:
#   Get-Process -Name java | Where-Object { $_.CommandLine -like '*sonarqube*' } | Stop-Process -Force
# ---------------------------------------------------------------

$sonarBat = "C:\Users\160246\Desktop\bitwa-na-kody\sonarqube-26.9.0.129388\bin\windows-x86-64\StartSonar.bat"

if (-not (Test-Path $sonarBat)) {
    Write-Error "SonarQube startup script not found at: $sonarBat"
    exit 1
}

Write-Host "Starting SonarQube Server..." -ForegroundColor Cyan
Write-Host "SonarQube will be available at: http://localhost:9000" -ForegroundColor Green
Write-Host "Default login/password: admin / admin" -ForegroundColor Yellow

# Start SonarQube
& $sonarBat
