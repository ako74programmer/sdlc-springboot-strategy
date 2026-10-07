# 🔍 Audyt: sdlc-springboot-strategy

## Podsumowanie

Projekt implementuje generator projektów Spring Boot ze zintegrowanym lokalnym pipeline'em SDLC (kompilacja → testy → OWASP → SonarQube). Koncepcja opisana w [strategia.md](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/doc/strategia.md) jest solidna — kluczowa zasada **"AI tworzy, pipeline weryfikuje, AI naprawia"** jest dobrze przemyślana.

Poniżej: co działa dobrze, co bym zmienił, i co bym dodał.

---

## ✅ Co działa dobrze

| Element | Ocena |
|---|---|
| Architektura koncepcyjna (strategia.md) | Doskonała — klarowna wizja pętli samonaprawczej |
| Deklaratywny config YAML | Dobry pomysł — jedno źródło prawdy |
| Generacja przez Spring Initializr API | Pragmatyczne i eleganckie |
| Wstrzykiwanie JaCoCo + OWASP do POM | Działa — rozszerza wygenerowany projekt |
| `sdlc.ps1` z bramkami i `sdlc-report.json` | Kluczowy element — output maszynowy dla AI |
| Docker Compose dla SonarQube | Gotowy do użycia, healthcheck na Postgres |
| `.gitignore` | Pokrywa `generated-projects/`, tokeny, IDE |

---

## 🔴 Co bym zmienił (problemy do naprawienia)

### 1. 🔐 Hardcoded token SonarQube w repozytorium

