# AGENTS.md - analiza poprawności procesu SDLC (pamięć robocza)

Ten plik opisuje, jak weryfikować, że proces SDLC tego repozytorium działa zgodnie z założeniami. Powstał po sesji testowej 2026-10-08. Czytaj go na początku każdej sesji, w której użytkownik testuje generator.

## 1. Zasady pracy z użytkownikiem

- Odpowiadaj po polsku, krótko i konkretnie. Pliki linkuj, nazw narzędzi nie podawaj.
- Pytanie nie jest zgodą na wykonanie. Na pytanie ("jak to przetestować?") odpowiedz i zatrzymaj się. Działaj dopiero po wyraźnym poleceniu ("rób", "testuj").
- Użytkownik prowadzi test sam w osobnym oknie VS Code (agent `@sdlc-orchestrator` jest w wygenerowanym projekcie, nie jest dostępny jako subagent). Twoja rola to monitorowanie: czytasz stan projektu, oceniasz, zgłaszasz odchylenia. Niczego nie poprawiaj w trakcie przebiegu agentów bez prośby.
- Tokeny: nigdy nie proś o wklejenie tokena do czatu i nie drukuj ich. Jeśli użytkownik wklei token (zdarzyło się z tokenem JFrog), napisz, że trzeba go unieważnić i wygenerować nowy.

## 2. Architektura procesu (co jest czym)

Repozytorium jest generatorem projektów Spring Boot (Initializr) z wbudowanym pipeline SDLC.

| Element | Rola |
|---|---|
| `config/project-config.yaml` | Jedyne źródło konfiguracji generatora i bramek |
| `scripts/generate-project.ps1` | Generuje projekt do `projects/<artifactId>` (`projectsDir`), znacznik `.sdlc-generated`; katalog bez znacznika nadpisuje tylko z `-Force`. Wstrzykuje pom, narzędzia, agentów, hook, `.gitignore`. Od 2026-10-12 robi `git init`: commit na `main`, gałąź robocza `sdlc-work`; odmawia regeneracji, gdy jest praca w gicie (bez `-Force`) |
| `scripts/fetch-project.ps1` | Brownfield odpowiednik generatora: `git clone` do `projects/<Project>`; nie rusza istniejącego folderu, `-Fresh` kasuje go po potwierdzeniu |
| `scripts/env-up.ps1` | Podnosi MongoDB (27017) i SonarQube (9000), tworzy token Sonara, kopiuje do projektu |
| `templates/greenfield/sdlc.ps1` | Lokalny pipeline bramek, kopiowany jako `tools/sdlc.ps1`; zapisuje `sdlc-report.json` |
| `templates/greenfield/jfrog-scan.ps1` | Bramka Xray, kopiowana jako `tools/jfrog-scan.ps1` |
| `templates/shared/copilot-quota.ps1` | Koszt zadania (kredyty premium Copilota, start/koniec), kopiowany jako `tools/copilot-quota.ps1`; stan w `sdlc-cost.json`; różnica obejmuje całe konto |
| `templates/greenfield/.github/agents/*` | Agenci: sdlc-orchestrator, planner, developer, test-engineer, security-reviewer, quality-fixer |
| `templates/greenfield/.github/workflows/sdlc.yml` | CI lustrzany do lokalnego pipeline |
| `templates/brownfield/*` | Osobny szablon dla pobranego kodu (`projects/`): własne kopie `sdlc.ps1`, `jfrog-scan.ps1`, agentów, plus `recon.ps1` i instrukcje brownfield. Używa go `scripts/attach-project.ps1` |
| `tests/scenarios/*` + `scripts/new-fixture.ps1` | Scenariusze testowe brownfield (B1, B2, B3, B6), instrukcja w `tests/scenarios/README.md`. `expected.md` = treść zadania + rozwiązanie; nie trafia do projektu |

Kolejność bramek w `sdlc.ps1`: Compilation, Tests, VulnerabilityCheck (OWASP, tylko gdy plugin jest w pom), XrayScan (tylko gdy istnieje `jfrog-xray.properties`), SonarQube, SonarQube-QualityGate.

