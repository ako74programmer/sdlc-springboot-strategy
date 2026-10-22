# Downgrades base project to Spring Boot 3.4.1 and Java 21 to test platform migration to Boot 4.1.1 / Java 25
Param([Parameter(Mandatory = $true)][string]$ProjectPath)

$pomFile = Join-Path $ProjectPath "pom.xml"
$pom = [IO.File]::ReadAllText($pomFile)

# Downgrade parent and Java version
$pom = $pom -replace '<version>4\.1\.1</version>', '<version>3.4.1</version>'
$pom = $pom -replace '<java\.version>25</java\.version>', '<java.version>21</java.version>'
[IO.File]::WriteAllText($pomFile, $pom, (New-Object System.Text.UTF8Encoding($false)))

# Downgrade test annotations to Spring Boot 3 syntax
$testFile = Join-Path $ProjectPath "src\test\java\com\example\shop\customer\controller\CustomerControllerTest.java"
if (Test-Path $testFile) {
    $code = [IO.File]::ReadAllText($testFile)
    $code = $code -replace 'import org\.springframework\.boot\.webmvc\.test\.autoconfigure\.WebMvcTest;', 'import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;'
    $code = $code -replace 'import org\.springframework\.test\.context\.bean\.override\.mockito\.MockitoBean;', 'import org.springframework.boot.test.mock.mockito.MockBean;'
    $code = $code -replace '@MockitoBean', '@MockBean'
    [IO.File]::WriteAllText($testFile, $code, (New-Object System.Text.UTF8Encoding($false)))
}
