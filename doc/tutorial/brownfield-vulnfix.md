# Tutorial: podatne zależności (Xray) - projekt `gekon/gekon-users`

Scenariusz brownfield typu `vulnfix`: orchestrator usuwa podatne zależności zgłaszane przez korporacyjny JFrog Xray (ewsi). Przenosi przy tym projekt na wersje docelowe z konfiguracji (`migrationBootVersion`, `migrationJavaVersion`) i naprawia wszystko, co po drodze znajdzie. Projekt kończy czysty: Xray 0, SonarQube 0, wszystkie testy zielone.

Potrzebujesz tylko podmienić wersje dla zadań CYB z raportu? Użyj szybszego scenariusza [`vulnquick`](brownfield-vulnquick.md) (filtr Jiry, tylko `pom.xml`, bez Sonara i planu).

## 1. Co sprawdza pipeline w scenariuszu `vulnfix`

Źródłem prawdy o podatnościach jest bramka `XrayScan`. `tools\jfrog-scan.ps1` skanuje zbudowany JAR na serwerze Xray z `jfrog-xray.properties` (`xrayUrl` z `config/project-config.yaml`, czyli ewsi). Raport korporacyjny nie jest potrzebny jako plik: te same podatności pipeline odczytuje sam.

Przepływ:

1. `-Baseline`: zapisuje podatności Xray (`xrayFindings`) i otwarte zgłoszenia Sonara.
2. `analyst`: wersje docelowe, podatności po komponentach (skąd trafiają do JAR-a, jak je naprawić), zmiany łamiące zgodność w nowych wersjach, zgłoszenia Sonara po regułach, brakujące testy.
3. Twoje decyzje, tylko gdy są potrzebne: nieunikniona zmiana zachowania albo podatność bez poprawki.
4. `planner`: `plan.md` z partiami w kolejności plik budowania -> kod produkcyjny -> testy -> zgłoszenia Sonara.
5. `developer`, `test-engineer`, `quality-fixer`: wykonują partie. `security-reviewer` wchodzi, gdy zmieniła się konfiguracja bezpieczeństwa.
6. Końcowa weryfikacja: `tools\sdlc.ps1 -CiParity`.

Kolejność poprawek w `pom.xml`:

1. Parent = `migrationBootVersion`, Java = `migrationJavaVersion`. Bez pytania, to są wersje docelowe z konfiguracji.
2. Właściwość wersji zarządzanej przez Boot (np. `<tomcat.version>`) z komentarzem o CVE.
3. Jawna wersja zależności bezpośredniej.
4. Wersja biblioteki, która zawiera podatny komponent w środku.
5. Nadpisania, które nowy parent czyni zbędnymi, są usuwane.

Bramki (wszystkie muszą być zielone):
- `XrayScan`: 0 ustaleń.
- `VulnGuard`: `pom.xml` ma wersje docelowe, testów nie mniej niż w baseline, skan Xray naprawdę wykonany (`-SkipXray` = `FAIL`).
- `SonarQube-Issues`: 0 otwartych zgłoszeń. Do tego `SonarQube` i `SonarQube-QualityGate`.
- `Regression`, `TestIntegrity`: jak w każdym scenariuszu.
- `-Baseline` nie zapisze się z `-SkipXray` ani `-SkipSonar` ani wtedy, gdy skan Xray lub analiza Sonara się nie wykonały. Powód jest w komunikacie.

Raport ma `metrics.xray.findings` i `delta.xrayFindings` (zmiana względem baseline).

## 2. Konfiguracja: `config/scenario-config.yaml`

```yaml
scenarioType: vulnfix
scenarioProject: "gekon-users"
scenarioRepoUrl: "https://gitlab.centrala.bzwbk/gekon/gekon-users.git"

migrationBootVersion: 4.1.1
migrationJavaVersion: 25

diffGuardMaxFiles: 40
diffGuardMaxLines: 1500
diffGuardMode: warn
coverageTolerance: 0.0
```

`attach-project.ps1 -Scenario vulnfix` zapisuje w `sdlc-settings.json` `migrationBootVersion`, `migrationJavaVersion`, `sonarMaxOpenIssues: 0` i JDK w wersji `migrationJavaVersion`. W `config/project-config.yaml`: `enableXray: true`, `xrayUrl`, `xrayWatches`, `mavenVersion` (jak w obrazie CI).

## 3. Kroki

### Krok 1. Terminal

W terminalu nie może być starych zmiennych `SONAR_TOKEN`, `JF_URL` ani `JF_ACCESS_TOKEN`. Token JFrog jest w `jfrog.token`, a token Sonara w `sonar-token.txt` (w katalogu głównym repozytorium). `attach-project.ps1` kopiuje oba pliki do projektu.

### Krok 2. Pobranie i podpięcie projektu

W katalogu głównym repozytorium:

```powershell
.\scripts\start-scenario.ps1
```

