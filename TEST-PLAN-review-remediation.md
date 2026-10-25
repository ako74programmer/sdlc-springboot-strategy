# Plan testu: review -> remediation (zmiany z 2026-10-25)

Ten plik przenosi kontekst sesji z 2026-10-25 na inny komputer. Na stanowisku źródłowym nie było narzędzi (JDK, Maven, Docker/SonarQube, jf), więc nic nie zostało uruchomione. Wszystko poniżej jest **niezweryfikowane w przebiegu agentów**. Przeszły tylko statyczne testy repozytorium (`python -m pytest -q tests`, 7/7).

## 1. Kontekst: co zostało zmienione i dlaczego

Punkt wyjścia: audyt zgodności z [refactor-model.md](refactor-model.md) (model: `review` -> raport -> wybór zakresu -> jeden scenariusz). Decyzje użytkownika:

| # | Decyzja | Realizacja |
|---|---|---|
| 1 | Xray poza `vulnfix` jest tylko pomiarem; czerwony wynik = kolejne zadanie `vulnfix` | `templates/brownfield/sdlc.ps1`: poza `vulnfix` ukończony skan z ustaleniami daje `XrayScan: FINDINGS`, nie blokuje `PASSED`, wpis w `warnings`. Skan, który nie mógł się wykonać (exit 2: jf/token/serwer), nadal `FAIL`. Skille, `quality-fixer`, `security-reviewer`, `copilot-instructions.md` zaktualizowane |
| 2 | `tests` nie zmienia `src/main` nawet dla testowalności; taka zmiana to świadoma decyzja użytkownika i osobne zadanie | `skills/tests/SKILL.md`; `pom.xml` tylko zależności/wtyczki testowe |
| 3 | Raport `review` z podziałem na obszary i numerami ustaleń | `skills/review/SKILL.md`: `Fxx` w `analysis.md`, `SEC-xx` w `security-review.md`, każde ustalenie ma typ kolejnego zadania; sekcja „Summary by area” (podatności + rekomendacja quick/full, Sonar mechaniczne/zmieniające zachowanie/do decyzji, testy, migracja) |
| 4 | Mocniejsze zabezpieczenie trybu `vulnfix` | `VulnGuard`: przy `vulnfixMode: auto` wymaga w `task.md` linii `VulnFix mode: quick` albo `VulnFix mode: full` przed zmianą; FAIL przy konflikcie z wymuszonym trybem i przy `full` ze zmianą kodu/testów bez `plan.md`. Raport ma `vulnfixModeEffective` |
| 5 | Agenci i skille tylko po angielsku (ASCII) | Test `test_agents_and_skills_are_ascii`; orchestrator klasyfikuje zadanie po znaczeniu, w dowolnym języku |
| - | `remediation` z czatu („Napraw ustalenia z review”) | Orchestrator nie nadpisuje `task.md` z `Scenario: review`; prosi o `start-scenario.ps1 -Scenario remediation -NewTask`. `remediation` bierze domyślnie CRITICAL/HIGH z typem `remediation` + Sonar do 0 (decyzja: Sonar zostaje w zakresie). Raport bez numerów = powtórz `review` |

## 2. Przygotowanie stanowiska

Wymagane: Git, PowerShell 5.1+, Python 3 (testy statyczne), JDK zgodne z projektem (+ JDK 25 dla migracji), Maven 3.9.16 (albo pobranie z Artifactory przez `attach-project.ps1`), Docker (SonarQube i baza), JFrog CLI `jf`.

```powershell
git clone https://github.com/ako74programmer/sdlc-springboot-strategy.git
cd sdlc-springboot-strategy
git checkout refactor/config-driven-factory
git pull
python -m pytest -q tests          # oczekiwane: 7 passed
```

Terminal nie może mieć starych zmiennych (stary `SONAR_TOKEN` ma pierwszeństwo przed `sonar-token.txt`):

```powershell
Remove-Item Env:SONAR_TOKEN, Env:JF_URL, Env:JF_ACCESS_TOKEN -ErrorAction SilentlyContinue
```

## 3. Parametryzacja konfiguracji

