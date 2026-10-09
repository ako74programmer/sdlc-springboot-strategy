# B2 - bug-fix z padającym testem

**Scenariusz:** `bugfix`

## Zadanie (wklej do czatu)

```
Po ostatniej zmianie w naliczaniu rabatów lojalnościowych testy w projekcie shop-service są czerwone.
Napraw błąd. Testów nie wolno zmieniać.
```

## Kryteria zaliczenia

- `sdlc-report.json`: `status: PASSED`, `Regression`, `TestIntegrity`, `ReproTest` = `PASS`
- zmieniony tylko `DiscountCalculator.java` (DiffGuard: 1 plik, kilka linii)
- `DiscountCalculatorTest` bez zmian (TestIntegrity)
- reprodukcja: istniejący czerwony test, bez pisania nowego (`-ReproTest DiscountCalculatorTest#discountPercent_Exactly1000_ReturnsFive`)

## Rozwiązanie (tylko dla oceniającego)

`DiscountCalculator.discountPercent` porównuje `> 0` zamiast `>= 0` przy obu progach (1000 i 5000), więc wartości dokładnie na progu dostają niższy rabat. Padają 2 testy: `discountPercent_Exactly1000_ReturnsFive`, `discountPercent_Exactly5000_ReturnsTen`. Poprawka: `>= 0` w dwóch miejscach.
