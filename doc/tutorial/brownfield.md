# Tutorial: scenariusz brownfield (istniejący projekt z GitLaba)

Brownfield to praca na kodzie, który już istnieje: pobierasz projekt z GitLaba, podpinasz do niego narzędzia SDLC i dajesz agentom zadanie (np. z Jiry). Agenci kończą dopiero wtedy, gdy wszystkie bramki jakości są zielone, w tym skan JFrog Xray.

## 1. Co musi być gotowe

| Co | Jak sprawdzić |
|---|---|
| Git z dostępem do GitLaba | `git ls-remote <url repozytorium>` zwraca listę gałęzi |
| Maven i firmowy `settings.xml` | `mvn -v`; ścieżka w `config/project-config.yaml` (`maven.settingsFile`) |
| Token JFrog | zmienna `JF_ACCESS_TOKEN` albo plik `jfrog.token` w katalogu głównym repozytorium |
| Zmienne dla serwera MCP (Jira, Confluence) | `ERSTE_INTRANET_MCP_SERVER_PROJECT_ROOT`, `..._JIRA_USER`, `..._JIRA_TOKEN`, `..._CONFLUENCE_USER`, `..._CONFLUENCE_TOKEN` |
| Czysty terminal | brak starych zmiennych `SONAR_TOKEN`, `JF_URL`, `JF_ACCESS_TOKEN` z innych sesji |

Tokenów nigdy nie wklejaj do czatu ani do URL repozytorium.

## 2. Konfiguracja: `config/scenario-config.yaml`

Ustawiasz trzy rzeczy: typ scenariusza, nazwę folderu projektu i adres repozytorium.

```yaml
projectsDir: projects

# greenfield | buildfix | bugfix | sonarfix | vulnfix | refactor | feature | tests | migration | review
scenarioType: feature
# Folder name inside projectsDir (ignored for greenfield)
scenarioProject: "bff-template"
# Optional: start-scenario.ps1 runs git clone into projectsDir/scenarioProject when the folder is missing
scenarioRepoUrl: "https://gitlab.centrala.bzwbk/steard-test/bff-template.git"

maxFixIterations: 5
maxOfficialCiAttempts: 2
sameGateStopAfter: 3

diffGuardMaxFiles: 40             # 15 for fixes, a feature adds many files
diffGuardMaxLines: 1500           # 400 for fixes
diffGuardMode: warn               # warn | fail
coverageTolerance: 0.0            # allowed drop of line coverage vs baseline, in percentage points
```

Co oznaczają pola:

| Pole | Znaczenie |
|---|---|
| `scenarioType` | Rodzaj pracy. Obsługiwane przez agentów: `feature` (nowa funkcja), `bugfix` (błąd), `buildfix` (projekt się nie buduje), `sonarfix` (problemy SonarQube). |
| `scenarioProject` | Nazwa folderu w `projects/`. Pusta = nazwa z adresu repozytorium. |
| `scenarioRepoUrl` | Adres do `git clone`. Pusty = kod musi już leżeć w `projects/<scenarioProject>`. |
| `maxFixIterations` | Ile razy agenci mogą poprawiać i weryfikować, zanim się zatrzymają. |
| `sameGateStopAfter` | Po ilu porażkach tej samej bramki z rzędu agenci przerywają i zgłaszają blokadę. |
| `diffGuardMaxFiles`, `diffGuardMaxLines` | Ostrzeżenie, gdy zmiana jest większa. Dla poprawek: 15 i 400, dla nowej funkcji: ok. 40 i 1500. |
| `diffGuardMode` | `warn` = tylko ostrzeżenie, `fail` = bramka czerwona. |
| `coverageTolerance` | O ile punktów procentowych może spaść pokrycie linii względem stanu początkowego. |

Przykład dla poprawki błędu w tym samym projekcie: `scenarioType: bugfix`, `diffGuardMaxFiles: 15`, `diffGuardMaxLines: 400`.

## 3. Kroki

### Krok 1. Pobierz kod i podepnij narzędzia

W katalogu głównym repozytorium:

```powershell
.\scripts\start-scenario.ps1                      # wartości z config/scenario-config.yaml
```

Skrypt robi po kolei:
1. `fetch-project.ps1`: `git clone` do `projects/<scenarioProject>`. Jeśli folder już jest, nic nie pobiera.
2. `attach-project.ps1`: tworzy gałąź `sdlc-work` (nigdy nie pracujemy na `main`), kopiuje narzędzia (`tools/sdlc.ps1`, agenci, `.vscode/mcp.json`), dodaje pomiar pokrycia (JaCoCo) do `pom.xml`, tworzy `sdlc-settings.json` i `recon-report.json`.

Inne warianty:

```powershell
.\scripts\fetch-project.ps1 -RepoUrl <url> -Ref develop   # tylko pobranie, z gałęzi develop
.\scripts\start-scenario.ps1 -Fresh                       # od nowa, z potwierdzeniem
.\scripts\start-scenario.ps1 -Scenario bugfix -Project my-app   # bez zmiany pliku konfiguracyjnego
```

