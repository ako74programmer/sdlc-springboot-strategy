# Tutorial: szybka poprawka podatności z filtra Jiry - scenariusz `vulnquick`

Scenariusz brownfield typu `vulnquick`: orchestrator czyta zadania CYB z filtra Jiry, sprawdza je skanem Xray i podmienia numery wersji w `pom.xml`. Bez analizy, planu, SonarQube, nowych testów i zmian w kodzie. Zajmuje kilka minut plus dwa lub trzy buildy.

Kiedy który scenariusz:

| | `vulnquick` | [`vulnfix`](brownfield-vulnfix.md) |
|---|---|---|
| Wejście | filtr Jiry (zadania CYB) | skan Xray + wersje docelowe z konfiguracji |
| Zmienia | tylko `pom.xml` (i `.mvn/`) | `pom.xml`, kod, testy |
| SonarQube | nie | do 0 zgłoszeń |
| Agenci | orchestrator + developer | analyst, planner, developer, test-engineer, quality-fixer |
| Pytania do użytkownika | żadnych, wszystko w raporcie | decyzje przy zmianie zachowania i braku poprawki |
| Gdy poprawka wymaga zmiany kodu | status `needs vulnfix` | naprawia |

## 1. Dlaczego nie samo podmienienie wersji z raportu

Raport korporacyjny mówi, co naprawić, ale nie mówi, czy poprawka zadziała. Przebieg `vulnfix` na gekon-users (2026-10-22) pokazał trzy przypadki, które `vulnquick` rozpoznaje:

1. **Zadanie już naprawione w kodzie.** Skan korporacyjny widział stary obraz (`BOOT-INF/lib/jackson-core-2.21.2.jar`), a kod ma już 2.21.8. Status `already fixed in code`: zadanie zamknie się po wdrożeniu.
2. **Komponent zaszyty w innej bibliotece.** `jackson-core` 2.19.2 siedzi w `hazelcast-5.6.0.jar`. Nie da się go podbić w `pom.xml`; zmienia się tylko z nowszym `hazelcast`. Status `embedded in hazelcast, no fixed release in the repository`.
3. **Nowsza wersja gorsza od starej.** `hazelcast` 5.7.0 usuwa 2 Critical, ale wnosi zaszyte kopie Jacksona: 45 ustaleń zamiast 14. Taki eksperyment orchestrator cofa.

Dlatego `vulnquick` zawsze robi skan Xray przed zmianą i po niej i naprawia wszystko, co Xray znajdzie, także poza filtrem. Wersje docelowe dla wszystkich komponentów daje jedno polecenie `.\tools\xray-candidates.ps1` (ok. 15 s): miejsce komponentu w JAR-ze (`BOOT-INF/lib` albo zaszyty w innej bibliotece), wersję naprawczą i najnowszą wersję w ewsi. Cel to zawsze **najnowsza wersja w ewsi**: dla komponentów ze skanu, dla parenta (`spring-boot-starter-parent`) i dla każdej wersji zapisanej w `pom.xml` (właściwości `*.version`, nadpisania wersji z parenta, jawne `<version>`), także bez ustaleń Xray. Również dla bibliotek, których najnowsza wersja nie usuwa wszystkich ustaleń (np. `hazelcast` 5.7.0) - raport podaje wtedy liczbę ustaleń przed i po.

Spójność `pom.xml` (to, co sprawdza recenzent): to samo wywołanie narzędzia zapisuje `sdlc-tmp\pom-consistency.json` - poziom Javy, którego build naprawdę używa (dodaje `java.version`), jedno źródło wersji dla rodziny bibliotek (`jackson-bom.version`, `jackson-2-bom.version`, `hazelcast.version`, `httpcore5.version`, `lombok.version` także w `annotationProcessorPaths`). Agent naprawia je w tej samej zmianie (`action: change`). **Z `pom.xml` nic nie jest usuwane**: zbędne zależności (np. `hazelcast-kubernetes` przy `hazelcast` 5), nieskuteczne wykluczenia czy stare właściwości trafiają do raportu jako propozycje (`action: proposal`), decyzja należy do Ciebie. Na koniec `analyst` robi krótki przegląd gotowego `pom.xml` (m.in. wykluczenia, sprawdzone `dependency:tree`) i zapisuje `## Pom review` w `analysis.md`; poprawki wersji z przeglądu idą w jeszcze jednej delegacji, reszta to propozycje w raporcie.

## 2. Co sprawdza pipeline

Przebiegi `tools\sdlc.ps1` w tym scenariuszu zawsze mają `-SkipSonar`:

1. `.\tools\sdlc.ps1 -Baseline -SkipSonar`: build, testy, skan Xray (bez skanu baseline się nie zapisze).
2. `.\tools\sdlc.ps1 -SkipSonar` po zmianie, najwyżej dwa razy (drugi raz tylko po cofnięciu nieudanego podbicia).

