# B6 - naprawa SonarQube

**Scenariusz:** `sonarfix`

## Zadanie (wklej do czatu)

```
SonarQube zgłasza problemy w projekcie shop-service. Usuń wszystkie otwarte problemy Sonara,
bez wyciszania reguł i bez zmiany zachowania aplikacji.
```

Przed startem: `attach-project.ps1 -Scenario sonarfix` (ustawia `sonarMaxOpenIssues: 0`) i działający SonarQube (`env-up.ps1`).

## Kryteria zaliczenia

- `sdlc-report.json`: `status: PASSED`, `SonarQube-Issues` = `PASS` (0 otwartych problemów)
- `TestIntegrity` = `PASS`: brak `NOSONAR`, `@SuppressWarnings`, zmian w `sonar-project.properties`
- `Regression` = `PASS`: testy jak w bazie, pokrycie nie spada
- zmiany ograniczone do `CustomerExportService.java` (i ewentualnie testu dla niego)

## Rozwiązanie (tylko dla oceniającego)

`CustomerExportService` zawiera typowe problemy wykrywane przez Sonar way (Community):
- wstrzykiwanie przez pole (`@Autowired` na polu) -> konstruktor
- nieużywane pole `lastExport` i nieużywana zmienna `skipped`
- zakomentowany kod
- pusty `catch` (zamknięcie `StringWriter` nie rzuca w praktyce; `try` można usunąć)
- `System.out.println` -> logger SLF4J

Liczba problemów w bazie zależy od wersji reguł Sonara; ważne, żeby na końcu było 0 i żeby zachowanie `exportCsv()` się nie zmieniło.