`-Fresh` usuwa folder projektu i klonuje go ponownie. Skrypt pyta o potwierdzenie i ostrzega, gdy w folderze są niezapisane zmiany. Używaj go, gdy chcesz powtórzyć test na czystym kodzie albo po zmianie szablonów (podpięty projekt ma kopię narzędzi z chwili podpięcia).

### Krok 2. Uruchom środowisko

```powershell
.\scripts\env-up.ps1 -ProjectPath projects\bff-template
```

Startuje MongoDB i SonarQube oraz zapisuje token SonarQube w projekcie. Orchestrator też uruchamia ten skrypt, ale wcześniej jest szybciej.

### Krok 3. Otwórz projekt w nowym oknie VS Code

Otwórz folder `projects\bff-template` (sam projekt, nie całe repozytorium). Tylko wtedy VS Code wczyta agentów i `.vscode/mcp.json` projektu.

### Krok 4. Uruchom serwer MCP

`Ctrl+Shift+P` > `MCP: List Servers` > `erste-intranet-mcp` > **Start Server**, zaakceptuj zaufanie. W **Show Output** Jira i Confluence mają status `enabled`.

Bez tego kroku orchestrator nie przeczyta zadania z Jiry i zatrzyma się z komunikatem, że narzędzia są niedostępne.

Folder `.vscode` bywa ukryty w Eksploratorze, bo projekt ma go w `.gitignore`. Plik i tak tam jest.

### Krok 5. Daj zadanie

W czacie wybierz agenta `@sdlc-orchestrator` i wpisz zadanie, np.:

```
zaimplementuj zadanie: https://godzilla.centrala.bzwbk:9999/browse/ACP-252
```

Dalej agenci pracują sami. Mogą zadać pytania o decyzje biznesowe, których nie ma w zadaniu (np. nazwy pól, kody błędów). Nie pytają o rzeczy techniczne, takie jak Xray.

## 4. Co robią agenci (scenariusz `feature`)

| Etap | Agent | Wynik |
|---|---|---|
| Zadanie | orchestrator | `task.md`: treść z Jiry i stron Confluence, linia `Scenario: feature` |
| Stan początkowy | orchestrator | `sdlc-baseline.json`: testy, pokrycie, problemy SonarQube przed zmianami |
| Analiza | analyst | `analysis.md`: konwencje projektu, co zmienić, czego nie ruszać |
| Plan | planner | `plan.md`: zadanie i test dla każdego kryterium akceptacji; orchestrator go sprawdza |
| Kod | developer | zmiany w `src/main` |
| Testy | test-engineer | testy w `src/test`, po jednym lub więcej na kryterium |
| Bezpieczeństwo | security-reviewer | `security-review.md` |
| Weryfikacja | orchestrator, quality-fixer | `.\tools\sdlc.ps1` aż do `PASSED`, poprawki zależności w `pom.xml` przy błędach Xray |

## 5. Jak sprawdzić wynik

W folderze projektu:

```powershell
.\tools\sdlc.ps1 -CheckReport          # czy raport opisuje obecny kod (exit 0 = tak)
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"tests: $($r.metrics.tests.passed)/$($r.metrics.tests.total) coverage: $($r.metrics.coverage.line)%"
$r.warnings
```

Gotowe znaczy:
- `status: PASSED`, pusta lista `errors`;
- `XrayScan: PASS` (bramka obowiązkowa, bez niej CI/CD nie przejdzie);
- `Regression` i `TestIntegrity`: `PASS` (nic, co działało, się nie zepsuło; testy nie zostały osłabione);
- `-CheckReport` kończy się kodem 0.

Zmiany są na gałęzi `sdlc-work`. Pliki narzędzi i raportów są wykluczone z gita (`.git/info/exclude`), więc nie trafią do commita.

## 6. Typowe problemy

| Objaw | Przyczyna i rozwiązanie |
|---|---|
| `git clone ... failed` | Brak dostępu do repozytorium albo zły URL. Sprawdź `git ls-remote <url>`. |
| `No pom.xml in ...` | Projekt nie jest projektem Maven w katalogu głównym. Obsługujemy tylko Maven. |
| `Folder exists - not cloning again` | Folder już jest. Chcesz od nowa: `-Fresh`. |
| Orchestrator: narzędzia `erste-intranet-mcp` niedostępne | Serwer MCP nie został uruchomiony w oknie projektu (krok 4). |
| `SonarQube: no ceTaskId ...` w `warnings` | Analiza SonarQube nie zapisała raportu. Sprawdź, czy SonarQube działa (`env-up.ps1`). |
| `XrayScan: FAIL` z błędem środowiska (exit code 2) | Brak tokena JFrog albo brak połączenia z serwerem. To nie jest błąd kodu. |
