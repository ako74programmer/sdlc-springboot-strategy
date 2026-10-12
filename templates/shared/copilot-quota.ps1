<#
.SYNOPSIS
    GitHub Copilot premium-request credits used by one SDLC task (delta between start and end).

.DESCRIPTION
    Reads the premium_interactions quota snapshot from the endpoint the VS Code Copilot status icon uses
    (GET https://api.github.com/copilot_internal/user - undocumented, may change).
    The OAuth token is read from the local Copilot credentials file and is never printed, logged or stored.
    The delta covers the whole GitHub account: Copilot use in other windows during the task is included.
    Cost is informational: any failure is reported as Available = false and the script still exits 0.

.EXAMPLE
    .\tools\copilot-quota.ps1 -Mode start
    .\tools\copilot-quota.ps1 -Mode end -Json
#>
[CmdletBinding()]
param(
    # start = record the baseline, end = delta since start, show = current value only
    [ValidateSet('show', 'start', 'end')]
    [string]$Mode = 'show',

    [switch]$Json,

    [string]$StatePath = 'sdlc-cost.json'
)

$ErrorActionPreference = 'Stop'
$note = 'Delta of the whole GitHub account: Copilot use in other windows during the task is included.'

function Get-CopilotQuotaSnapshot {
    $appsPath = Join-Path $env:LOCALAPPDATA 'github-copilot\apps.json'
    if (-not (Test-Path $appsPath)) {
        throw "Copilot credentials not found at '$appsPath'. Sign in to Copilot in VS Code first."
    }
    $entry = (Get-Content $appsPath -Raw | ConvertFrom-Json).PSObject.Properties |
        Where-Object { $_.Value.oauth_token } |
        Select-Object -First 1
    if (-not $entry) { throw "No OAuth token found in '$appsPath'." }

    $headers = @{
        Authorization    = "token $($entry.Value.oauth_token)"
        Accept           = 'application/json'
        'Editor-Version' = 'vscode/1.100.0'
    }
    $user = Invoke-RestMethod -Uri 'https://api.github.com/copilot_internal/user' -Headers $headers -Method Get
    $premium = $user.quota_snapshots.premium_interactions
    if (-not $premium) { throw 'Response contained no premium_interactions quota snapshot.' }

    # Some models have fractional multipliers (e.g. 0.33), so credits are not whole numbers
    $used = if ($null -ne $premium.credits_used) { [double]$premium.credits_used }
            elseif ($null -ne $premium.entitlement -and $null -ne $premium.remaining) { [double]$premium.entitlement - [double]$premium.remaining }
            else { $null }

    [pscustomobject]@{
        CreditsUsed      = $used
        Entitlement      = $premium.entitlement
        Remaining        = $premium.remaining
        PercentRemaining = $(if ($null -ne $premium.percent_remaining) { [math]::Round([double]$premium.percent_remaining, 1) } else { $null })
        Unlimited        = [bool]$premium.unlimited
        ResetDate        = $user.quota_reset_date
        CapturedAt       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    }
}

function Write-Result($result) {
    if ($Json) { $result | ConvertTo-Json -Compress -Depth 4 } else { $result | Format-List }
}

try {
    $current = Get-CopilotQuotaSnapshot
} catch {
    Write-Result ([pscustomobject]@{ Mode = $Mode; Available = $false; Reason = $_.Exception.Message })
    exit 0
}

switch ($Mode) {
    'start' {
        [ordered]@{ start = $current } | ConvertTo-Json -Depth 4 | Set-Content -Path $StatePath -Encoding UTF8
        $result = [pscustomobject]@{ Mode = 'start'; Available = $true; CreditsUsed = $current.CreditsUsed; CapturedAt = $current.CapturedAt }
    }
    'end' {
        if (-not (Test-Path $StatePath)) {
            $result = [pscustomobject]@{ Mode = 'end'; Available = $false; Reason = "No baseline in '$StatePath'. Run with -Mode start first." }
            break
        }
        $start = (Get-Content $StatePath -Raw | ConvertFrom-Json).start
        $delta = if ($null -ne $start.CreditsUsed -and $null -ne $current.CreditsUsed) { [math]::Round($current.CreditsUsed - [double]$start.CreditsUsed, 2) } else { $null }
        $minutes = [math]::Round(((Get-Date $current.CapturedAt) - (Get-Date $start.CapturedAt)).TotalMinutes, 1)
        # No percentage without a finite monthly pool (unlimited plans)
        $percentOfEntitlement = if ($null -ne $delta -and -not $current.Unlimited -and [double]$current.Entitlement -gt 0) { [math]::Round(100 * $delta / [double]$current.Entitlement, 2) } else { $null }
        $result = [pscustomobject]@{
            Mode                 = 'end'
            Available            = ($null -ne $delta)
            CreditsUsed          = $delta
            PercentOfEntitlement = $percentOfEntitlement
            CreditsBefore        = $start.CreditsUsed
            CreditsAfter         = $current.CreditsUsed
            Entitlement          = $current.Entitlement
            Remaining            = $current.Remaining
            PercentRemaining     = $(if ($current.Unlimited) { $null }
                                     elseif ($null -ne $current.CreditsUsed -and [double]$current.Entitlement -gt 0) { [math]::Round(100 * ([double]$current.Entitlement - $current.CreditsUsed) / [double]$current.Entitlement, 1) }
                                     else { $current.PercentRemaining })
            Unlimited            = $current.Unlimited
            StartedAt            = $start.CapturedAt
            EndedAt              = $current.CapturedAt
            DurationMinutes      = $minutes
            Note                 = $note
        }
        [ordered]@{ start = $start; end = $current; result = $result } | ConvertTo-Json -Depth 4 | Set-Content -Path $StatePath -Encoding UTF8
    }
    'show' {
        $result = $current
    }
}

Write-Result $result
