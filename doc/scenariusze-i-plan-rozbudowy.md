# Scenariusze bitwy na kody i plan rozbudowy generatora (backend Spring Boot)

> Dokument roboczy, zakres: tylko backend (Spring Boot + MongoDB + Maven). Frontend (Angular, san-ui, Playwright) jest poza zakresem tej części.
> Stan wyjściowy: generator obsługuje wyłącznie scenariusz **greenfield** (kod od zera z opisu funkcji). Cały pipeline (`tools/sdlc.ps1`, agenci, bramki) zakłada, że projekt jest świeży i generowany przez nas.

## 1. Ustalenia (odpowiedzi użytkownika, 2026-10-09)

| # | Pytanie | Ustalenie | Skutek dla planu |
|---|---|---|---|
| Z1 | Forma zadania | Użytkownik wpisuje zadanie w czacie GitHub Copilot | Brak integracji z Jira/GitLab na wejściu. Orchestrator zapisuje treść zadania do `task.md` i rozpoznaje typ scenariusza z treści |
| Z2 | Kod istniejącego projektu | Użytkownik sam pobiera kod do katalogu projektów | Brak klonowania w narzędziach. Import = podpięcie istniejącego katalogu (`attach-project.ps1`). Pobrany kod w osobnym katalogu `projects/`; `generated-projects/` bez zmian (patrz 4.0) |
| Z3 | Punktacja | Wszystko: zielony CI, jakość (Sonar), pokrycie | Wszystkie bramki obowiązują w każdym scenariuszu; nie ma bramek "opcjonalnych" poza wyłączanymi konfiguracją |
| Z4 | Limity | Limit prób CI parametrycznie | Parametry w `project-config.yaml`: `sdlc.maxFixIterations` (dziś na sztywno 5 w orchestratorze), `sdlc.maxOfficialCiAttempts`, `sdlc.sameGateStopAfter` (dziś 3) |
| Z5 | Zmiany w `pom.xml` | Dozwolone, wręcz konieczne (np. naprawa CVE) | Nie trzeba budować trybu nieinwazyjnego. JaCoCo można dopisać do pom, jeśli go brakuje. `DiffGuard` nie traktuje `pom.xml` jako zabronionego (w B7/C4 to właściwa zmiana) |
| Z6 | Typ CI organizatora | Nieznany, możliwy Jenkins | Szablon CI odłożony (P3). Lokalny `sdlc.ps1` jest jedynym źródłem prawdy; Jenkinsfile/GitLab CI dopiero gdy typ CI będzie znany |

Czas bitwy: limit nieznany; narzędzia powinny dawać szybki tryb (kompilacja + testy + regresja) i pełny tryb (z Sonarem i Xray).

## 2. Katalog scenariuszy

Legenda priorytetu: **P1** = bardzo prawdopodobne i warto mieć gotowe, **P2** = prawdopodobne, **P3** = możliwe, robić na końcu.
Wejście: co dostajemy. Wynik: co się liczy jako sukces.

### Grupa A: kod od zera (greenfield)

| ID | Scenariusz | Wejście | Wynik / kryterium | Prior. | Status |
|---|---|---|---|---|---|
| A1 | Funkcja z opisu słownego | Opis wymagań (CRUD, workflow, import CSV, agregacje) | Zielony pipeline, testy, pokrycie | P1 | Zrobione |
| A2 | Implementacja pod kontrakt API (OpenAPI first) | Plik `openapi.yaml` | Endpointy zgodne ze specyfikacją co do statusów i schematów; testy kontraktowe | P2 | Brak |
| A3 | Implementacja pod gotowe testy (TDD odwrócone) | Zestaw testów, które na starcie nie przechodzą | Wszystkie dostarczone testy zielone, bez ich modyfikacji | P2 | Brak |
| A4 | Integracja z zewnętrznym serwisem | Opis API zewnętrznego, odporność na błędy | Timeouty, retry, obsługa 5xx, testy z WireMock | P3 | Brak |

### Grupa B: naprawa istniejącego projektu (brownfield, naprawcze)