Przepływ agentów: orchestrator -> planner (`plan.md`) -> developer -> test-engineer -> security-reviewer (`security-review.md`) -> `tools\sdlc.ps1` -> przy FAILED: quality-fixer, maks. 5 iteracji. Definicja ukończenia: `sdlc-report.json` ma `status: PASSED`.

## 3. Konfiguracja na koniec sesji 2026-10-08

- `enableOwaspCheck: false` (baza NVD niedostępna w sieci firmowej). Skan korporacyjny jest jedyną bramką podatności.
- `enableXray: true`, `xrayUrl: https://ewsi.centrala.bzwbk:9999`, `xrayWatches: XrayWatch`, `xrayInsecureTls: true`.
- `owaspFailOnError` działa tylko przy włączonym OWASP.
- Token JFrog: zmienna `JF_ACCESS_TOKEN` albo plik `jfrog.token` (w repo głównym generator kopiuje go do projektu). Token Sonara: `SONAR_TOKEN` albo `sonar-token.txt`.
- `jf` jest instalowany bez uprawnień administratora w `%LOCALAPPDATA%\jfrog-cli\jf.exe`.
- JDK: domyślny w PATH to 25 (`java-tools\java`), obok są `jdk-21`, `jdk-17`, `jdk-23`, `jdk-11.0.6`, `jdk1.8.0_201`. Od 2026-10-13 `attach-project.ps1` wybiera JDK zgodny z `pom.xml` (`maven.jdksDir` w `project-config.yaml`) i zapisuje `javaHome` w `sdlc-settings.json`; `sdlc.ps1`/`recon.ps1` przełączają się przez `tools/use-java.ps1`. JDK 23+ nie uruchamia Lomboka bez `-proc:full`.
- Maven (od 2026-10-19): `maven.mavenVersion` (3.9.16 = obraz CI) i `maven.mavensDir` (`java-tools`) w `project-config.yaml`. `attach-project.ps1` szuka `apache-maven-<wersja>`, brakującą pobiera z Artifactory (`org.apache.maven:apache-maven:<v>:zip:bin`), zapisuje `mavenHome` w `sdlc-settings.json`; `use-java.ps1` przełącza też Mavena. Maven Wrapper w projekcie ma pierwszeństwo. W PATH nadal jest 3.9.11.
- Stan `~/.jfrog` (sprawdzone `jf config show`): serwery `sdlc-xray` (używa go `jfrog-scan.ps1`), `prod` i `Default-Server` (domyślny, utworzony przez moje próby diagnostyczne z tokenem z pliku `jfrog.token`). Podczas diagnostyki usuwałem i odtwarzałem wpisy `Default-Server`, więc jego dawna zawartość mogła zostać nadpisana. Użytkownik, który miał własną konfigurację, powinien ją sprawdzić.

## 4. Procedura monitorowania testu

Wszystko poniżej to odczyt. Uruchamiaj z katalogu głównego repozytorium.

### 4.1 Przed startem

1. Terminal agenta nie ma starych zmiennych: `SONAR_TOKEN`, `JF_URL`, `JF_ACCESS_TOKEN`. Stary `SONAR_TOKEN` ma pierwszeństwo przed `sonar-token.txt` i psuje bramkę Sonara.
2. `projects\<projekt>` ma: `tools\sdlc.ps1`, `tools\jfrog-scan.ps1`, `jfrog-xray.properties`, `.github\agents`, `.gitignore` z `jfrog.token`, `sonar-token.txt`, `*.token`, `.env`.
3. `pom.xml` projektu: brak wpisu `dependency-check-maven`, gdy OWASP wyłączony.

### 4.2 Planner (`plan.md`)

Sprawdź, czy plan ma: pakiet po funkcji, Controller -> Service -> Repository, DTO osobno od encji, wszystkie endpointy z wymagania, walidację `@Valid`, globalną obsługę błędów, plan testów (webmvc, data-mongodb, integracyjny), pokrycie co najmniej 60%.
Zgłoś, jeśli orchestrator dopisał nadpisania na górze zamiast odesłać plan plannerowi (plan staje się sprzeczny).

### 4.3 Developer (kod)

