# ==============================================================================
# JFROG XRAY SCAN (gate helper, run from the project root)
# Scans the packaged jar. Zero tolerance: any violation or vulnerability => exit 1.
# Findings are written to target/xray-findings.json for sdlc.ps1 / the quality-fixer agent.
# Token: $env:JF_ACCESS_TOKEN or file 'jfrog.token' (never on the command line).
# ==============================================================================
Param(
    [string]$ConfigFile = "jfrog-xray.properties",   # url, watches, insecureTls
    [string]$TokenFile = "jfrog.token",
    [string]$ServerId = "sdlc-xray",
    [switch]$SkipConfig                               # use the jf server already configured (e.g. setup-jfrog-cli in CI)
)

# Continue: jf writes logs to stderr; exit codes are checked explicitly
$ErrorActionPreference = "Continue"

function Get-XrayProperty {
    param([string]$Name, [string]$Default = "")
    if (-not (Test-Path $ConfigFile)) { return $Default }
    $pattern = "^\s*$([regex]::Escape($Name))\s*=\s*(.+)$"
    foreach ($line in (Get-Content $ConfigFile)) {
        if ($line -match $pattern) { return $matches[1].Trim() }
    }
    return $Default
}

function Fail([string]$Message) {
    Write-Host "    ERROR: $Message" -ForegroundColor Red
    exit 2
}

$url         = Get-XrayProperty "url"
$watches     = Get-XrayProperty "watches"
$insecureTls = (Get-XrayProperty "insecureTls" "false") -eq "true"

# 1. Locate or install jf (Windows user-level install, no admin rights)
$jf = (Get-Command jf -ErrorAction SilentlyContinue).Source
if (-not $jf -and $IsLinux -ne $true -and $IsMacOS -ne $true) {
    $jfDir = Join-Path $env:LOCALAPPDATA "jfrog-cli"
    $jf = Join-Path $jfDir "jf.exe"
    if (-not (Test-Path $jf)) {
        Write-Host "    Installing JFrog CLI to $jfDir ..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $jfDir | Out-Null
        Invoke-WebRequest -Uri "https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/[RELEASE]/jfrog-cli-windows-amd64/jf.exe" -OutFile $jf -UseBasicParsing -ErrorAction Stop
    }
}
if (-not $jf) { Fail "JFrog CLI (jf) not found in PATH." }

# 2. Register the Xray server (token piped via stdin)
$common = @()
if (-not $SkipConfig) {
    if (-not $url) { Fail "Missing 'url' in $ConfigFile." }
    $token = $env:JF_ACCESS_TOKEN
    if (-not $token -and (Test-Path $TokenFile)) { $token = (Get-Content $TokenFile -Raw).Trim() }
    if (-not $token) { Fail "No JFrog token. Set JF_ACCESS_TOKEN or create $TokenFile." }

    $cfg = @("config", "add", $ServerId, "--url=$($url.TrimEnd('/'))", "--access-token-stdin", "--interactive=false", "--overwrite")
    if ($insecureTls) { $cfg += "--insecure-tls=true" }
    $token | & $jf @cfg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "jf config add failed." }
    $common += "--server-id=$ServerId"
}
if ($insecureTls) { $common += "--insecure-tls=true" }
if ($watches)     { $common += "--watches=$watches" }

# 3. Find the jar produced by 'mvnw verify'
$jar = Get-ChildItem "target" -Filter "*.jar" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*.original" -and $_.Name -notlike "*-plain.jar" } | Select-Object -First 1
if (-not $jar) { Fail "No packaged jar in target/. Run '.\mvnw.cmd verify' first." }

# 4. Scan (stdout = JSON, logs go to stderr); --fail=false because the verdict is decided below
Write-Host "    Scanning $($jar.Name)" -ForegroundColor Gray
$raw = & $jf scan $jar.FullName @common --fail=false --format=json | Out-String
if ($LASTEXITCODE -ne 0) { Fail "jf scan failed (exit code $LASTEXITCODE)." }
Set-Content -Path "target/xray-report.json" -Value $raw -Encoding UTF8

# 5. Flatten violations + vulnerabilities into one list
$result = $raw | ConvertFrom-Json
$findings = @()
foreach ($item in @(@($result.violations) + @($result.vulnerabilities))) {
    if (-not $item) { continue }
    foreach ($component in $item.components.PSObject.Properties) {
        $findings += [pscustomobject]@{
            severity      = $item.severity
            type          = $item.type
            component     = $component.Name -replace "^gav://", ""
            cves          = @($item.cves | ForEach-Object { $_.cve } | Where-Object { $_ })
            issueId       = $item.issue_id
            fixedVersions = @($component.Value.fixed_versions | Where-Object { $_ })
            summary       = (($item.summary -split "`n")[0]).Trim() | ForEach-Object { if ($_.Length -gt 200) { $_.Substring(0, 200) + "..." } else { $_ } }
        }
    }
}

ConvertTo-Json -InputObject @($findings) -Depth 4 | Set-Content -Path "target/xray-findings.json" -Encoding UTF8

if ($findings.Count -eq 0) {
    Write-Host "    No Xray findings." -ForegroundColor Green
    exit 0
}

Write-Host "    Xray findings: $($findings.Count)" -ForegroundColor Red
foreach ($f in ($findings | Sort-Object { @("Critical", "High", "Medium", "Low", "Unknown").IndexOf($_.severity) })) {
    $fix = if ($f.fixedVersions.Count) { $f.fixedVersions -join " " } else { "no fix available" }
    Write-Host "    [$($f.severity)] $($f.component) $($f.cves -join ',') - fix: $fix" -ForegroundColor Red
}
exit 1
