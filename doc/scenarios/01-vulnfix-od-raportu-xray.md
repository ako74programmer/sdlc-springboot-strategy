# Scenariusz użytkownika: `vulnfix` — naprawa podatności

## Cel

Naprawić podatności i tylko te zmiany w `pom.xml`, kodzie lub testach, które są wymagane przez aktualizację zależności. Problemy SonarQube, coverage i ogólna refaktoryzacja są osobnymi scenariuszami.

## Warunki początkowe

- Wykonano [konfigurację fabryki](00-konfiguracja-fabryki.md).
- Dostępne są Maven, JDK i Xray zgodnie z konfiguracją lokalną.
- Użytkownik ma URL repozytorium albo projekt znajduje się już w `projects/`.

## Wariant zalecany — najpierw review

Jeżeli nie wiadomo, czy aktualizacja wymaga zmian w kodzie, najpierw uruchom [przegląd i wybór zakresu](05-review-i-wybor-zakresu.md). Review nie zmienia kodu i zwraca rekomendację:

- `vulnfix.quick` — tylko `pom.xml`/`.mvn/`,
- `vulnfix.full` — wymagane zmiany kodu lub testów,
- `sonarfix` — problemy SonarQube,
- `tests` — coverage i brakujące testy,
- `migration` — zmiana platformy/JDK,
- `refactor` — zmiana struktury bez zmiany zachowania.

## Kroki bez wcześniejszego review

1. Uruchom PowerShell w katalogu fabryki.
2. Uruchom jeden scenariusz biznesowy `vulnfix`:

   ```powershell
   .\scripts\start-scenario.ps1 `
     -Scenario vulnfix `
     -RepoUrl https://git.example.corp/team/service.git `
     -Project service
   ```

   Domyślny tryb `auto` pozwala orchestratorowi wybrać `quick` albo `full` po analizie.
3. Aby wymusić zakres, użyj:

   ```powershell
   # Tylko aktualizacje plików builda
   .\scripts\start-scenario.ps1 -Scenario vulnfix -VulnFixMode quick -Project service

   # Dopuszczalne konieczne zmiany kodu i testów
   .\scripts\start-scenario.ps1 -Scenario vulnfix -VulnFixMode full -Project service
   ```

4. Otwórz `projects/service` w VS Code i przekaż agentowi:

   ```text
   Napraw podatności. Nie naprawiaj przy okazji problemów SonarQube ani coverage.
   Jeśli wystarczą zmiany w pom.xml, użyj vulnfix.quick. Jeśli potrzebne są zmiany kodu lub testów, użyj vulnfix.full.
   ```

5. Poczekaj na analizę, baseline Xray, zmiany i ponowny skan.
6. Sprawdź:

   ```powershell
   git -C projects/service status --short --branch
   Get-Content projects/service/sdlc-settings.json
   Get-Content projects/service/sdlc-report.json
   ```

## Oczekiwany rezultat

- `sdlc-settings.json` ma `scenario: "vulnfix"` oraz `vulnfixMode: "auto"`, `"quick"` albo `"full"`.
- `XrayScan`, `VulnGuard`, `Compilation`, `Tests`, `Regression` i `TestIntegrity` mają właściwy status.
- W trybie `quick` zmienione są wyłącznie `pom.xml` i/lub `.mvn/`.
- W trybie `full` każda zmiana kodu/testów jest uzasadniona aktualizacją zależności.
- Raport pokazuje podatności i komponenty przed → po oraz nierozwiązane elementy z dowodami.
- Problemy SonarQube nie są automatycznie naprawiane w ramach vulnfix.

Jeżeli aktualizacja wymaga kodu lub testów, tryb `quick` ma się zatrzymać i wskazać konieczność uruchomienia `vulnfix.full`, a nie rozszerzać zakres samodzielnie.
