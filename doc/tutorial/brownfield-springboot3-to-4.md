# Tutorial: migracja Spring Boot 3.5 → 4.1, Java 21 → 25 - projekt `icbs/insurancesv1`

Scenariusz brownfield typu `migration`: orchestrator przenosi istniejący projekt na nową wersję platformy. Kod produkcyjny zmienia się tylko tam, gdzie wymagają tego nowe wersje. Testy są dostosowywane tylko do przeniesionych API, bez zmiany oczekiwanych wyników. Zadanie kończy się, gdy pipeline jest zielony (w tym Xray), a `pom.xml` deklaruje docelowe wersje.

Poprzedni krok na tym projekcie: [brownfield-spock-to-junit5.md](brownfield-spock-to-junit5.md) (testy w JUnit 5, commit `9d35643` na `sdlc-work`). Kiedy który typ scenariusza: sekcja 1 tamtego tutorialu.

## 1. Co sprawdza pipeline w scenariuszu `migration`

Przepływ: `analyst` (lista zmian łamiących) -> `planner` -> `developer` (`pom.xml` + `src/main`) -> `test-engineer` (tylko przeniesione API w testach) -> `security-reviewer` (gdy zmieniła się konfiguracja bezpieczeństwa) -> weryfikacja.

Bramka `MigrationGuard` (tylko gdy `sdlc-settings.json` ma `scenario: migration`):
- `pom.xml` deklaruje `migrationBootVersion` (rodzic `spring-boot-starter-parent`) i `migrationJavaVersion` (`java.version`);
- liczba wykonanych i zaliczonych testów nie mniejsza niż w baseline.

`TestIntegrity` działa w pełnym trybie: usunięty test, usunięta metoda, mniej asercji, `@Disabled` lub nowe `NOSONAR` = `FAIL`. `Regression`: każdy test zielony w baseline musi być zielony po migracji, pokrycie nie może spaść. Nowe zgłoszenie Sonara blokuje tylko wtedy, gdy leży na linii zmienionej w zadaniu. Zgłoszenia na niezmienionym kodzie (reguły włączone przez nową wersję Javy, adnotacje nullability w Spring 7) trafiają do `warnings` i należą do osobnego zadania `sonarfix`.

## 2. Konfiguracja: `config/scenario-config.yaml`

```yaml
scenarioType: migration
scenarioProject: "icbs-insurances"
scenarioRepoUrl: "https://gitlab.centrala.bzwbk/icbs/insurancesv1.git"

migrationBootVersion: 4.1.1
migrationJavaVersion: 25

diffGuardMaxFiles: 200
diffGuardMaxLines: 12000
diffGuardMode: warn
coverageTolerance: 0.0
```

JDK: przy `scenario: migration` `attach-project.ps1` wybiera JDK wersji `migrationJavaVersion` (tu 25, `java-tools\java`). Baseline też jest liczony na JDK 25. Projekt kompiluje się na nim od czasu migracji testów, bo Lombok jest jawnie na ścieżce procesorów adnotacji.

## 3. Kroki

### Krok 1. Nowe zadanie na podpiętym projekcie

W katalogu głównym repozytorium:

```powershell
.\scripts\start-scenario.ps1 -NewTask
```

`-NewTask`:
- przenosi pliki poprzedniego zadania (`task.md`, `analysis.md`, `plan.md`, `sdlc-baseline.json`, `sdlc-report.json`, `sdlc-cost.json`, `recon-report.json`) do `sdlc-history\<data-czas>\`;
- nadpisuje narzędzia i agentów aktualnymi szablonami (`tools\*.ps1`, `.github\agents`, `.github\copilot-instructions.md`);
- zapisuje `sdlc-settings.json` z `scenario: migration`, `migrationBootVersion`, `migrationJavaVersion` i `javaHome` = JDK 25;
- uruchamia rozpoznanie (`recon-report.json`).

Wymaganie: drzewo gita czyste (poprzednia praca w commicie).

### Krok 2. Okno VS Code

Otwórz `projects\icbs-insurances` w nowym oknie VS Code (zamknij poprzednie okno projektu, żeby wczytały się nowe wersje agentów). Środowisko orchestrator podnosi sam.

### Krok 3. Zadanie

W czacie `@sdlc-orchestrator`, prompt z sekcji 4.

## 4. Prompt dla orchestratora

```
Scenariusz: migration. Migracja projektu ze Spring Boot 3.5.16 na 4.1.1 i z Javy 21 na 25. Gałąź: sdlc-work.

