# C4 - migracja platformy ze Spring Boot 3 na 4

**Scenariusz:** `migration`

## Zadanie (wklej do czatu)

```
Zmigruj aplikację shop-service ze Spring Boot 3 na docelową wersję Spring Boot 4.1.1 oraz Java 25. Zaktualizuj konfigurację pom.xml oraz adnotacje testowe tak, aby wszystkie testy przechodziły, a bramka MigrationGuard była zielona.
```

## Kryteria zaliczenia

- `sdlc-report.json`: `status: PASSED`, bramki `Compilation`, `Tests`, `Regression`, `TestIntegrity` i `MigrationGuard` = `PASS`
- w `pom.xml`: wersja parenta to `4.1.1`, właściwość `<java.version>` to `25`
- testy: co najmniej tyle samo testów przechodzących co w baseline (15 testów), bez wyłączania `@Disabled`
- adnotacje testowe zaktualizowane do Spring Boot 4 (`@MockitoBean` zamiast `@MockBean`)

## Rozwiązanie (tylko dla oceniającego)

1. W `pom.xml`:
   - `<parent>` podbity z `3.4.1` do `4.1.1`.
   - `<java.version>` podbite z `21` do `25`.
2. W `CustomerControllerTest.java`:
   - Zamiana `org.springframework.boot.test.mock.mockito.MockBean` na `org.springframework.test.context.bean.override.mockito.MockitoBean` (oraz `@MockBean` -> `@MockitoBean`).
   - Zamiana importu `WebMvcTest` z `org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest` na `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest`.
3. Kompilacja i uruchomienie `tools\sdlc.ps1` – `MigrationGuard` potwierdza poprawność wersji.