Przeczytaj wszystkie pliki w `src\main`. Kryteria z `.github\copilot-instructions.md`: wstrzykiwanie tylko przez konstruktor, kontroler nie dotyka repozytorium, DTO i `@Valid`, zapytania tylko pochodne, w logach tylko id (bez danych osobowych).
Znane pułapki Spring Boot 4:
- Właściwości Mongo to `spring.mongodb.uri` i `spring.data.mongodb.auto-index-creation`. Stare nazwy (`spring.data.mongodb.uri`, `autoindex-creation`) są ignorowane po cichu, a unikalny indeks się nie tworzy.
- Handler `@ExceptionHandler(Exception.class)` w `@RestControllerAdvice` zamienia 405/415/404 frameworka na 500. Poprawnie: rozszerzyć `ResponseEntityExceptionHandler`.
- Adnotacje testowe są w nowych pakietach (`org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest`, `...data.mongodb.test.autoconfigure.DataMongoTest`), mocki to `@MockitoBean`, JSON to Jackson 3 (`tools.jackson.*`; adnotacje nadal w `com.fasterxml.jackson.annotation`).
- `src/test/resources/application.properties` całkowicie przesłania plik z `src/main`.

### 4.3.1 Testy (test-engineer)

- Lista metod: `Select-String -Path src\test\java -Pattern "void \w+\("`.
- Izolacja: testy używają bazy `sdlcdemo_test`, nie główną; są testy potwierdzające to (`*_UsesIsolatedTestDatabase`).
- Test 415 nie może zostać osłabiony; jego porażka jest oczekiwanym sygnałem błędu handlera.
- Brak `@Disabled`, `@SuppressWarnings`, `NOSONAR`.

### 4.4 Security-reviewer (`security-review.md`)

Oceń jakość: czy pokrywa OWASP Top 10, NoSQL injection, mass assignment, wycieki w błędach, PII w logach, sekrety. Ustalenia dotyczące generatora i szablonów trzeba poprawiać u źródła (w `scripts/` i `templates/`), a nie tylko w wygenerowanym projekcie, bo zniknęłyby przy kolejnym generowaniu.

### 4.5 Raport pipeline

```powershell
cd projects\<projekt>
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"tests: $($r.metrics.tests.total)/$($r.metrics.tests.passed) cov: $($r.metrics.coverage.line)/$($r.metrics.coverage.branch)"
@($r.errors) | Group-Object gate | ForEach-Object { "$($_.Name): $($_.Count)" }
$r.warnings
```
Szczegóły Xray (komponent, CVE, wersja naprawcza): `target\xray-findings.json`; surowy raport: `target\xray-report.json`. Pełny log: `sdlc-run.log`.

Problemy Sonara (odczyt, token z `sonar-token.txt`, nagłówek `Authorization: Bearer`):
```powershell
$t=(Get-Content sonar-token.txt -Raw).Trim(); $h=@{Authorization="Bearer $t"}
(Invoke-RestMethod "http://localhost:9000/api/issues/search?componentKeys=<projectKey>&resolved=false&ps=50" -Headers $h).issues |
  ForEach-Object { "$($_.severity) $($_.type) | $($_.component -replace '.*:',''):$($_.line) | $($_.message)" }
```

### 4.6 Pętla napraw (quality-fixer)

- Xray: poprawka ma być w `pom.xml`. Najpierw wersja `spring-boot-starter-parent`; gdy się nie da, nadpisanie właściwości (`<tomcat.version>`, `<jackson-bom.version>`) z komentarzem o CVE. Nie wolno dublować zależności ani ignorować podatności. Brak wersji naprawczej zgłasza się użytkownikowi.
- Sonar: naprawa kodu, nie wyciszanie. Sprawdź `Select-String -Pattern "SuppressWarnings|NOSONAR|@Disabled"` oraz `sonar-project.properties` (brak nowych wykluczeń).
- Limity: maks. 5 iteracji; ta sama bramka 3 razy z rzędu oznacza zatrzymanie i raport blokady.
- Weryfikacja końcowa jest niezależna: sam odczytaj `sdlc-report.json`, nie polegaj na deklaracji agenta. Sprawdź znacznik czasu raportu (`LastWriteTime`) i że `errors` jest puste.

### 4.7 Brownfield (`projects/`, scenariusze testowe)

