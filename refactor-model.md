Użytkownik nie powinien zaczynać od konfiguracji technicznej ani zastanawiać się, jaki typ pipeline’u wybrać. Powinien powiedzieć:

> „Przejrzyj projekt i powiedz, co wymaga naprawy.”

Dopiero na podstawie raportu wybiera się zakres pracy:

- tylko podatności,
- tylko problemy SonarQube,
- tylko testy i coverage,
- migracja,
- refaktoryzacja,
- kompleksowe uporządkowanie projektu.

To jest naturalny proces:

```text
Review → raport → decyzja o zakresie → wybrany scenariusz → wykonanie → weryfikacja
```

## Proponowany model scenariuszy

### 1. `review` — pierwszy krok

`review` powinien być scenariuszem diagnostycznym, który:

- analizuje kod,
- uruchamia testy,
- sprawdza coverage,
- wykonuje SonarQube,
- wykonuje Xray,
- sprawdza konfigurację Maven/JDK,
- analizuje `pom.xml`,
- identyfikuje ryzyka migracyjne,
- nie zmienia kodu.

Wynikiem powinien być raport z podziałem na obszary:

```text
Podatności:
- 7 podatności Xray
- 3 mają prostą aktualizację wersji
- 2 wymagają zmian w kodzie
- 2 nie mają obecnie wersji naprawczej

SonarQube:
- 24 problemy
- 18 mechanicznych
- 4 potencjalnie zmieniające zachowanie
- 2 wymagają decyzji użytkownika

Testy:
- coverage linii: 41%
- coverage branchy: 22%
- brak testów dla 5 kluczowych serwisów

Migracja:
- Spring Boot 3.x
- Java 17
- przestarzałe API
- ryzyka aktualizacji bibliotek
```

Najważniejsze: `review` nie powinien automatycznie naprawiać wszystkiego. Ma dostarczyć podstawę decyzji.

### 2. `vulnfix` — tylko podatności
Ten scenariusz powinien realizować:
- aktualizację zależności,
- zmiany w `pom.xml`,
- konieczne zmiany w kodzie,
- konieczne dostosowanie testów,
- skan Xray,
- weryfikację regresji.

Cel:

```text
Napraw podatności i nie zmieniaj niezwiązanej funkcjonalności.
```

To może być kompleksowa naprawa podatności, ale nie musi automatycznie naprawiać wszystkich problemów SonarQube ani zwiększać coverage, chyba że są bezpośrednim skutkiem aktualizacji.

### 3. `sonarfix` — tylko jakość kodu

Ten scenariusz powinien realizować:

- naprawę problemów SonarQube,
- zachowanie istniejącego zachowania,
- ochronę przed wyciszaniem problemów,
- ochronę przed usuwaniem lub osłabianiem testów.

Cel:

```text
Zredukuj problemy SonarQube bez zmiany zachowania aplikacji.
```

Nie powinien przy okazji aktualizować wszystkich zależności ani przeprowadzać migracji Spring Boot.

### 4. `tests` — testy i coverage

Ten scenariusz powinien:

- dodawać brakujące testy,
- zwiększać coverage,
- zachować kod produkcyjny, poza ewentualnymi minimalnymi zmianami wymaganymi do testowalności,
- nie zmieniać zachowania biznesowego,
- nie zajmować się podatnościami jako głównym celem.

Cel:

```text
Zwiększ pokrycie i jakość testów bez modyfikowania funkcjonalności.
```

### 5. `migration`, `refactor`, `feature`, `remediation`

Te scenariusze pozostają jako osobne typy, bo mają inne kryteria:

- `migration` — zmiana platformy, Spring Boot, JDK lub głównych bibliotek,
- `refactor` — zmiana struktury kodu bez zmiany zachowania,
- `feature` — nowa funkcjonalność,
- `remediation` — naprawa ustaleń z wcześniejszego review.

## Co z `vulnquick`?

Tu widzę największą możliwość uproszczenia.

Moim zdaniem `vulnquick` nie powinien być głównym scenariuszem biznesowym widocznym dla zwykłego użytkownika. To jest raczej **tryb wykonania dla `vulnfix`**:

```text
vulnfix:
  mode: quick
```

albo:

```text
vulnfix:
  mode: full
```

### Tryb szybki

Może być wybrany automatycznie, gdy review ustali, że:

