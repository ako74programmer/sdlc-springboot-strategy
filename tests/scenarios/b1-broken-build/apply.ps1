# Breaks the build the way a careless upgrade does: a dependency pinned to a version that does not exist.
Param([Parameter(Mandatory = $true)][string]$ProjectPath)

$pomFile = Join-Path $ProjectPath "pom.xml"
$pom = [IO.File]::ReadAllText($pomFile)
$nl = if ($pom.Contains("`r`n")) { "`r`n" } else { "`n" }
$dependency = @(
    "`t`t<dependency>",
    "`t`t`t<groupId>org.apache.commons</groupId>",
    "`t`t`t<artifactId>commons-lang3</artifactId>",
    "`t`t`t<version>3.99.0</version>",
    "`t`t</dependency>"
) -join $nl
$index = $pom.IndexOf("</dependencies>")
if ($index -lt 0) { throw "No </dependencies> in $pomFile" }
$pom = $pom.Insert($index, $dependency + $nl + "`t")
[IO.File]::WriteAllText($pomFile, $pom, (New-Object System.Text.UTF8Encoding($false)))