Kontekst (z pom.xml i Artifactory, sprawdzone 2026-10-15):
- jawnie przypięte wersje, które blokują nowy BOM: hibernate-core 6.5.3.Final, spring-boot-maven-plugin 3.4.7, springdoc-openapi 2.8.6 (dostępne 3.1.1), spring-cloud-contract 4.2.1 (dostępne 5.0.3), rest-assured spring-mock-mvc 5.4.0 (dostępne 6.1.0), jacoco 0.8.11 (Java 25 wymaga co najmniej 0.8.14), jackson-bom 2.22.3 (import jawny, Boot 4 używa Jacksona 3), jakarta.validation-api, httpcore5;
- biblioteki firmowe mają wersje pod Boot 4: logging-filter 4.1.3 (Boot 4.1.1, Java 25), dcicbs 4.1.2 (Boot 4.1.1, Java 25), jwt-spring 4.2.0 (Boot 4.0.2, Java 21), icbs-starter-monitoring 1.0.5 (Boot 4.1.1, Java 25; deklaruje jwt-spring 3.1.0 - sprawdź konflikt z 4.2.0);
- QueryDSL: com.querydsl 5.1.0 nie ma poprawki CVE-2024-49203; fork io.github.openfeign.querydsl 7.x ją ma i wspiera Hibernate 7, ale wymaga zmiany w src/main (InsuranceRiskPremiumQuerydslRepositoryImpl: .sum() -> .sumAggregate()). querydsl-apt zostaje tylko na ścieżce procesorów adnotacji;
- XrayScan przed migracją: 4 znaleziska (spring-webmvc 6.2.19 x3 - poprawka w Spring 7.0.9; querydsl-jpa 5.1.0). Po migracji Xray musi być PASS;
- mvn verify uruchamia aplikację (spring-boot:start, profil dev) i springdoc nadpisuje insurances.yaml - przywróć go przez git checkout -- insurances.yaml przed końcową weryfikacją.

Najpierw analiza (analysis.md), przed jakąkolwiek zmianą:
1. Tabela wszystkich zależności i pluginów z jawną wersją: obecna -> docelowa, czy zarządza nią BOM Boot 4, czy to biblioteka firmowa.
2. Zmiany łamiące, które dotykają tego kodu, z file:line: przeniesione pakiety, usunięte API, zmienione nazwy właściwości konfiguracji, Jackson 2 -> 3, Hibernate 7, Spring Security 7, adnotacje testowe Boot 4 (@MockBean, pakiety @WebMvcTest/@DataJpaTest), springdoc 3, Spring Cloud Contract 5.
3. Procesory adnotacji (Lombok, QueryDSL) na Javie 25.
4. Lista decyzji dla mnie: zmiany zachowania, których nie da się uniknąć (np. format JSON, format błędów).

Zasady:
- Kolejność: pom.xml -> kompilacja src/main -> konfiguracja -> testy -> Xray.
- Usuń przypięcia wersji, którymi zarządza nowy BOM; zostaw tylko z komentarzem dlaczego.
- Testy: zmieniaj tylko importy, adnotacje i konfigurację mocków. Nie zmieniaj asercji, danych ani oczekiwanych wartości. Jeśli test pada, bo zmieniło się zachowanie produkcyjne - zatrzymaj się i zapytaj.
- Nie kopiuj ani nie forkuj bibliotek firmowych.

