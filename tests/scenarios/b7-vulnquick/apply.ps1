# Adds an older library and override to test vulnfix quick (only build files changed)
Param([Parameter(Mandatory = $true)][string]$ProjectPath)

$pomFile = Join-Path $ProjectPath "pom.xml"
$pom = [IO.File]::ReadAllText($pomFile)
$nl = if ($pom.Contains("`r`n")) { "`r`n" } else { "`n" }

# Add older commons-text (CVE-2022-42889) and commons-io
$dependency = @(
    "`t`t<dependency>",
    "`t`t`t<groupId>org.apache.commons</groupId>",
    "`t`t`t<artifactId>commons-text</artifactId>",
    "`t`t`t<version>1.9</version>",
    "`t`t</dependency>"
) -join $nl

$index = $pom.IndexOf("</dependencies>")
if ($index -lt 0) { throw "No </dependencies> in $pomFile" }
$pom = $pom.Insert($index, $dependency + $nl + "`t")
[IO.File]::WriteAllText($pomFile, $pom, (New-Object System.Text.UTF8Encoding($false)))