- Przygotowanie: `.\scripts\new-fixture.ps1 -Name <scenariusz>` -> `.\scripts\attach-project.ps1 -Project <scenariusz> -Scenario <typ z expected.md>`. Instrukcja: `tests\scenarios\README.md`. Agent `@sdlc-orchestrator` w projekcie to wersja brownfield (scenariusze `buildfix`, `bugfix`, `sonarfix`).
- Orchestrator musi: zapisać `task.md` z `Scenario:`, uruchomić `-Baseline` przed pierwszą zmianą i nie powtarzać go później (sprawdź `createdAt` w `sdlc-baseline.json` względem czasu zmian).
- `bugfix`: w `sdlc-report.json` musi być `ReproTest: PASS`; wcześniej w przebiegu `RED-RECORDED` (nowy test) albo test czerwony w baseline.
- Odczyt końcowy: `gates` (`Regression`, `TestIntegrity` = `PASS`), `metrics.diff.changed`, `delta`, `warnings`. Porównaj z sekcją "Kryteria zaliczenia" w `tests\scenarios\<scenariusz>\expected.md`.
- `sonarfix` wymaga `sonarMaxOpenIssues: 0` w `sdlc-settings.json` (ustawia `attach-project.ps1 -Scenario sonarfix`).
- `sonarfix` (od 2026-10-16): analyst (grupy po regułach, ryzyko) -> decyzje użytkownika -> planner (partie po regułach) -> quality-fixer partiami (`mvn test`) -> verify. Bramka `TestCount` (testów nie mniej niż w baseline); łączenie/podział testów (S5976/S5961) to w `TestIntegrity` tylko ostrzeżenie. Od 2026-10-19 `sdlc.ps1` w `sonarfix` nie zapisze baseline bez danych Sonara i nie da `PASSED` bez odczytanych zgłoszeń; orchestrator przy niedziałającym Sonarze zatrzymuje się (w innych scenariuszach przechodzi na `-SkipSonar`). Tutorial: `doc/tutorial/brownfield-sonarfix.md`.
- Wszystkie scenariusze mają ten sam klucz Sonara (`com.example.shop:shop-service`); uruchamiaj je po kolei, nie równolegle.
- `tests` (od 2026-10-13): przepływ analyst -> planner -> test-engineer -> verify, bez zmian w `src/main`. Bramka `TestMigration` (liczba wykonanych/zaliczonych testów >= baseline, brak zmian `src/main`); `TestIntegrity` liczy też metody Spock (`.groovy`), a w `tests` zamiana pliku testowego to tylko ostrzeżenie. Tutorial: `doc/tutorial/brownfield-spock-to-junit5.md`.
- `migration` (od 2026-10-15): analyst -> planner -> developer -> test-engineer -> (security-reviewer) -> verify. Bramka `MigrationGuard`: `pom.xml` ma `migrationBootVersion`/`migrationJavaVersion` z `scenario-config.yaml`, testów nie mniej niż w baseline. JDK = `migrationJavaVersion`. Końcowa weryfikacja przy zmianach `pom.xml`/`.mvn/`: `tools\sdlc.ps1 -CiParity` (puste repozytorium Maven jak w CI). Kolejne zadanie na podpiętym projekcie: `start-scenario.ps1 -NewTask` (archiwum w `sdlc-history/`, odświeżenie narzędzi). Tutorial: `doc/tutorial/brownfield-springboot3-to-4.md`.
- `sdlc.ps1` (od 2026-10-19): śledzone pliki nadpisane przez build (np. kontrakt generowany z kodu) przywraca do stanu sprzed przebiegu i wypisuje w `warnings`; `-Baseline` ustawia w Sonarze okres nowego kodu na analizę baseline (`SPECIFIC_ANALYSIS`, w baseline `sonarNewCodeAnalysis`), więc Quality Gate ocenia tylko zmiany zadania; raport ma `maven` (wersja) i `ciParity`.
- `feature` (od 2026-10-12): `start-scenario.ps1` -> `fetch-project.ps1` (`git clone` z `scenarioRepoUrl`, bez MCP GitLab; istniejący folder pomija, `-Fresh` kasuje i klonuje po potwierdzeniu) -> `attach-project.ps1`. `attach-project.ps1` kopiuje `.vscode/mcp.json` (tylko Jira/Confluence, read-only). Orchestrator dopisuje treść zgłoszenia do `task.md` (`## Source`), przepływ: analyst -> planner -> developer -> test-engineer -> security-reviewer -> verify. Sprawdź: każde kryterium akceptacji ma test, `plan.md` zgodny z konwencjami projektu.
- `review` (od 2026-10-20, wersja z 11:30): przegląd, **tylko raport, bez napraw**. Zakres z treści zadania: `Review scope: changes <baza>..HEAD` (jak MR) albo `Review scope: project`. Przepływ: `-Baseline` (bramka `Toolchain`: JDK = `pom.xml`, Maven = `mavenVersion` z `sdlc-settings.json`, `settings.xml`, Sonar i Xray naprawdę uruchomione, każde `-Skip*` = FAIL, wrapper tylko ostrzeżenie; Sonar czerwieni `Toolchain` tylko bez połączenia z serwerem) -> przy `Toolchain: FAIL` stop -> jeden `-CiParity` -> analyst (`analysis.md`) -> security-reviewer (`security-review.md`) -> raport. Inne czerwone bramki, Sonar i Xray to ustalenia. Koniec: `Toolchain` PASS, oba raporty, pusty `git diff --stat refs/sdlc/baseline`; `PASSED` niewymagany. Sprawdź: brak delegacji do developer/quality-fixer/build-doctor. Historia: rano `review` naprawiał czerwone bramki, o 11:00 także Sonar do 0 - przebieg na be-wesola zakończył się `PASSED` z 3 zgłoszeniami Sonara (końcowy przebieg na starym skrypcie) i użytkownik uznał scenariusz za źle zdefiniowany. „Przejęcie projektu i doprowadzenie do czystości” = `review` + `remediation` (zamiast planowanego wcześniej `onboarding`). Tutorial: `doc/tutorial/brownfield-review.md`. Przebieg 2026-10-20 11:47-12:06 (be-wesola, zakres `project`): zgodny ze scenariuszem, 0 zmian w gicie. Poprawki po nim w agentach: jedna skala ważności (bezpieczeństwo i Xray ocenia tylko security-reviewer, `SEC-xx`), orchestrator nie edytuje raportów, CVE „bez poprawki” to tylko skanowana wersja (bez pytań o akceptację), kolejne zadania z istniejących typów albo `remediation`, przegląd o nic nie pyta.
- `remediation` (od 2026-10-20): naprawa ustaleń z `review`. Start: `start-scenario.ps1 -Scenario remediation -NewTask` (raport przeglądu idzie do `sdlc-history/<ts>/`, `attach-project.ps1` zapisuje `reviewSource`, `sonarMaxOpenIssues: 0`). Zakres domyślny: CRITICAL+HIGH, Xray 0, działający Sonar, Sonar 0; MEDIUM/LOW po ID. Przepływ: decyzje (jedna lista) -> planner (tabela ustaleń + partie: build/Sonar config -> Xray -> konfiguracja/sekrety -> kod -> Sonar -> testy) -> delegaci -> security-reviewer (re-check `SEC-xx`, nowy `security-review.md`) -> `-CiParity`. Bramki jak `sonarfix` (`SonarQube-Issues`, `TestCount`), ale baseline bez danych Sonara jest dozwolony (zepsuta konfiguracja Sonara to ustalenie). Sekrety: `${ENV}` w konfiguracji, wartości w `secrets.local.env` (użytkownik; `.gitignore` + exclude), `tools\load-secrets.ps1` wczytuje je w `sdlc.ps1` (raport: `secretsLoaded`, wartości maskowane `***`, środowisko przywracane) i `tools\run-local.ps1` (start aplikacji, tylko użytkownik). Sprawdź: tabela statusów w `plan.md`, brak wartości sekretów w diffie, rotacja jako czynność użytkownika. Test 2026-10-20 na fixture: sekret dociera do JVM testów, raport i baseline bez wartości, maskowanie też dla formy JSON. Tutorial: `doc/tutorial/brownfield-remediation.md`.
- `sdlc.ps1` (od 2026-10-20): `Parse-TestResults` liczy `surefire-reports` i `failsafe-reports` (`metrics.tests.integration`). Wcześniej testy integracyjne z failsafe były niewidoczne dla `Tests`/`Regression`/`TestCount` (be-wesola: 4 zamiast 5). Stare baseline mają mniej testów - nowe przypadki nie psują `Regression`. `recon.ps1` uruchamia tylko `test`, więc failsafe go nie dotyczy.

