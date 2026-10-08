### Przegląd planu „Bitwa na kody”

| Etap | Co jest gotowe | Co trzeba zrobić |
|------|----------------|------------------|
| **Środowisko lokalne** | Java 25, Maven 3.9.11, Node 26, Angular CLI 22, MongoDB uruchomiony ręcznie, Git, VS Code | Uruchamiać `mongod.exe` przed każdą sesją (komenda w sekcji *Do zrobienia*). |
| **Scenariusze testowe** | A‑F opisane w tabeli (Smoke, Backend‑only, Frontend‑only, E2E, CI dry‑run, Bug‑fix) | Wybrać kolejny scenariusz, przygotować wymagane polecenia i uruchomić. |
| **CI/CD – dry‑run** | `gitlab‑runner` zainstalowany, SonarQube dostępny, MCP skonfigurowany | Uruchamiać lokalny „pipeline” ręcznie (Maven → Sonar → ng → Playwright). |
| **Pętla napraw** | Mechanizm 3 przebiegów (build → odczyt MCP → delegacja → powtórka) opisany w sekcji 6 | Stosować przy wykrytych błędach – nie więcej niż 3 iteracje. |

---

## Propozycja metodycznego podejścia (kilka dni)

### Dzień 1 – Przygotowanie i Smoke test (Scenariusz A) - skrypt: scripts\start-mongo.ps1
1. **Uruchom MongoDB**  
   ```powershell
   & "C:\Users\160246\Desktop\bitwa-na-kody\mongodb-win32-x86_64-windows-8.3.8\bin\mongod.exe" `
     --dbpath "C:\Users\160246\Desktop\bitwa-na-kody\mongodb-data" --port 27017
   ```
2. **Sprawdź repozytorium**  
   ```bash
   git status
   git branch -vv
   ```
3. **Wykonaj smoke test** – jednorazowo sprawdź, czy możesz zrobić commit i push:  
   ```bash
   git add .
   git commit -m "Smoke test – initial commit"
   git push origin HEAD
   ```
4. **Zapisz w notatce** krótkie wnioski (czy połączenie sieciowe i uprawnienia działają).

Koniec testów Dzień 1.


### Dzień 2 – Backend‑only (Scenariusz B)
1. **Uruchom aplikację Spring Boot** (w katalogu projektu backendowego):  
   ```bash
   mvn spring-boot:run
   ```
2. **Sprawdź endpointy** przy pomocy `curl` lub Postmana.  
3. **Uruchom testy jednostkowe i integracyjne**:  
   ```bash
   mvn verify
   ```
4. **Zbadaj wyniki** – czy wszystkie testy przeszły? Jeśli nie, zanotuj przyczynę i napraw (np. brak zależności, niekompatybilny JDK).  
5. **Zrób commit** z opisem „Backend‑only – testy przejść pomyślnie”.

### Dzień 3 – Frontend‑only (Scenariusz C)
1. **Zainstaluj zależności** (jeśli nie zostały):  
   ```bash
   npm ci
   ```
2. **Uruchom lint**:  
   ```bash
   ng lint
   ```
3. **Uruchom testy jednostkowe** (headless):  
   ```bash
   ng test --watch=false --browsers=ChromeHeadless
   ```
4. **Sprawdź raport** – napraw ewentualne błędy lint lub niepowodzenia testów.  
5. **Commit** z opisem „Frontend‑only – lint i testy OK”.

### Dzień 4 – E2E (Scenariusz D)
1. **Zainstaluj Playwright** (jeśli nie):  
   ```bash
   npx playwright install
   ```
2. **Uruchom jedną prostą specyfikację** (np. `tests/e2e/smoke.spec.ts`):  
   ```bash
   npx playwright test
   ```
3. **Zobacz wyniki** – czy przeglądarka uruchomiła się, czy test przeszedł?  
4. **Ewentualne poprawki** w kodzie UI lub w konfiguracji Playwright (np. ścieżka do Chrome).  
5. **Commit** „E2E – happy‑path test passed”.

### Dzień 5 – CI dry‑run (Scenariusz E)
1. **Uruchom kolejno wszystkie kroki** w jednej sesji:  
   ```bash
   mvn verify                     # backend + Sonar (jeśli skonfigurowany)
   ng lint
   ng test --watch=false --browsers=ChromeHeadless
   npx playwright test
   ```
2. **Obserwuj kolejność** – w razie błędu zatrzymaj i napraw (np. brak zależności w Maven, nieudany lint).  
3. **Zapisz logi** (przekieruj wyjście do pliku, np. `pipeline.log`).  
4. **Commit** „CI dry‑run – wszystkie etapy OK”.

### Dzień 6 – Bug‑fix pod presją (Scenariusz F)
1. **Wprowadź celowy błąd** (np. usuń `@Service` z klasy serwisu).  
2. **Uruchom ponownie `mvn verify`** – powinien się nie powieść.  
3. **Zastosuj pętlę napraw** (max 3 przebiegi):  
   - **Iteracja 1** – odczytaj błąd, napraw go (przywróć adnotację).  
   - **Iteracja 2** – uruchom ponownie, sprawdź, czy błąd zniknął.  
   - **Iteracja 3** – ewentualna dodatkowa poprawka (np. brak obsługi wyjątku).  
4. **Po sukcesie** – commit „Bug‑fix – naprawiono celowy błąd”.

---

## Dodatkowe wskazówki

| Co zrobić | Dlaczego |
|-----------|----------|
| **Używać `git status` i `git log --oneline` po każdym kroku** | Śledzisz postęp i masz historię zmian. |
| **Zapisuj krótkie notatki w `bitwa-na-kody-plan.md`** | Łatwo wrócisz do wyników po przerwie. |
| **Nie łącz wszystkich komend w jedną długą linijkę** – uruchamiaj je osobno, aby łatwo zidentyfikować, który krok zawiódł. |
| **Jeśli testy frontendowe nie uruchamiają się w CI (brak przeglądarki)** – zainstaluj `playwright install` w trybie CI (dodaj `npx playwright install-deps`). |
| **W razie problemów z Sonar** – sprawdź, czy zmienna `ERSTE_INTRANET_MCP_SERVER_SONAR_TOKEN` jest dostępna w sesji PowerShell (`$env:ERSTE_INTRANET_MCP_SERVER_SONAR_TOKEN`). Nie zapisuj jej w kodzie. |
| **Po każdym udanym przebiegu** – zwiększ wersję w `plugin.json` (patch) i dodaj wpis do `details` zgodnie z instrukcjami repo. |

---

### Co dalej?

1. **Wybierz scenariusz, od którego chcesz zacząć** (np. najpierw Smoke, potem Backend).  
2. **Zaplanuj konkretne godziny** – np. 1 h na uruchomienie środowiska, 2 h na testy, 30 min na notatki.  
3. **Po zakończeniu każdego dnia** zrób `git push` i zaktualizuj `index.md` (nowy wpis „Day X – completed <scenariusz>”).  

Jeśli potrzebujesz dokładnych poleceń dla konkretnego kroku (np. konfiguracja Sonar w `pom.xml` lub przykładowy test Playwright), daj znać – przygotuję gotowy szablon. Powodzenia!