# Tutorial: przegląd kodu (scenariusz `review`) - projekt `be-wesola_banda_piratow`

Scenariusz `review` to przegląd, którego wynikiem jest **sam raport**. Agenci niczego nie poprawiają: nie zmieniają kodu, testów, `pom.xml`, konfiguracji ani zgłoszeń w SonarQube.

Dwa warianty, wybierane treścią zadania:

| Wariant | Co jest przeglądane | Przykład |
|---|---|---|
| przegląd zmian | różnice gałęzi względem gałęzi docelowej (`git diff <baza>...HEAD`), jak w merge requeście | „zrób review gałęzi `feature/x` względem `origin/main`” |
| przegląd projektu | cały projekt: kod, konfiguracja, zależności, bezpieczeństwo | „zrób przegląd kodu i bezpieczeństwa całego projektu” |

Przy okazji przegląd mierzy projekt: czy buduje się na właściwym JDK i Mavenie z CI, jakie bramki są czerwone, ile zgłoszeń ma Sonar i Xray. Te wyniki są ustaleniami w raporcie, a nie zadaniami do zrobienia.

Gdy chcesz, żeby projekt po przeglądzie był czysty (bramki zielone, Sonar i Xray na zero), to następne zadanie: [`remediation`](brownfield-remediation.md), które bierze ten raport jako wsad.

## 1. Co sprawdza pipeline

`tools\sdlc.ps1` uruchamia zwykłe bramki brownfield (`Compilation`, `Tests`, `XrayScan`, `SonarQube`, `SonarQube-QualityGate`) i dodatkowo bramkę `Toolchain` (włącza ją `scenario: review` w `sdlc-settings.json`). `Toolchain` sprawdza, czy pomiar jest wiarygodny:

| Sprawdzenie | `FAIL`, gdy | Tylko ostrzeżenie, gdy |
|---|---|---|
| JDK | wersja `java` z przebiegu inna niż w `pom.xml` (`java.version`, `maven.compiler.release` albo `maven.compiler.source`), brak `java` | `pom.xml` nie deklaruje wersji Javy; `javaHome` pusty, a JDK z PATH akurat pasuje |
| Maven | wersja z przebiegu inna niż `maven.mavenVersion` (obraz CI, 3.9.16) | projekt ma Maven Wrapper: on decyduje o wersji |
| `settings.xml` | skonfigurowany plik nie istnieje | brak pliku w konfiguracji |
| SonarQube | `-SkipSonar`, serwer niedostępny, brak lub zły token, wynik Quality Gate nieodczytany | skaner połączył się z serwerem, a analizę przerwała konfiguracja projektu: to ustalenie (bramka `SonarQube`), nie problem środowiska |
| Xray | `-SkipXray`, brak `jfrog-xray.properties`, skaner nie ruszył (`jf`, token, serwer) | Xray nie ruszył, bo build albo testy padły |

`Toolchain` = `FAIL` oznacza problem Twojego środowiska: orchestrator zatrzymuje się i podaje przyczyny. Każda inna czerwona bramka to ustalenie w raporcie, przebieg idzie dalej.

W `sdlc-report.json` są: `toolchain` (użyte Java i Maven, oczekiwane wersje, wrapper, `settings.xml`) oraz `metrics.sonar.byRule` (otwarte zgłoszenia Sonara według reguł, z przykładowymi miejscami). Szczegóły Xray: `target\xray-findings.json`. Liczba testów obejmuje surefire i failsafe (od 2026-10-20); `metrics.tests.integration` to testy z failsafe.

## 2. Co robią agenci

| Etap | Agent | Wynik |
|---|---|---|
| Zadanie | orchestrator | `task.md` z liniami `Scenario: review` i `Review scope: changes <baza>..HEAD` albo `Review scope: project` |
| Pomiar | orchestrator | `.\tools\sdlc.ps1 -Baseline`; przy `Toolchain` = `FAIL` stop. Potem jeden przebieg `.\tools\sdlc.ps1 -CiParity` (build od pustego repozytorium Maven, jak w CI) |
| Przegląd kodu | analyst | `analysis.md`: zakres, narzędzia, tabele bramek, ustalenia według ważności (`file:line`, dlaczego, propozycja poprawki), Sonar i Xray w liczbach, proponowane kolejne zadania. Ustalenia bezpieczeństwa i zależności tylko z odwołaniem `SEC-xx`, bez własnej oceny |
| Bezpieczeństwo | security-reviewer | `security-review.md`: OWASP Top 10, sekrety w repozytorium (tylko miejsce, bez wartości), dane osobowe w logach, zależności. Jedyne źródło ocen bezpieczeństwa: komponent z Xray ma ocenę swojego najpoważniejszego CVE |
| Raport | orchestrator | podsumowanie w czacie, dowód, że żaden śledzony plik się nie zmienił. Raportów sam nie poprawia - odsyła je autorowi |