| ID | Scenariusz | Wejście | Wynik / kryterium | Prior. |
|---|---|---|---|---|
| B1 | Udrożnienie projektu ("nie buduje się / nie startuje") | Projekt z błędem builda lub startu: zła wersja Javy, brakujące zależności, zły plik konfiguracji, konflikt wersji, nieistniejące repo artefaktów, błędne właściwości Mongo | `mvn verify` zielone, aplikacja startuje | **P1** |
| B2 | Bug-fix z padającym testem | Projekt + test, który nie przechodzi | Test zielony, reszta bez regresji | **P1** |
| B3 | Bug-fix z opisem słownym | Opis błędu z Jira ("endpoint zwraca 500 dla pustego pola") | Błąd odtworzony testem, naprawiony, test zostaje w repo | **P1** |
| B4 | Bug-fix ze stack trace / logiem | Wycinek logu produkcyjnego, brak testu | Zlokalizowana przyczyna, test regresyjny, poprawka | P2 |
| B5 | Polowanie na błędy (audyt) | Działający kod bez zgłoszenia | Lista znalezionych błędów + testy je dowodzące + poprawki | P2 |
| B6 | Naprawa Quality Gate | Projekt z czerwonym Sonarem (smells, bugs, podatności, niskie pokrycie) | Quality Gate OK bez wyciszania reguł | **P1** (już przećwiczone w `sonar-loop-test`) |
| B7 | Naprawa podatności zależności | Raport Xray/OWASP z CVE | Podniesione wersje w `pom.xml`, zero naruszeń | P2 |
| B8 | Błąd współbieżności / wyścigu | Test niestabilny lub zduplikowane dane przy równoległych żądaniach | Naprawa (atomowe operacje, unikalny indeks, wersjonowanie `@Version`), test równoległy | P3 |
| B9 | Problem wydajności | Wolny endpoint (N+1, brak indeksu Mongo, ładowanie całej kolekcji, brak paginacji) | Mierzalna poprawa (czas lub liczba zapytań), bez zmiany kontraktu | P3 |

Typowe źródła błędów w Spring Boot + Mongo, na które trzeba przygotować agentów: brak `@Valid`, handler wyjątków zamieniający 4xx na 500, stare nazwy właściwości Mongo po zmianie wersji Boot, `Optional.get()` bez sprawdzenia, porównania `==` na obiektach, `BigDecimal`/daty i strefy czasowe, paginacja przesunięta o 1, wyciek encji w odpowiedzi, brak unikalnego indeksu, zapytania budowane z wejścia użytkownika, `@Transactional` bez managera transakcji w Mongo.

### Grupa C: zmiany w istniejącym projekcie (brownfield, rozwojowe)

| ID | Scenariusz | Wejście | Wynik / kryterium | Prior. |
|---|---|---|---|---|
| C1 | Refaktoryzacja legacy kodu | Klasa-bóg, logika w kontrolerze, duplikacje, brak testów | Zachowanie bez zmian (testy charakteryzujące zielone przed i po), mniej smells, czytelny podział na warstwy | **P1** |
| C2 | Dodanie funkcji do istniejącego projektu | Projekt + opis nowej funkcji | Funkcja zgodna z konwencjami projektu, bez regresji, nowy kod pokryty | **P1** |
| C3 | Uzupełnienie testów | Projekt z niskim pokryciem | Pokrycie powyżej progu (linie i branche), testy sensowne, nie puste asercje | P1 |
| C4 | Migracja frameworka / języka | Stary projekt: Boot 2.x -> 3/4, `javax` -> `jakarta`, Java 8/11 -> 21/25, JUnit 4 -> 5, `RestTemplate` -> `RestClient` | Build i testy zielone na nowej wersji, brak przestarzałych API | P2 |
| C5 | Migracja warstwy danych | Repozytorium JPA/SQL -> MongoDB albo zmiana schematu dokumentu | Dane poprawnie mapowane, migracja idempotentna, testy | P3 |
| C6 | Ewolucja API bez łamania zgodności | Nowa wersja endpointu, pole opcjonalne, wersjonowanie | Stary kontrakt nadal działa, nowy dodany, testy obu | P3 |
| C7 | Obserwowalność i gotowość produkcyjna | Projekt bez logów/health/metryk | Logi bez danych osobowych, health/readiness, metryki, konfiguracja profili | P3 |
| C8 | Odtworzenie dokumentacji z kodu | Projekt bez dokumentacji | OpenAPI, README, opis architektury zgodne z kodem | P3 |

