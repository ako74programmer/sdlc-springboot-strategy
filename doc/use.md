Read skill `graphify`

Find files matching `.github/**/*`

Find files matching `graphify-out/graph.json`

Find files matching `**/*copilot*`

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\templates\\.github\\copilot-instructions.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Find files matching `templates/.github/**/*`

Find files matching `**/README*`

Ran terminal command: Get-ChildItem -Force; Write-Output '--- repo .github ---'; Get-ChildItem -Force 'C:\Users\Andrzej\Desktop\foo\sdlc\sdlc-springboot-strategy\.github' -ErrorAction SilentlyContinue; Write-Output '--- project ---'; Get-ChildItem -Force 'C:\Users\Andrzej\Desktop\foo\sdlc\sdlc-springboot-strategy\generated-projects\springboot-sdlc-demo'; Write-Output '--- agents anywhere ---'; Get-ChildItem -Path 'C:\Users\Andrzej\Desktop\foo\sdlc\sdlc-springboot-strategy' -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -match '\.github|agent|copilot' } | Select-Object -ExpandProperty FullName

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\.github\\agents\\planner.agent.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\.github\\agents\\developer.agent.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\.github\\agents\\test-engineer.agent.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\.github\\agents\\quality-fixer.agent.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\.github\\agents\\security-reviewer.agent.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\sdlc-report.json",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Find files matching `src/main/resources/*`

"Search" failed
Tool execution failed: rg: unrecognized file type:

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\README.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , line 1 to the end
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\.github\\copilot-instructions.md",
  "view_range": [
    1,
    -1
  ],
  "forceReadLargeFiles": false
}

Read , lines 1 to 240
Completed with input: {
  "path": "C:\\Users\\Andrzej\\Desktop\\foo\\sdlc\\sdlc-springboot-strategy\\generated-projects\\springboot-sdlc-demo\\tools\\sdlc.ps1",
  "view_range": [
    1,
    240
  ],
  "forceReadLargeFiles": false
}

## Jak użytkownik powinien pracować z agentami

Wygenerowany projekt zawiera instrukcję Copilota oraz pięciu dedykowanych agentów:

- `copilot-instructions.md`
- `planner.agent.md`
- `developer.agent.md`
- `test-engineer.agent.md`
- `security-reviewer.agent.md`
- `quality-fixer.agent.md`

Praca powinna przebiegać według kolejności:

```text
Wymaganie
   ↓
@planner
   ↓
plan.md
   ↓
@developer
   ↓
implementacja
   ↓
@test-engineer
   ↓
testy
   ↓
@security-reviewer
   ↓
security-review.md
   ↓
.\tools\sdlc.ps1
   ↓
sdlc-report.json
   ↓
PASS albo @quality-fixer
```

## Przykładowe wymaganie użytkownika

Użytkownik może napisać:

> Zaimplementuj prosty CRUD dla danych klienta w Spring Boot.  
> Encja klienta ma zawierać: `id`, `firstName`, `lastName`, `email`, `phone`.  
> Dane mają być przechowywane w bazie H2.  
> Udostępnij endpointy REST:
>
> - `POST /api/customers`
> - `GET /api/customers`
> - `GET /api/customers/{id}`
> - `PUT /api/customers/{id}`
> - `DELETE /api/customers/{id}`
>
> Dodaj walidację danych wejściowych, obsługę błędów i pełny zestaw testów.  
> Pracuj zgodnie z instrukcją Copilota, architekturą Controller → Service → Repository oraz pipeline’em SDLC. Nie kończ pracy, dopóki pipeline nie przejdzie.

## Co dzieje się dalej

### 1. Planowanie

Uruchamiany jest agent `@planner`.

Jego zadaniem jest:

- przeanalizowanie wymagania,
- ustalenie modelu danych,
- zaplanowanie encji, DTO, repozytorium, serwisu i kontrolera,
- zaplanowanie walidacji i obsługi wyjątków,
- wskazanie testów,
- utworzenie `plan.md`.

Agent planner nie powinien implementować kodu. Tworzy wyłącznie plan.

Przykładowe polecenie:

> @planner Przygotuj plan implementacji CRUD dla klienta zgodnie z opisanym wymaganiem. Uwzględnij H2, walidację, obsługę błędów, testy i kryteria akceptacji. Utwórz `plan.md`.

### 2. Implementacja

Po utworzeniu planu uruchamiany jest `@developer`.

Przykładowe polecenie:

> @developer Przeczytaj `plan.md` i zaimplementuj całość zgodnie z planem. Użyj architektury Controller → Service → Repository, DTO jako rekordów Java, walidacji Bean Validation, constructor injection i transakcji. Nie twórz testów — zrobi to osobny agent. Po implementacji uruchom kompilację zgodnie z instrukcją agenta.

Developer powinien utworzyć między innymi:

```text
src/main/java/.../customer/
├── controller/CustomerController.java
├── dto/CustomerRequest.java
├── dto/CustomerResponse.java
├── entity/Customer.java
├── exception/CustomerNotFoundException.java
├── repository/CustomerRepository.java
└── service/CustomerService.java
```

### 3. Testy

Następnie uruchamiany jest `@test-engineer`.

Przykładowe polecenie:

> @test-engineer Przeczytaj `plan.md` oraz zaimplementowany kod. Dodaj testy jednostkowe serwisu, testy repozytorium z `@DataJpaTest` oraz testy kontrolera z `@WebMvcTest`. Pokryj scenariusze sukcesu, walidacji, braku klienta, aktualizacji i usuwania. Uruchom testy i popraw ewentualne błędy.

Wymagane są między innymi:

- testy serwisu z Mockito,
- testy mapowania i zapisu w H2,
- testy wszystkich endpointów,
- testy błędnych danych wejściowych,
- testy odpowiedzi `404 Not Found`.

### 4. Przegląd bezpieczeństwa

Następnie uruchamiany jest `@security-reviewer`.

Przykładowe polecenie:

> @security-reviewer Przeanalizuj zmodyfikowane pliki pod kątem OWASP Top 10, walidacji danych, ujawniania danych, obsługi wyjątków, konfiguracji CORS, zależności i logowania. Utwórz `security-review.md`. Nie modyfikuj kodu.

Jeśli agent znajdzie problemy, należy je naprawić przed końcowym pipeline’em.

### 5. Pipeline SDLC

Na końcu uruchamiany jest lokalny pipeline:

```powershell
.\tools\sdlc.ps1
```

Sprawdza on:

1. kompilację,
2. testy,
3. pokrycie kodu JaCoCo,
4. podatności zależności przez OWASP Dependency-Check,
5. analizę SonarQube i Quality Gate.

Źródłem prawdy jest `sdlc-report.json`.

## Co w przypadku błędu

Jeżeli raport zawiera:

```json
{
  "status": "FAILED"
}
```

należy uruchomić `@quality-fixer`.

Przykładowe polecenie:

> @quality-fixer Przeczytaj `sdlc-report.json`, zidentyfikuj dokładnie wszystkie nieudane bramki i napraw wyłącznie przyczyny tych błędów. Nie wyłączaj bramek, nie obniżaj progów pokrycia i uruchom pipeline ponownie.

Agent powinien działać iteracyjnie:

```text
sdlc-report.json → analiza errors i metrics → poprawka → sdlc.ps1 → ponowna analiza
```

## Aktualny stan projektu

Obecny raport projektu wskazuje:

- kompilacja: **PASS**,
- testy: **PASS**,
- SonarQube i OWASP: pominięte w ostatnim uruchomieniu,
- pokrycie linii: **33,3%**,
- wymagane minimum: **60%**,
- wynik końcowy: **FAILED**.

Czyli pipeline prawidłowo wykrył niedostateczne pokrycie testami. W takiej sytuacji właściwym kolejnym krokiem jest `@quality-fixer` albo — jeżeli brakuje testów funkcjonalnych — ponowne uruchomienie `@test-engineer`.

Najważniejsza zasada: użytkownik opisuje wymaganie biznesowe, a agenci realizują kolejne etapy. Użytkownik nie powinien prosić wszystkich agentów jednocześnie o implementację, ponieważ każdy z nich ma inną odpowiedzialność.