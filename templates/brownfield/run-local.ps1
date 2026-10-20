# ==============================================================================
# START THE APPLICATION LOCALLY WITH THE SECRETS FROM secrets.local.env
#   .\tools\run-local.ps1                        mvn spring-boot:run
#   .\tools\run-local.ps1 -SpringProfile local        with a Spring profile
#   .\tools\run-local.ps1 -MavenArgs "-Dspring-boot.run.arguments=--server.port=8081"
# For the user only. Agents never start the application: it may connect to company environments.
# secrets.local.env (KEY=VALUE per line) is filled by the user and never committed.
# ==============================================================================
Param(
    [string]$SpringProfile,
    [string[]]$MavenArgs = @()
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
$secrets = $null
try {
    & (Join-Path $PSScriptRoot "use-java.ps1") -Quiet
    $secrets = & (Join-Path $PSScriptRoot "load-secrets.ps1")
    if ($secrets.Names.Count -eq 0) {
        Write-Host "No values in secrets.local.env - the application starts without them" -ForegroundColor DarkYellow
    }

    $mvnArgs = @()
    if (Test-Path "sdlc-settings.json") {
        $ms = (Get-Content "sdlc-settings.json" -Raw | ConvertFrom-Json).mavenSettings
        if ($ms -and (Test-Path $ms)) { $mvnArgs += @("-s", $ms) }
    }
    $mvnArgs += "spring-boot:run"
    if ($SpringProfile) { $mvnArgs += "-Dspring-boot.run.profiles=$SpringProfile" }
    $mvnArgs += $MavenArgs

    $mvn = if (Test-Path "mvnw.cmd") { ".\mvnw.cmd" } else { "mvn" }
    & $mvn @mvnArgs
    $code = $LASTEXITCODE
} finally {
    if ($secrets) {
        foreach ($k in $secrets.Previous.Keys) { [Environment]::SetEnvironmentVariable($k, $secrets.Previous[$k], "Process") }
    }
    Pop-Location
}
exit $code
