# Plan: Bitwa na kody (przygotowanie lokalnego SDLC)

> Dokument roboczy — aktualizujemy go w miarę postępów. Stack: Java Spring Boot, MongoDB, Maven, Angular, san-ui, Playwright, Karma + Jasmine, Node.js + npm, IntelliJ IDEA / VS Code.

## 1. Status środowiska lokalnego

| Narzędzie | Status | Szczegóły |
|---|---|---|
| Java (JDK) | ✅ | OpenJDK 25.0.1 |
| Maven | ✅ | 3.9.11 |
| Node.js | ✅ | v26.8.1 |
| npm | ✅ | 11.16.0 |
| Angular CLI | ✅ | 22.0.4 |
| Git | ✅ | 2.49.0 |
| MongoDB (mongod) | ✅ | **działa lokalnie bez admina** — ZIP 8.3.8, `--dbpath`, port 27017 potwierdzony (`Test-NetConnection` → `TcpTestSucceeded: True`) |
| MongoDB Shell (mongosh) | ✅ | zainstalowany przez `winget install MongoDB.Shell` (2.9.2, bez admina) — połączenie do `mongod` potwierdzone (`{ ok: 1 }`) |
| Docker / Docker Compose | ❌ | **potwierdzone: brak na tym komputerze** — nie instalujemy, Mongo poszło ręcznie (ZIP) |
| Playwright | ⚠️ brak globalnie | normalne — instaluje się per-projekt (`npm i -D @playwright/test` + `npx playwright install`) |
| Karma + Jasmine | ⚠️ brak globalnie | normalne — przychodzi z `ng new` |
| VS Code | ✅ | — |
| IntelliJ IDEA | ⚠️ niesprawdzalne z terminala | potwierdzić ręcznie |

### Do zrobienia (środowisko)
- [x] MongoDB zainstalowane **ręcznie, bez Dockera, bez admina** (użytkownik nie ma uprawnień administratora — wariant B odpadł)
- [x] **Wariant A zrealizowany i zweryfikowany (2026-09-02)**: ZIP `mongodb-win32-x86_64-windows-8.3.8` rozpakowany do `C:\Users\160246\Desktop\bitwa-na-kody\mongodb-win32-x86_64-windows-8.3.8`, dane w `C:\Users\160246\Desktop\bitwa-na-kody\mongodb-data`, serwer wystartowany na `127.0.0.1:27017`, połączenie TCP potwierdzone
- [X] Do zapamiętania: serwer trzeba **ręcznie odpalać przed każdą sesją pracy** (nie jest zarejestrowany jako usługa Windows) — patrz komenda w sekcji niżej

#### Instalacja MongoDB bez Dockera — zrealizowane (2026-09-02)
- Ścieżka instalacji: `C:\Users\160246\Desktop\bitwa-na-kody\mongodb-win32-x86_64-windows-8.3.8`
- Katalog danych: `C:\Users\160246\Desktop\bitwa-na-kody\mongodb-data`
- **Komenda startowa (uruchamiać ręcznie na początku każdej sesji pracy)**:
  ```
  & "C:\Users\160246\Desktop\bitwa-na-kody\mongodb-win32-x86_64-windows-8.3.8\bin\mongod.exe" --dbpath "C:\Users\160246\Desktop\bitwa-na-kody\mongodb-data" --port 27017
  ```
- Weryfikacja: log `"Waiting for connections","port":27017` + `Test-NetConnection 127.0.0.1 -Port 27017` → `TcpTestSucceeded: True` ✅
- Brak `mongosh` w tym ZIP-ie (tylko `mongod.exe`/`mongos.exe`) — do doinstalowania osobno (`winget install MongoDB.Shell`, sprawdzić czy wymaga admina), jeśli potrzebny interaktywny klient zamiast łączenia się z poziomu aplikacji