## 5. Znane odchylenia agentów z sesji 2026-10-08

- Orchestrator zamiast odesłać plan do plannera dopisał nadpisania (z błędnymi nazwami właściwości Mongo) i zakazał zmian w `pom.xml`, co kolidowało z naprawą Xray. Później zniósł zakaz.
- Przegląd bezpieczeństwa znalazł H-1 (`sonar-token.txt` poza `.gitignore`); orchestrator naprawił tylko projekt. Generator naprawiono osobno.
- Wynik końcowy był poprawny: `PASSED`, 77 testów, pokrycie 97,8% linii i 100% branchy, po jednej iteracji napraw.

## 6. Pułapki narzędziowe (żeby ich nie powtarzać)

- Sesja 2026-10-15 (`tests`, icbs-insurances): orchestrator sam edytował `pom.xml` (poprawki Xray) przed powstaniem planu i odczytał hasło z `~/.m2/settings.xml`, żeby pytać Artifactory (Basic auth, `curl -k`). Od tej sesji zabraniają tego agent i `copilot-instructions.md` (pkt 12); wersje sprawdza się przez `mvn dependency:get` / `versions:display-dependency-updates`.
- Spock raportuje dla funkcji z `where:` dodatkowy wpis zbiorczy (nazwa z `#zmienna` albo bez `[..]`). `TestMigration`/`MigrationGuard` ich nie liczą; przy ręcznym porównaniu też je pomijaj.
- `mvn verify` bez `clean` zostawia stare `TEST-*.xml` (np. 239 zamiast 237). Liczy się raport `sdlc.ps1`, który robi `clean`.
- Build, który nadpisuje śledzony plik (springdoc -> `insurances.yaml`), trafiał do migawki baseline. Od 2026-10-15 migawka powstaje przed buildem.
- `jf scan` zwraca kod 0 mimo naruszeń watcha bez akcji blokującej. Werdykt liczy `jfrog-scan.ps1` (każdy wpis w `violations` lub `vulnerabilities` to błąd); `jf scan` jest wołany z `--fail=false`.
- Xray "no fix available" dotyczy tylko skanowanej wersji, nie znaczy, że poprawki nie ma. Sesja 2026-10-09: 8 takich CVE Tomcata 11.0.24 zniknęło po podbiciu do 11.0.26 (nadpisanie dla innych CVE). Przed zgłoszeniem blokady podbij wersję i przeskanuj ponownie.
- Flagi logiczne `jf` podawaj jako `--insecure-tls=true`. Bez wartości `jf config add` kończy się błędem.
- Token do `jf config add` przekazuj przez stdin (`--access-token-stdin`); w tym trybie nie ma sensu dopisywać tokena do argumentów.
- Zmienne `JF_URL` i `JF_ACCESS_TOKEN` nie wystarczają dla `jf scan` (błąd "--url or --xray-url"); trzeba skonfigurować serwer.
- Przy diagnozie nie ukrywaj błędów przez `| Out-Null` ani `2>&1 | Out-Null`; maskuje to przyczynę.
- `Select-Object -First N` na końcu potoku zamyka skrypt przed czasem; do podglądu używaj `-Last N` lub przekieruj do pliku.
- W PowerShell argument `-Djacoco.skip=true` podawaj w cudzysłowie.
- Bramka OWASP z `failOnError=false` potrafiła dawać PASS bez raportu (`target\dependency-check-report.json`). Teraz zapisuje to w `warnings` raportu.
- Regeneracja (`generate-project.ps1`) kasuje cały katalog projektu, w tym zaimplementowany kod. Do testów generatora użyj `-OutputDir scratch\gen` i usuń katalog po teście.
- Sonar: `api/ce/component` pokazuje w `current` ostatnie zakończone zadanie, a nowe czeka w `queue`. Wynik Quality Gate i problemy trzeba wiązać z `ceTaskId` z `target/sonar/report-task.txt` (`api/ce/task`, potem `project_status?analysisId=`). Do 2026-10-12 `sdlc.ps1` czytał wynik poprzedniej analizy, a baseline miał 0 problemów. Brownfield `Regression` porównuje teraz klucze problemów (`sonarIssueKeys` w baseline).
- Xray jest bramką obowiązkową (CI/CD). Agenci nie mogą traktować podatności zależności jako "poza zakresem" ani pytać o `-SkipXray`.
- Sesja 2026-10-16 (`migration`, icbs-insurances, PASSED): podnosząc wersję Javy, Sonar włącza nowe reguły na niezmienionym kodzie (`S7467`, nullability Spring 7). Od tej sesji `Regression` w `migration` blokuje tylko zgłoszenia na zmienionych liniach (`git diff -U0` od `gitBase`), resztę daje do `warnings`. SCC 5 pomija "aktualne" testy kontraktowe (`incrementalContractTests=false`). H2 2.4.240 psuje CHECK z Hibernate 7.
- Monitorując, nie podsuwaj użytkownikowi gotowych odpowiedzi dla agenta, chyba że o to prosi. Moja podpowiedź "porównaj JSON z insurances.yaml" trafiła do decyzji i skończyła się pobraniem danych klientów z AS400.
- Sesja 2026-10-20 (`review`, be-wesola_banda_piratow): szablon `templates/brownfield/sonar-project.properties` wpisywał na sztywno `sonar.sources`, `sonar.tests=src/test/java`, binaria i ścieżkę JaCoCo; `sdlc.ps1` podaje każdą linię jako `-D`, co nadpisuje `pom.xml`. Projekt z samymi testami Spock (`src/test/groovy`) padał na skanerze, a pokrycie szło z innego raportu niż w CI (`jacoco-merged`). Od tej sesji szablon ma tylko `projectKey`, `projectName`, `host.url`, `scm.disabled`. Plik jest poza gitem (`.git/info/exclude`), więc agent nie może go „commitować”; jego zmiana po baseline to `TestIntegrity: FAIL`. W tej samej sesji: `JAVA_TOOL_OPTIONS` użytkownika wskazuje truststore JDK 25 (`java-tools\java\lib\security\cacerts`) także dla JDK 21 - działa, ale to zależność między JDK.
- Sesja 2026-10-19 (`sonarfix`, icbs-insurances): lokalnie PASSED, w CI (obraz Java 25, Maven 3.9.16) `ClassCastException: BasicAuthCache cannot be cast to AuthCache`. Przyczyna: `spring-cloud-contract-maven-plugin` 5.0.3 wnosi `maven-resolver-transport-http` 1.9.27 + `httpclient` 4.5.14; Maven 3.9.16 miesza je ze swoimi przy pobieraniu z uwierzytelnieniem. Lokalny 3.9.11 i pełne `~/.m2` tego nie pokazują. Odtworzenie: Maven z obrazu CI + `-Dmaven.repo.local=<pusty katalog>`. Naprawa w projekcie: `.mvn/maven.config` z `-Dmaven.resolver.transport=wagon`. Usunięcie `<extensions>true</extensions>` nie wystarcza (błąd przesuwa się do `surefire`). Przy diagnozie CI najpierw czytaj log, potem stawiaj hipotezy.

## 7. Co jeszcze nie zostało zweryfikowane

- Zachowanie OWASP przy `enableOwaspCheck: true` i `owaspFailOnError: true` (wymaga bazy NVD lub klucza API).
- Krok Xray w GitHub Actions (`jfrog/setup-jfrog-cli@v4` + `tools/jfrog-scan.ps1 -SkipConfig`), wymaga sekretów `JF_URL` i `JF_ACCESS_TOKEN`.
- Praca endpointów na działającej aplikacji (testy je pokrywają, ale nie wykonano ręcznych wywołań).
- Pre-commit hook w wygenerowanym projekcie (`-SkipSonar -SkipOwasp -SkipXray`).
- Przebieg agentów brownfield (orchestrator -> analyst/build-doctor/bug-hunter/developer/quality-fixer) na fixtures B1, B2, B3, B6. Bramki sprawdzone tylko z ręcznie zasymulowaną poprawką.
