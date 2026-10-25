# Scenariusz użytkownika: review i wybór zakresu

## Cel

Najpierw zdiagnozować projekt, bez zmiany kodu, a następnie zdecydować, który zakres naprawy uruchomić.

## Kroki

1. Skonfiguruj stanowisko według [instrukcji konfiguracji](00-konfiguracja-fabryki.md).
2. Podepnij projekt jako `review`:

   ```powershell
   .\scripts\start-scenario.ps1 `
     -Scenario review `
     -RepoUrl https://git.example.corp/team/service.git `
     -Project service
   ```

3. Otwórz `projects/service` w VS Code. Nie uruchamiaj ręcznie `env-up.ps1` — orchestrator uruchomi SonarQube i wymaganą bazę w ramach flow review.
4. W chacie agenta wpisz:

   ```text
   Przejrzyj projekt i powiedz, co wymaga naprawy.
   ```

   To krótkie polecenie wystarcza. Orchestrator rozpoznaje `review`, przyjmuje
   zakres `project` i uruchamia pełny diagnostyczny flow opisany w skillu review.

5. Poczekaj na `analysis.md`, `security-review.md` i raport pipeline’u.
6. Sprawdź, że review nie zmienił śledzonych plików projektu:

   ```powershell
   git -C projects/service diff --stat refs/sdlc/baseline
   Get-Content projects/service/analysis.md
   Get-Content projects/service/security-review.md
   ```

7. Wybierz kolejny scenariusz na podstawie raportu. Przykłady:

   ```text
   Napraw tylko podatności. Nie zajmuj się SonarQube ani coverage.
   ```

   ```text
   Napraw problemy SonarQube bez zmiany zachowania aplikacji.
   ```

   ```text
   Dodaj brakujące testy i zwiększ coverage, bez zmian funkcjonalnych.
   ```

## Oczekiwany raport

Raport powinien zawierać osobne sekcje:

- **Podatności** — komponent, CVE, severity, wersja obecna, możliwa wersja docelowa, Xray przed/po;
- **SonarQube** — liczba problemów według reguły i severity, lokalizacje oraz ryzyko zmiany zachowania;
- **Testy** — liczba testów, wyniki, coverage linii i branchy, brakujące obszary;
- **Build/toolchain** — JDK, Maven, `settings.xml`, problemy kompilacji i konfiguracji;
- **Migracja** — ryzyka Spring Boot/JDK/API;
- **Follow-up** — osobne propozycje z typem scenariusza: `vulnfix`, `sonarfix`, `tests`, `migration`, `refactor`, `buildfix` albo `remediation`.

## Oczekiwany rezultat

- `review` nie modyfikuje kodu, testów ani `pom.xml`.
- Raport może mieć czerwone bramki — są one ustaleniami, nie zmianami wykonywanymi w review.
- Każda dalsza praca ma jeden jasno określony scenariusz i własne kryteria zakończenia.

## Xray poza `vulnfix`

W scenariuszach innych ni? `vulnfix` skan Xray jest tylko pomiarem: bramka ma stan `FINDINGS`, nie blokuje `PASSED`, a ustalenia trafiaj? do raportu jako kolejne zadanie `vulnfix`. Skan, kt?ry nie m?g? si? wykona? (jf, token, serwer), nadal jest `FAIL`.
