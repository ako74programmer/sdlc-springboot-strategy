# 🚀 Spring Boot AI SDLC Generator & Quality Pipeline Strategy

[🇵🇱 Wersja Polska](#-polska-wersja) | [🇬🇧 English Version](#-english-version)

---

## 🇵🇱 Polska Wersja

### 📖 O Projekcie
System automatycznego generowania i wzbogacania projektów **Spring Boot 3.x (Java 21)** o lokalny, samonaprawialny pipeline jakościowy **SDLC** wspierany przez Agenty AI (np. GitHub Copilot).

Główna zasada architektoniczna:
> **Copilot/AI generuje kod ➔ Lokalny pipeline SDLC weryfikuje ➔ Bramki jakości decydują ➔ AI poprawia błędy na podstawie pliku `sdlc-report.json` ➔ Ponowna weryfikacja.**

---

### ✨ Kluczowe Funkcje
- ⚙️ **Konfiguracja fabryki z lokalnym override**: `config/project-config.yaml` zawiera bezpieczne wartości bazowe, a opcjonalny `config/project-config.local.yaml` (tworzony z `config/project-config.local.example.yaml`) zawiera ścieżki stanowiska i adresy korporacyjne. Lokalny plik jest ładowany automatycznie i ignorowany przez Git.
- ⚡ **Integracja ze Spring Initializr REST API**: Automatyczne pobieranie najnowszej oficjalnej struktury i skryptów Maven Wrapper (`mvnw` / `mvnw.cmd`).
- 🛡️ **Lokalne Bramki Jakościowe (`tools/sdlc.ps1`)**:
  1. Kompilacja projektu (`compile`)
  2. Testy jednostkowe i integracyjne (`test`) + metryki (ilość testów, pokrycie)
  3. Skanowanie podatności zależności CVE (OWASP Dependency Check)
  4. Skan JFrog Xray zbudowanego jara — zero podatności (opcjonalnie: `sdlc.enableXray`, token w `JF_ACCESS_TOKEN` lub `jfrog.token`)
  5. Statyczna analiza kodu + **walidacja Quality Gate** (SonarQube API)
- 📊 **Strukturalny raport `sdlc-report.json`**: Zawiera status bramek, metryki testów (total/passed/failed), pokrycie kodu (linie/branche) i szczegóły błędów — jako input dla AI.
- �️ **SonarQube uruchamiany lokalnie bez kontenerów (`scripts/start-sonarqube.ps1`)**: korzysta z rozpakowanej dystrybucji SonarQube Community na dysku (brak wymagania Dockera i uprawnień administratora).
- 🤖 **5 Agentów AI (`.github/agents/`)**:
  - `planner` — dekompozycja wymagań na plan architektoniczny
  - `developer` — implementacja kodu Spring Boot
  - `test-engineer` — tworzenie testów (piramida testów)
  - `security-reviewer` — przegląd bezpieczeństwa (OWASP Top 10)
  - `quality-fixer` — automatyczna naprawa na podstawie `sdlc-report.json`
- 🔒 **Pre-commit hooki**: Automatyczna walidacja jakości przed każdym commitem.
- 🔄 **CI/CD Template**: GitHub Actions workflow lustrzany do lokalnego `sdlc.ps1`.

---

### 📂 Struktura Repozytorium (generator)

```text
sdlc-springboot-strategy/
├── config/
│   ├── project-config.yaml       # Neutralna konfiguracja projektu + SDLC
│   ├── project-config.local.example.yaml # Wzór konfiguracji stanowiska
│   └── scenario-config.yaml      # Reguły fabryki, katalog projects/, limity
├── templates/
│   ├── greenfield/               # Szablon generatora (kod od zera)
│   │   ├── sdlc.ps1              # Lokalny skrypt bramek jakościowych
│   │   ├── jfrog-scan.ps1        # Bramka JFrog Xray
│   │   ├── sonar-project.properties
│   │   └── .github/              # copilot-instructions, agents/, workflows/sdlc.yml
│   └── brownfield/               # Szablon dla pobranego kodu (projects/)
│       ├── sdlc.ps1              # Własna kopia bramek (mvn, gdy brak wrappera)
│       ├── recon.ps1             # Rozpoznanie projektu -> recon-report.json
│       ├── jfrog-scan.ps1
│       ├── sonar-project.properties
│       ├── copilot-instructions.md
│       └── agents/
├── scripts/
│   ├── generate-project.ps1      # Główny skrypt generatora projektu
│   ├── attach-project.ps1        # Podpięcie pobranego projektu z projects/
│   ├── start-scenario.ps1        # Wspólny punkt wejścia (greenfield / brownfield)
│   ├── start-sonarqube.ps1       # Start lokalnej dystrybucji SonarQube
│   ├── start-mongo.ps1           # Start lokalnego MongoDB (bez Dockera)
│   └── setup-sonar-token.ps1     # Generator tokena SonarQube (z auto-wait)
├── doc/
│   └── strategia.md              # Dokumentacja architektoniczna strategii SDLC
└── README.md
```

### 📂 Struktura wygenerowanego projektu

```text
springboot-sdlc-demo/
├── .github/
│   ├── copilot-instructions.md   # Reguły dla Copilota
│   ├── agents/                   # 5 wyspecjalizowanych agentów AI
│   └── workflows/sdlc.yml       # CI pipeline
├── .githooks/
│   └── pre-commit                # Walidacja jakości przed commitem
├── tools/
│   ├── sdlc.ps1                  # Lokalny pipeline SDLC
│   └── enable-hooks.ps1          # Aktywacja pre-commit hooków
├── src/                          # Kod źródłowy Spring Boot
├── pom.xml                       # Maven z JaCoCo + OWASP plugins
├── sonar-project.properties      # Sparametryzowana konfiguracja SonarQube
├── mvnw / mvnw.cmd               # Maven Wrapper
└── README.md
```

---

### 🚀 Instrukcja Szybkiego Uruchomienia

#### Wymagania
- Java 21 (JDK)
- Lokalna dystrybucja SonarQube Community (rozpakowany ZIP) — **bez Dockera**
- PowerShell 5.1+ (Windows) lub PowerShell Core (Linux/macOS)
- Git

#### Krok 1: Skonfiguruj stanowisko (jednorazowo)
Skopiuj `config/project-config.local.example.yaml` do `config/project-config.local.yaml` i uzupełnij ścieżki JDK/Mavena, `settings.xml`, adres Xray oraz typ używanej bazy. Szczegóły: [scenariusze testowe](doc/scenarios/00-konfiguracja-fabryki.md).

#### Krok 2: Wygeneruj projekt lub uruchom scenariusz
Nie trzeba edytować YAML przed każdym zadaniem. Dla nowego projektu uruchom:
```powershell
.\scripts\generate-project.ps1
```
Nowy projekt zostanie utworzony w katalogu `projects/springboot-sdlc-demo` (`projectsDir` w `config/scenario-config.yaml`). Generator oznacza swoje projekty plikiem `.sdlc-generated` i nadpisuje tylko takie katalogi; istniejący katalog bez znacznika (np. pobrany kod) wymaga `-Force`.

**Istniejący projekt (brownfield)**: jedno polecenie pobiera repozytorium, podpina narzędzia i tworzy branch roboczy:
```powershell
.\scripts\start-scenario.ps1 -Scenario vulnfix -RepoUrl https://git.example.corp/team/service.git -Project service
```
Następnie otwórz `projects/service` w VS Code i przekaż zadanie agentowi `sdlc-orchestrator`. Parametry repozytorium i scenariusza są bieżącym wejściem zadania; nie trzeba wpisywać ich do `scenario-config.yaml`.

**Brownfield - bramki porównawcze**: przed pierwszą zmianą `.\tools\sdlc.ps1 -Baseline` (zapis `sdlc-baseline.json`), potem każdy przebieg sprawdza `Regression` (żaden wcześniej zielony test nie pada, pokrycie i liczba problemów Sonara nie gorsze), `TestIntegrity` (brak usuniętych/wyłączonych/osłabionych testów, `NOSONAR`, zmian w `sonar-project.properties`), `DiffGuard` (rozmiar zmiany) i opcjonalnie `ReproTest` (`-ReproTest Klasa#metoda`: test czerwony przed poprawką, zielony po niej). Projekty treningowe: `.\scripts\new-fixture.ps1 -Name b2-failing-test` (lista i instrukcja: [tests/scenarios/README.md](tests/scenarios/README.md)).  
Generator automatycznie uruchomi smoke test kompilacji.

**Repozytorium artefaktów (Maven `settings.xml`)**: Maven domyślnie używa `~/.m2/settings.xml`. Jeśli plik leży gdzie indziej, wpisz go raz w `config/project-config.local.yaml`, użyj `-MavenSettings` albo zmiennej `MAVEN_SETTINGS`.

#### Krok 2: Uruchom SonarQube
Skrypt startuje lokalnie rozpakowaną dystrybucję SonarQube (ścieżka do `StartSonar.bat` jest w skrypcie):
```powershell
.\scripts\start-sonarqube.ps1
```

#### Krok 3: Wygeneruj Token SonarQube (Jednorazowo)
Skrypt automatycznie czeka na gotowość SonarQube (do 180 sekund):
```powershell
..\..\scripts\setup-sonar-token.ps1
```

#### Krok 4: Uruchom Bramki Jakościowe
```powershell
.\tools\sdlc.ps1
```

Oczekiwany output:
```text
========================================
          LOCAL SDLC PIPELINE
========================================

[RUNNING GATE] Compilation...
[GATE PASS] Compilation

[RUNNING GATE] Tests...
[GATE PASS] Tests
    Tests: 3 total, 3 passed, 0 failed, 0 errors, 0 skipped
    Line Coverage: 72.5%

[RUNNING GATE] VulnerabilityCheck...
[GATE PASS] VulnerabilityCheck

[RUNNING GATE] SonarQube...
[GATE PASS] SonarQube
[GATE PASS] SonarQube Quality Gate

========================================
          GATE SUMMARY
========================================
  [OK]   Compilation
  [OK]   Tests
  [OK]   VulnerabilityCheck
  [OK]   SonarQube
  [OK]   SonarQube-QualityGate

  Tests: 3 total | 3 passed | 0 failed | 0 skipped
  Coverage: 72.5% lines

========================================
  RESULT: ALL GATES PASSED
========================================
```

#### Krok 5 (opcjonalnie): Aktywuj Pre-Commit Hooki
```powershell
.\tools\enable-hooks.ps1
```

---

### 🤖 Workflow z Agentami AI

```text
Wymaganie użytkownika
        │
        ▼
   @planner ──────────► plan.md
        │
        ▼
   @developer ────────► implementacja kodu
        │
        ▼
   @test-engineer ────► testy (unit, integration, API)
        │
        ▼
   @security-reviewer ► security-review.md
        │
        ▼
   .\tools\sdlc.ps1 ──► sdlc-report.json
        │
     ┌──┴──┐
   PASS   FAIL
    │       │
    ▼       ▼
  DONE   @quality-fixer ──► poprawki ──► sdlc.ps1 (ponownie)
```

---
---

## 🇬🇧 English Version

### 📖 Overview
An automated generation and enrichment framework for **Spring Boot 3.x (Java 21)** projects with a local, self-correcting **SDLC quality pipeline** tailored for AI coding assistants (such as GitHub Copilot).

Core architectural principle:
> **AI/Copilot generates code ➔ Local SDLC pipeline validates ➔ Quality gates decide ➔ AI fixes issues using `sdlc-report.json` ➔ Pipeline re-verifies.**

---

### ✨ Key Features
- ⚙️ **Declarative YAML Config (`config/project-config.yaml`)**: Single source of truth for Java version, build tools, project metadata, Spring Boot starters, and SDLC configuration.
- ⚡ **Spring Initializr REST API Integration**: Directly downloads the official project skeleton and standard Maven Wrappers (`mvnw` / `mvnw.cmd`).
- 🛡️ **Automated Local Quality Gates (`tools/sdlc.ps1`)**:
  1. Compilation check (`compile`)
  2. Unit & integration test suite (`test`) + metrics (counts, coverage)
  3. Dependency vulnerability scanning (OWASP Dependency Check)
  4. JFrog Xray scan of the built jar — zero findings allowed (optional: `sdlc.enableXray`, token in `JF_ACCESS_TOKEN` or `jfrog.token`)
  5. Static code analysis + **Quality Gate validation** (SonarQube API)
- 📊 **Structured `sdlc-report.json`**: Contains gate statuses, test metrics (total/passed/failed), code coverage (line/branch), and detailed errors — as input for AI agents.
- �️ **Container-free local SonarQube (`scripts/start-sonarqube.ps1`)**: Starts an unpacked SonarQube Community distribution from disk — no Docker and no admin rights required.
- 🤖 **5 AI Agents (`.github/agents/`)**:
  - `planner` — requirement decomposition into architectural plan
  - `developer` — Spring Boot code implementation
  - `test-engineer` — test creation (testing pyramid)
  - `security-reviewer` — security audit (OWASP Top 10)
  - `quality-fixer` — automated fix loop based on `sdlc-report.json`
- 🔒 **Pre-commit Hooks**: Automatic quality validation before every commit.
- 🔄 **CI/CD Template**: GitHub Actions workflow mirroring local `sdlc.ps1`.

---

### 🚀 Quick Start Guide

#### Prerequisites
- Java 21 (JDK)
- Local SonarQube Community distribution (unpacked ZIP) — **no Docker required**
- PowerShell 5.1+ (Windows) or PowerShell Core (Linux/macOS)
- Git

#### Step 1: Generate a New Project
Copy `config/project-config.local.example.yaml` to `config/project-config.local.yaml` once for machine-specific paths and corporate URLs. Then run:
```powershell
.\scripts\generate-project.ps1
```
The newly bootstrapped application will be placed in `projects/springboot-sdlc-demo` (`projectsDir` in `config/scenario-config.yaml`).  
The generator runs a smoke compile test automatically.

**Artifact repository (Maven `settings.xml`)**: Maven picks up `~/.m2/settings.xml` by default. For a settings file in a different location, set `maven.settingsFile` in the config, pass `-MavenSettings`, or export `MAVEN_SETTINGS` — the generator and `tools/sdlc.ps1` forward it to Maven as `-s`.

#### Step 2: Start Local SonarQube
```powershell
.\scripts\start-sonarqube.ps1
```

#### Step 3: Setup SonarQube Authentication Token (One-time)
The script waits for SonarQube to be ready (up to 180 seconds):
```powershell
..\..\scripts\setup-sonar-token.ps1
```

#### Step 4: Execute Local Quality Gates
```powershell
.\tools\sdlc.ps1
```

#### Step 5 (optional): Enable Pre-Commit Hooks
```powershell
.\tools\enable-hooks.ps1
```

---

### 📜 License
MIT License. Free to use and customize for enterprise & personal Spring Boot projects.