**Plik:** [sonar-token.txt](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/sonar-token.txt) + [sdlc.ps1:79](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/templates/sdlc.ps1#L79)

> [!CAUTION]
> Token SonarQube `squ_e94ef3b9a1c0bc71830b1ae895ed89aec340edbf` jest zahardcodowany jako fallback w `sdlc.ps1` linia 79. Plik `sonar-token.txt` jest w `.gitignore`, ale sam token wewnątrz skryptu template'u — nie. Jeśli to repozytorium trafi na GitHub, token zostanie wyeksponowany.

**Rekomendacja:** Usunąć hardcoded fallback. Jeśli brak tokena → wyraźny błąd z instrukcją uruchomienia `setup-sonar-token.ps1`.

---

### 2. 🧩 Parser YAML w PowerShell jest kruchy

**Plik:** [generate-project.ps1:24-33](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/scripts/generate-project.ps1#L24-L33)

Regex `Get-YamlValue` nie obsługuje:
- Wartości w cudzysłowach ze znakami specjalnymi (`#`, `:`)
- Multiline values
- Zagnieżdżonych map (np. sekcja `sdlc:` z `project-config.yaml` jest **kompletnie ignorowana** — `enableSonarQube`, `enableOwaspCheck`, `sonarHostUrl`, `owaspFailOnCvss` nie są nigdzie czytane!)

**Rekomendacja:** 
- Opcja A: Zainstalować moduł `powershell-yaml` (`Install-Module powershell-yaml`) i używać `ConvertFrom-Yaml`
- Opcja B: Zmienić format konfiguracji na JSON (natywne wsparcie w PowerShell)
- Minimum: Zacząć konsumować sekcję `sdlc:` z configa — teraz jest dekoracyjna

---

### 3. ⚡ Sekcja `sdlc:` w config YAML jest martwa

**Plik:** [project-config.yaml:25-31](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/config/project-config.yaml#L25-L31)

```yaml
sdlc:
  enableSonarQube: true
  enableOwaspCheck: true
  sonarHostUrl: "http://localhost:9000"
  owaspFailOnCvss: 7.0
```

Te wartości **nie są nigdzie odczytywane**. Generator ich nie parsuje, `sdlc.ps1` ich nie używa. OWASP CVSS threshold jest hardcoded na `7.0` w dwóch miejscach (POM i skrypt), a SonarQube URL na `localhost:9000`.

**Rekomendacja:** Albo faktycznie konsumować te wartości i parametryzować templatesy, albo usunąć sekcję żeby nie dawać złudzeń konfigurowalności.

---

### 4. 🐋 `docker-compose.yml` — przestarzały format

**Plik:** [docker-compose.yml:1](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/docker/docker-compose.yml#L1)

```yaml
version: '3.8'
```

> [!WARNING]
> Klucz `version` jest deprecated od Docker Compose V2. Nowoczesne wersje go ignorują i wyrzucają ostrzeżenie.

**Rekomendacja:** Usunąć linię `version: '3.8'`.

---

### 5. 📊 `sdlc.ps1` — brak bramki SonarQube Quality Gate (walidacja statusu)

**Plik:** [sdlc.ps1:76-85](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/templates/sdlc.ps1#L76-L85)

Skrypt uruchamia analizę SonarQube (`sonar:sonar`), ale **nie sprawdza statusu Quality Gate po analizie**. Plugin Maven `sonar:sonar` zawsze zwraca exit code 0 jeśli upload się powiódł — nawet gdy Quality Gate jest FAILED w SonarQube.

**Rekomendacja:** Po analizie odpytać SonarQube API:
```powershell
# Po sonar:sonar
$qg = Invoke-RestMethod "http://localhost:9000/api/qualitygates/project_status?projectKey=$projectKey" -Headers $headers
if ($qg.projectStatus.status -ne "OK") { exit 1 }
```

Albo użyć flagi `-Dsonar.qualitygate.wait=true` (dostępna od SonarQube Scanner 3.x+) — wtedy Maven sam czeka i failuje na Quality Gate FAILED.

---

### 6. 📁 Rozbieżność ścieżek: strategia mówi `tools/`, implementacja ma `templates/`

Strategia konsekwentnie odwołuje się do `tools/sdlc.ps1`, wygenerowany projekt też ma `tools/sdlc.ps1` — ale w repozytorium generatora plik leży w `templates/sdlc.ps1`. Nie jest to błąd, ale jest mylące — `templates/` jest w generator repo, `tools/` w generated project. Warto to wyjaśnić w README.

---

### 7. 🧹 `sonar-project.properties` — brak `sonar.projectKey`

**Plik:** [sonar-project.properties](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/templates/sonar-project.properties)

Brak `sonar.projectKey`, który jest **wymagany** przez SonarQube. Bez tego SonarQube zgaduje klucz z katalogu, co jest niestabilne.

**Rekomendacja:** Generator powinien wstrzykiwać `sonar.projectKey` z `artifactId` konfiguracji:
```properties
sonar.projectKey=springboot-sdlc-demo
sonar.projectName=springboot-sdlc-demo
```

---

### 8. ❌ `setup-sonar-token.ps1` — brak czekania na gotowość SonarQube

**Plik:** [setup-sonar-token.ps1](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/scripts/setup-sonar-token.ps1)

Skrypt od razu próbuje generować token, ale po `docker-compose up -d` SonarQube potrzebuje ~60-120 sekund na start. Brak retry/wait = pewny fail przy pierwszym uruchomieniu.

**Rekomendacja:** Dodać polling na `http://localhost:9000/api/system/status` z timeoutem:
```powershell
Write-Host "Waiting for SonarQube..."
$maxWait = 120; $elapsed = 0
do {
    try { $s = Invoke-RestMethod "http://localhost:9000/api/system/status"; if ($s.status -eq "UP") { break } } catch {}
    Start-Sleep 5; $elapsed += 5
} while ($elapsed -lt $maxWait)
```

---

## 🟢 Co bym dodał

### 1. 🤖 Brakujące agenty z koncepcji strategii

Strategia opisuje 5 agentów:
- `planner.agent.md`
- `spring-developer.agent.md`
- `test-engineer.agent.md`
- `security-reviewer.agent.md`
- `quality-fixer.agent.md` ← **jedyny zaimplementowany**

**Rekomendacja:** Dodać przynajmniej:
- **`planner.agent.md`** — dekompozycja wymagań na tasks
- **`developer.agent.md`** — generacja kodu wg standardów
- **`test-engineer.agent.md`** — generacja testów po implementacji

To fundamentalny element koncepcji, a dziś mamy tylko 1 z 5 agentów.

---

### 2. 📋 Brakujące skills z koncepcji

Strategia wspomina o katalogu `.github/skills/` z:
- `springboot/`
- `testing/`
- `security/`
- `sdlc/`

**Żaden nie istnieje.** Skills powinny zawierać kontekstowe instrukcje dla agentów — np. konwencje nazewnictwa, wzorce architektoniczne, zasady testowania.

---

### 3. 🔄 Pętla samonaprawcza (feedback loop) — brak orkiestracji

Strategia opisuje pętlę: **SDLC fail → AI fix → SDLC rerun**. Ale nie ma żadnego mechanizmu orkiestracji. `sdlc.ps1` generuje raport i kończy pracę. Kto/co uruchamia quality-fixera i ponownie sdlc?

**Rekomendacja:** Dodać skrypt orkiestracyjny `tools/sdlc-loop.ps1`:
```powershell
$maxRetries = 3
for ($i = 0; $i -lt $maxRetries; $i++) {
    .\tools\sdlc.ps1
    if ($LASTEXITCODE -eq 0) { break }
    Write-Host "Invoking quality-fixer agent..."
    # Tu integracja z Copilot CLI / API
}
```

Nawet jeśli orkiestracja jest ręczna (człowiek odpala Copilota z raportem), warto to udokumentować jako konkretny workflow w README.

---

### 4. 📈 Bramka pokrycia testami (coverage threshold)

JaCoCo jest skonfigurowany do generowania raportów, ale **nie ma progu minimalnego pokrycia**. Brak `check` goal w POM.

**Rekomendacja:** Dodać do wstrzykiwanego JaCoCo w [generate-project.ps1](file:///c:/Users/Andrzej/Desktop/foo/sdlc/sdlc-springboot-strategy/scripts/generate-project.ps1#L111-L141):
```xml
<execution>
    <id>check</id>
    <goals><goal>check</goal></goals>
    <configuration>
        <rules>
            <rule>
                <element>BUNDLE</element>
                <limits>
                    <limit>
                        <counter>LINE</counter>
                        <value>COVEREDRATIO</value>
                        <minimum>0.60</minimum>
                    </limit>
                </limits>
            </rule>
        </rules>
    </configuration>
</execution>
```

---

### 5. 🔀 GitHub Actions workflow template

Strategia (sekcja 13) mówi o przygotowaniu `github/workflows/sdlc.yml` dla CI. **Nie istnieje.**

**Rekomendacja:** Dodać `templates/.github/workflows/sdlc.yml` z pipeline'em lustrzanym do lokalnego `sdlc.ps1`:
```yaml
name: SDLC Quality Pipeline
on: [push, pull_request]
jobs:
  sdlc:
    runs-on: ubuntu-latest
    services:
      sonarqube: ...
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
      - run: ./mvnw clean verify
      - run: ./mvnw sonar:sonar
      - run: ./mvnw dependency-check:check
```

---

### 6. 🧪 Smoke test po generacji

Po `generate-project.ps1` nie ma walidacji, że wygenerowany projekt w ogóle się kompiluje. Generator mógłby fail'ować na siebie.

**Rekomendacja:** Dodać opcjonalny krok 6.5:
```powershell
Write-Host "[6/7] Smoke test - compiling generated project..."
Push-Location $targetPath
.\mvnw.cmd clean compile
Pop-Location
```

---

### 7. 📝 Parametryzacja template'ów sonar-project.properties

Teraz kopiowany jest generyczny plik. Powinien być parametryzowany wartościami z `project-config.yaml`:

```properties
sonar.projectKey={{artifactId}}
sonar.projectName={{name}}
sonar.host.url={{sonarHostUrl}}
```

---

### 8. 🛡️ Pre-commit hooks

Strategia mówi o Git jako bramce (sekcja 12): "nie commitujesz dopóki SDLC nie przejdzie". Ale nie ma mechanizmu wymuszającego.

**Rekomendacja:** Dodać template `.githooks/pre-commit`:
```bash
#!/bin/sh
./tools/sdlc.ps1 -SkipSonar
if [ $? -ne 0 ]; then
    echo "SDLC gate failed. Commit blocked."
    exit 1
fi
```

---

### 9. 📊 Rozbudowa `sdlc-report.json`

Aktualny raport to minimum. Brakuje:
- Liczby testów (passed/failed/skipped)
- Pokrycia testami (%)
- Listy CVE znalezionych przez OWASP
- Statusu Quality Gate z SonarQube (z konkretnym powodem failu)

Bogatszy raport = lepszy kontekst dla AI quality-fixera.

---

### 10. 📖 `CONTRIBUTING.md` / developer onboarding

Brak dokumentu opisującego:
- Wymagane narzędzia (Java 21, Maven, Docker, PowerShell)
- Jak rozwijać sam generator (nie projekt wygenerowany)
- Jak testować zmiany w templateach

---

## 📊 Podsumowanie priorytetów

| Priorytet | Co | Typ |
|---|---|---|
| 🔴 Krytyczny | Usunąć hardcoded token z `sdlc.ps1` | Zmiana |
| 🔴 Krytyczny | Dodać sprawdzanie statusu Quality Gate z SonarQube | Zmiana |
| 🟠 Wysoki | Konsumować sekcję `sdlc:` z YAML albo ją usunąć | Zmiana |
| 🟠 Wysoki | Dodać `sonar.projectKey` do properties | Zmiana |
| 🟠 Wysoki | Dodać brakujących agentów (planner, developer, test-engineer) | Dodanie |
| 🟡 Średni | Dodać wait/retry do `setup-sonar-token.ps1` | Zmiana |
| 🟡 Średni | Dodać JaCoCo coverage threshold | Dodanie |
| 🟡 Średni | Dodać CI workflow template | Dodanie |
| 🟡 Średni | Rozbudować `sdlc-report.json` o metryki | Dodanie |
| 🟢 Niski | Usunąć `version: '3.8'` z docker-compose | Zmiana |
| 🟢 Niski | Dodać smoke test po generacji | Dodanie |
| 🟢 Niski | Dodać pre-commit hooks | Dodanie |
| 🟢 Niski | Wymienić regex YAML parser na `powershell-yaml` | Zmiana |

---

> [!IMPORTANT]
> Koncepcja w `strategia.md` jest **znacznie bogatsza** niż obecna implementacja. Strategia opisuje ekosystem 5 agentów, skills, pełną orkiestrację i pętlę samonaprawczą. Implementacja realizuje ~30% tej wizji. To nie jest zarzut — PoC jest poprawny — ale gap między wizją a kodem jest duży. Priorytetem powinno być zamknięcie tego gap'u przyrostowo, zaczynając od krytycznych poprawek bezpieczeństwa i brakujących agentów.
