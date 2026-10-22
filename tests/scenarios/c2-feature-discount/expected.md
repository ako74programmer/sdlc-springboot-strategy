# C2 - nowa funkcja (kalkulator rabatu)

**Scenariusz:** `feature`

## Zadanie (wklej do czatu)

```
Zaimplementuj nową funkcję: kalkulator rabatu dla klienta w shop-service.
Endpoint: POST /api/customers/{id}/discount
Żądanie (JSON):
{
  "amount": 100.0,
  "code": "SUMMER10"
}

Odpowiedź (JSON):
{
  "originalAmount": 100.0,
  "discount": 10.0,
  "finalAmount": 90.0
}

Reguły biznesowe i walidacja:
- amount musi być większe od 0 (@Positive lub @DecimalMin).
- code nie może być pusty (@NotBlank).
- Jeśli code to "SUMMER10", nalicz 10% rabatu. W każdym innym przypadku nalicz 0% rabatu (finalAmount = originalAmount).
- Jeśli klient o podanym {id} nie istnieje w bazie, zwróć kod HTTP 404 Not Found.
- Zaimplementuj kontroler, serwis i DTO zgodnie z konwencją projektu.
- Dodaj komplet testów jednostkowych serwisu oraz testów WebMvc kontrolera pokrywających sukces, błędny kod, nieistniejącego klienta i błędy walidacji 400.
```

## Kryteria zaliczenia

- `sdlc-report.json`: `status: PASSED`, bramki `Compilation`, `Tests`, `Regression`, `TestIntegrity` i `DiffGuard` = `PASS`
- dotychczasowe 15 testów klientów przechodzi bez zmian (zero regresji)
- nowe testy jednostkowe i integracyjne dla kalkulacji rabatu, nieistniejącego klienta i walidacji wejścia
- DTO jako Java records lub spójne z konwencjami projektu
- brak bezpośredniego dostępu kontrolera do repozytorium (Controller -> Service -> Repository)

## Rozwiązanie (tylko dla oceniającego)

1. Nowe DTO w pakiecie `customer.dto`: `DiscountRequest(BigDecimal amount, String code)` oraz `DiscountResponse(BigDecimal originalAmount, BigDecimal discount, BigDecimal finalAmount)`.
2. Metoda w `CustomerService`: `calculateDiscount(String customerId, DiscountRequest request)`. Sprawdza istnienie klienta (rzuca `CustomerNotFoundException` w razie braku).
3. Nowy endpoint w `CustomerController`: `@PostMapping("/{id}/discount")`.
4. Testy w `CustomerServiceTest` i `CustomerControllerTest`.
