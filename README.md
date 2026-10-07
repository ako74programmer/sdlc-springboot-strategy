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
- ⚙️ **Deklaratywny plik YAML (`config/project-config.yaml`)**: Jedno źródło prawdy określające wersję Java, build tool, metadane, zależności oraz konfigurację SDLC (SonarQube URL, OWASP threshold).
- ⚡ **Integracja ze Spring Initializr REST API**: Automatyczne pobieranie najnowszej oficjalnej struktury i skryptów Maven Wrapper (`mvnw` / `mvnw.cmd`).
- 🛡️ **Lokalne Bramki Jakościowe (`tools/sdlc.ps1`)**:
  1. Kompilacja projektu (`compile`)
  2. Testy jednostkowe i integracyjne (`test`) + metryki (ilość testów, pokrycie)
  3. Skanowanie podatności zależności CVE (OWASP Dependency Check)
  4. Statyczna analiza kodu + **walidacja Quality Gate** (SonarQube API)
- 📊 **Strukturalny raport `sdlc-report.json`**: Zawiera status bramek, metryki testów (total/passed/failed), pokrycie kodu (linie/branche) i szczegóły błędów — jako input dla AI.
- 🐳 **Konteneryzacja lokalna (`docker-compose.yml`)**: SonarQube Community Edition + baza PostgreSQL gotowe do użycia od razu po wygenerowaniu.
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
│   └── project-config.yaml       # Plik konfiguracyjny projektu + SDLC
├── docker/
│   └── docker-compose.yml        # Usługi SonarQube + PostgreSQL
├── templates/
│   ├── sdlc.ps1                  # Lokalny skrypt bramek jakościowych
│   ├── sonar-project.properties  # Szablon konfiguracji SonarQube
│   └── .github/
│       ├── copilot-instructions.md
│       ├── agents/
│       │   ├── planner.agent.md
│       │   ├── developer.agent.md
│       │   ├── test-engineer.agent.md
│       │   ├── security-reviewer.agent.md
│       │   └── quality-fixer.agent.md
│       └── workflows/
│           └── sdlc.yml          # CI pipeline (GitHub Actions)
├── scripts/
│   ├── generate-project.ps1      # Główny skrypt generatora projektu
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
├── docker-compose.yml            # Lokalny SonarQube
├── sonar-project.properties      # Sparametryzowana konfiguracja SonarQube
├── mvnw / mvnw.cmd               # Maven Wrapper
└── README.md
```

---

### 🚀 Instrukcja Szybkiego Uruchomienia

#### Wymagania
- Java 21 (JDK)
- Docker & Docker Compose
- PowerShell 5.1+ (Windows) lub PowerShell Core (Linux/macOS)
- Git

#### Krok 1: Wygeneruj Projekt
Dostosuj parametry w `config/project-config.yaml`, a następnie uruchom:
```powershell
.\scripts\generate-project.ps1
```
Nowy projekt zostanie utworzony w katalogu `generated-projects/springboot-sdlc-demo`.  
Generator automatycznie uruchomi smoke test kompilacji.

#### Krok 2: Uruchom SonarQube
```powershell
cd generated-projects\springboot-sdlc-demo
docker-compose up -d
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
  4. Static code analysis + **Quality Gate validation** (SonarQube API)
- 📊 **Structured `sdlc-report.json`**: Contains gate statuses, test metrics (total/passed/failed), code coverage (line/branch), and detailed errors — as input for AI agents.
- 🐳 **Docker Container Stack (`docker-compose.yml`)**: Pre-configured SonarQube Community Edition + PostgreSQL database.
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
- Docker & Docker Compose
- PowerShell 5.1+ (Windows) or PowerShell Core (Linux/macOS)
- Git

#### Step 1: Generate a New Project
Configure your metadata in `config/project-config.yaml` and run:
```powershell
.\scripts\generate-project.ps1
```
The newly bootstrapped application will be placed in `generated-projects/springboot-sdlc-demo`.  
The generator runs a smoke compile test automatically.

#### Step 2: Start Local SonarQube Stack
```powershell
cd generated-projects\springboot-sdlc-demo
docker-compose up -d
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