Bramki:
- `VulnGuard`: skan Xray naprawdę wykonany, testów nie mniej niż w baseline, zmienione tylko pliki budowania (`pom.xml`, `.mvn/`). Każdy inny zmieniony plik = `FAIL`.
- `Compilation`, `Tests`, `Regression`, `TestIntegrity`: jak w każdym scenariuszu.
- `XrayScan`: `PASS` albo `FAIL` tylko z ustaleniami, które w raporcie mają status inny niż `fixed`.

Bez `-CiParity`: CI używa tej samej wersji Mavena (`mavenVersion` z `config/project-config.yaml`) i i tak zbuduje projekt od zera.

## 3. Kroki

### Krok 1. Terminal

W terminalu nie może być starych zmiennych `SONAR_TOKEN`, `JF_URL` ani `JF_ACCESS_TOKEN`. Token JFrog jest w `jfrog.token` w katalogu głównym repozytorium.

### Krok 2. Podpięcie projektu

Projekt pobrany pierwszy raz (`config/scenario-config.yaml`: `scenarioType: vulnquick`, `scenarioProject`, `scenarioRepoUrl`):

```powershell
.\scripts\start-scenario.ps1 -Scenario vulnquick
```

Projekt już podpięty (kolejne zadanie):

```powershell
.\scripts\start-scenario.ps1 -Scenario vulnquick -NewTask
```

`-NewTask` przenosi pliki poprzedniego zadania do `sdlc-history\` i odświeża narzędzia oraz agentów. JDK jest dobierany do `pom.xml` (bez wersji docelowych).

Gałąź `sdlc-work` powstaje domyślnie z gałęzi, na której stoi projekt (po klonie: domyślnej, np. `master`). Inną bazę podasz parametrem `-BaseBranch feature` albo w `config/scenario-config.yaml` (`scenarioBaseBranch: feature`): skrypt pobiera `origin/feature` i od niej zakłada `sdlc-work`. Istniejącej `sdlc-work` z własnymi commitami na innej bazie nie nadpisze: zatrzyma się z instrukcją (zmień nazwę starej gałęzi albo podaj `-Branch <inna nazwa>`).

### Krok 3. Środowisko

SonarQube nie jest potrzebny. Jeśli testy projektu wymagają MongoDB, uruchom `.\scripts\env-up.ps1 -ProjectPath projects\<projekt>`.

### Krok 4. Okno VS Code

Otwórz `projects\<projekt>` w nowym oknie i wybierz `@sdlc-orchestrator`. `.vscode\mcp.json` w projekcie daje dostęp do Jiry (tylko odczyt).

### Krok 5. Prompt

```
Scenariusz: vulnquick. Popraw wersje zależności dla zadań z filtra Jiry:
project = Cyber AND issuetype = Zadanie AND "Epic Link" is not EMPTY AND status = OPEN AND cf[24904] = "gekon-starter-release/gekon-users"
```

Filtr podmień na swój projekt (`cf[24904]` = nazwa produktu w skanie korporacyjnym). Zamiast filtra możesz podać listę kluczy (`CYB-561162, CYB-561161`).

## 4. Wynik

Orchestrator kończy krótkim raportem:

| Kolumna | Znaczenie |
|---|---|
| Zadanie, CVE, komponent | z Jiry |
| Wersja przed -> po | albo powód, dla którego się nie zmieniła |
| Status | `fixed`, `already fixed in code`, `embedded in <biblioteka>, no fixed release`, `no fix version in the repository`, `needs vulnfix` |

Pod tabelą: pozostałe ustalenia Xray, Xray baseline -> teraz, tabela bramek i koszt (`tools\copilot-quota.ps1`).

`needs vulnfix` oznacza, że podbicie wymaga zmiany kodu, testów, wersji Javy albo nowszej linii Spring Boota. Takie zadanie zrób osobno: [brownfield-vulnfix.md](brownfield-vulnfix.md).

## 5. Na co patrzeć (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Baseline bez skanu Xray | `sdlc-baseline.json` ma `xrayFindings`; `createdAt` sprzed zmiany |
| Zmiany poza `pom.xml` | `git status --short`; `VulnGuard` = PASS |
| Dublowanie zależności, wykluczenia | `git diff refs/sdlc/baseline -- pom.xml` |
| Wolne sprawdzanie wersji | jedno wywołanie `tools\xray-candidates.ps1`; żadnego `dependency:get` po kolei ani `versions-maven-plugin` |
| Zbyt wiele przebiegów | najwyżej 3 przebiegi `sdlc.ps1` (baseline + 2) |
| Zadanie bez statusu | każde zadanie z filtra jest w tabeli raportu |

Odczyt końcowy:

```powershell
cd projects\<projekt>
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"xray: $($r.metrics.xray.findings) (delta $($r.delta.xrayFindings)); changed: $($r.metrics.diff.changed -join ', ')"
@($r.errors) | ForEach-Object { "$($_.gate): $($_.summary)" }
.\tools\sdlc.ps1 -CheckReport
```

Gotowe znaczy: `VulnGuard`, `Compilation`, `Tests`, `Regression`, `TestIntegrity` = `PASS`, w `changed` tylko `pom.xml`, `-CheckReport` = 0, a każde ustalenie w `XrayScan` ma w raporcie status inny niż `fixed`.
