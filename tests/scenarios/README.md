# Scenariusze testowe (brownfield)

Poligon do sprawdzania agentów i bramek brownfield przed bitwą. Każdy scenariusz to projekt z jednym celowo wstrzykniętym problemem i znanym rozwiązaniem.

## Lista

| Scenariusz | Typ (`-Scenario`) | Problem | Wymaga SonarQube |
|---|---|---|---|
| `b1-broken-build` | `buildfix` | projekt się nie buduje (zła wersja zależności, API ze Spring Boot 3) | nie |
| `b2-failing-test` | `bugfix` | błąd wykrywany przez istniejący, czerwony test | nie |
| `b3-bug-report` | `bugfix` | błąd opisany słownie, bez testu | nie |
| `b6-red-sonar` | `sonarfix` | 7 problemów Sonara w jednej klasie | tak |

## Jak uruchomić

Z katalogu głównego repozytorium:

```powershell
# 1. Środowisko (MongoDB, SonarQube)
.\scripts\env-up.ps1

# 2. Projekt ze scenariusza -> projects\b2-failing-test (osobne repo git, jak pobrany kod)
.\scripts\new-fixture.ps1 -Name b2-failing-test

# 3. Podpięcie narzędzi SDLC z typem scenariusza z tabeli
.\scripts\attach-project.ps1 -Project b2-failing-test -Scenario bugfix
```

4. Otwórz `projects\b2-failing-test` w osobnym oknie VS Code i wywołaj `@sdlc-orchestrator` z tekstem z sekcji **"Zadanie (wklej do czatu)"** w `expected.md` scenariusza.
5. Po zakończeniu porównaj `projects\b2-failing-test\sdlc-report.json` z sekcją **"Kryteria zaliczenia"** w `expected.md`.

Ponowne podejście: usuń `projects\<scenariusz>` i zacznij od kroku 2. Scenariusze uruchamiaj po kolei - wszystkie mają ten sam klucz projektu w Sonarze.

## Zasady

- `expected.md` zawiera rozwiązanie. Nie wklejaj agentom sekcji "Rozwiązanie" i nie kopiuj pliku do projektu (`new-fixture.ps1` tego nie robi).
- Projekt ze scenariusza nie ma znacznika `.sdlc-generated`, więc generator go nie nadpisze.

## Budowa katalogu

| Element | Rola |
|---|---|
| `fixture-config.yaml` | stała konfiguracja generatora dla bazy (`shop-service`, Spring Boot 4.1.1, Java 25), niezależna od `config/project-config.yaml` |
| `_base/overlay/` | poprawna, zielona aplikacja (serwis klientów, 15 testów) nakładana na wygenerowany projekt |
| `<scenariusz>/overlay/` | pliki podmieniane względem bazy |
| `<scenariusz>/apply.ps1` | opcjonalne zmiany, których nie da się zrobić podmianą pliku (np. wpis w `pom.xml`) |
| `<scenariusz>/expected.md` | treść zadania, kryteria zaliczenia, rozwiązanie |

## Nowy scenariusz

1. Utwórz `tests/scenarios/<nazwa>/` z `overlay/` (i ewentualnie `apply.ps1 -ProjectPath <ścieżka>`).
2. Dodaj `expected.md` z sekcjami: Scenariusz (typ), Zadanie (wklej do czatu), Kryteria zaliczenia, Rozwiązanie.
3. Sprawdź bramki: `new-fixture.ps1 -Name <nazwa> -ProjectsDir scratch\projects`, `attach-project.ps1 ... -ProjectsDir scratch\projects`, `tools\sdlc.ps1 -Baseline`, ręczna poprawka, `tools\sdlc.ps1`.
4. Dopisz wiersz do tabeli "Lista".