- wszystkie zmiany dotyczą wyłącznie wersji w `pom.xml`,
- nie ma potrzeby zmian w kodzie,
- nie ma potrzeby zmian w testach,
- aktualizacja przechodzi kompilację i testy,
- nie ma konfliktu API,
- nie trzeba wykonywać SonarQube.

### Tryb pełny

Powinien zostać użyty, gdy:

- zależność wymaga zmian w kodzie,
- zmieniła się wersja Spring Boot,
- zmieniły się API,
- trzeba dostosować testy,
- trzeba przeanalizować wpływ na zachowanie aplikacji,
- szybka aktualizacja nie rozwiązała podatności.

W takim modelu użytkownik mówi tylko:

```text
Napraw podatności.
```

A orchestrator po review decyduje:

```text
Wybrano tryb szybki: zmiany tylko w pom.xml.
```

albo:

```text
Wybrano pełny tryb vulnfix: aktualizacja wymaga zmian w kodzie i testach.
```

To daje prosty UX bez utraty zabezpieczeń.

## Czy użytkownik powinien móc wybrać zakres ręcznie?

Tak. Powinny być dostępne oba warianty:

### Decyzja automatyczna

```text
Przeanalizuj projekt i napraw podatności.
```

Orchestrator wykonuje review i dobiera tryb.

### Decyzja jawna

```text
Napraw wyłącznie podatności w pom.xml.
Nie zmieniaj kodu ani testów.
```

Wtedy fabryka powinna wykonać szybki wariant i zatrzymać się, jeśli aktualizacja wymaga zmian w kodzie.

Albo:

```text
Wykonaj kompleksową naprawę podatności razem z koniecznymi zmianami kodu i testów.
```

Wtedy wybierany jest pełny `vulnfix`.

## Najlepszy docelowy przepływ

### Opcja A — od razu konkretny zakres

```text
Użytkownik:
Napraw podatności.

Fabryka:
- rozpoznaje vulnfix,
- wykonuje baseline,
- analizuje Xray,
- dobiera tryb quick/full,
- realizuje zadanie,
- raportuje wynik.
```

### Opcja B — najpierw przegląd

```text
Użytkownik:
Zrób przegląd projektu i przygotuj raport.

Fabryka:
- wykonuje review,
- nie zmienia kodu,
- tworzy raport.

Użytkownik:
Napraw tylko podatności.

Fabryka:
- realizuje vulnfix.

Użytkownik:
Teraz napraw problemy SonarQube.

Fabryka:
- realizuje sonarfix.

Użytkownik:
Na końcu zwiększ coverage.

Fabryka:
- realizuje tests.
```

To jest bardzo dobry model dla pracy korporacyjnej, bo każda zmiana ma jasny cel i osobny zakres odpowiedzialności.

## Ważne rozdzielenie: cel i zakres

Scenariusz powinien definiować:

- co wolno zmienić,
- czego nie wolno zmienić,
- jakie bramki są obowiązkowe,
- jaki jest warunek zakończenia,
- jaki raport trzeba przygotować.

Nie powinien natomiast definiować tego, jak użytkownik ma konfigurować pliki.

Konfiguracja powinna być automatyczna, a scenariusz powinien wynikać z polecenia:

| Polecenie użytkownika | Scenariusz |
|---|---|
| „Zrób przegląd” | `review` |
| „Napraw podatności” | `vulnfix` |
| „Napraw problemy SonarQube” | `sonarfix` |
| „Zwiększ coverage” | `tests` |
| „Przeprowadź migrację Spring Boot” | `migration` |
| „Zrób refaktoryzację” | `refactor` |
| „Dodaj funkcjonalność” | `feature` |
| „Napraw ustalenia z review” | `remediation` |

## Moja rekomendacja

Nie usuwałbym całkowicie technicznego rozróżnienia `vulnfix` i `vulnquick`, ponieważ mają różne zabezpieczenia i zakres zmian.

Natomiast zmieniłbym ich rolę:

- `vulnfix` — scenariusz użytkownika „napraw podatności”,
- `vulnquick` — wewnętrzny tryb szybkiego wykonania `vulnfix`,
- użytkownik może wymusić tryb szybki, ale nie musi znać jego nazwy,
- orchestrator może automatycznie przełączyć się z quick na full, jeżeli sama zmiana `pom.xml` nie wystarczy.

Czyli docelowo:

```text
Scenariusze biznesowe:
review
vulnfix
sonarfix
tests
migration
refactor
feature
remediation

Tryby techniczne:
vulnfix.quick
vulnfix.full
```