### Grupa D: przeglądy i analiza (bez pisania kodu produkcyjnego)

| ID | Scenariusz | Wejście | Wynik | Prior. |
|---|---|---|---|---|
| D1 | Code review merge requesta | Diff z błędami i naruszeniami standardu | Raport z ustaleniami wg ważności | P3 |
| D2 | Przegląd bezpieczeństwa istniejącego kodu | Projekt | Raport OWASP Top 10, NoSQL injection, mass assignment, sekrety | P2 |

### Grupa E: scenariusze złożone

| ID | Scenariusz | Opis | Prior. |
|---|---|---|---|
| E1 | Mieszanka pod presją czasu | Jeden projekt: nie buduje się (B1) -> ma bug (B2) -> brak testów (C3) -> czerwony Sonar (B6) | P2 |
| E2 | Rozbudowa + sprzątanie | Nowa funkcja (C2) w legacy kodzie, który najpierw trzeba okiełznać (C1) | P2 |

## 3. Co łączy scenariusze (wspólne wymagania)

Wszystkie scenariusze naprawcze i rozwojowe (grupy B-E) mają inną naturę niż greenfield. Wynikają z tego wymagania na narzędzia:

1. **Wczytanie cudzego projektu** (nie generowanie z Initializr) i automatyczne rozpoznanie: narzędzie budowania, wersje Java/Boot, struktura pakietów.
2. **Stan bazowy (baseline)**: zanim cokolwiek zmienimy, zapisujemy ile testów przechodzi, jakie jest pokrycie i ile jest problemów w Sonarze. Bez tego nie da się udowodnić "nie zepsułem niczego".
3. **Bramka regresji** zamiast sztywnych progów: liczba przechodzących testów nie spada, pokrycie nie spada, brak nowych problemów Sonara na nowym kodzie.
4. **Minimalna ingerencja w kod**: projekt z zadania ma własne konwencje. `pom.xml` wolno zmieniać, gdy wymaga tego zadanie, ale agenci nie mogą "przy okazji" przepisywać pół projektu. Potrzebny strażnik rozmiaru diffu.
5. **Testy najpierw**: bug ma najpierw test, który pada; refaktoryzacja ma najpierw testy charakteryzujące. To musi być wymuszone w agentach, nie zostawione domyślnemu zachowaniu modelu.
6. **Dowód odtworzenia**: raport musi pokazywać, że test czerwony przed poprawką jest zielony po niej.

## 4. Plan rozbudowy aplikacji

### 4.0 Zasada zgodności wstecznej (decyzja 2026-10-09)

Scenariusz greenfield działa i nie może zostać zepsuty przez rozbudowę.

- **Faza 1 tylko dodaje nowe pliki.** Bez edycji logiki: `scripts/generate-project.ps1`, `templates/greenfield/*`, `scripts/env-up.ps1`, `config/project-config.yaml`.
- **Dwa rozdzielne szablony (decyzja 2026-10-09):** `templates/greenfield/` (generator) i `templates/brownfield/` (`attach-project.ps1`). Pliki wspólne (`sdlc.ps1`, `jfrog-scan.ps1`, `sonar-project.properties`, agenci) mają osobne kopie w każdym szablonie, bo w brownfield i tak się rozjadą. Jedyna zmiana generatora: ścieżki na `templates/greenfield` (test regresji: wynik identyczny, 26 plików).
- Każda późniejsza zmiana istniejącego pliku (np. bramki w `sdlc.ps1` w Fazie 2) wymaga wcześniej testu regresji greenfield i osobnej zgody użytkownika.
- **Test regresji greenfield:** generacja do `scratch\gen-before` przed zmianami i do `scratch\gen-after` po nich (`-OutputDir`, bez dotykania `generated-projects/`), porównanie listy plików i sum kontrolnych, potem usunięcie obu katalogów. Przy zmianach w `sdlc.ps1` dodatkowo przebieg bramek na projekcie greenfield z `scratch`.
- **Katalogi:** `generated-projects/` zostaje bez zmian (wyłącznie generator). Kod pobrany przez użytkownika trafia do osobnego `projects/`, którego generator nie dotyka, więc regeneracja nie może skasować pobranego kodu.

