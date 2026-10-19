# Tutorial: czysty SonarQube (0 otwartych zgłoszeń) - projekt `icbs/insurancesv1`

Scenariusz brownfield typu `sonarfix`: orchestrator usuwa wszystkie otwarte zgłoszenia SonarQube poprawkami w kodzie, bez zmiany zachowania. Nie wolno niczego wyciszać. Zadanie kończy się, gdy pipeline jest zielony, a Sonar ma 0 otwartych zgłoszeń.

Poprzedni krok na tym projekcie: [brownfield-springboot3-to-4.md](brownfield-springboot3-to-4.md) (Spring Boot 4.1.1, Java 25, gałąź `sdlc-work`).

## 1. Co sprawdza pipeline w scenariuszu `sonarfix`

Przepływ: `analyst` (zgłoszenia pogrupowane po regułach, ryzyko każdej poprawki) -> decyzje użytkownika -> `planner` (partie po regułach) -> `quality-fixer` (jedna partia na delegację, dowód: `mvn test`) -> weryfikacja `tools\sdlc.ps1` co 2-3 partie i na końcu.

Bramki:
- `SonarQube-Issues`: liczba otwartych zgłoszeń <= `sonarMaxOpenIssues` (tu 0). Każde zgłoszenie jest w `errors[]`. W `sonarfix` przebieg bez odczytanych zgłoszeń (`-SkipSonar`, Sonar wyłączony, niepotwierdzona analiza) daje `FAIL`, a `-Baseline` bez danych Sonara kończy się błędem i nie zapisuje `sdlc-baseline.json`.
- `TestCount`: liczba wykonanych i zaliczonych testów nie mniejsza niż w baseline.
- `TestIntegrity`: bez `NOSONAR`, `@SuppressWarnings`, `@Disabled` i zmian w `sonar-project.properties`. Wyjątek dla `sonarfix`: połączenie testów w jeden sparametryzowany (reguła `S5976`) albo podział testu (`S5961`) daje ostrzeżenie, a nie `FAIL`. Strażnikiem jest wtedy `TestCount`.
- `Regression`: testy zielone w baseline zostają zielone, pokrycie nie spada, brak nowych zgłoszeń Sonara.
- `XrayScan` jak zawsze obowiązkowy.

Hotspoty bezpieczeństwa nie wchodzą do bramki (`api/issues` ich nie zwraca). Na starcie projekt ma ich 0.

## 2. Stan wyjściowy (2026-10-16, po migracji)

134 otwarte zgłoszenia, 127 w `src/main`, 7 w `src/test`:

| Liczba | Reguła | Opis | Uwagi |
|---|---|---|---|
| 109 | `java:S116` | nazwy pól (`nr_pesel` -> camelCase) | 103 w `IcbsSchemaField` (pola wysyłane do IBM i przez DCICBS, mają `@RequestField(name=...)`), 3 w `IcbsBeneficiaresField`, 3 w teście |
| 12 | `java:S8688` | jawna strefa czasowa (`ZoneId`/`Clock`) | |
| 2 | `java:S1128` | nieużywany import | |
| 2 | `java:S1165` | pole wyjątku `final` | |
| 1 | `java:S1068` | nieużywane pole prywatne | |
| 1 | `java:S131` | brak `default` w `switch` | |
| 1 | `java:S1450` | pole -> zmienna lokalna | |
| 1 | `java:S1948` | pole nieserializowalne w klasie `Serializable` | |
| 1 | `java:S3400` | metoda zwracająca stałą | |
| 1 | `java:S5786` | zbędne modyfikatory w teście | |
| 1 | `java:S5961` | test z 33 asercjami | |
| 1 | `java:S5976` | 3 testy -> jeden sparametryzowany | |
| 1 | `java:S6856` (BUG) | zmienna `policyId` z mapowania niepowiązana z parametrem | |

## 3. Konfiguracja: `config/scenario-config.yaml`

```yaml
scenarioType: sonarfix
scenarioProject: "icbs-insurances"

diffGuardMaxFiles: 200
diffGuardMaxLines: 12000
diffGuardMode: warn
coverageTolerance: 0.0
```

