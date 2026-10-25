# Tutorial: migracja testów Spock (Groovy) na JUnit 5 - projekt `icbs/insurancesv1`

Scenariusz brownfield typu `tests`: pobierasz istniejący projekt, a orchestrator zastępuje wszystkie testy w Groovy (Spock) testami w JUnit 5. Kod produkcyjny się nie zmienia. Zadanie kończy się dopiero wtedy, gdy pipeline jest zielony (w tym Xray), a nowe testy sprawdzają co najmniej tyle samo co stare.

Ogólny opis kroków brownfield (MCP, środowisko, raport): [brownfield-bff-template.md](brownfield-bff-template.md).

## 1. Kiedy który `scenarioType`

| Typ | Kiedy używać | Przykład | Obsługa przez orchestratora |
|---|---|---|---|
| `greenfield` | Nowy projekt od zera z generatora | serwis CRUD z Initializr | tak (agent greenfield) |
| `buildfix` | Projekt się nie kompiluje albo nie startuje | brak zależności, błąd kompilacji | tak |
| `bugfix` | Opisany błąd, stack trace albo czerwony test | "endpoint zwraca 500 dla pustej listy" | tak |
| `sonarfix` | Trzeba usunąć problemy SonarQube / zazielenić Quality Gate | 12 code smells, 1 bug | tak |
| `feature` | Nowe wymaganie biznesowe (zwykle story z Jiry) | nowy endpoint, nowe pole | tak |
| `vulnfix` | Podatności zależności (Xray), projekt kończy czysty: wersje docelowe, Xray 0, Sonar 0 | podbicie Tomcata | tak ([brownfield-vulnfix.md](brownfield-vulnfix.md)) |
| `vulnfix.quick` | Szybki tryb naprawy podatności: tylko pliki builda | `jackson-2-bom.version` 2.21.2 -> 2.21.8 | tak ([brownfield-vulnquick.md](brownfield-vulnquick.md)) |
| `refactor` | Zmiana struktury **kodu produkcyjnego** bez zmiany zachowania | wydzielenie serwisu, rozbicie klasy | nie |
| `tests` | Praca **tylko na testach**: dopisanie, wymiana frameworka, poprawa jakości | Spock -> JUnit 5, pokrycie 40% -> 70% | tak |
| `migration` | Zmiana wersji platformy lub frameworka w **kodzie produkcyjnym** | Spring Boot 3 -> 4, Java 17 -> 21 | tak ([brownfield-springboot3-to-4.md](brownfield-springboot3-to-4.md)) |
| `review` | Tylko ocena, bez zmian w kodzie | przegląd MR | nie |

Reguła rozstrzygająca: patrz, **co się zmienia**. Zmienia się tylko `src/test` i część testowa `pom.xml` -> `tests`. Zmienia się `src/main` bez zmiany zachowania -> `refactor`. Zmienia się wersja platformy produkcyjnej -> `migration`.

Dla tego ćwiczenia: **`tests`** (nie `refactor`, bo `src/main` się nie zmienia; nie `migration`, bo platforma produkcyjna zostaje ta sama).

Przepływ `tests` w orchestratorze: `analyst` (inwentarz testów i tabela mapowania stary -> nowy test) -> `planner` -> `test-engineer` -> weryfikacja. Bez `developer` i `security-reviewer`; `src/main` nie może się zmienić.

Dodatkowa bramka `TestMigration` (tylko gdy `sdlc-settings.json` ma `scenario: tests`):
- liczba wykonanych i zaliczonych testów nie mniejsza niż w baseline;
- brak zmian w `src/main`.

W tym scenariuszu `TestIntegrity` nie blokuje usunięcia lub zamiany pliku testowego (tylko ostrzeżenie w `warnings`), ale nadal blokuje `@Disabled`, mniej asercji w pozostałych plikach i nowe `NOSONAR`. Bramka rozpoznaje też testy Spock (`def "..."()` w plikach `.groovy`).

## 2. Konfiguracja: `config/scenario-config.yaml`

```yaml
projectsDir: projects
scenarioType: tests
scenarioProject: "icbs-insurances"
scenarioRepoUrl: "https://gitlab.centrala.bzwbk/icbs/insurancesv1.git"

maxFixIterations: 5
maxOfficialCiAttempts: 2
sameGateStopAfter: 3

diffGuardMaxFiles: 200            # 71 Groovy files deleted + their Java replacements + pom.xml
diffGuardMaxLines: 12000          # ~3000 Groovy lines deleted, Java replacements are longer
diffGuardMode: warn
coverageTolerance: 0.0            # new tests must cover at least as much as Spock did
```

Rozmiar zmierzony po pobraniu (2026-10-13): `src/test/groovy` ma 71 plików (19 klas `*Spec`, ok. 140 metod feature, 3055 linii), `src/test/java` ma 16 plików JUnit, kontrakty to 2 pliki Groovy DSL. Baseline: 150 przypadków testowych, wszystkie zielone.