Skrypt klonuje gałąź domyślną do `projects\gekon-users`. Istniejący folder zostaje bez zmian, a `-Fresh` klonuje od nowa po potwierdzeniu. Inną gałąź pobierzesz przed tym krokiem: `.\scripts\fetch-project.ps1 -RepoUrl https://gitlab.centrala.bzwbk/gekon/gekon-users.git -Ref <gałąź>`. Potem `attach-project.ps1 -Scenario vulnfix` tworzy gałąź `sdlc-work`, kopiuje narzędzia i agentów, zapisuje `sdlc-settings.json` i robi rekonesans.

Kolejne zadanie na już podpiętym projekcie: `.\scripts\start-scenario.ps1 -NewTask`. Poprzednie pliki zadania trafiają do `sdlc-history\`, a narzędzia, agenci i `sdlc-settings.json` są odświeżani.

Gałąź bazowa dla `sdlc-work` (domyślnie gałąź, na której stoi projekt): `.\scripts\start-scenario.ps1 -BaseBranch feature` albo `scenarioBaseBranch: feature` w `config/scenario-config.yaml`. Skrypt pobiera `origin/feature` i od niej zakłada `sdlc-work`; istniejącej `sdlc-work` z własnymi commitami na innej bazie nie nadpisze.

### Krok 3. Środowisko

```powershell
.\scripts\env-up.ps1 -ProjectPath projects\gekon-users
```

SonarQube musi działać: bez niego baseline się nie zapisze.

### Krok 4. Okno VS Code

Otwórz `projects\gekon-users` w nowym oknie i wybierz `@sdlc-orchestrator`.

### Krok 5. Zadanie

Prompt z sekcji 4.

## 4. Prompt dla orchestratora

```
Scenariusz: vulnfix. Usuń podatne zależności zgłaszane przez JFrog Xray i doprowadź projekt do czystego stanu. Gałąź: sdlc-work.

Zasady:
- Wersje docelowe z sdlc-settings.json (migrationBootVersion, migrationJavaVersion). Kod i testy dostosuj tylko tam, gdzie wymagają tego nowe wersje.
- Podatności: najpierw parent, potem właściwość wersji z komentarzem o CVE, potem wersja zależności. Bez dublowania zależności, wykluczeń i reguł ignorowania w Xray.
- Sonar: poprawki w kodzie, bez wyciszania. Testy: nie usuwaj przypadków i nie zmieniaj oczekiwanych wartości; brakujące testy dopisz.
- Jeśli poprawka zmienia zachowanie aplikacji albo podatność nie ma poprawki, zatrzymaj się i zapytaj.

Kryteria akceptacji:
1. tools\sdlc.ps1 -CiParity bez flag -Skip* kończy się PASSED: XrayScan (0 ustaleń), VulnGuard, SonarQube-Issues (0 zgłoszeń), Regression i TestIntegrity = PASS.
2. Raport: wersje przed -> po, każdy komponent z jego CVE, zmiany w kodzie i testach z powodem, Xray i Sonar baseline -> teraz, moje decyzje.
```

Jeśli masz zadania z korporacyjnego raportu podatności, dopisz w prompcie ich klucze i CVE. Orchestrator przypisze każde do ustalenia ze skanu albo oznaczy je jako „nie ma w skanowanym JAR-ze”.

## 5. Na co patrzeć w trakcie (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Baseline bez danych Xray lub Sonara | `sdlc-baseline.json` ma `xrayFindings` i `sonarIssueKeys`; `createdAt` sprzed pierwszej zmiany |
| Wersje docelowe nie wzięte z konfiguracji | `plan.md`: pierwsza partia ustawia parent i Javę na wartości z `sdlc-settings.json` |
| Orchestrator sam edytuje `pom.xml` albo kod | log czatu: edycje tylko w delegacjach |
| Dublowanie zależności zamiast podbicia parenta lub właściwości | `git diff refs/sdlc/baseline -- pom.xml` |
| Zbędne nadpisania po zmianie parenta | `analysis.md`: lista nadpisań, którymi nowy parent już zarządza; zniknęły z `pom.xml` |
| Osłabione testy | `git diff refs/sdlc/baseline -- src/test`: asercje i oczekiwane wartości bez zmian; `TestIntegrity` = PASS |
| Wyciszanie Sonara | `Select-String -Path src -Pattern "NOSONAR|SuppressWarnings" -Recurse`; brak zmian w `sonar-project.properties` |
| „Brak poprawki” bez sprawdzenia nowszej łatki | w raporcie: najnowsza łatka sprawdzona przez `dependency:get` i ponowny skan |

Odczyt końcowy:

```powershell
cd projects\gekon-users
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status) ciParity: $($r.ciParity)"; $r.gates | Format-List
"xray: $($r.metrics.xray.findings) (delta $($r.delta.xrayFindings)); sonar: $($r.metrics.sonar.openIssues); tests: $($r.metrics.tests.total)"
@($r.errors) | ForEach-Object { "$($_.gate): $($_.summary)" }
$r.warnings
.\tools\sdlc.ps1 -CheckReport
```

Gotowe znaczy: `status: PASSED`, `ciParity: True`, wszystkie bramki `PASS` (lub `SKIPPED` dla wyłączonego OWASP), `metrics.xray.findings` = 0, `metrics.sonar.openIssues` = 0, `-CheckReport` = 0.
