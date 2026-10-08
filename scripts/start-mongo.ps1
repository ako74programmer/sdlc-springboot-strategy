# PowerShell script to start MongoDB server for the Bitwa na kody project
# ---------------------------------------------------------------
# This script launches the MongoDB server (mongod.exe) using the
# manually unpacked distribution located in the project folder.
# It uses the data directory `mongodb-data` and listens on the default
# port 27017. The server is started in the foreground, so the script
# will keep running until the process is stopped (Ctrl+C) or killed
# externally.
#
# Usage:
#   pwsh -File .\scripts\start-mongo.ps1
#
# To stop the server you can run:
#   Stop-Process -Name mongod -Force
# ---------------------------------------------------------------

$mongoExe = "C:\Users\160246\Desktop\bitwa-na-kody\mongodb-win32-x86_64-windows-8.3.8\bin\mongod.exe"
$dbPath   = "C:\Users\160246\Desktop\bitwa-na-kody\mongodb-data"
$port     = 27017

# Ensure the data directory exists
if (-not (Test-Path $dbPath)) {
    New-Item -ItemType Directory -Path $dbPath | Out-Null
}

# Start mongod with the specified parameters
& $mongoExe --dbpath $dbPath --port $port
