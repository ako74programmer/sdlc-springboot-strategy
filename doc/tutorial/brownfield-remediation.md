# Tutorial: naprawa po przeglądzie (scenariusz `remediation`) - projekt `be-wesola_banda_piratow`

`remediation` naprawia to, co znalazł `review`. Raport z przeglądu (`analysis.md`, `security-review.md`) jest wsadem: każde ustalenie ma ID (`F01`, `SEC-02`), a zadanie kończy się tabelą, w której każde ustalenie z zakresu ma status.

| Krok | Scenariusz | Wynik |
|---|---|---|
| 1 | [`review`](brownfield-review.md) | raport, bez zmian w kodzie |
| 2 | `remediation` | poprawki, zielony pipeline jak w CI, status każdego ustalenia |

## 1. Zakres

Domyślnie (gdy zadanie nie wskazuje inaczej):
- wszystkie ustalenia CRITICAL i HIGH z obu raportów;
- Xray do zera (każdy podatny komponent, niezależnie od ważności);
- działająca analiza SonarQube i 0 otwartych zgłoszeń.

MEDIUM i LOW tylko po wskazaniu ID w zadaniu, np. „dodatkowo F06, F07”.

Statusy w tabeli ustaleń (`plan.md`):

| Status | Znaczenie |
|---|---|
| `fixed` | naprawione, z dowodem (test, bramka, ponowny skan) |
| `user decision` | Twoja decyzja, np. „nie usuwamy `jwt`” |
| `deferred` | przeniesione, z powodem, np. polityka autoryzacji wymaga decyzji biznesowej (to nowa funkcja, nie poprawka) |

## 2. Sekrety: `secrets.local.env` i `tools\run-local.ps1`

Hasło wpisane w konfigurację (np. `application.yml`) agenci zamieniają na `${NAZWA_ZMIENNEJ}` bez wartości domyślnej i dopisują `secrets.local.env` do `.gitignore`. Wartość wpisujesz Ty:

```
# projects\be-wesola_banda_piratow\secrets.local.env  (nigdy nie trafia do gita)
DEMO_MONGO_PASSWORD=...
```

| Narzędzie | Co robi z `secrets.local.env` |
|---|---|
| `tools\sdlc.ps1` | wczytuje plik do zmiennych środowiskowych na czas przebiegu (testy, także failsafe), w raporcie podaje tylko nazwy (`secretsLoaded`), wartości maskuje (`***`), po przebiegu przywraca środowisko |
| `tools\run-local.ps1` | uruchamia aplikację z tymi zmiennymi: `.\tools\run-local.ps1`, `.\tools\run-local.ps1 -SpringProfile local` |

Agenci nie czytają tego pliku, nie wpisują wartości i nie kopiują ich z historii gita. Nazwy zmiennych podają w raporcie; orchestrator czeka, aż wypełnisz plik, gdy test go potrzebuje.

Stare hasło zostaje w historii gita. Rotacja (i ewentualne czyszczenie historii) to Twoja czynność - raport wypisze ją jako otwartą. W projekcie demo możesz to świadomie pominąć.

Plik jest też w `.git/info/exclude`. Wartości trafiają do JVM testów, więc mogą się pojawić w `target\surefire-reports` (ignorowany przez gita) i w wyjściu Mavena w terminalu, gdy test wypisze je w komunikacie błędu.

## 3. Co robią agenci

