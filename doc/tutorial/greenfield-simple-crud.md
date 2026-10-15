# Tutorial: scenariusz greenfield (nowy projekt z generatora)

Greenfield to nowy projekt Spring Boot tworzony od zera przez generator (Spring Initializr) z gotowym pipeline SDLC. Opisujesz funkcjonalność w czacie, a agenci planują, piszą kod i testy, robią przegląd bezpieczeństwa i kończą, gdy wszystkie bramki jakości są zielone, w tym skan JFrog Xray.

## 1. Co musi być gotowe

| Co | Jak sprawdzić |
|---|---|
| Dostęp do start.spring.io | generator pobiera z niego szkielet projektu |
| Maven i firmowy `settings.xml` | ścieżka w `config/project-config.yaml` (`maven.settingsFile`) |
| Token JFrog | zmienna `JF_ACCESS_TOKEN` albo plik `jfrog.token` w katalogu głównym repozytorium |
| Czysty terminal | brak starych zmiennych `SONAR_TOKEN`, `JF_URL`, `JF_ACCESS_TOKEN` z innych sesji |

Tokenów nigdy nie wklejaj do czatu.

## 2. Konfiguracja

Greenfield używa dwóch plików.

### `config/scenario-config.yaml`: rodzaj scenariusza

```yaml
projectsDir: projects

# greenfield | buildfix | bugfix | sonarfix | vulnfix | refactor | feature | tests | migration | review
scenarioType: greenfield
# Folder name inside projectsDir (ignored for greenfield)
scenarioProject: ""

maxFixIterations: 5
maxOfficialCiAttempts: 2
sameGateStopAfter: 3

diffGuardMaxFiles: 15
diffGuardMaxLines: 400
diffGuardMode: warn               # warn | fail
coverageTolerance: 0.0            # allowed drop of line coverage vs baseline, in percentage points
```

Dla greenfield znaczenie mają tylko `projectsDir` i `scenarioType: greenfield`. `scenarioProject`, `scenarioRepoUrl` i pola `diffGuard*`, `coverageTolerance` są pomijane (dotyczą istniejących projektów).

### `config/project-config.yaml`: jaki projekt wygenerować

```yaml
project:
  type: maven-project
  language: java
  bootVersion: 4.1.1
  groupId: pl.erste.sdlc
  artifactId: springboot-sdlc-demo     # nazwa folderu w projects/
  name: springboot-sdlc-demo
  packageName: pl.erste.sdlc.demo
  packaging: jar
  javaVersion: 25

dependencies:
  - web
  - data-mongodb
  - validation
  - actuator
  - lombok

maven:
  settingsFile: "C:\Users\<user>\.m2\settings.xml"

sdlc:
  enableSonarQube: true
  enableOwaspCheck: false              # baza NVD niedostępna w sieci firmowej
  sonarHostUrl: "http://localhost:9000"
  enableXray: true                     # bramka obowiązkowa
  xrayUrl: "https://ewsi.centrala.bzwbk:9999"
  xrayWatches: "XrayWatch"
  xrayInsecureTls: true
  jacocoVersion: 0.8.15
```

| Pole | Znaczenie |
|---|---|
| `artifactId` | Nazwa projektu i folderu `projects/<artifactId>`. Nowy projekt = nowa nazwa. |
| `bootVersion`, `javaVersion` | Wersje Spring Boot i Javy. |
| `dependencies` | Moduły Spring Boot (identyfikatory z start.spring.io). |
| `maven.settingsFile` | Firmowy `settings.xml` (Artifactory). |
| `enableXray` | Skan JFrog Xray. Zostaw `true`: CI/CD blokuje projekty z podatnościami. |

## 3. Kroki

### Krok 1. Wygeneruj projekt

W katalogu głównym repozytorium:

```powershell
.\scripts\start-scenario.ps1                         # wartości z config/scenario-config.yaml
.\scripts\start-scenario.ps1 -Scenario greenfield    # bez zmiany pliku konfiguracyjnego
```

Generator tworzy `projects/<artifactId>` z narzędziami (`tools/sdlc.ps1`, `tools/jfrog-scan.ps1`), agentami (`.github/agents`), pipeline CI (`.github/workflows/sdlc.yml`), konfiguracją SonarQube i pomiarem pokrycia (JaCoCo, próg 60%). Na końcu sprawdza, czy projekt się kompiluje.

Każdy projekt jest od początku pod kontrolą wersji:
- `main`: pierwszy commit z wygenerowanym projektem (stan wyjściowy);
- `sdlc-work`: gałąź robocza, na której pracują agenci. Nigdy nie pracujemy na `main`.

Pliki robocze (`sdlc-report.json`, `plan.md`, `security-review.md`, `sdlc-run.log`) i tokeny nie trafiają do commitów. Jeśli pierwszy commit się nie uda (brak `git config user.name` / `user.email`), generator poda polecenia do wykonania ręcznie.

Ponowne uruchomienie **usuwa cały folder projektu** i generuje go od nowa. Generator odmówi, jeśli w folderze jest praca w gicie: niezapisane zmiany albo commity na `sdlc-work`, których nie ma na `main`. Wtedy wypchnij lub zapisz pracę, zmień `artifactId` albo użyj `-Force` (usuwa wszystko). Folderu, którego nie utworzył generator (brak pliku `.sdlc-generated`), skrypt też nie ruszy bez `-Force`.

Do sprawdzenia samego generatora użyj osobnego katalogu i usuń go po teście:

```powershell
.\scripts\generate-project.ps1 -OutputDir scratch\gen
```

### Krok 2. Uruchom środowisko

```powershell
.\scripts\env-up.ps1 -ProjectPath projects\springboot-sdlc-demo
```

Startuje MongoDB i SonarQube oraz zapisuje token SonarQube w projekcie.

### Krok 3. Otwórz projekt w nowym oknie VS Code

Otwórz folder `projects\springboot-sdlc-demo` (sam projekt, nie całe repozytorium). Tylko wtedy VS Code wczyta agentów projektu.

### Krok 4. Opisz funkcjonalność

W czacie wybierz agenta `@sdlc-orchestrator` i wklej wymaganie jako tekst. Greenfield nie ma połączenia z Jirą, więc link do zgłoszenia nie wystarczy: skopiuj jego treść i kryteria akceptacji.

Przykład:

```
Zaimplementuj REST API do zarządzania klientami (Customer):
- pola: id, firstName, lastName, email (unikalny), createdAt
- endpointy: POST /api/customers, GET /api/customers/{id}, GET /api/customers, PUT /api/customers/{id}, DELETE /api/customers/{id}
- walidacja: imię i nazwisko wymagane, poprawny email
- błędy: 404 dla brakującego klienta, 409 dla zajętego emaila, 400 dla błędnych danych
- dane w MongoDB
```

Im dokładniejsze kryteria (pola, kody błędów, reguły), tym mniej agenci muszą zgadywać.

## 4. Co robią agenci

| Etap | Agent | Wynik |
|---|---|---|
| Plan | planner | `plan.md`: pakiety, warstwy (Controller, Service, Repository), DTO, walidacja, plan testów |
| Kod | developer | zmiany w `src/main` |
| Testy | test-engineer | testy jednostkowe, warstwy web i bazy danych, integracyjne |
| Bezpieczeństwo | security-reviewer | `security-review.md` |
| Weryfikacja | orchestrator, quality-fixer | `.\tools\sdlc.ps1` aż do `PASSED`; najwyżej `maxFixIterations` poprawek |

Bramki `sdlc.ps1` po kolei: Compilation, Tests (pokrycie min. 60%), VulnerabilityCheck (tylko z OWASP), XrayScan, SonarQube, SonarQube-QualityGate.

## 5. Jak sprawdzić wynik

W folderze projektu:

```powershell
.\tools\sdlc.ps1 -CheckReport          # czy raport opisuje obecny kod (exit 0 = tak)
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"tests: $($r.metrics.tests.passed)/$($r.metrics.tests.total) coverage: $($r.metrics.coverage.line)%"
$r.warnings
git log --oneline main..sdlc-work     # zmiany agentów względem wygenerowanego projektu
```

Gotowe znaczy:
- `status: PASSED`, pusta lista `errors`;
- `XrayScan: PASS` (bramka obowiązkowa, bez niej CI/CD nie przejdzie);
- `SonarQube-QualityGate: PASS`;
- `-CheckReport` kończy się kodem 0;
- brak `@Disabled`, `@SuppressWarnings` i `NOSONAR` w kodzie: `Select-String -Path src -Recurse -Pattern "SuppressWarnings|NOSONAR|@Disabled"`.

Kod jest na gałęzi `sdlc-work`. Aby wypchnąć go do GitLaba, dodaj zdalne repozytorium (`git remote add origin <url>`) i wypchnij obie gałęzie. Hook pre-commit (kompilacja i testy przed każdym commitem) włączysz przez `.\tools\enable-hooks.ps1`.

### Koszt zadania

Orchestrator na starcie zapisuje stan licznika zapytań premium Copilota (`.\tools\copilot-quota.ps1 -Mode start`), a na końcu podaje w raporcie sekcję **Cost**: zużyte kredyty, czas trwania i liczbę przebiegów `sdlc.ps1`. Dane zostają w `sdlc-cost.json`.

Licznik obejmuje całe konto GitHub: jeśli w tym czasie używasz Copilota w innym oknie, to też się wliczy. Do wiarygodnego pomiaru nie pracuj równolegle w innych czatach.

## 6. Typowe problemy

| Objaw | Przyczyna i rozwiązanie |
|---|---|
| `... exists and was not created by this generator` | Folder o tej nazwie już jest i nie pochodzi z generatora. Zmień `artifactId` albo użyj `-Force` (usuwa folder). |
| `... has work in git` | W projekcie jest praca agentów (zmiany albo commity na `sdlc-work`). Generator jej nie usunie. Zapisz ją, zmień `artifactId` albo użyj `-Force`. |
| `initial commit failed` | Brak tożsamości gita. Ustaw `git config --global user.name` i `user.email`, potem wykonaj polecenia podane przez generator. |
| `Smoke test FAILED` | Wygenerowany projekt się nie kompiluje. Sprawdź `bootVersion`, `javaVersion` i dostęp do Artifactory. |
| SonarQube: token odrzucony (401) | W terminalu został stary `SONAR_TOKEN`. Usuń go (`$env:SONAR_TOKEN = $null`) i uruchom `env-up.ps1` ponownie. |
| `XrayScan: FAIL` z błędem środowiska (exit code 2) | Brak tokena JFrog albo brak połączenia z serwerem. To nie jest błąd kodu. |
| Orchestrator prosi o treść zadania z Jiry | Greenfield nie czyta Jiry. Wklej treść zgłoszenia do czatu. |

Zatrzymanie środowiska: `.\scripts\env-down.ps1`.