Przegląd o nic nie pyta. Pytania do kolejnych zadań są przy tych zadaniach, z dopiskiem „odpowiedz przy starcie zadania”. Kolejne zadania mają typy, które workflow obsługuje (`buildfix`, `bugfix`, `sonarfix`, `feature`, `tests`, `migration`); podbicia wersji pod Xray, konfiguracja Sonara i builda, sekrety w konfiguracji, nieużywane zależności i utwardzanie bezpieczeństwa należą do `remediation` (następne zadanie, wsadem jest ten raport). CVE z Xray bez wersji naprawczej dotyczy tylko skanowanej wersji: raport podaje najnowszą łatkę do sprawdzenia i nigdy nie proponuje akceptacji.

Nie biorą udziału: planner, developer, test-engineer, build-doctor, bug-hunter, quality-fixer.

Koniec zadania: `Toolchain` = `PASS`, są `analysis.md` i `security-review.md`, każde ustalenie ma ważność i `file:line`, `git diff --stat refs/sdlc/baseline` jest pusty. Wynik `PASSED` nie jest wymagany.

## 3. Co musi być gotowe

| Co | Jak sprawdzić |
|---|---|
| Dostęp do GitLaba | `git ls-remote https://gitlab.centrala.bzwbk/dev-tournament-base/forks-demo/be-wesola_banda_piratow.git` |
| JDK z `pom.xml` w `maven.jdksDir` | dla tego projektu `jdk-21` w `C:\Users\160246\Desktop\java-tools\java` |
| Maven z obrazu CI | `maven.mavenVersion: 3.9.16`, `maven.mavensDir` w `config/project-config.yaml` |
| `settings.xml` | `maven.settingsFile` w `config/project-config.yaml` |
| Token JFrog | `jfrog.token` w katalogu głównym repozytorium albo `JF_ACCESS_TOKEN` |
| Czysty terminal | brak starych `SONAR_TOKEN`, `JF_URL`, `JF_ACCESS_TOKEN` |

## 4. Konfiguracja: `config/scenario-config.yaml`

```yaml
scenarioType: review
scenarioProject: "be-wesola_banda_piratow"
scenarioRepoUrl: "https://gitlab.centrala.bzwbk/dev-tournament-base/forks-demo/be-wesola_banda_piratow.git"
```

`diffGuard*` i `coverageTolerance` nie mają znaczenia: przegląd niczego nie zmienia.

## 5. Kroki

### Krok 1. Pobierz kod i podepnij narzędzia

Przegląd projektu (gałąź domyślna):

```powershell
.\scripts\start-scenario.ps1
```

Przegląd zmian (gałąź z merge requesta):

```powershell
.\scripts\fetch-project.ps1 -RepoUrl <url> -Project be-wesola_banda_piratow -Ref <gałąź>
.\scripts\attach-project.ps1 -Project be-wesola_banda_piratow -Scenario review
```

Sprawdź `[3/6] Maven and Java`: `Maven 3.9.16` i `Java 21 (from pom.xml)`. Jeśli `[4/6] JaCoCo` dopisał wtyczkę do `pom.xml`, ta zmiana wchodzi do baseline i nie jest zmianą przeglądu.

### Krok 2. Środowisko

Nie uruchamiaj ręcznie `env-up.ps1`. Po otrzymaniu promptu orchestrator uruchamia SonarQube i wymaganą bazę w ramach flow review. Użytkownik musi tylko mieć skonfigurowane ścieżki, dostęp do usług oraz tokeny.

### Krok 3. Okno VS Code

Otwórz `projects\be-wesola_banda_piratow` w **nowym** oknie VS Code, wybierz `@sdlc-orchestrator`. Po każdej Twojej odpowiedzi sprawdź, czy tryb nie przeskoczył na `agent`.

