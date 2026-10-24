# Scenariusz użytkownika: migracja Spring Boot

## Cel

Sprawdzić, że fabryka potrafi przeprowadzić migrację projektu Spring Boot, zachowując testy, wykrywając regresję i używając właściwego JDK.

## Kroki

1. Skopiuj repozytorium lub użyj już pobranego projektu.
2. Uruchom:

   ```powershell
   .\scripts\start-scenario.ps1 `
     -Scenario migration `
     -RepoUrl https://git.example.corp/team/service.git `
     -Project service-migration `
     -BaseBranch develop
   ```

3. Otwórz `projects/service-migration` w VS Code.
4. W chacie uruchom `sdlc-orchestrator` poleceniem:

   ```text
   Przeprowadź migrację zgodnie ze scenariuszem migration.
   Użyj docelowych wersji z konfiguracji fabryki, zachowaj testy i zakończ dopiero po przejściu bramek.
   ```

5. Poczekaj na zakończenie iteracji.
6. Sprawdź raport:

   ```powershell
   Get-Content projects/service-migration/sdlc-settings.json
   Get-Content projects/service-migration/sdlc-report.json
   ```

## Oczekiwany rezultat

- `MigrationGuard` ma status `PASS`.
- `Regression` ma status `PASS`.
- `TestIntegrity` ma status `PASS`.
- `Toolchain` potwierdza JDK zgodny z wymaganiem projektu lub migracji.
- Zmiany w `pom.xml` i kodzie są opisane w `plan.md`.
- W przypadku niegotowej bazy wynik jasno wskazuje problem środowiska; fabryka nie raportuje fałszywego sukcesu.
