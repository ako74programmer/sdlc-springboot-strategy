# B7 - szybka aktualizacja wersji podatności (vulnfix.quick)

**Scenariusz:** `vulnfix`

**Tryb:** `quick`

## Zadanie (wklej do czatu)

```
Zaktualizuj wersje zależności w pom.xml zgodnie z zadaniami podatności CYB: podbij wersje do najnowszych bezpiecznych w repozytorium firmowym. Zmieniaj wyłącznie pliki budowania (pom.xml), nie modyfikuj kodu źródłowego ani testów.
```

## Kryteria zaliczenia

- `sdlc-report.json`: `status: PASSED`, bramki `Compilation`, `Tests`, `Regression`, `TestIntegrity` i `VulnGuard` = `PASS`
- zmienione wyłącznie pliki budowania (`pom.xml`, `.mvn/`)
- wersja `commons-text` podniesiona do bezpiecznej (>= 1.10.0 lub najnowszej w repozytorium) z komentarzem CVE
- zero zmian w katalogu `src/` (żaden plik Java niezmodyfikowany)

## Rozwiązanie (tylko dla oceniającego)

1. Narzędzie `tools/xray-candidates.ps1` wykrywa starszą wersję `commons-text:1.9` (CVE-2022-42889).
2. Agent podnosi wersję w `pom.xml` na najnowszą dostępną (np. `1.12.0` lub `1.13.0`) z komentarzem `<!-- CVE-2022-42889 -->`.
3. Testy kompilują się i przechodzą czysto bez dotykania kodu produkcyjnego.