**Wariant B — winget, z adminem (odrzucony, brak uprawnień):**
- `winget install MongoDB.Server` (pakiet istnieje w winget, wersja 8.3.7) — wymaga podniesionych uprawnień, niedostępne na tym koncie
- [x] Zapasowe JDK 17/21 LTS **już istnieją lokalnie** (odkryte 2026-09-02): `c:\Users\160246\Desktop\java-tools\java\jdk-17` (openjdk 17+35) i `...\jdk-21` (openjdk 21+35) działają — potwierdzone `java -version`. Doświadczenie: to samo `java-tools\java\` ma też `jdk-11.0.6`, `jdk-23`, `jdk1.8.0_201`. Przełączanie: ustaw `JAVA_HOME` na wybrany katalog i dopisz `\bin` na początek `Path`
- [x] mongosh zainstalowany (`winget install MongoDB.Shell`, 2.9.2) — **bez admina, bez UAC** (WiX installer per-user), połączenie z `mongod` na `127.0.0.1:27017` potwierdzone (`db.runCommand({ping:1})` → `{ ok: 1 }`)
- [x] IntelliJ — **nieaktualne**: użytkownik pracuje w VS Code, nie w IntelliJ (potwierdzone 2026-09-02)

## 0. Środowisko: 🟢 ZAMKNIĘTE (2026-09-02)
Wszystkie punkty checklisty środowiskowej odhaczone. IDE: VS Code.

## 2. Scenariusze testowe „sucha przeprawa" całego SDLC

| # | Scenariusz | Co sprawdza |
|---|---|---|
| A | Smoke test repo — branch, commit, push | Git, IDE, uprawnienia, sieć |
| B | Backend-only — endpoint Spring Boot + Mongo repo, test jednostkowy/integracyjny, `mvn verify` | Java/Maven/Mongo toolchain + gate testowy CI |
| C | Frontend-only — komponent Angular z san-ui, `ng test --watch=false --browsers=ChromeHeadless`, `ng lint` | Node/Angular/san-ui/Karma toolchain + lint gate |
| D | E2E — 1 test Playwright na happy path | integracja front+back+DB, konfiguracja przeglądarek Playwright |
| E | Pełny „CI dry-run" — skrypt lokalny: `mvn verify` → statyczna analiza (Checkstyle/SpotBugs/PMD/SonarLint) → `ng lint` → `ng test` → `npx playwright test` | symulacja realnego pipeline'u oceniającego |
| F | Bug-fix pod presją czasu — naprawa celowo wstrzykniętego buga bez psucia reszty testów/analizy | trening pod scenariusz „napraw i nie zepsuj" |

## 3. Przykładowe zadania na bitwę na kody

1. Rejestr zgłoszeń serwisowych — CRUD (Spring Boot + MongoDB) + lista/formularz Angular (san-ui) z walidacją; testy backend + Karma + 1 Playwright e2e.
2. Wyszukiwarka produktów z filtrami i paginacją — query params, filtr kategoria/cena, komponent listy z filtrami san-ui; przypadki brzegowe.
3. Workflow zatwierdzania wniosków (`NEW → IN_REVIEW → APPROVED/REJECTED`) — walidacja przejść stanów, testy na ścieżki negatywne.
4. Import CSV do MongoDB — upload, walidacja wiersz po wierszu, raport błędów.
5. Panel statystyk — MongoDB aggregation pipeline + tabela/wykres Angular.
6. Bug-fix + refaktoryzacja istniejącego kodu — nie psuć testów, utrzymać jakość pod statyczną analizą.

## 4. Ocena przez CI/CD — jak symulować lokalnie

- `mvn verify` (kompilacja + testy backend) + plugin statycznej analizy (Checkstyle/SpotBugs/PMD), jeśli skonfigurowany
- `ng lint` i `ng test --watch=false --browsers=ChromeHeadless`
- `npx playwright test`
- Pilnować formatowania/stylu — statyczna analiza najczęściej łapie właśnie to
- Jeśli liczone jest pokrycie (JaCoCo) — nie zostawiać klas bez testów
- Commitować małymi, działającymi krokami (zabezpiecza częściowe punkty przy limicie czasu)

## 5. Integracja MCP (`.vscode/mcp.json`)

Skonfigurowane serwery:
- `my-mcp-server-9653ca3b` — Figma MCP (http, `https://mcp.figma.com/mcp`)
- `erste-intranet-mcp` — stdio, uruchamiany przez `npm run start` w `${env:ERSTE_INTRANET_MCP_SERVER_PROJECT_ROOT}`, integruje GitLab / Jira / Confluence / Sonar / san-ui (wszystkie sekrety przez zmienne środowiskowe, nic na twardo w pliku)