| Etap | Agent | Wynik |
|---|---|---|
| Wsad | orchestrator | czyta raport z `reviewSource` (`sdlc-history/<data>`), zapisuje w `task.md` zakres jako listę ID |
| Stan początkowy | orchestrator | `.\tools\sdlc.ps1 -Baseline`; baseline może nie mieć danych Sonara, gdy przegląd znalazł zepsutą konfigurację Sonara - wtedy to pierwsza partia |
| Decyzje | Ty | jedna lista: pytania z raportu, poprawki zmieniające zachowanie lub zabezpieczenia (`permitAll`, CSRF, publiczne endpointy, usuwane zależności), Twoje czynności (rotacja, `secrets.local.env`) |
| Plan | planner | `plan.md`: tabela ustaleń (ID, ważność, partia, agent, dowód, status) i partie |
| Partie | build-doctor / quality-fixer / developer / test-engineer | konfiguracja builda i Sonara -> zależności (Xray) -> konfiguracja i sekrety -> kod -> zgłoszenia Sonara -> testy |
| Weryfikacja | orchestrator | `.\tools\sdlc.ps1` po każdej partii builda/zależności i co 2-3 pozostałe |
| Sprawdzenie bezpieczeństwa | security-reviewer | nowy `security-review.md`: każde `SEC-xx` z zakresu `fixed` / `still open` z dowodem, nowe problemy w diffie |
| Koniec | orchestrator | `.\tools\sdlc.ps1 -CiParity`, raport z tabelą ustaleń |

## 4. Bramki

Jak w `sonarfix`: `SonarQube-Issues` (0 otwartych zgłoszeń; `attach-project.ps1 -Scenario remediation` ustawia `sonarMaxOpenIssues: 0`), `TestCount` (testów nie mniej niż w baseline), `Regression`, `TestIntegrity`. `XrayScan` obowiązkowy. Przebieg bez odczytanych zgłoszeń Sonara nigdy nie jest `PASSED`.

Gotowe znaczy: `status: PASSED` z `-CiParity`, `SonarQube`, `SonarQube-QualityGate`, `SonarQube-Issues`, `XrayScan`, `TestCount`, `Regression`, `TestIntegrity` = `PASS`, każde ustalenie z zakresu ma status w `plan.md`.

## 5. Konfiguracja: `config/scenario-config.yaml`

```yaml
scenarioType: remediation
scenarioProject: "be-wesola_banda_piratow"

diffGuardMaxFiles: 40             # remediation touches build, config, code and tests
diffGuardMaxLines: 1500
diffGuardMode: warn
```

## 6. Kroki

### Krok 1. Przegląd

Projekt musi mieć zakończony `review` (w głównym katalogu projektu: `task.md` z `Scenario: review`, `analysis.md`, `security-review.md`). Zobacz [brownfield-review.md](brownfield-review.md).

### Krok 2. Nowe zadanie

W katalogu głównym repozytorium:

```powershell
.\scripts\start-scenario.ps1 -Scenario remediation -NewTask
```

`-NewTask` przenosi raport z przeglądu do `sdlc-history\<data-czas>\`, odświeża narzędzia i agentów z szablonów, a `sdlc-settings.json` dostaje `scenario: remediation`, `sonarMaxOpenIssues: 0` i `reviewSource`. Sprawdź w wyjściu linię `Review report for remediation: sdlc-history/...`.

### Krok 3. Środowisko i okno VS Code

```powershell
.\scripts\env-up.ps1 -ProjectPath projects\be-wesola_banda_piratow
```

Zamknij okno z przeglądu. Otwórz `projects\be-wesola_banda_piratow` w **nowym** oknie VS Code, wybierz `@sdlc-orchestrator`.

### Krok 4. Zadanie

Prompt z sekcji 7. Po pierwszej odpowiedzi orchestratora (lista decyzji) odpowiedz na każdy punkt. Gdy poprosi o `secrets.local.env`, wypełnij plik i napisz, że gotowe.

## 7. Prompt dla orchestratora

```
Scenariusz: remediation. Napraw ustalenia z ostatniego przeglądu (reviewSource w sdlc-settings.json).

Zakres: wszystkie CRITICAL i HIGH z analysis.md i security-review.md, Xray do zera, działająca analiza SonarQube i 0 otwartych zgłoszeń. MEDIUM i LOW: brak (albo: <lista ID>).

Zasady:
- Decyzje (pytania z raportu, zmiany zachowania i zabezpieczeń, moje czynności) zbierz w jedną listę przed planem.
- Hasła z konfiguracji do zmiennych środowiskowych bez wartości domyślnej; wartości wpiszę sam do secrets.local.env.
- Bez wyciszania (NOSONAR, @SuppressWarnings, wykluczenia), bez osłabiania testów, bez nowych funkcji.