### Krok 4. Zadanie

Wklej prompt z sekcji 6.

## 6. Prompt dla orchestratora

Przegląd projektu:

```
Przejrzyj projekt i powiedz, co wymaga naprawy.
```

Orchestrator sam wybiera `review`, ustawia `Review scope: project` i wykonuje
baseline, testy, coverage, SonarQube, Xray, kontrolę toolchainu, `-CiParity`,
analizę kodu oraz raport bezpieczeństwa. Nie zmienia kodu.

Przegląd zmian: zamień drugą linię na `Zakres: zmiany gałęzi <gałąź> względem origin/main.`

## 7. Na co patrzeć w trakcie (monitorowanie)

| Ryzyko | Jak sprawdzić |
|---|---|
| Agent coś naprawia | `git diff --stat refs/sdlc/baseline` pusty; w czacie brak delegacji do developer / quality-fixer / build-doctor |
| Zatrzymanie na czerwonej bramce, która nie jest `Toolchain` | orchestrator ma zapisać ją jako ustalenie i iść dalej |
| Zły JDK lub Maven | `sdlc-report.json` -> `toolchain`: `java` 21, `maven` = `mavenExpected` |
| Pominięte skanery | brak `-SkipSonar` / `-SkipXray` w poleceniach |
| Przegląd zmian obejmuje cały projekt (lub odwrotnie) | `Review scope:` w `task.md`; sekcja „Scope” w `analysis.md` |
| Wartości sekretów w raporcie | `security-review.md` podaje tylko plik i linię |

## 8. Odczyt końcowy

```powershell
cd projects\be-wesola_banda_piratow
git --no-pager diff --stat refs/sdlc/baseline     # pusto = nic nie zmieniono
Select-String -Path task.md -Pattern "Scenario:|Review scope:"
$r = Get-Content sdlc-report.json -Raw | ConvertFrom-Json
"status: $($r.status), ciParity: $($r.ciParity)"; $r.gates | Format-List
$r.toolchain | Format-List
$r.metrics.sonar.byRule | Format-Table rule, severity, type, count
Select-String -Path analysis.md, security-review.md -Pattern "CRITICAL|HIGH" | Select-Object -First 20
```

Gotowe znaczy: `Toolchain` = `PASS`, są `analysis.md` i `security-review.md`, każde ustalenie ma ważność i `file:line`, pusty `git diff` względem baseline.

## 9. Typowe problemy

| Objaw | Co zrobić |
|---|---|
| `Toolchain`: `JDK 25 used, pom.xml declares Java 21` | brak JDK 21 w `maven.jdksDir` albo stary `sdlc-settings.json`; ponownie `attach-project.ps1 -Scenario review` |
| `Toolchain`: `Maven 3.9.11 used, CI uses 3.9.16` | brak `apache-maven-3.9.16` w `maven.mavensDir`; sprawdź Artifactory i ponownie `attach-project.ps1` |
| `Toolchain`: `SonarQube analysis did not run` | `.\scripts\env-up.ps1 -ProjectPath projects\be-wesola_banda_piratow`; w terminalu `$env:SONAR_TOKEN = $null` |
| `SonarQube` = `FAIL`, w `warnings` „server reached, the analysis failed on the project's configuration” | ustalenie w raporcie, np. `sonar.tests` w `pom.xml` wskazuje nieistniejący katalog (2026-10-20: `src/test/java` przy samych testach Spock). Bez analizy nie ma liczby zgłoszeń Sonara - raport ma to powiedzieć |
| `Toolchain`: `Xray scan could not run` | brak `jfrog.token` / `JF_ACCESS_TOKEN`, brak `jf` albo serwer niedostępny |
| Ostrzeżenie `Maven Wrapper decides the Maven version` | wrapper projektu ma inną wersję niż CI; ustalenie do raportu |
| Projekt nie widoczny w SonarQube | klucz pochodzi z `groupId:artifactId` w `pom.xml` (tu `com.example:hello-world-backend`); Sonar wymaga zalogowania |
| Stary `sonar-project.properties` (podpięty przed 2026-10-20) ma sztywne `sonar.sources` / `sonar.tests` | usuń plik i uruchom `attach-project.ps1` ponownie; nowy ma tylko `projectKey`, `projectName`, `host.url`, `scm.disabled` |