### Wymagane zmienne środowiskowe (przed uruchomieniem `erste-intranet-mcp`)
- [ ] `ERSTE_INTRANET_MCP_SERVER_PROJECT_ROOT`
- [ ] `ERSTE_INTRANET_MCP_SERVER_GITLAB_TOKEN`
- [ ] `ERSTE_INTRANET_MCP_SERVER_GITLAB_DEFAULT_GROUP`
- [ ] `ERSTE_INTRANET_MCP_SERVER_JIRA_USER`
- [ ] `ERSTE_INTRANET_MCP_SERVER_JIRA_TOKEN`
- [ ] `ERSTE_INTRANET_MCP_SERVER_JIRA_DEFAULT_PROJECT`
- [ ] `ERSTE_INTRANET_MCP_SERVER_CONFLUENCE_USER`
- [ ] `ERSTE_INTRANET_MCP_SERVER_CONFLUENCE_TOKEN`
- [ ] `ERSTE_INTRANET_MCP_SERVER_SONAR_TOKEN`
- [ ] `ERSTE_INTRANET_MCP_SERVER_SONAR_NEXT_TOKEN`

### Wynik smoke testu (2026-09-02)
- ✅ `.vscode/mcp.json` — poprawny JSON (naprawiono zniekształcony URL Figmy i zbędne backticki wokół URL-i z wklejki)
- ✅ Wszystkie wymagane zmienne środowiskowe `ERSTE_INTRANET_MCP_SERVER_*` są ustawione (sprawdzone tylko pod kątem obecności, bez ujawniania wartości)
- ✅ `ERSTE_INTRANET_MCP_SERVER_PROJECT_ROOT` wskazuje na istniejący katalog z `package.json` (`erste-intranet-mcp-server`)
- ✅ Endpoint `https://mcp.figma.com/mcp` jest osiągalny sieciowo (HTTP 400 na "gołe" HEAD bez handshake MCP — to oczekiwane, potwierdza że serwer żyje)
- ✅ Serwery uruchomione przez użytkownika w VS Code — `erste-intranet-mcp` aktywny, narzędzia GitLab/Jira/Confluence/Sonar/san-ui widoczne
- ✅ **GitLab: połączenie potwierdzone** — projekty w grupie domyślnej (`ai-ibmi`), np. `ibmi-expert-assistance-portable`, `prompt-generator`
- ✅ **Jira: połączenie potwierdzone** — lista projektów zwrócona poprawnie (kilkadziesiąt pozycji, np. `PIO178`, `CKUX`, `PRO253`)
- ✅ **Confluence: połączenie potwierdzone** — lista spaces zwrócona poprawnie, w tym `1.10 Bitwa na Analizy`
- ✅ **san-ui: połączenie potwierdzone** — pełnotekstowe wyszukiwanie w źródłach zwróciło realny kod komponentów (`san-button-set`)
- ✅ **Sonar: połączenie potwierdzone** — brak globalnego `Browse All Projects` (403 na `sonar.project.list`), ale odczyt konkretnego projektu działa w pełni: `osh-icbs-restapi-transactions` (branch `feature`) → Quality Gate OK, coverage 98.1%, 0 bugs/vulnerabilities, 21 code smells. W praktyce wystarczające — w bitwie i tak pytamy o konkretny `project_key`
- ✅ Figma MCP — endpoint osiągalny sieciowo (HTTP 400 na gołe HEAD, oczekiwane bez handshake)

**Podsumowanie smoke testu: 🟢 WSZYSTKIE INTEGRACJE ZIELONE (GitLab, Jira, Confluence, san-ui, Sonar, Figma)**

## 6. Wysyłka kodu i weryfikacja przez CI/CD (GitLab Runner)

**Zgadzam się z ogólnym modelem**: push do GitLab → pipeline CI/CD (statyczna analiza + testy) → weryfikacja wyniku. To spójne z tym, co jury i tak robi (patrz sekcja 4).