Kryteria akceptacji:
1. Końcowy tools\sdlc.ps1 -CiParity: PASSED; SonarQube, SonarQube-QualityGate, SonarQube-Issues (0), XrayScan, TestCount, Regression, TestIntegrity = PASS.
2. plan.md: każde ustalenie z zakresu ma status fixed / user decision / deferred z dowodem albo powodem.
3. Raport: tabela ustaleń, moje decyzje, otwarte czynności po mojej stronie, Xray i Sonar przed -> po, ustalenia poza zakresem jako kolejne zadania.
```

## 8. Na co patrzeć w trakcie (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Wsad nie z przeglądu | `reviewSource` w `sdlc-settings.json`; raport w `sdlc-history\<data>\` niezmieniony |
| Zakres rozjechany z zadaniem | lista ID w `task.md` = tabela w `plan.md` |
| Wartość sekretu w repozytorium | `git diff refs/sdlc/baseline` zawiera `${...}`, a nie wartości; `git status` nie pokazuje `secrets.local.env`; `.gitignore` zawiera `secrets.local.env` |
| Zmiana zabezpieczeń bez decyzji | zmiany w konfiguracji Spring Security tylko z decyzją w `task.md` |
| Wyciszanie Sonara | brak `NOSONAR`, `@SuppressWarnings`, nowych `sonar.exclusions` w `pom.xml`; `sonar-project.properties` bez zmian |
| Osłabione testy | `TestIntegrity`, `TestCount` = `PASS` |
| Xray „bez poprawki” | przed zgłoszeniem blokady: podbita najnowsza łatka i ponowny skan |

## 9. Odczyt końcowy

```powershell
cd projects\be-wesola_banda_piratow
.\tools\sdlc.ps1 -CheckReport
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status), ciParity: $($r.ciParity), secrets: $($r.secretsLoaded -join ',')"; $r.gates | Format-List
"sonar: $($r.metrics.sonar.openIssues), tests: $($r.metrics.tests.passed)/$($r.metrics.tests.total) (failsafe $($r.metrics.tests.integration))"
git --no-pager diff --stat refs/sdlc/baseline
Select-String -Path plan.md -Pattern "fixed|user decision|deferred"
```

## 10. Typowe problemy

| Objaw | Co zrobić |
|---|---|
| `No archived review report in sdlc-history/` | najpierw `review`, potem `start-scenario.ps1 -Scenario remediation -NewTask` |
| `The review report is still in the project root` | uruchomiono bez `-NewTask`; powtórz z `-NewTask`, inaczej `remediation` nadpisze `task.md` i `security-review.md` przeglądu |
| `SonarQube-Issues: Open SonarQube issues not read` | Sonar nie działa albo konfiguracja projektu przerywa analizę; ta druga to pierwsza partia planu |
| Test pada z braku zmiennej (np. `DEMO_MONGO_PASSWORD`) | wypełnij `secrets.local.env`; `sdlc-report.json` -> `secretsLoaded` pokazuje wczytane nazwy |
| Test wymaga VPN (failsafe) | od 2026-10-20 `sdlc.ps1` liczy też failsafe; bez VPN test będzie czerwony - decyzja o teście jest na liście decyzji |

## Start z czatu (od 2026-10-25)

Gdy w projekcie leży jeszcze raport `review` (`task.md` z `Scenario: review`), orchestrator go nie nadpisuje: prosi o `start-scenario.ps1 -Scenario remediation -NewTask` i ponowienie polecenia. Raport `review` numeruje ustalenia `Fxx` (analysis.md) i `SEC-xx` (security-review.md) i każdemu przypisuje typ kolejnego zadania; `remediation` bierze domyślnie CRITICAL/HIGH z typem `remediation` oraz Sonar do 0. Raport bez numerów (stary format) = powtórz `review`.