1. Konfiguracja stanowiska (plik ignorowany przez Git):

   ```powershell
   Copy-Item config\project-config.local.example.yaml config\project-config.local.yaml
   notepad config\project-config.local.yaml
   ```

   Uzupełnij: `maven.settingsFile`, `maven.jdksDir`, `maven.mavensDir`, `maven.mavenVersion` (3.9.16 = obraz CI), `sdlc.xrayUrl`, `sdlc.xrayWatches`, `sdlc.xrayInsecureTls`, `databaseType` (`none|mongodb|postgresql|db2|h2`), `databaseHost`, `databasePort`.

2. Tokeny (nigdy nie wklejaj ich do czatu):
   - JFrog: zmienna `JF_ACCESS_TOKEN` albo plik `jfrog.token` w katalogu głównym repo;
   - SonarQube: tworzy go `env-up.ps1` (`sonar-token.txt`).

3. Scenariusz w `config/scenario-config.yaml` zostaw pusty (`scenarioType`, `scenarioProject`, `scenarioRepoUrl`, `scenarioBaseBranch` = `""`); podawaj je parametrami CLI. `vulnfixMode: auto`.

## 4. Wariant A: projekt z GitLaba

```powershell
# pobranie (git clone do projects\<Project>) i podpięcie jako review
.\scripts\start-scenario.ps1 -Scenario review `
    -Project <nazwa-projektu> `
    -RepoUrl https://<gitlab-host>/<grupa>/<nazwa-projektu>.git `
    -BaseBranch <gałąź-bazowa>        # opcjonalnie, np. develop

