# ==============================================================================
# LOAD secrets.local.env INTO THE CURRENT PROCESS ENVIRONMENT
#   $s = & .\tools\load-secrets.ps1          returns @{ Names; Values; Previous }
# secrets.local.env is filled by the user (KEY=VALUE per line, # comments) and is never committed
# (.gitignore and .git/info/exclude). Only names are printed. Callers use Values to mask output and
# Previous to restore the environment. Agents never read this file.
# ==============================================================================
Param(
    [string]$File = (Join-Path (Split-Path $PSScriptRoot -Parent) "secrets.local.env"),
    [switch]$Quiet
)

$result = @{ Names = @(); Values = @(); Previous = @{} }
if (-not (Test-Path $File)) { return $result }

$lineNo = 0
foreach ($line in Get-Content $File) {
    $lineNo++
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.*?)\s*$') {
        Write-Host "secrets.local.env line ${lineNo}: not KEY=VALUE - skipped" -ForegroundColor DarkYellow
        continue
    }
    $name = $matches[1]
    $value = $matches[2]
    if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $matches[1] }
    if (-not $result.Previous.ContainsKey($name)) {
        $result.Previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
    $result.Names += $name
    # Very short values would mask ordinary text
    if ($value.Length -ge 4) { $result.Values += $value }
}
if (-not $Quiet -and $result.Names.Count -gt 0) {
    Write-Host "Secrets from secrets.local.env: $($result.Names -join ', ')" -ForegroundColor Gray
}
return $result
