# Shared configuration loader for the SDLC factory.
# Reads a small, dependency-free YAML subset used by the factory and merges an
# optional <name>.local.yaml file over the base configuration.

function ConvertTo-ConfigScalar([string]$raw) {
    $value = ($raw -split '(?<!["''])#', 2)[0].Trim()
    if ($value -match '^"(.*)"$') { return $matches[1] }
    if ($value -match "^'(.*)'$") { return $matches[1] }
    return $value
}

function Read-ConfigFile([string]$File) {
    $values = @{}
    if (-not $File -or -not (Test-Path $File)) { return $values }
    $sections = @()
    foreach ($line in Get-Content $File) {
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#') -or $line.TrimStart().StartsWith('-')) { continue }
        if ($line -notmatch '^(\s*)([A-Za-z][\w-]*)\s*:\s*(.*)$') { continue }
        $indent = $matches[1].Length
        $key = $matches[2]
        $raw = $matches[3].Trim()
        while ($sections.Count -gt 0 -and $sections[$sections.Count - 1].Indent -ge $indent) {
            $sections = @($sections | Select-Object -First ($sections.Count - 1))
        }
        if (-not $raw) {
            $sections += [pscustomobject]@{ Indent = $indent; Key = $key }
            continue
        }
        $prefix = if ($sections.Count) { (($sections | ForEach-Object Key) -join '.') + '.' } else { '' }
        $value = ConvertTo-ConfigScalar $raw
        $values["$prefix$key"] = $value
        # Keep the leaf alias for compatibility with the original flat parser.
        if (-not $values.ContainsKey($key)) { $values[$key] = $value }
    }
    return $values
}

function Get-LocalConfigPath([string]$BaseFile) {
    if (-not $BaseFile) { return $null }
    $full = [IO.Path]::GetFullPath($BaseFile)
    $dir = [IO.Path]::GetDirectoryName($full)
    $name = [IO.Path]::GetFileNameWithoutExtension($full)
    $ext = [IO.Path]::GetExtension($full)
    return (Join-Path $dir "$name.local$ext")
}

function Read-FactoryConfig([string]$BaseFile, [string]$LocalFile = '') {
    $base = Read-ConfigFile $BaseFile
    if (-not $LocalFile) { $LocalFile = Get-LocalConfigPath $BaseFile }
    $local = Read-ConfigFile $LocalFile
    foreach ($key in $local.Keys) { $base[$key] = $local[$key] }
    return [pscustomobject]@{
        Values = $base
        BaseFile = $BaseFile
        LocalFile = $LocalFile
        LocalLoaded = [bool]($LocalFile -and (Test-Path $LocalFile))
    }
}

function Get-ConfigValue([hashtable]$Values, [string]$Key, [string]$Default = '') {
    if ($Values.ContainsKey($Key) -and $null -ne $Values[$Key] -and "$($Values[$Key])" -ne '') { return "$($Values[$Key])" }
    return $Default
}