### 4.1 Zmiany architektoniczne generatora

| # | Zmiana | Plik / miejsce | Opis |
|---|---|---|---|
| 0 | Katalog `projects` | nowy katalog; `.gitignore`, `README.md`, `AGENTS.md` za osobną zgodą | Osobny katalog na pobrany kod obok `generated-projects/`. Bez przemianowywania (decyzja 2026-10-09) |
| 1 | Pojęcie **scenariusza** | `config/scenario-config.yaml` (nowy) | Osobny plik, żeby nie ruszać `project-config.yaml`. Unikalne klucze (płaski parser generatora już używa `type`): `projectsDir`, `scenarioType` (`greenfield|bugfix|refactor|...`), `scenarioProject`, `maxFixIterations` (5), `maxOfficialCiAttempts`, `sameGateStopAfter` (3). Typ może też rozpoznać orchestrator z treści zadania |
| 2 | Wspólny punkt wejścia | `scripts/start-scenario.ps1` (nowy) | Jedna komenda: `-Scenario bugfix -Project <nazwa>`. Dla `greenfield` woła dotychczasowy `generate-project.ps1`, dla pozostałych `attach-project.ps1` |
| 3 | Podpięcie istniejącego projektu | `scripts/attach-project.ps1` (nowy) | Pracuje na katalogu pobranym przez użytkownika do `projects/<nazwa>`, wymaga `pom.xml`. Niczego nie klonuje, nie kasuje i nie woła generatora. Tworzy gałąź roboczą (jeśli to repo git). Kopiuje `tools/` i `.github/agents` **tylko brakujące pliki**, bez nadpisywania własnego `.github` projektu; dodane pliki wpisuje do `.git/info/exclude`. Brak Maven Wrappera: nic nie dodaje; brownfieldowy `sdlc.ps1` i `recon.ps1` używają wtedy `mvn` z PATH (dogenerowany wrapper nie startował przez uszkodzony wpis w `~\.m2\wrapper\dists`). Tokeny i `jfrog-xray.properties` kopiuje, jeśli istnieją. Na końcu uruchamia `recon.ps1`. Środowisko (Mongo, Sonar) podnosi `env-up.ps1 -ProjectPath projects\<nazwa>` jak dziś |
| 4 | Rozpoznanie projektu | `templates/brownfield/recon.ps1` -> `tools/recon.ps1` (nowy) | Wykrywa Maven/Gradle, wersję Javy i Boot, projekt wielomodułowy (`<modules>`: w Fazie 1 tylko ostrzeżenie, metryki niepełne), uruchamia build i testy, zapisuje `recon-report.json` (czy się buduje, ile testów pada, klasy bez testów, największe klasy, czy jest JaCoCo i `sonar-project.properties`) |
| 5 | Baseline i regresja | `templates/brownfield/sdlc.ps1` (Faza 2) | Przełączniki `-Baseline` (zapis `sdlc-baseline.json`) i bramka `Regression` (porównanie z bazą). Szczegóły w 4.2 |
| 6 | JaCoCo i Sonar w cudzym projekcie | `scripts/attach-project.ps1` | Brak JaCoCo w pom: dopisuje go **tylko do pomiaru** (`prepare-agent` + `report`, bez reguły `check`), żeby legacy z niskim pokryciem nie padło przed zapisaniem stanu bazowego; próg w brownfield przejmie `Regression`. Kod własny skryptu (świadoma duplikacja; generatora nie ruszamy). Brak `sonar-project.properties`: generuje go z lokalnym kluczem; istniejącego nie nadpisuje |
| 7 | Progi i limity z configu | `config/scenario-config.yaml`; użycie w orchestratorze i `sdlc.ps1` od Fazy 2 | Próg pokrycia, `maxFixIterations`, `maxOfficialCiAttempts`, `sameGateStopAfter`. Brownfield: dodatkowo pokrycie nowego kodu i brak spadku całości |
| 7a | Instrukcje Copilota dla brownfield | `templates/brownfield/copilot-instructions.md` (nowy) | Krótki wariant: trzymaj się konwencji projektu, minimalna zmiana, `sdlc.ps1` jako źródło prawdy. Greenfieldowy plik (Java 25, Boot 4, pakiety per funkcja) nie trafia do cudzych projektów; istniejącego pliku projektu nie nadpisuje |
| 8 | Kontekst zadania dla agentów | `task.md` w projekcie | Orchestrator zapisuje treść zadania z czatu i typ scenariusza; agenci czytają to zamiast polegać na rozmowie |
| 9 | Szablon CI (odłożony) | `templates/` | Jenkinsfile lub `.gitlab-ci.yml` dopiero po ustaleniu typu CI organizatora (Z6) |