### Decyzje (potwierdzone przez użytkownika, 2026-09-02)
1. **Runner/pipeline jest lokalny, na tym komputerze**, odpalany komendą CLI — nie polegamy na infrastrukturze organizatora do wykrywania problemów.
2. **Powód**: regulamin bitwy dopuszcza **max 2 próby oficjalnego CI/CD**. Lokalny dry-run musi wykryć i pozwolić naprawić problemy z kodem *zanim* zużyjemy którąkolwiek z tych dwóch prób.
3. **Nowy mechanizm weryfikacji — pętla max 3 przebiegów**:
   - krok 1: uruchom lokalną komendę CLI (odpowiednik pipeline'u: build + testy + statyczna analiza)
   - krok 2: odczytaj/sparsuj wynik — błędy kompilacji, failed testy, naruszenia statycznej analizy
   - krok 3: jeśli są problemy — deleguj poprawkę do właściwego developera (Backend/Angular/QA, wg warstwy, w której wystąpił problem)
   - krok 4: powtórz od kroku 1
   - stop, gdy: CLI przechodzi czysto (PASS) **albo** wyczerpano 3 przebiegi pętli (wtedy raport do użytkownika, nie ślepe próbowanie w nieskończoność)

### Otwarta kwestia implementacyjna (do rozstrzygnięcia przy przejściu z planu do realizacji)
Zgodnie z dotychczasową zasadą tego pluginu, komendy budowania/testów/lintu uruchamia **wyłącznie Skippy** (orkiestrator) — subagenci-developerzy nigdy nie odpalają CLI, tylko dostarczają/poprawiają kod na podstawie przekazanych im wyników. To sugeruje, że opisana pętla to raczej **nowy blok warsztatowy orkiestrowany przez Skippy'ego** (Skippy uruchamia CLI i czyta wynik, deleguje tylko poprawki), a niekoniecznie osobny plik `.agent.md` w `agents/`. Do potwierdzenia, gdy przejdziemy z planowania do wdrożenia — na razie zostaje to jako notatka projektowa, **nic nie tworzymy**.

- [x] Runner/pipeline: lokalny, CLI
- [x] Zakres nowego mechanizmu: pętla do 3x — uruchom CLI → odczytaj problemy → deleguj poprawkę → powtórz
- [x] **Zweryfikowane 2026-09-02: `gitlab-runner` zainstalowany.** `winget install Gitlab.Runner` (19.3.1, installer type: portable) — bez admina, bez usługi Windows, tylko dopisanie do PATH. Zweryfikowane: `gitlab-runner --version` działa.
- [x] **Zweryfikowane 2026-09-02: brak możliwości automatycznego zakładania `project_key` w SonarQube.** Dostępne narzędzia `erste-intranet-mcp` są tylko do odczytu (`sonar_project_list`, `sonar_metrics_get`, `sonar_gate_get`, `sonar_issue_list`, `sonar_metrics_history`) — żadne nie tworzy/rejestruje projektu. To sprzeczne z wymaganiem „użytkownik nie zakłada ręcznie projektów” — **realna, nierozwiązana luka dla pełnej skali bitwy**. Na potrzeby tego jednego testu: użytkownik zakłada projekt ręcznie i podaje `project_key` — jednorazowy wyjątek, nie rozwiązanie docelowe.
- [x] **Projekt testowy założony i potwierdzony (2026-09-02)**: `project_key = -code-test-bitwa-kody` (SonarQube LIVE), zweryfikowany przez `sonar_metrics_get` — projekt istnieje, brak jeszcze analizy (wszystkie metryki `N/A`, czeka na pierwszy skan)
- [ ] Do ustalenia później: dokładna komenda CLI (gitlab-runner exec vs. bezpośrednio mvn/ng/playwright) — zależy od konkretnego repo bitwy, które jeszcze nie istnieje
- [ ] Do ustalenia później: czy to nowy blok orkiestrowany przez Skippy'ego, czy nowy plik agenta — **decyzja odłożona do fazy implementacji**

### Luka w rosterze agentów Skippy'ego
Sprawdziłem `agents/` — **brak dedykowanej roli odpowiedzialnej za CI/CD** (pisanie `.gitlab-ci.yml`, rejestrację/diagnostykę runnera, interpretację wyników pipeline'u). Najbliżej tematu są:
- `Code Review Specialist` — recenzja kodu post-hoc, nie konfiguracja pipeline'u
- `QA Developer` — implementuje/wzmacnia testy, nie infrastrukturę CI
- `Architecture Analyst/Developer` — decyzje architektoniczne, ADR-y, nie pipeline YAML

Luka nie zamyka się nowym plikiem agenta automatycznie — patrz "Otwarta kwestia implementacyjna" wyżej: pętla dry-run najpewniej jest nowym blokiem orkiestrowanym przez Skippy'ego (uruchamia CLI), a developerzy z istniejącego rostera (Backend/Angular/QA) tylko naprawiają zgłoszone problemy — bez tworzenia nowej persony.

### Status planu
🛑 **Etap planowania — nic nie implementujemy, nic nie tworzymy.** Gdy przejdziemy do wdrożenia, zostają dwie rzeczy do domknięcia: dokładna komenda CLI (zależna od repo bitwy, które jeszcze nie istnieje) oraz ostateczny kształt bloku (Skippy-orkiestrowany dry-run vs. nowy agent).

## 7. Scenariusz testowy: pętla samonaprawy SonarQube (do uruchomienia w osobnym oknie czatu)

**Cel**: sprawdzić w praktyce mechanizm z sekcji 6 (uruchom analizę → odczytaj problemy → deleguj poprawkę → powtórz, max 3 przebiegi) na małym, kontrolowanym przykładzie, gdzie *świadomie* siejemy błędy, żeby Sonar miał co wykryć.

### Założenia / co trzeba mieć przed startem
- **Zweryfikowane 2026-09-02 — środowisko dla realnego wariantu z SonarQube jest teraz kompletne**: `gitlab-runner` zainstalowany lokalnie (portable, bez admina), projekt testowy `-code-test-bitwa-kody` założony i potwierdzony w SonarQube LIVE (czeka na pierwszy skan)
- Konsekwencja dla briefu niżej: wygenerowany projekt musi mieć skonfigurowany skan Sonara wskazujący na `project_key: -code-test-bitwa-kody` (np. `mvn sonar:sonar -Dsonar.projectKey=-code-test-bitwa-kody -Dsonar.host.url=https://codeqa.centrala.bzwbk`, token do dogadania) zamiast/obok lokalnego Checkstyle/SpotBugs

### Zadanie dla Skippy'ego (do wklejenia w nowym oknie czatu)

```
Zadanie: wygeneruj minimalny endpoint REST w Spring Boot do zarządzania notatkami
(CRUD na kolekcji MongoDB "notes": pola id, title, content, tags) w
dedykowanym katalogu C:\Users\160246\Desktop\bitwa-na-kody\sonar-loop-test
(osobno od repo pluginu skippy-the-magnificent).

Skonfiguruj w pom.xml plugin org.sonarsource.scanner.maven:sonar-maven-plugin
(nie wymaga osobnej instalacji sonar-scanner - Maven pobiera go sam) tak,
żeby skan szedł do:
  sonar.projectKey = -code-test-bitwa-kody
  sonar.host.url   = https://codeqa.centrala.bzwbk
  sonar.token       = wartość zmiennej środowiskowej ERSTE_INTRANET_MCP_SERVER_SONAR_TOKEN
                       (już ustawiona w środowisku, NIE wpisuj jej na twardo do
                       pom.xml/kodu - przekaż jako -Dsonar.token=%zmienna% przy
                       wywołaniu albo przez settings.xml)
Komenda skanu: mvn verify sonar:sonar -Dsonar.projectKey=-code-test-bitwa-kody
  -Dsonar.host.url=https://codeqa.centrala.bzwbk -Dsonar.token=%ERSTE_INTRANET_MCP_SERVER_SONAR_TOKEN%

Świadomie wprowadź w kodzie te problemy (mają zostać wykryte przez SonarQube):
1. VULNERABILITY: zbuduj jedno z zapytań Mongo przez konkatenację
   niezaufanego stringa z requestu zamiast parametryzowanego zapytania
   (ryzyko NoSQL injection) - np. w metodzie wyszukiwania notatek po tagu.
2. CODE_SMELL: zostaw blok zakomentowanego kodu w kontrolerze.
3. CODE_SMELL: pusty/nieużywany parametr wyjątku w catch (np. "catch
   (Exception e) {}" bez obsługi).
4. Dodaj podstawowy test jednostkowy dla warstwy serwisu (happy path).

Następnie uruchom pętlę weryfikacji lokalnej (max 3 przebiegi):
1. Uruchom `mvn verify sonar:sonar` (komenda wyżej) - build, testy, wysyłka
   analizy do SonarQube.
2. Odczytaj wynik przez narzędzia MCP: `sonar_gate_get` (Quality Gate) i
   `sonar_issue_list` (project_key: -code-test-bitwa-kody) - realny odczyt
   z serwera, nie z lokalnego logu Maven.
3. Jeśli są problemy - deleguj poprawkę do właściwego developera z rostera
   (Backend Developer, bo to Spring Boot) z konkretnym opisem błędu,
   lokalizacją i regułą Sonar (np. "java:S...") - nie z ogólnikiem "napraw
   kod".
4. Powtórz od kroku 1 (analiza Sonar potrzebuje realnego czasu na
   przetworzenie skanu - jeśli `sonar_gate_get` zwraca jeszcze stary
   wynik, odczekaj i sprawdź ponownie zanim uznasz przebieg za
   zakończony).
5. Zatrzymaj się, gdy: Quality Gate = OK ALBO wyczerpano 3 przebiegi - w
   obu przypadkach zrób krótkie podsumowanie: ile przebiegów zużyto, co
   naprawiono w każdym, czy zostały nierozwiązane problemy.

Nie pomijaj wykrytej podatności NoSQL injection jako "tylko code smell" -
to ma być realny test wykrycia i naprawy podatności bezpieczeństwa, nie
tylko stylu kodu.
```

### Co obserwować/zapisać po teście (wrócić do tego planu z wynikiem)
- [x] `mvn verify sonar:sonar` uruchomione samodzielnie w obu przebiegach; build i test przeszły.
- [x] Skan dotarł do SonarQube LIVE: odczyt MCP zwrócił realne metryki i Quality Gate zamiast `N/A`.
- [x] Pętla zużyła 2 z maksymalnie 3 przebiegów; zatrzymana po drugim, gdy Quality Gate był `OK` i lista problemów była pusta.
- [x] NoSQL injection wykryto jako VULNERABILITY `javasecurity:S5147` (BLOCKER) w `NoteService.java`; naprawiono przez typowane `Query`/`Criteria` zamiast budowania `BasicQuery` z wejścia użytkownika.
- [x] Poprawkę z konkretnymi lokalizacjami i regułami Sonara delegowano do Regular Backend Developera; Skippy wykonał wyłącznie buildy, skany i odczyty MCP.
- [x] Nie osiągnięto limitu 3 przebiegów: końcowy komunikat raportuje sukces po 2 przebiegach i brak nierozwiązanych problemów.
- [x] Token Sonar nie został wpisany do `pom.xml` ani wypisany w logu; przekazano go tylko przez zmienną środowiskową procesu PowerShell.

### Wynik próby SonarQube (2026-09-02)

| Przebieg | Wynik odczytu MCP | Działanie |
|---|---|---|
| 1 | Quality Gate `OK`, ale 7 otwartych problemów: `java:S125`, `java:S4684` (2x), `javasecurity:S5147`, `java:S2201`, `java:S4719`, `java:S108` | Delegowana naprawa: DTO na granicy HTTP, usunięcie zakomentowanego/pustego kodu oraz bezpieczne zapytanie MongoDB. |
| 2 | Quality Gate `OK`; 0 issues, 0 vulnerabilities, 0 code smells, 0 bugs | Stop: cel pętli osiągnięty. |

Uwagi: pierwszy `mvn verify` wykrył niezgodność Mockito/Byte Buddy z aktywnym JDK 25. Aktualizacja Byte Buddy do `1.17.8` przywróciła wykonanie testu; po niej oba przebiegi Sonara zakończyły się powodzeniem.
