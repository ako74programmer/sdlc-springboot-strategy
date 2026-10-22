# ==============================================================================
# XRAY FIX CANDIDATES - target versions for every component of the last Xray scan, in one step
#   .\tools\xray-candidates.ps1
# Reads target\xray-findings.json (written by the XrayScan gate of tools\sdlc.ps1). Per component: where it sits in the
# scanned jar (BOOT-INF/lib or embedded in another library), the lowest version that fixes every finding, and the newest
# version in the company repository - two versions-maven-plugin runs in parallel on a temporary pom (about half a minute).
# target = always the newest version in the company repository (also when it does not fix every finding - the note
# says so), plus rows for the parent of pom.xml and for every version pom.xml declares (dependency versions and
# overrides of the parent's version properties). Result: table + target\sdlc-tmp\xray-candidates.json.
# Also checks pom.xml consistency (one Java level, one version source per library family, Lombok, add-ons the main
# library contains): target\sdlc-tmp\pom-consistency.json. Changes nothing in the project.
# ==============================================================================
Param(
    [string]$Findings = "target\xray-findings.json"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Findings)) { Write-Error "No $Findings - run .\tools\sdlc.ps1 first (the XrayScan gate writes it)" }
$settings = if (Test-Path "sdlc-settings.json") { Get-Content "sdlc-settings.json" -Raw | ConvertFrom-Json } else { $null }
if (Test-Path (Join-Path $PSScriptRoot "use-java.ps1")) { & (Join-Path $PSScriptRoot "use-java.ps1") -Quiet }
$mvnSettings = @()
if ($settings -and $settings.mavenSettings -and (Test-Path $settings.mavenSettings)) { $mvnSettings = @("-s", $settings.mavenSettings) }

function ConvertTo-Ver([string]$text) {
    if ($text -match '^(\d+)\.(\d+)(?:\.(\d+))?(.*)$') {
        return [pscustomobject]@{ Major = [int]$Matches[1]; Minor = [int]$Matches[2]; Patch = $(if ($Matches[3]) { [int]$Matches[3] } else { 0 }); Text = $text }
    }
    return $null
}
function Compare-Ver($a, $b) {
    foreach ($p in "Major", "Minor", "Patch") { if ($a.$p -ne $b.$p) { return [Math]::Sign($a.$p - $b.$p) } }
    return 0
}
function Compare-Line($a, $b) { if ($a.Major -ne $b.Major) { return [Math]::Sign($a.Major - $b.Major) }; return [Math]::Sign($a.Minor - $b.Minor) }