### 4.2 Zmiany w `sdlc.ps1` (bramki)

Obecne bramki zostają. Dochodzą:

| Bramka | Kiedy | Co sprawdza |
|---|---|---|
| `Baseline` (tryb, nie bramka) | Raz, na początku scenariusza brownfield | Zapisuje liczbę testów (przeszły/padły/nazwy), pokrycie, liczbę problemów Sonara |
| `Regression` | Po zmianach | Żaden test, który przechodził w bazie, nie przestał przechodzić; pokrycie >= baza; brak nowych problemów Sonara |
| `ReproTest` | Scenariusze B2-B4 | Wskazany test (`-ReproTest Klasa#metoda`) jest zielony; w bazie był czerwony (zapisany) |
| `DiffGuard` | Refaktoryzacja, bug-fix | Ostrzeżenie/błąd, gdy zmieniono więcej plików lub linii niż próg (parametr), zmodyfikowano istniejące testy (zmiana asercji) albo konfigurację Sonara. Zmiany w `pom.xml` są dozwolone, ale raportowane (w refaktoryzacji i bug-fixie to sygnał ostrzegawczy, w B7/C4 oczekiwany) |
| `TestIntegrity` | Wszystkie brownfield | Brak `@Disabled`, usuniętych testów, osłabionych asercji względem bazy |
| `Mutation` (opcjonalna) | C3 | PIT na zmienionych klasach, żeby testy nie były pustymi asercjami |

Raport `sdlc-report.json` dostaje pola `scenario`, `baseline` i `delta` (testy, pokrycie, Sonar przed i po).

### 4.3 Nowi agenci i zmiany w istniejących

| Agent | Rola | Scenariusze |
|---|---|---|
| `analyst` (nowy) | Rozpoznaje projekt, czyta `recon-report.json`, pisze `analysis.md`: jak się buduje, co jest zepsute, gdzie leży problem, plan minimalnej zmiany | B1-B5, C1-C4 |
| `build-doctor` (nowy) | Naprawia wyłącznie to, co blokuje build i start (pom, właściwości, wersje, konfiguracja), bez ruszania logiki | B1 |
| `bug-hunter` (nowy) | Odtwarza błąd testem (czerwony), lokalizuje przyczynę, proponuje najmniejszą poprawkę; w trybie audytu szuka błędów w kodzie | B2-B5, B8 |
| `refactorer` (nowy) | Najpierw testy charakteryzujące, potem małe kroki, po każdym pipeline; zakaz zmiany zachowania | C1 |
| `migrator` (nowy) | Prowadzi migracje wersji i API krokami, z listą zmian niekompatybilnych | C4, C5 |
| `perf-investigator` (nowy, P3) | Mierzy przed i po (liczba zapytań, czas), wskazuje indeksy i paginację | B9 |
| `planner` | Dochodzi tryb "plan zmiany w istniejącym kodzie" (minimalny zakres, lista dotykanych plików) | C2 |
| `developer` | Dochodzi zasada: zgodność z konwencjami projektu, nie z naszymi szablonami, gdy projekt ma własne | wszystkie brownfield |
| `test-engineer` | Dochodzą tryby: test odtwarzający błąd, testy charakteryzujące, uzupełnianie pokrycia | B2-B4, C1, C3 |
| `security-reviewer` | Tryb audytu istniejącego kodu, wynik jako lista z lokalizacjami | D2, B7 |
| `quality-fixer` | Bez zmian w roli; dopisać obsługę bramek `Regression`, `DiffGuard`, `TestIntegrity` | wszystkie |
| `sdlc-orchestrator` | Wybór przepływu wg `task.md` (tabela niżej), wspólne Definition of Done | wszystkie |

