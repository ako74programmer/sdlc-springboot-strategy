# B3 - bug-fix z opisu zgłoszenia

**Scenariusz:** `bugfix`

## Zadanie (wklej do czatu)

```
Zgłoszenie z produkcji (shop-service): da się założyć dwóch klientów z tym samym adresem e-mail,
jeśli różnią się wielkością liter, np. "Jan.Kowalski@Example.com" i "jan.kowalski@example.com".
Oczekiwane: druga rejestracja kończy się błędem 409 Conflict, tak jak przy identycznym adresie.
Napraw błąd i zabezpiecz go testem.
```

## Kryteria zaliczenia

- nowy test reprodukujący (np. w `CustomerServiceTest`), najpierw czerwony (`ReproTest` = `RED-RECORDED`), po poprawce zielony (`ReproTest` = `PASS`)
- `sdlc-report.json`: `status: PASSED`, `Regression` i `TestIntegrity` = `PASS`
- zmiana w `CustomerService.java` (+ test), bez zmian w kontrolerze, encji i istniejących testach

## Rozwiązanie (tylko dla oceniającego)

`CustomerService.create` szuka i zapisuje e-mail tylko po `trim()`, bez normalizacji wielkości liter. Poprawka: `trim().toLowerCase(Locale.ROOT)` przed `findByEmail` i zapisem. Dobra odpowiedź może też wspomnieć o istniejących danych zapisanych z wielkimi literami (migracja poza zakresem).
