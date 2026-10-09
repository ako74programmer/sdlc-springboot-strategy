# B1 - udrożnienie projektu (nie buduje się)

**Scenariusz:** `buildfix`

## Zadanie (wklej do czatu)

```
Projekt shop-service przestał się budować po podbiciu Spring Boot do wersji 4. Udrożnij build tak,
żeby kompilacja i wszystkie testy przechodziły. Nie zmieniaj logiki biznesowej.
```

## Kryteria zaliczenia

- `sdlc-report.json`: `status: PASSED`, `Compilation` i `Tests` = `PASS`, 15 testów zielonych
- `TestIntegrity` = `PASS` (żaden test nie usunięty, nie wyłączony, bez mniejszej liczby asercji)
- zmienione tylko `pom.xml` i importy/adnotacje w `CustomerControllerTest.java`; `CustomerService` nadal używa `StringUtils.normalizeSpace`
- bez `-DskipTests`, bez usuwania zależności, z której korzysta kod

## Rozwiązanie (tylko dla oceniającego)

Dwie usterki, druga wychodzi dopiero po naprawie pierwszej:
1. `pom.xml`: `commons-lang3` w wersji `3.99.0`, która nie istnieje. Poprawka: usunąć `<version>` (wersją zarządza BOM Spring Boot) albo podać istniejącą wersję. Usunięcie zależności psuje kompilację `CustomerService`.
2. `CustomerControllerTest`: importy ze Spring Boot 3 (`org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest`, `org.springframework.boot.test.mock.mockito.MockBean`). Poprawka: `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest` i `@MockitoBean` (`org.springframework.test.context.bean.override.mockito.MockitoBean`).