Przepływy w orchestratorze (jedna tabela, bez osobnych orchestratorów):

| Scenariusz | Kolejność |
|---|---|
| A1 | planner -> developer -> test-engineer -> security-reviewer -> sdlc -> quality-fixer (obecny) |
| B1 | analyst -> build-doctor -> sdlc (kompilacja, testy) |
| B2/B3/B4 | `-Baseline` -> analyst -> bug-hunter (test czerwony) -> developer (poprawka) -> sdlc (`Regression`, `ReproTest`) -> quality-fixer |
| B5 | analyst -> bug-hunter (audyt) -> test-engineer -> developer -> sdlc |
| B6/B7 | sdlc (odczyt problemów) -> quality-fixer -> sdlc (pętla jak dziś) |
| C1 | `-Baseline` -> analyst -> test-engineer (charakteryzujące) -> refactorer (małe kroki) -> sdlc po każdym kroku |
| C2 | `-Baseline` -> analyst -> planner -> developer -> test-engineer -> security-reviewer -> sdlc |
| C3 | `-Baseline` -> analyst -> test-engineer -> sdlc (`Mutation` opcjonalnie) |
| C4 | `-Baseline` -> analyst -> migrator -> test-engineer -> sdlc |
| D1/D2 | security-reviewer lub code review -> raport, bez bramek |

### 4.4 Zestaw treningowy (fixtures)

Do ćwiczeń potrzebne projekty z celowo wstrzykniętymi problemami. Bez nich nie da się sprawdzić, czy nowe agenci i bramki działają.

