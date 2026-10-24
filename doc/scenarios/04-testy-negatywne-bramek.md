# Scenariusz testów negatywnych bramek

## Cel

Sprawdzić, że fabryka nie kończy pracy statusem `PASS`, gdy dowód jakości lub bezpieczeństwa jest niedostępny.

## Test A — brak Xray dla `vulnfix`

1. Ustaw `enableXray: true`, ale pozostaw `xrayUrl` pusty albo użyj `-SkipXray`.
2. Uruchom `vulnfix`.
3. Sprawdź `sdlc-report.json`.

Oczekiwany rezultat: `VulnGuard` lub `XrayScan` ma `FAIL`/`SKIPPED`, a pipeline nie kończy się jako `ALL GATES PASSED`.

## Test B — brak reprodukcji dla `bugfix`

1. Uruchom scenariusz `bugfix` bez `-ReproTest` i bez zapisanego `sdlc-repro.json`.
2. Uruchom pipeline.

Oczekiwany rezultat: `ReproTest = FAIL`.

## Test C — zbyt duża zmiana

1. W `scenario-config.yaml` ustaw `diffGuardMode: fail`.
2. Wykonaj zmianę przekraczającą `diffGuardMaxFiles` albo `diffGuardMaxLines`.
3. Uruchom pipeline.

Oczekiwany rezultat: `DiffGuard = FAIL`, a kod wyjścia skryptu jest różny od zera.

## Test D — brak SonarQube dla `review`

1. Zatrzymaj SonarQube.
2. Uruchom scenariusz `review` bez `-SkipSonar`.
3. Sprawdź raport.

Oczekiwany rezultat: wynik nie jest `PASS`; raport wskazuje brak analizy lub niedostępne środowisko.