Kryteria akceptacji:
1. pom.xml: spring-boot-starter-parent 4.1.1, java.version 25 (bramka MigrationGuard).
2. Wszystkie testy z baseline zielone, liczba testów nie mniejsza (Regression, MigrationGuard), testy nieosłabione (TestIntegrity).
3. Pokrycie linii nie spadło (Regression).
4. Aplikacja startuje w mvn verify (spring-boot:start + springdoc generate przechodzą).
5. tools\sdlc.ps1 kończy się PASSED bez flag -Skip*, w tym XrayScan.
6. Raport: wersje przed -> po dla platformy, Javy i każdej zmienionej zależności; każda zmiana w src/main z powodem.
```

## 5. Na co patrzeć w trakcie (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Baseline na złym JDK | `sdlc-settings.json` `javaHome` = `java-tools\java` (25); `recon-report.json` `versions.javaRuntime` = 25 |
| JaCoCo 0.8.11 nie czyta klas Javy 25 | brak `target\site\jacoco\jacoco.csv` albo pokrycie `null` w raporcie |
| Agent zmienia oczekiwane wartości w testach | `TestIntegrity` (asercje); ręcznie: `git diff HEAD -- src/test` - tylko importy i adnotacje |
| Zmiana zachowania API (Jackson 3: daty, null-e, kolejność pól) | testy kontrolerów i kontraktów; `insurances.yaml` po buildzie (różnice w OpenAPI) |
| Konflikt jwt-spring 3.1.0 (z icbs-starter-monitoring) vs 4.2.0 | `mvn dependency:tree "-Dincludes=pl.santander.utils"` |
| Orchestrator sam edytuje `pom.xml` lub czyta hasła z `settings.xml` | log czatu; reguły w agencie i `copilot-instructions.md` (pkt 12) tego zabraniają |
| `spring-boot:start` nie wstaje (profil `dev`, IBM i) | log `sdlc-run.log`, faza `pre-integration-test` |

Odczyt końcowy:

```powershell
cd projects\icbs-insurances
$b = Get-Content sdlc-baseline.json -Raw | ConvertFrom-Json
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"tests: $($b.tests.total) -> $($r.metrics.tests.total); coverage: $($b.coverage.line) -> $($r.metrics.coverage.line)"
Select-String pom.xml -Pattern '<version>4\.1\.1</version>|<java.version>'
git diff --stat HEAD -- src/main src/test
.\tools\sdlc.ps1 -CheckReport
```

Gotowe znaczy: `status: PASSED`, `MigrationGuard`, `Regression`, `TestIntegrity` i `XrayScan` = `PASS`, `-CheckReport` = 0.

## 6. Wynik przebiegu 2026-10-16

`PASSED` po 4 uruchomieniach `tools\sdlc.ps1` (baseline i 3 weryfikacje), 120 minut, około 3055 premium requests (3,8% puli). Testy 239 → 239, pokrycie linii 64,4% → 71,8%, Xray 4 → 0, Sonar 134 → 134 otwartych.

Co wyszło dopiero w trakcie (nie było w analizie):

| Problem | Rozwiązanie |
|---|---|
| H2 2.4.240 z BOM: "Check constraint invalid" na CHECK generowanych przez Hibernate 7 | `h2.version` 2.3.232 (tylko testy) z komentarzem |
| Hibernate 7: `TransientPropertyValueException` - testy zapisywały składkę bez rodzica `InsuranceRiskDetail` | decyzja użytkownika: zapis rodzica w przygotowaniu danych testu |
| rest-assured 6 (Jackson 3) odrzuca `null` dla `int` przy `.as(...)` | mapper w teście z `configureForJackson2()` |
| `DB2400Dialect` nie istnieje w Hibernate 7, aplikacja nie startowała w `mvn verify` | `DB2iDialect` |
| Spring Cloud Contract 5 pomija testy kontraktowe uznane za aktualne (237 zamiast 239) | `incrementalContractTests=false` |
| Spring Data 4: `PropertyReferenceException`, `TypeInformation` w `org.springframework.data.core` | zmiana importów |
| Xray po migracji: Tomcat 11.0.24 (21), Jackson 3.1.5 (8) | `tomcat.version` 11.0.27, `jackson-bom.version` 3.1.7 z komentarzami CVE |
| 14 "nowych" zgłoszeń Sonara na niezmienionym kodzie (`S7467` Java 22+, `S2259` z nullability Spring 7) | wtedy poprawione w 11 plikach `src/main`; od teraz to ostrzeżenia, do zadania `sonarfix` |

Odchylenia procesu i co zmieniono w szablonach:
- analyst nie miał terminala, wersje były UNVERIFIED i sprawdzał je orchestrator -> analyst ma terminal tylko do odczytu;
- orchestrator uruchomił aplikację z profilem `dev` na prawdziwym AS400 i zapisał odpowiedzi (dane klientów) do porównania JSON -> zakaz w orchestratorze i w `copilot-instructions.md` (pkt 13); dowodem są testy i start w `mvn verify`;
- orchestrator poprawiał pliki źródłowe sam (`Set-Content`, edycje równolegle z delegatem) -> zakaz także przez terminal, brak równoległych delegacji na te same pliki;
- przy czerwonym teście JPA (warunek STOP z planu) najpierw eksperymentował z wersjami, potem zapytał -> STOP = najpierw pytanie;
- `plan.md` bez odhaczonych zadań -> delegaci zaznaczają `[x]`;
- rozpakowane jary i skrypty w `C:\Temp` -> pliki robocze tylko w `target\sdlc-tmp\`;
- czat przeskoczył z `@sdlc-orchestrator` na tryb `agent` po pytaniu do użytkownika - przy każdej odpowiedzi sprawdź, czy wybrany jest `sdlc-orchestrator`.
