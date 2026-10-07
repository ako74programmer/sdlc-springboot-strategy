# ==============================================================================
# SETUP SONARQUBE TOKEN
# Waits for SonarQube to be ready, then generates an authentication token.
# ==============================================================================
Param(
    [string]$SonarUrl = "http://localhost:9000",
    [string]$OutputFile = "sonar-token.txt",
    [int]$MaxWaitSeconds = 180
)

$ErrorActionPreference = "Stop"

$pair = "admin:admin"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "Basic $base64" }

# 1. Wait for SonarQube to be ready
Write-Host "Waiting for SonarQube at $SonarUrl to be ready..." -ForegroundColor Yellow
$elapsed = 0
$ready = $false

do {
    try {
        $response = Invoke-RestMethod -Uri "$SonarUrl/api/system/status" -ErrorAction Stop
        if ($response.status -eq "UP") {
            $ready = $true
            Write-Host "SonarQube is UP and ready." -ForegroundColor Green
            break
        }
        Write-Host "    Status: $($response.status) - waiting..." -ForegroundColor Gray
    } catch {
        Write-Host "    SonarQube not reachable yet ($elapsed/$MaxWaitSeconds s)..." -ForegroundColor Gray
    }
    Start-Sleep 5
    $elapsed += 5
} while ($elapsed -lt $MaxWaitSeconds)

if (-not $ready) {
    Write-Error "SonarQube did not become ready within $MaxWaitSeconds seconds. Is Docker running? Try: docker-compose up -d"
}

# 2. Revoke existing token if exists
try {
    Invoke-RestMethod -Uri "$SonarUrl/api/user_tokens/revoke?name=sdlc-token" -Method Post -Headers $headers -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Revoked existing sdlc-token (if any)." -ForegroundColor Gray
} catch {}

# 3. Generate new token
try {
    $res = Invoke-RestMethod -Uri "$SonarUrl/api/user_tokens/generate?name=sdlc-token" -Method Post -Headers $headers
    $token = $res.token
    
    Set-Content -Path $OutputFile -Value $token -Encoding UTF8
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Token generated and saved to: $OutputFile" -ForegroundColor Green
    Write-Host "  SONAR_TOKEN=$token" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can also set it as environment variable:" -ForegroundColor Yellow
    Write-Host "  `$env:SONAR_TOKEN = `"$token`"" -ForegroundColor Gray
} catch {
    Write-Error "Failed to generate SonarQube token: $_"
}