# środowisko (SonarQube + baza wg databaseType, token Sonara do projektu)
.\scripts\env-up.ps1 -ProjectPath projects\<nazwa-projektu>
```

`-Fresh` kasuje istniejący folder i klonuje ponownie (pyta o potwierdzenie). Klonowanie używa Twoich poświadczeń Gita (SSH albo Git Credential Manager).

## 5. Wariant B: fixture lokalny (bez GitLaba)

```powershell
.\scripts\new-fixture.ps1 -Name b6-red-sonar
.\scripts\start-scenario.ps1 -Scenario review -Project b6-red-sonar
.\scripts\env-up.ps1 -ProjectPath projects\b6-red-sonar
```

Uruchamiaj fixture po kolei: wszystkie mają ten sam klucz Sonara.

## 6. Kontrola przed startem agentów

```powershell
cd projects\<projekt>
Get-Content sdlc-settings.json | ConvertFrom-Json | Select scenario, vulnfixMode, javaHome, mavenHome, sonarMaxOpenIssues, reviewSource
Test-Path tools\sdlc.ps1, tools\jfrog-scan.ps1, jfrog-xray.properties, .github\skills\review\SKILL.md, .github\agents\sdlc-orchestrator.agent.md
```

Oczekiwane: `scenario = review`, wszystkie pliki `True`.

## 7. Krok 1: review (w VS Code otwartym na `projects\<projekt>`)

W czacie wybierz agenta `@sdlc-orchestrator` i napisz:

> Przejrzyj projekt i powiedz, co wymaga naprawy.

Sprawdź po przebiegu:

- [ ] `task.md`: `Scenario: review`, `Review scope: project`; orchestrator nie pytał o listę kontrolną;
- [ ] `sdlc-report.json` z baseline: `gates.Toolchain = PASS`; `XrayScan` = `FINDINGS` albo `PASS` (nie `FAIL`, gdy skan się wykonał);
- [ ] `analysis.md`: ustalenia `F01`, `F02`... z ważnością, `file:line`, typem kolejnego zadania; sekcja **Summary by area** (podatności z rekomendacją quick/full, Sonar w trzech grupach, testy, migracja);
- [ ] `security-review.md`: `SEC-01`... z **Follow-up**; ważność Xray tylko tutaj (w `analysis.md` same odwołania);
- [ ] każdy numer w dokładnie jednym proponowanym zadaniu;
- [ ] `git diff --stat refs/sdlc/baseline` jest pusty; brak delegacji do developer/quality-fixer/build-doctor.

## 8. Krok 2: remediation z czatu (test ochrony raportu)

W tym samym czacie, **bez** uruchamiania skryptu:

> Napraw ustalenia z review

Oczekiwane: orchestrator **nie** nadpisuje `task.md` i prosi o uruchomienie skryptu. Sprawdź:

```powershell
Select-String task.md -Pattern 'Scenario: review'   # nadal jest
```

Następnie, w katalogu głównym repo:

```powershell
.\scripts\start-scenario.ps1 -Scenario remediation -Project <projekt> -NewTask
Get-Content projects\<projekt>\sdlc-settings.json | ConvertFrom-Json | Select scenario, reviewSource, sonarMaxOpenIssues
```

Oczekiwane: `scenario = remediation`, `reviewSource = sdlc-history/<data>`, `sonarMaxOpenIssues = 0`.

W nowym czacie ponów: „Napraw ustalenia z review”.

## 9. Krok 3: przebieg remediation

- [ ] `task.md`: `Scenario: remediation`, zakres jako lista ID (domyślnie CRITICAL/HIGH z typem `remediation`);
- [ ] jedno pytanie zbiorcze o decyzje (zmiany zachowania/bezpieczeństwa, czynności użytkownika), zanim ruszy planner;
- [ ] `plan.md`: tabela ustaleń (id, ważność, partia, delegat, dowód, status) na ID `Fxx`/`SEC-xx`; **brak partii Xray**;
- [ ] ustalenia typu `vulnfix`, `tests`, `migration` pozostają jako kolejne zadania;
- [ ] brak `NOSONAR`, `@SuppressWarnings`, `@Disabled`, zmian w `sonar-project.properties`;
- [ ] końcowy `-CiParity`, `security-review.md` w katalogu głównym ze statusem `fixed`/`still open` dla każdego `SEC-xx` w zakresie.

Raport końcowy:

```powershell
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status) ciParity: $($r.ciParity)"; $r.gates | Format-List
"xray: $($r.metrics.xray.findings) sonar: $($r.metrics.sonar.openIssues)"
$r.warnings
.\tools\sdlc.ps1 -CheckReport     # exit 0 = raport opisuje bieżący kod
```

Oczekiwane: `PASSED`, `SonarQube-Issues`/`TestCount`/`Regression`/`TestIntegrity` = `PASS`, `XrayScan` = `FINDINGS` (z wpisem w `warnings`) lub `PASS`.

## 10. Dodatkowe testy zmian

| Test | Polecenie / działanie | Oczekiwane |
|---|---|---|
| Tryb vulnfix niezadeklarowany | `start-scenario.ps1 -Scenario vulnfix -Project <p> -NewTask`, baseline, zmiana tylko w `pom.xml`, `task.md` bez `VulnFix mode:`, `tools\sdlc.ps1 -SkipSonar` | `VulnGuard: FAIL` „vulnfix mode not decided” |
| Tryb quick | dopisz `VulnFix mode: quick`, zmień plik w `src/main` | `VulnGuard: FAIL` „Files other than build files” |
| Tryb full bez planu | `VulnFix mode: full`, zmiana w `src/main`, brak `plan.md` | `VulnGuard: FAIL` „without plan.md” |
| Xray jako pomiar | scenariusz `sonarfix` lub `tests` na projekcie z podatnościami | `XrayScan: FINDINGS`, `status` niezależny od Xray |
| Xray bez dostępu | błędny token w `tests` | `XrayScan: FAIL` (exit 2) |
| tests bez `src/main` | `tests` - orchestrator przy nietestowalnym kodzie | zatrzymuje się i pyta; brak zmian w `src/main` |

## 11. Wznowienie rozmowy z asystentem na drugim komputerze

Napisz w czacie:

> Przeczytaj `AGENTS.md` i `TEST-PLAN-review-remediation.md`. Monitoruję test review -> remediation na projekcie `<projekt>`. Sprawdzaj stan według sekcji 7-10.

Asystent tylko odczytuje stan projektu i zgłasza odchylenia; niczego nie poprawia w trakcie przebiegu agentów bez prośby.
