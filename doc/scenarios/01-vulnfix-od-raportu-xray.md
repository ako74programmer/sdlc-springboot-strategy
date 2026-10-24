# Scenariusz użytkownika: naprawa podatności z raportu Xray

## Cel

Sprawdzić pełny przepływ brownfield: repozytorium → branch roboczy → baseline → analiza Xray → zmiany w `pom.xml`/kodzie → ponowne skany → raport końcowy.

## Warunki początkowe

- Wykonano [konfigurację fabryki](00-konfiguracja-fabryki.md).
- Dostępne są Maven, JDK, SonarQube i Xray zgodnie z konfiguracją lokalną.
- Użytkownik ma URL repozytorium i raport podatności albo link do zadania Jira.

## Kroki

1. Uruchom PowerShell w katalogu fabryki.
2. Uruchom scenariusz, podając repozytorium i nazwę scenariusza:

   ```powershell
   .\scripts\start-scenario.ps1 `
     -Scenario vulnfix `
     -RepoUrl https://git.example.corp/team/service.git `
     -Project service
   ```

3. Poczekaj na zakończenie pobierania i `attach-project.ps1`.
4. Otwórz `projects/service` w nowym oknie VS Code.
5. W chacie wybierz agenta `sdlc-orchestrator`.
6. Wklej polecenie, na przykład:

   ```text
   Zrealizuj scenariusz vulnfix na podstawie raportu Xray z zadania Jira ABC-123.
   Nie kończ pracy, dopóki wymagane bramki nie przejdą.
   ```

7. Pozwól orchestratorowi wykonać analizę, baseline, plan, zmiany i iteracje pipeline’u.
8. Po zakończeniu sprawdź:

   ```powershell
   git -C projects/service status --short --branch
   Get-Content projects/service/sdlc-report.json
   ```

## Oczekiwany rezultat

- Projekt znajduje się w `projects/service`.
- Istnieje branch roboczy `sdlc-work`.
- Istnieją `sdlc-baseline.json`, `sdlc-report.json`, `analysis.md` i `plan.md`.
- Zmiany w `pom.xml` są ograniczone do wymaganych aktualizacji zależności.
- `Tests`, `Regression`, `VulnGuard` i wymagane skany mają status `PASS`.
- Raport końcowy nie pokazuje nierozwiązanych podatności objętych zadaniem.
- Narzędzia fabryki i raporty robocze nie są przypadkowo commitowane do repozytorium projektu.

Jeżeli Xray lub SonarQube są niedostępne, wynik powinien być jawnie nieukończony albo `FAIL`, a nie `PASS`.
