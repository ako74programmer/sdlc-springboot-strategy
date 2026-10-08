# ==============================================================================
# SETUP SONARQUBE TOKEN
# Waits for SonarQube to be ready, then generates an authentication token.
# ==============================================================================
Param(
    [string]$SonarUrl = "http://localhost:9000",
    [string]$OutputFile = "sonar-token.txt",
    [int]$MaxWaitSeconds = 180,
    [string]$AdminUser = $(if ($env:SONAR_ADMIN_USER) { $env:SONAR_ADMIN_USER } else { "admin" }),
    [string]$AdminPassword = $(if ($env:SONAR_ADMIN_PASSWORD) { $env:SONAR_ADMIN_PASSWORD } else { "admin" }),
    [string]$TokenName = "sdlc-token"
)

$ErrorActionPreference = "Stop"

$pair = "${AdminUser}:${AdminPassword}"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
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
    Write-Error "SonarQube did not become ready within $MaxWaitSeconds seconds. Start it first: .\scripts\start-sonarqube.ps1"
}

# 2. Verify admin credentials before attempting anything else
$credentialsValid = $false
try {
    $validation = Invoke-RestMethod -Uri "$SonarUrl/api/authentication/validate" -Headers $headers -ErrorAction Stop
    $credentialsValid = [bool]$validation.valid
} catch {
    $credentialsValid = $false
}

if (-not $credentialsValid) {
    Write-Host ""
    Write-Host "SonarQube rejected the credentials for user '$AdminUser'." -ForegroundColor Red
    Write-Host "SonarQube forces a password change on the first login, so 'admin/admin' stops working afterwards." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option A - provide the real admin password (type it yourself, do not paste it into chat):" -ForegroundColor Yellow
    Write-Host '    $env:SONAR_ADMIN_PASSWORD = Read-Host "SonarQube admin password" -AsSecureString | ConvertFrom-SecureString -AsPlainText' -ForegroundColor Gray
    Write-Host "    .\scripts\setup-sonar-token.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Option B - create the token manually in the UI ($SonarUrl > My Account > Security)," -ForegroundColor Yellow
    Write-Host "           then save it:" -ForegroundColor Yellow
    Write-Host "    Set-Content $OutputFile '<token>' -NoNewline" -ForegroundColor Gray
    Write-Error "Cannot generate a SonarQube token without valid admin credentials."
}

# 3. Revoke existing token if exists
try {
    Invoke-RestMethod -Uri "$SonarUrl/api/user_tokens/revoke?name=$TokenName" -Method Post -Headers $headers -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Revoked existing $TokenName (if any)." -ForegroundColor Gray
} catch {}

# 4. Generate new token
try {
    $res = Invoke-RestMethod -Uri "$SonarUrl/api/user_tokens/generate?name=$TokenName" -Method Post -Headers $headers
    $token = $res.token
    
    Set-Content -Path $OutputFile -Value $token -Encoding UTF8 -NoNewline
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Token generated and saved to: $OutputFile" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "A SONAR_TOKEN environment variable (if set) takes precedence over this file" -ForegroundColor Yellow
    Write-Host "and a token from another server will always fail with HTTP 401. Clear it with:" -ForegroundColor Yellow
    Write-Host '    $env:SONAR_TOKEN = $null' -ForegroundColor Gray
    Write-Host "...or point it at the new token:" -ForegroundColor Yellow
    Write-Host "    `$env:SONAR_TOKEN = (Get-Content $OutputFile -Raw).Trim()" -ForegroundColor Gray
} catch {
    Write-Error "Failed to generate SonarQube token: $_"
}