Wynik przebiegu (2026-10-15): analityk znalazł dodatkowo 23 "uśpione" specyfikacje `*Test.groovy`, których surefire nigdy nie uruchamiał (razem 40 specyfikacji). Po migracji: 237 testów, pokrycie linii 34,6% -> 64,4%. Z 150 przypadków baseline 15 to wpisy zbiorcze Spocka dla `where:` - `TestMigration` ich nie liczy.

## 3. Kroki

### Krok 1. Pobierz kod i podepnij narzędzia

```powershell
.\scripts\start-scenario.ps1
```

Klonuje repozytorium do `projects\icbs-insurances`, tworzy gałąź `sdlc-work`, kopiuje narzędzia i agentów, zapisuje `sdlc-settings.json` (`scenario: tests`) i uruchamia rozpoznanie (`recon-report.json`). JaCoCo jest już w `pom.xml` (profil `coverage`, aktywny domyślnie), więc skrypt nie zmienia `pom.xml`.

JDK: skrypt czyta wersję Javy z `pom.xml` (tu 21), szuka pasującego JDK w `jdksDir` z `config/project-config.yaml` i zapisuje go jako `javaHome` w `sdlc-settings.json`. `tools\sdlc.ps1` i `tools\recon.ps1` same się na niego przełączają. Do ręcznego `mvn` w terminalu: `.\tools\use-java.ps1` (zmiana obowiązuje do zamknięcia terminala). Bez tego domyślne JDK 25 nie uruchamia Lomboka i projekt się nie kompiluje.

### Krok 2. Sprawdź rozmiar migracji (tylko odczyt)

W `projects\icbs-insurances`:

```powershell
Get-ChildItem src\test -Recurse -File -Include *.groovy | Select-Object -ExpandProperty FullName
(Get-ChildItem src\test\groovy -Recurse -File -Filter *.groovy | Get-Content | Measure-Object -Line).Lines
Get-ChildItem src\test\resources\contracts -Recurse -File -ErrorAction SilentlyContinue | Select-Object Name
Get-ChildItem src\test\java -Recurse -File -ErrorAction SilentlyContinue | Select-Object Name
```

Na tej podstawie popraw limity DiffGuard w `sdlc-settings.json` projektu (albo w `config/scenario-config.yaml` i podepnij ponownie).

### Krok 3. Okno VS Code

Otwórz folder `projects\icbs-insurances` w nowym oknie VS Code. Serwer MCP nie jest potrzebny (zadanie nie pochodzi z Jiry).

Środowisko (MongoDB, SonarQube, token) orchestrator podnosi sam przez `..\..\scripts\env-up.ps1`. Opcjonalnie możesz je uruchomić wcześniej, żeby nie czekać na start SonarQube:

```powershell
.\scripts\env-up.ps1 -ProjectPath projects\icbs-insurances
```

### Krok 4. Daj zadanie

W czacie wybierz `@sdlc-orchestrator` i wklej prompt z sekcji 4.

## 4. Prompt dla orchestratora