`attach-project.ps1 -Scenario sonarfix` ustawia `sonarMaxOpenIssues: 0` w `sdlc-settings.json`. JDK jest wybierany z `pom.xml` (Java 25).

## 4. Kroki

### Krok 1. Commit migracji

Drzewo gita musi być czyste. W `projects\icbs-insurances`: `git checkout -- insurances.yaml`, potem commit i push migracji (robisz to sam).

### Krok 2. Nowe zadanie

W katalogu głównym repozytorium:

```powershell
.\scripts\start-scenario.ps1 -NewTask
```

Pliki migracji trafiają do `sdlc-history\<data-czas>\`. Narzędzia i agenci są nadpisywani aktualnymi szablonami, a `sdlc-settings.json` dostaje `scenario: sonarfix` i `sonarMaxOpenIssues: 0`.

### Krok 3. Okno VS Code

Zamknij poprzednie okno projektu. Otwórz `projects\icbs-insurances` w nowym oknie i wybierz `@sdlc-orchestrator`. Po każdej Twojej odpowiedzi sprawdź, czy tryb nie przeskoczył na `agent`.

### Krok 4. Zadanie

Prompt z sekcji 5.

## 5. Prompt dla orchestratora

```
Scenariusz: sonarfix. SonarQube ma być czysty: 0 otwartych zgłoszeń. Gałąź: sdlc-work.

Zasady:
- Poprawki w kodzie, bez zmiany zachowania. Żadnych NOSONAR, @SuppressWarnings, wykluczeń, zmian w sonar-project.properties ani oznaczania zgłoszeń w SonarQube jako "won't fix" / "false positive".
- Najpierw analiza (analysis.md): zgłoszenia pogrupowane po regułach, plan poprawki i ryzyko dla każdej grupy. Poprawki, które mogą zmienić zachowanie (nazwy trafiające do systemów zewnętrznych, strefy czasowe, obsługa null, sygnatury publicznego API, mapowania żądań, łączenie i dzielenie testów), zbierz w jedną listę decyzji dla mnie przed planem.
- Testy: nie usuwaj przypadków i nie zmieniaj oczekiwanych wartości. Liczba wykonanych testów nie może spaść.
- Pracuj partiami po regułach, od mechanicznych do ryzykownych.

Kryteria akceptacji:
1. tools\sdlc.ps1 bez flag -Skip* kończy się PASSED, SonarQube-Issues = PASS przy 0 otwartych zgłoszeniach.
2. Regression, TestIntegrity, TestCount i XrayScan = PASS.
3. Raport: zgłoszenia przed -> po dla każdej reguły, moje decyzje i liczba hotspotów.
```

## 6. Na co patrzeć w trakcie (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Zmiana nazw pól wysyłanych do IBM i | czy analiza sprawdziła, jak `dcicbs` mapuje pola (nazwa z `@RequestField` czy nazwa pola Javy) i czy jest na liście decyzji |
| Zmiana strefy czasowej (`S8688`) | czy decyzja zachowuje dotychczasową strefę (`ZoneId.systemDefault()`) |
| Wyciszanie zamiast poprawek | `Select-String -Path src -Pattern "NOSONAR|SuppressWarnings" -Recurse`; `git diff HEAD -- sonar-project.properties` |
| Osłabione testy przy `S5976`/`S5961` | `git diff HEAD -- src/test`: każdy dawny przypadek jest wierszem danych, oczekiwane wartości bez zmian; `TestCount` = PASS |
| Orchestrator sam edytuje kod | log czatu: edycje tylko w delegacjach, bez `Set-Content` na plikach źródłowych |

Odczyt końcowy:

```powershell
cd projects\icbs-insurances
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status)"; $r.gates | Format-List
"sonar: $($r.metrics.sonar.openIssues) (delta $($r.delta.sonarOpenIssues)); tests: $($r.metrics.tests.total)"
$r.warnings
.\tools\sdlc.ps1 -CheckReport
```

Gotowe znaczy: `status: PASSED`, `SonarQube-Issues`, `TestCount`, `Regression`, `TestIntegrity` i `XrayScan` = `PASS`, 0 otwartych zgłoszeń, `-CheckReport` = 0.