$groups = @(Get-Content $Findings -Raw | ConvertFrom-Json) | Where-Object { $_.component } | Group-Object component
# The project's parent (e.g. spring-boot-starter-parent) is checked too: it moves to its newest version
$parent = $null
if (Test-Path "pom.xml") {
    [xml]$projectPom = Get-Content "pom.xml" -Raw
    $pp = $projectPom.SelectSingleNode("/*[local-name()='project']/*[local-name()='parent']")
    if ($pp) {
        $pg = $pp.SelectSingleNode("*[local-name()='groupId']").InnerText.Trim()
        $pa = $pp.SelectSingleNode("*[local-name()='artifactId']").InnerText.Trim()
        $pv = $pp.SelectSingleNode("*[local-name()='version']").InnerText.Trim()
        if ($pg -and $pa -and $pv) { $parent = @{ ga = "${pg}:$pa"; version = $pv } }
    }
}
# Every version pom.xml declares goes to its newest version too: dependency versions (literal or ${property})
# and overrides of the parent's version properties (tomcat.version, jackson-2-bom.version, log4j2.version ...)
$declared = New-Object System.Collections.Generic.List[object]
if ($projectPom) {
    $props = @{}
    $pn = $projectPom.SelectSingleNode("/*[local-name()='project']/*[local-name()='properties']")
    if ($pn) { foreach ($c in $pn.ChildNodes) { if ($c.NodeType -eq "Element") { $props[$c.LocalName] = $c.InnerText.Trim() } } }
    $used = @{}
    $depPath = "/*[local-name()='project']/*[local-name()='dependencies']/*[local-name()='dependency'] | /*[local-name()='project']/*[local-name()='dependencyManagement']/*[local-name()='dependencies']/*[local-name()='dependency']"
    foreach ($d in $projectPom.SelectNodes($depPath)) {
        $dv = $d.SelectSingleNode("*[local-name()='version']")
        if (-not $dv) { continue }
        $raw = $dv.InnerText.Trim()
        if ($raw -match '^\$\{(.+)\}$') {
            if (-not $props.ContainsKey($Matches[1])) { continue }
            $name = $Matches[1]; $val = $props[$name]; $via = "property $name"; $used[$name] = $true
        } else { $val = $raw; $via = "explicit version" }
        if ($val -notmatch '^\d') { continue }
        $dt = $d.SelectSingleNode("*[local-name()='type']")
        $declared.Add(@{ ga = "$($d.SelectSingleNode("*[local-name()='groupId']").InnerText.Trim()):$($d.SelectSingleNode("*[local-name()='artifactId']").InnerText.Trim())"; version = $val; type = $(if ($dt) { $dt.InnerText.Trim() } else { "" }); via = $via })
    }
    if ($parent) {
        # The parent's BOM tells which artifact a version property stands for
        $m2 = Join-Path $env:USERPROFILE ".m2\repository"
        $pgPath = ($parent.ga -split ':')[0].Replace('.', '\')
        $boms = @((Join-Path $m2 "$pgPath\$(($parent.ga -split ':')[1])\$($parent.version)\$(($parent.ga -split ':')[1])-$($parent.version).pom"),
            (Join-Path $m2 "$pgPath\spring-boot-dependencies\$($parent.version)\spring-boot-dependencies-$($parent.version).pom")) | Where-Object { Test-Path $_ }
        foreach ($bomFile in $boms) {
            [xml]$bom = Get-Content $bomFile -Raw
            foreach ($d in $bom.SelectNodes($depPath)) {
                $dv = $d.SelectSingleNode("*[local-name()='version']")
                if (-not $dv -or $dv.InnerText.Trim() -notmatch '^\$\{(.+)\}$') { continue }
                $name = $Matches[1]
                if (-not $props.ContainsKey($name) -or $used.ContainsKey($name) -or $props[$name] -notmatch '^\d') { continue }
                $used[$name] = $true
                $dt = $d.SelectSingleNode("*[local-name()='type']")
                $declared.Add(@{ ga = "$($d.SelectSingleNode("*[local-name()='groupId']").InnerText.Trim()):$($d.SelectSingleNode("*[local-name()='artifactId']").InnerText.Trim())"; version = $props[$name]; type = $(if ($dt) { $dt.InnerText.Trim() } else { "" }); via = "property $name (overrides the parent)" })
            }
        }
    }
}
if ($groups.Count -eq 0 -and -not $parent -and $declared.Count -eq 0) { Write-Host "No Xray findings in $Findings" -ForegroundColor Green; return }
$tmp = "target\sdlc-tmp\xray-candidates"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# --- Newest versions in the company repository: two runs in parallel ----------
$coords = @{}
$types = @{}
foreach ($grp in $groups) {
    $p = $grp.Name -split ':'
    $coords["$($p[0]):$($p[1])"] = $p[2]
}
foreach ($dcl in $declared) {
    if (-not $coords.ContainsKey($dcl.ga)) { $coords[$dcl.ga] = $dcl.version; if ($dcl.type) { $types[$dcl.ga] = $dcl.type } }
}
if ($parent -and -not $coords.ContainsKey($parent.ga)) { $coords[$parent.ga] = $parent.version; $types[$parent.ga] = "pom" }
$deps = ($coords.Keys | Sort-Object | ForEach-Object {
        $p = $_ -split ':'
        $type = if ($types[$_]) { "<type>$($types[$_])</type>" } else { "" }
        "<dependency><groupId>$($p[0])</groupId><artifactId>$($p[1])</artifactId><version>$($coords[$_])</version>$type</dependency>"
    }) -join "`n    "
Set-Content "$tmp\pom.xml" -Encoding UTF8 -Value @"
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>sdlc.tmp</groupId><artifactId>xray-candidates</artifactId><version>1</version><packaging>pom</packaging>
  <dependencies>
    $deps
  </dependencies>
</project>
"@
$ignore = '.*-M\d+.*,.*-RC\d*.*,.*-[Aa]lpha.*,.*-[Bb]eta.*,.*-SNAPSHOT,.*-android,.*redhat.*'
$runs = @(
    @{ Name = "patch"; Args = @("-DallowMajorUpdates=false", "-DallowMinorUpdates=false") },
    @{ Name = "latest"; Args = @() }
)
$pom = (Resolve-Path "$tmp\pom.xml").Path
$out = $runs | ForEach-Object -ThrottleLimit 2 -Parallel {
    $s = $using:mvnSettings
    $text = & mvn -B @s -f $using:pom org.codehaus.mojo:versions-maven-plugin:2.18.0:display-dependency-updates `
        "-DprocessDependencyManagement=false" "-Dmaven.version.ignore=$($using:ignore)" @($_.Args) 2>&1 | Out-String
    [pscustomobject]@{ Name = $_.Name; Ok = ($LASTEXITCODE -eq 0); Text = $text }
}
$newest = @{ patch = @{}; latest = @{} }
foreach ($o in $out) {
    Set-Content "$tmp\$($o.Name).log" $o.Text -Encoding UTF8
    if (-not $o.Ok) { Write-Error "versions-maven-plugin failed ($($o.Name)) - see $tmp\$($o.Name).log" }
    # "  group:artifact ....... 1.0 -> 1.1", a long name wraps the versions to the next line
    $pending = $null
    foreach ($line in ($o.Text -split "`r?`n")) {
        $l = $line -replace '^\[INFO\]\s*', ''
        if ($l -match '^([\w.\-]+:[\w.\-]+)\s.*?(\S+)\s+->\s+(\S+)\s*$') { $newest[$o.Name][$Matches[1]] = $Matches[3]; $pending = $null }
        elseif ($l -match '^([\w.\-]+:[\w.\-]+)\s+\.*\s*$') { $pending = $Matches[1] }
        elseif ($pending -and $l -match '^\s*(\S+)\s+->\s+(\S+)\s*$') { $newest[$o.Name][$pending] = $Matches[2]; $pending = $null }
    }
}

# --- Where each component sits in the scanned jar -----------------------------
$jar = Get-ChildItem "target\*.jar" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(original|sources|javadoc)' } |
    Sort-Object Length -Descending | Select-Object -First 1
$libs = @(); $embedded = $null
if ($jar) {
    Add-Type -AssemblyName System.IO.Compression
    $zip = [IO.Compression.ZipFile]::OpenRead($jar.FullName)
    $libs = @($zip.Entries | Where-Object { $_.FullName -like "BOOT-INF/lib/*.jar" } | ForEach-Object Name)
    $missing = @($groups | Where-Object { $p = $_.Name -split ':'; $libs -notcontains "$($p[1])-$($p[2]).jar" })
    if ($missing.Count -gt 0) {
        # Shaded or bundled copies are found by the Maven descriptor a library keeps inside its own jar
        $embedded = @{}
        foreach ($entry in @($zip.Entries | Where-Object { $_.FullName -like "BOOT-INF/lib/*.jar" })) {
            $ms = New-Object IO.MemoryStream
            $st = $entry.Open(); $st.CopyTo($ms); $st.Dispose()
            $inner = New-Object IO.Compression.ZipArchive($ms)
            foreach ($e in $inner.Entries) {
                if ($e.FullName -match '^META-INF/maven/([^/]+)/([^/]+)/pom\.properties$') {
                    $key = "$($Matches[1]):$($Matches[2])"
                    if (-not $embedded.ContainsKey($key)) { $embedded[$key] = New-Object System.Collections.Generic.List[string] }
                    $embedded[$key].Add($entry.Name)
                }
            }
            $inner.Dispose(); $ms.Dispose()
        }
    }
    $zip.Dispose()
}

# --- Target version per component ---------------------------------------------
$rows = foreach ($grp in $groups) {
    $p = $grp.Name -split ':'
    $ga = "$($p[0]):$($p[1])"; $v = $p[2]
    $cur = ConvertTo-Ver $v
    $location = if (-not $jar) { "unknown (no jar in target)" }
        elseif ($libs -contains "$($p[1])-$v.jar") { "BOOT-INF/lib" }
        else {
            $hosts = @($embedded[$ga] | Where-Object { $_ -and $_ -notlike "$($p[1])-*.jar" })
            if ($hosts.Count -gt 0) { "embedded in $($hosts -join ', ')" } else { "not in the scanned jar" }
        }
    # Lowest version that fixes every finding: same line first, else the lowest newer line that has fixes for all
    $fixes = @(foreach ($f in $grp.Group) {
            , @(@($f.fixedVersions) | ForEach-Object { [regex]::Matches("$_", '\d+\.\d+(?:\.\d+)?[\w.-]*') | ForEach-Object { ConvertTo-Ver $_.Value } } | Where-Object { $_ })
        })
    # A finding without any fixed version cannot steer the target; it is counted in the note
    $noFix = @($fixes | Where-Object { $_.Count -eq 0 }).Count
    $fixes = @($fixes | Where-Object { $_.Count -gt 0 })
    $required = $null
    if ($cur) {
        $lines = @($fixes | ForEach-Object { $_ } | Where-Object { (Compare-Line $_ $cur) -ge 0 } | Sort-Object Major, Minor)
        foreach ($line in $lines) {
            $need = $null; $ok = $true
            foreach ($fx in $fixes) {
                $inLine = @($fx | Where-Object { (Compare-Line $_ $line) -eq 0 } | Sort-Object Major, Minor, Patch)
                if ($inLine.Count -gt 0) { $r = $inLine[0] }
                elseif (@($fx | Where-Object { (Compare-Line $_ $line) -lt 0 }).Count -gt 0) { $r = [pscustomobject]@{ Major = $line.Major; Minor = $line.Minor; Patch = 0; Text = "$($line.Major).$($line.Minor).0" } }
                else { $ok = $false; break }
                if (-not $need -or (Compare-Ver $r $need) -gt 0) { $need = $r }
            }
            if ($ok -and (Compare-Ver $need $cur) -gt 0) { $required = $need; break }
        }
    }
    $patch = if ($newest.patch[$ga]) { ConvertTo-Ver $newest.patch[$ga] } else { $cur }
    $latest = if ($newest.latest[$ga]) { ConvertTo-Ver $newest.latest[$ga] } else { $cur }
    $target = $null; $experiment = $null; $note = ""
    $newer = ($latest -and $cur -and (Compare-Ver $latest $cur) -gt 0)
    # Target = always the newest version in the company repository
    if ($newer) {
        $target = $latest.Text
        if ($required -and (Compare-Ver $latest $required) -lt 0) { $note = "newest version does not fix every finding (needs $($required.Text)) - report findings before -> after" }
        elseif (-not $required) { $note = "no fixed version known to Xray - newest version, re-scan" }
        elseif ((Compare-Line $latest $cur) -ne 0) { $note = "newer line - the build and tests prove compatibility" }
    } elseif ($required) {
        $note = "no fixing version in the company repository (needs $($required.Text), newest $($latest.Text))"
    } else {
        $note = "no fixed version known to Xray, already the newest version"
    }
    if ($location -like "embedded in*") {
        $target = $null; $experiment = $null
        $note = "changes only with the containing library"
    }
    if ($noFix -gt 0) { $note = (@($note, "$noFix finding(s) without a fixed version - re-scan after the upgrade") | Where-Object { $_ }) -join "; " }
    [pscustomobject][ordered]@{
        component = $ga; version = $v; findings = $grp.Count
        cves      = @($grp.Group | ForEach-Object { @($_.cves) } | Where-Object { $_ } | Sort-Object -Unique)
        location  = $location; required = $(if ($required) { $required.Text } else { "" })
        newestPatch = $(if ($patch) { $patch.Text } else { "" }); newest = $(if ($latest) { $latest.Text } else { "" })
        target    = $target; note = $note
    }
}
$rows = @($rows)
$inFindings = @($groups | ForEach-Object { (($_.Name -split ':')[0..1]) -join ':' })
$seenDeclared = @{}
foreach ($dcl in $declared) {
    if ($inFindings -contains $dcl.ga -or $seenDeclared.ContainsKey($dcl.ga) -or ($parent -and $dcl.ga -eq $parent.ga)) { continue }
    $seenDeclared[$dcl.ga] = $true
    $dl = $newest.latest[$dcl.ga]
    $rows += [pscustomobject][ordered]@{
        component = $dcl.ga; version = $dcl.version; findings = 0; cves = @()
        location  = "pom.xml: $($dcl.via)"; required = ""; newestPatch = ""; newest = $(if ($dl) { $dl } else { $dcl.version })
        target    = $dl; note = $(if ($dl) { "newest version" } else { "already the newest version" })
    }
}
if ($parent) {
    $pl = $newest.latest[$parent.ga]
    $rows += [pscustomobject][ordered]@{
        component = $parent.ga; version = $parent.version; findings = 0; cves = @()
        location  = "parent of pom.xml"; required = ""; newestPatch = ""; newest = $(if ($pl) { $pl } else { $parent.version })
        target    = $pl; note = $(if ($pl) { "parent - newest stable version" } else { "parent - already the newest version" })
    }
}

$rows | ConvertTo-Json -Depth 4 | Set-Content "target\sdlc-tmp\xray-candidates.json" -Encoding UTF8
$rows | Format-Table component, version, findings, location, required, newest, target, note -Wrap | Out-String -Width 250 | Write-Host
Write-Host "Saved: target\sdlc-tmp\xray-candidates.json (Maven output: $tmp\patch.log, latest.log)" -ForegroundColor Gray

# --- Consistency of pom.xml: what a reviewer checks by hand ------------------
# One mechanism per version: the property the parent manages a library with, the BOM a library family comes from,
# one Java level, one Lombok version; no add-on that the main library already contains.
$issues = New-Object System.Collections.Generic.List[object]
if ($projectPom) {
    $m2 = Join-Path $env:USERPROFILE ".m2\repository"
    $bomProps = @{}
    $bomImports = New-Object System.Collections.Generic.List[object]
    $parentProps = @{}
    if ($parent) {
        $pParts = $parent.ga -split ':'
        $pDir = Join-Path $m2 ($pParts[0].Replace('.', '\'))
        $parentPom = Join-Path $pDir "$($pParts[1])\$($parent.version)\$($pParts[1])-$($parent.version).pom"
        if (Test-Path $parentPom) {
            [xml]$ppx = Get-Content $parentPom -Raw
            $ppn = $ppx.SelectSingleNode("/*[local-name()='project']/*[local-name()='properties']")
            if ($ppn) { foreach ($c in $ppn.ChildNodes) { if ($c.NodeType -eq "Element") { $parentProps[$c.LocalName] = $c.InnerText.Trim() } } }
        }
        foreach ($bomFile in @($parentPom, (Join-Path $pDir "spring-boot-dependencies\$($parent.version)\spring-boot-dependencies-$($parent.version).pom")) | Where-Object { Test-Path $_ }) {
            [xml]$bx = Get-Content $bomFile -Raw
            foreach ($d in $bx.SelectNodes($depPath)) {
                $dv = $d.SelectSingleNode("*[local-name()='version']")
                if (-not $dv -or $dv.InnerText.Trim() -notmatch '^\$\{(.+)\}$') { continue }
                $bp = $Matches[1]
                $bg = $d.SelectSingleNode("*[local-name()='groupId']").InnerText.Trim()
                $ba = $d.SelectSingleNode("*[local-name()='artifactId']").InnerText.Trim()
                $bs = $d.SelectSingleNode("*[local-name()='scope']")
                if ($bs -and $bs.InnerText.Trim() -eq "import") { $bomImports.Add(@{ g = $bg; ga = "${bg}:$ba"; prop = $bp }) }
                elseif (-not $bomProps.ContainsKey("${bg}:$ba")) { $bomProps["${bg}:$ba"] = $bp }
            }
        }
    }
    # Java: maven.compiler.* in pom.xml, but the parent compiles with its own java.version
    if (-not $props.ContainsKey("java.version")) {
        $want = @("maven.compiler.release", "maven.compiler.source", "maven.compiler.target") | Where-Object { $props.ContainsKey($_) } | ForEach-Object { $props[$_] } | Select-Object -First 1
        $pomText = Get-Content "pom.xml" -Raw
        if ($want -and ($parentProps.ContainsKey("java.version") -or $pomText -match '\$\{java\.version\}')) {
            $issues.Add([pscustomobject]@{ check = "java"; where = "properties maven.compiler.*, maven-compiler-plugin"
                problem = "pom.xml says Java $want, but the build compiles with java.version = $($parentProps['java.version']) from the parent"
                fix = "add <java.version>$want</java.version> and remove maven.compiler.source/target/release from properties" })
        }
    }
    # Own versions on libraries the parent manages with a property or through a BOM of their family
    $own = New-Object System.Collections.Generic.List[object]
    foreach ($d in $projectPom.SelectNodes($depPath)) { $own.Add(@{ node = $d; kind = "dependency" }) }
    foreach ($d in $projectPom.SelectNodes("//*[local-name()='annotationProcessorPaths']/*[local-name()='path']")) { $own.Add(@{ node = $d; kind = "annotationProcessorPaths" }) }
    foreach ($o in $own) {
        $dv = $o.node.SelectSingleNode("*[local-name()='version']")
        if (-not $dv) { continue }
        $raw = $dv.InnerText.Trim()
        $prop = if ($raw -match '^\$\{(.+)\}$') { $Matches[1] } else { $null }
        $g = $o.node.SelectSingleNode("*[local-name()='groupId']").InnerText.Trim()
        $ga = "${g}:$($o.node.SelectSingleNode("*[local-name()='artifactId']").InnerText.Trim())"
        $managedBy = $bomProps[$ga]
        $family = $null
        if (-not $managedBy) { $family = @($bomImports | Where-Object { $g -eq $_.g -or $g.StartsWith("$($_.g).") }) | Select-Object -First 1 }
        $want = if ($managedBy) { $managedBy } elseif ($family) { $family.prop } else { $null }
        if (-not $want -or $prop -eq $want) { continue }
        $via = if ($family) { "the family BOM $($family.ga)" } else { "the parent" }
        $fix = if ($o.kind -eq "annotationProcessorPaths") { "use `${$want} as its version (set <$want> to the newest version)" }
               else { "remove its own <version> and set <$want> in properties to the newest version" }
        $issues.Add([pscustomobject]@{ check = "version source"; where = "$($o.kind) $ga ($raw)"
            problem = "$via manages it with <$want>; its own version can drift from the rest of the family"; fix = $fix })
    }
    # Add-ons that the main library contains since a version (duplicate classes on the classpath)
    $hz = @($declared | Where-Object { $_.ga -eq "com.hazelcast:hazelcast" }) | Select-Object -First 1
    if ($hz -and ($declared | Where-Object { $_.ga -eq "com.hazelcast:hazelcast-kubernetes" }) -and $hz.version -match '^(\d+)' -and [int]$Matches[1] -ge 5) {
        $issues.Add([pscustomobject]@{ check = "duplicate"; where = "dependency com.hazelcast:hazelcast-kubernetes"
            problem = "hazelcast $($hz.version) contains the Kubernetes discovery; the separate plugin duplicates its classes"; fix = "remove the dependency (the build and tests prove it)" })
    }
}
$issues | ConvertTo-Json -Depth 3 | Set-Content "target\sdlc-tmp\pom-consistency.json" -Encoding UTF8
if ($issues.Count -gt 0) {
    Write-Host "pom.xml consistency - $($issues.Count) issue(s), fix them in the same change:" -ForegroundColor Yellow
    $issues | Format-Table check, where, problem, fix -Wrap | Out-String -Width 250 | Write-Host
} else {
    Write-Host "pom.xml consistency: no issues" -ForegroundColor Green
}
Write-Host "Saved: target\sdlc-tmp\pom-consistency.json" -ForegroundColor Gray