- Katalog `fixtures/` z gotowymi, małymi projektami lub łatkami (`*.patch`) nakładanymi na świeżo wygenerowany projekt greenfield.
- Jeden fixture na scenariusz priorytetu P1/P2: `b1-broken-build`, `b2-failing-test`, `b3-bug-report`, `b6-red-sonar`, `c1-god-class`, `c2-add-feature`, `c3-low-coverage`, `c4-boot-upgrade`.
- Każdy fixture ma `expected.md`: co jest błędem, jaki jest poprawny wynik, ile prób dopuszczamy. To jest kryterium zaliczenia ćwiczenia.
- Skrypt `scripts/new-fixture.ps1 -Name b2-failing-test` rozpakowuje fixture do `scratch\` i uruchamia scenariusz.

## 5. Fazy realizacji

| Faza | Zakres | Wynik / kryterium zaliczenia |
|---|---|---|
| 0 | Z1-Z6 ustalone (sekcja 1); osobny katalog `projects/`; zasada zgodności wstecznej (4.0) | Zatwierdzony zakres |
| 1 | Fundament brownfield, wyłącznie nowe pliki: `config/scenario-config.yaml`, `scripts/attach-project.ps1`, `scripts/start-scenario.ps1`, `templates/brownfield/*` (recon, instrukcje, własne kopie `sdlc.ps1`/agentów); `templates/greenfield/` = przeniesione dotychczasowe szablony. Za osobną zgodą: `projects/` w `.gitignore`, notatki w `README.md` i `AGENTS.md` | (1) Atrapa projektu Maven w `scratch` daje `recon-report.json` i przechodzi `sdlc.ps1`. (2) Test regresji greenfield (4.0): wynik generatora identyczny przed i po |
| 2 | Test regresji greenfield przed zmianą `sdlc.ps1`; Baseline + `Regression` + `TestIntegrity` + `DiffGuard`; limity z configu w orchestratorze; agenci `analyst`, `build-doctor`, `bug-hunter`; przepływy B1-B3, B6 | Fixture B1, B2, B3, B6 zaliczone przez orchestratora |
| 3 | Agenci `refactorer`, rozszerzony `test-engineer`; przepływy C1-C3 | Fixture C1, C2, C3 zaliczone; refaktoryzacja nie zmienia zachowania (testy charakteryzujące zielone przed i po) |
| 4 | `Mutation` opcjonalnie; `migrator` (C4), przepływy B4, B5, B7, D2 | Fixture C4, B4, B5 zaliczone |
| 5 | P3: B8, B9, C5-C8, A2-A4, D1; szablon CI (po ustaleniu typu) | Według czasu |
| 6 | Próba generalna: scenariusz E1 na nieznanym fixture, pomiar czasu, korekta promptów | Raport z próby, lista poprawek |

Każda faza kończy się aktualizacją `AGENTS.md` (nowe pułapki, nowa procedura monitorowania) oraz sekcji "Co jeszcze nie zostało zweryfikowane".

## 6. Ryzyka i decyzje do podjęcia

| Ryzyko | Konsekwencja | Propozycja |
|---|---|---|
| Cudzy projekt używa Gradle lub starej Javy | `sdlc.ps1` jest pod Maven i Javę z configu | Faza 1: wykrywanie narzędzia; Gradle jako osobna ścieżka dopiero po potwierdzeniu Z1 |
| Agent poprawia więcej niż trzeba (przepisuje projekt) | Regresje, rozjazd z konwencjami, kara za diff | `DiffGuard` + jawna zasada minimalnej zmiany w każdym agencie brownfield |
| Agent "naprawia" test zamiast kodu | Fałszywy sukces | `TestIntegrity` i porównanie z bazą po nazwach testów |
| Brak sieci do baz CVE/NVD | OWASP niedziała | Jak dziś: Xray jako jedyna bramka podatności |
| Wstrzykiwanie `.github/` i `tools/` do repo zadania | Zaśmiecenie lub naruszenie reguł zadania | `.git/info/exclude`, nie `.gitignore` projektu |
| Regeneracja kasuje katalog projektu | Utrata pobranego kodu i pracy | Pobrany kod w osobnym `projects/`, którego generator nie dotyka; `attach-project.ps1` nigdy nie woła generatora |
| Rozbudowa psuje działający greenfield | Utrata sprawdzonej funkcjonalności | Zasada 4.0: Faza 1 tylko nowe pliki; późniejsze zmiany istniejących plików po teście regresji i za zgodą |
| Cudzy projekt bez Maven Wrappera | Greenfieldowy `sdlc.ps1` woła tylko `mvnw.cmd` | Brownfieldowa kopia `sdlc.ps1` używa `mvn` z PATH, gdy brak wrappera |
| Legacy z niskim pokryciem | Reguła JaCoCo `check` 60% wywala bramkę Tests przed jakąkolwiek zmianą | W brownfield JaCoCo tylko do pomiaru; próg przez `Regression` (Faza 2) |
| Zadanie tylko w czacie, bez formalnego typu | Zły przepływ | Orchestrator zapisuje `task.md`, podaje rozpoznany scenariusz i pyta, gdy typ jest niejednoznaczny |
| Sonar: projekt zadania ma własny `projectKey` | Skan idzie w złe miejsce | `sonar.projectKey` nadpisywany z linii poleceń na klucz lokalny; klucz organizatora tylko przy oficjalnej próbie |
| Typ CI organizatora nieznany | Lokalny wynik może się różnić od oficjalnego | Lokalny pipeline jest odpowiednikiem, nie kopią; po ustaleniu CI dopasować komendy i progi |
| Ograniczony czas bitwy | Za wolna pętla (pełny Sonar po każdej zmianie) | Tryb szybki: kompilacja + testy + regresja; Sonar na końcu i przed oficjalną próbą CI |

## 7. Pierwszy krok

Faza 0 zamknięta. Następny krok: Faza 1 w zakresie z sekcji 5, po potwierdzeniu użytkownika. Najwięcej wartości dają B1, B2, B3, B6, C1, C2, bo to najczęstsze scenariusze i wszystkie opierają się na tym samym fundamencie (import, baseline, regresja).