```
Scenariusz: tests. Migracja testów ze Spock (Groovy) na JUnit 5. Kod produkcyjny (src/main) bez zmian.

Kontekst projektu (z pom.xml):
- Spring Boot 3.5, Java 21, testy Spock 2.4 (spock-spring) kompilowane przez gmavenplus-plugin z src/test/groovy,
- maven-surefire-plugin uruchamia tylko klasy **/*Spec.java - dlatego 16 istniejących plików JUnit w src/test/java dziś się nie wykonuje,
- spring-cloud-contract-maven-plugin ma testFramework SPOCK, klasy bazowe w pakiecie pl.santander.insurances.infrastructure.cdc, kontrakty to 2 pliki Groovy DSL w src/test/resources/contracts,
- dostępne biblioteki testowe: spring-boot-starter-test (JUnit 5, AssertJ, Mockito, MockMvc), rest-assured spring-mock-mvc, H2,
- mvn verify uruchamia aplikację i springdoc nadpisuje insurances.yaml w katalogu głównym - to efekt builda, nie zmiana zadania.

Najpierw analiza (analysis.md), przed jakąkolwiek zmianą:
1. Lista wszystkich plików *.groovy w src/test: specyfikacje, klasy bazowe, helpery, kontrakty DSL.
2. Dla każdej specyfikacji: liczba metod feature, liczba wierszy where:, rodzaj testu (jednostkowy, @SpringBootTest, @WebMvcTest, JPA, kontrakt) i użyte mocki (Mock(), Stub(), Spy(), @SpringBean).
3. Tabela mapowania: metoda Spock -> planowana klasa i metoda JUnit 5.
4. Liczba testów i pokrycie z sdlc-baseline.json.
5. Które z 16 istniejących testów JUnit w src/test/java przechodzą po włączeniu ich w surefire (osobna lista, nie wliczaj ich do mapowania Spock -> JUnit 5).

Zasady migracji:
- Każda metoda feature ma odpowiednik w JUnit 5; bloki where: -> @ParameterizedTest z tymi samymi danymi; asercje z then:/expect: -> AssertJ; interakcje (1 * mock.metoda()) -> Mockito verify z tą samą krotnością; @SpringBean -> @MockitoBean.
- Nie upraszczaj testów i nie usuwaj przypadków. Test, który był czerwony w baseline, zostaje opisany w raporcie, a nie pominięty.
- Kontrakty Spring Cloud Contract: pliki DSL kontraktów nie są testami - zostają bez zmian. Zmień testFramework na JUNIT5 i przepisz klasy bazowe na Javę w tym samym pakiecie. Jeśli kontrakty są w Groovy DSL i nie da się ich wygenerować jako JUnit 5, zatrzymaj się i zapytaj.
- Nowe testy w src/test/java, ten sam pakiet co testowana klasa.
- pom.xml: usuń spock-spring, gmavenplus-plugin i objenesis (jeśli nic go już nie używa); w surefire zamień include **/*Spec.java na wzorce pasujące do nowych klas (**/*Test.java, **/*Tests.java). Nie dodawaj innych bibliotek bez potrzeby.
- Pliki *.groovy z src/test/groovy usuwaj dopiero, gdy ich odpowiednik w Javie przechodzi.
- Istniejące testy JUnit z src/test/java, które zaczną się wykonywać i będą czerwone: popraw test, nigdy src/main. Jeśli czerwony test wskazuje błąd w kodzie produkcyjnym, zatrzymaj się i zgłoś.
- Zmiany insurances.yaml (generowanego przez springdoc w czasie builda) nie są częścią zadania: przywróć plik przez git checkout -- insurances.yaml przed końcową weryfikacją.

Kryteria akceptacji:
1. W src/test nie ma plików *.groovy (poza plikami DSL kontraktów, jeśli zostały).
2. pom.xml nie zawiera Spocka ani gmavenplus-plugin.
3. Każda metoda feature Spocka ma odpowiednik (tabela w analysis.md uzupełniona o nazwę nowego testu).
4. Liczba wykonanych przypadków testowych >= liczba z baseline (porównaj metrics.tests.total), a liczba przypadków w klasach zmigrowanych ze Spocka >= liczba przypadków Spock z baseline (bez 16 wcześniejszych testów JUnit).
5. Pokrycie linii nie spadło względem baseline (bramka Regression).
6. tools\sdlc.ps1 kończy się PASSED bez flag -Skip*, w tym XrayScan.
```

## 5. Na co patrzeć w trakcie (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Nowe testy się nie uruchamiają (surefire nadal tylko `*Spec.java`) | `TestMigration: FAIL` "Fewer executed tests than in baseline"; brak `TEST-*Test.xml` w `target\surefire-reports` |
| Zgubione przypadki testowe | `TestMigration` pilnuje liczby; jakość odpowiedników sprawdź w tabeli mapowania w `analysis.md` |
| 16 dotychczasowych testów JUnit zawyża licznik po zmianie `includes` i może ukryć zgubione przypadki Spock | porównaj 150 przypadków Spock z baseline z liczbą przypadków w nowych klasach (bez tych 16 plików), np. z `target\surefire-reports\TEST-*.xml` |
| `insurances.yaml` w zmianach | springdoc nadpisuje go przy każdym `mvn verify`; na końcu ma być przywrócony |
| `mvn verify` startuje aplikację (`spring-boot:start` z profilem `dev` w `pre-integration-test`) | jeśli baseline pada na tym kroku, to problem środowiska, nie migracji: zgłoś, nie każ agentom zmieniać pluginu bez zgody |
| Kontrakty generowane jako Spock | `target\generated-test-sources\contracts` nie może zawierać `.groovy` po migracji |
| Osłabione testy | `Select-String -Path src\test\java -Recurse -Pattern "@Disabled|NOSONAR|SuppressWarnings"` |
| Zmiany w `src/main` | `TestMigration: FAIL` "Production code changed"; lista w `metrics.diff.changed` |

Odczyt końcowy:

```powershell
cd projects\icbs-insurances
$b = Get-Content sdlc-baseline.json -Raw | ConvertFrom-Json
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"tests: baseline $($b.tests.total) -> $($r.metrics.tests.total); coverage: $($b.coverage.line) -> $($r.metrics.coverage.line)"
@($r.metrics.diff.changed) | Where-Object { $_ -match '^src/main/' }
(Get-ChildItem src\test -Recurse -File -Include *.groovy).Count
$r.warnings
```

Gotowe znaczy: `status: PASSED`, `TestMigration`, `TestIntegrity`, `Regression` i `XrayScan` = `PASS`, zero plików `.groovy` w `src/test` (poza DSL kontraktów, jeśli zostały).

## 6. Uwaga o szablonach

Podpięty projekt ma kopię agentów i `tools/sdlc.ps1` z chwili podpięcia. Projekt podpięty przed dodaniem scenariusza `tests` trzeba pobrać od nowa: `.\scripts\start-scenario.ps1 -Fresh`.
