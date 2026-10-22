# Audyt scenariuszy – otwarte punkty do decyzji (2026-10-22)

> Wyjaśniona zasada bazowa: **Xray i Sonar są bezwzględnie obowiązkowe w każdym scenariuszu**, ponieważ oficjalne CI/CD bitwy ma tylko 2 próby i każdy czerwony skan pali podejście.

---

## 1. Scenariusz-widmo: `refactor`
* **Stan:** Typ `refactor` figuruje w `config/scenario-config.yaml` oraz w `scripts/start-scenario.ps1`.
* **Problem:** Brak katalogu `templates/brownfield/skills/refactor/`. Orkiestrator w `sdlc-orchestrator.agent.md` odrzuca go: *„Other types (refactor) are not supported by this workflow yet - say so and stop”*.
* **Do decyzji:** Dopisujemy skill `refactor` (testy charakteryzujące, refaktoryzacja bez zmian w API), czy usuwamy wpis ze skryptów/konfiguracji, by nie wprowadzał w błąd?
* **Rekomendacja:** Zostawić w konfiguracji i dopisać brakujący `templates/brownfield/skills/refactor/SKILL.md` (przepływ: `analyst` -> `test-engineer` tworzy testy charakteryzujące -> `developer`/`refactorer` czyści kod małymi krokami -> weryfikacja bramek `Regression` i `DiffGuard`). Odblokować `refactor` w `sdlc-orchestrator.agent.md`.

---

## 2. Automatyzacja bramki `ReproTest` w scenariuszu `bugfix`
* **Stan:** Bramki `MigrationGuard`, `VulnGuard`, `TestMigration`, `SonarQube-Issues` włączają się same na podstawie wpisu `scenario` w `sdlc-settings.json`.
* **Problem:** Bramka `ReproTest` wymaga jawnego parametru CLI `-ReproTest <id>`. Jeśli orkiestrator w ferworze pętli napraw (`quality-fixer`) uruchomi zwykłe `.\tools\sdlc.ps1`, bramka weryfikująca test odtwarzający się nie wykona.
* **Do decyzji:** Czy `attach-project.ps1` / `task.md` / `sdlc-repro.json` powinny utrwalać ID testu, aby `sdlc.ps1` w scenariuszu `bugfix` zawsze sam pilnował `ReproTest: PASS`?
* **Rekomendacja:** Automatyczne zaciąganie testu w `sdlc.ps1`. Pierwsze wywołanie (lub `bug-hunter`) utrwala ID testu w `sdlc-repro.json`. Każde kolejne uruchomienie `sdlc.ps1` w scenariuszu `bugfix` bez parametru CLI automatycznie czyta ten plik i egzekwuje bramkę `ReproTest`. Brak pliku i brak parametru = `ReproTest: FAIL` (ochrona przed pominięciem odtworzenia błędu).

---

## 3. Luka poligonowa (brak fixtures dla 6 scenariuszy)
* **Stan:** W `tests/scenarios/` są tylko: `b1-broken-build`, `b2-failing-test`, `b3-bug-report`, `b6-red-sonar`.
* **Problem:** Brak fixtures dla: `vulnquick`, `vulnfix`, `migration`, `tests`, `feature`, `review` / `remediation`.
* **Do decyzji:** Które z tych poligonów są krytyczne do przygotowania przed konkursem, aby przetestować agentów w warunkach bojowych?
* **Rekomendacja:** Wykorzystać istniejący generator `new-fixture.ps1` do utworzenia lekkich receptur (overlay + `apply.ps1`) bez commitowania całych projektów do gita. W pierwszej kolejności przygotować 3 kluczowe poligony: `b7-vulnquick` (przestarzały parent i biblioteki z CVE pod filtr Jiry), `c4-boot3-to-4` (migracja Boot 3.4/Java 17 -> Boot 4/Java 25 pod `MigrationGuard`) oraz `c2-feature-discount` (rozbudowa o nowy endpoint pod `DiffGuard`). Pozostałe (`tests`, `review`, `remediation`) testować w drugiej kolejności lub na istniejących projektach.

---

## 4. Ryzyko projektów wielomodułowych (Multi-module)
* **Stan:** `recon.ps1` daje tylko ostrzeżenie o `<modules>`. Szablon `sonar-project.properties` i JaCoCo w `sdlc.ps1` zakładają pojedynczy moduł.
* **Do decyzji:** Czy w regulaminie lub specyfice bitwy mogą pojawić się projekty wielomodułowe (np. `core` + `api`), czy zakładamy wyłącznie projekty jednomodułowe?
* **Rekomendacja:** Zabezpieczyć `sdlc.ps1` na wypadek repozytorium wielomodułowego bez żadnego narzutu i ryzyka dla pojedynczych projektów. `sonar-maven-plugin` i `Parse-TestResults` (szukające po `**`) już natywnie obsługują strukturę modułów. Wystarczy w `Parse-Coverage` w `sdlc.ps1` zmienić sztywne `target/site/jacoco/jacoco.xml` na rekurencyjne wyszukiwanie plików `jacoco.xml` i sumowanie liczników pokrycia (w projekcie pojedynczym znajdzie 1 plik i zadziała identycznie jak dotychczas, w wielomodułowym poprawnie zagreguje całość).

---

## 5. Rola Greenfield vs Brownfield
* **Stan:** Cały rozwój (skille, detekcja JDK/Mavena, quota tokenów, baseline) trafił do szablonu brownfield. Greenfield w `templates/greenfield/` jest starym, monolitycznym szablonem.
* **Do decyzji:** Czy na bitwie jest przewidziane zadanie pisania mikroserwisu od zera (greenfield), czy wszystkie zadania będą oparte o pobrany kod z repozytorium (brownfield)?
* **Rekomendacja:** Pełna gotowość na scenariusz od zera (`greenfield`). `generate-project.ps1` błyskawicznie stawia bazę ze Spring Initializr pod konfigurację z `project-config.yaml`, ale generowany projekt musi otrzymać zaktualizowane narzędzia (monitor kosztów `copilot-quota.ps1`, `load-secrets.ps1`, zgodność z najnowszymi wersjami bramek Sonar/Xray). Alternatywnie: włączenie `greenfield` jako regularnego skilla w brownfield, co pozwoli na jednakowe wsparcie niezależnie od tego, czy projekt był generowany, czy pobrany jako puste repozytorium.

---

## 6. Narzut czasowy `-CiParity` w warunkach bitewnych
* **Stan:** Końcowa weryfikacja w skillach wymaga `sdlc.ps1 -CiParity` (czyszczenie lokalnego cache Mavena).
* **Problem:** Przy wolniejszej sieci pobieranie wszystkich zależności od nowa może zająć 5–15 minut cennego czasu bitwy.
* **Do decyzji:** Czy zostawiamy twardy wymóg `-CiParity`, czy wprowadzamy przełącznik awaryjny (np. `-Fast` / `-SkipParity`) na wypadek kończącego się czasu?
* **Rekomendacja:** Dodać do `sdlc.ps1` przełącznik `-Fast` (oraz flagę `fastMode` w `sdlc-settings.json`), który pozwala pominąć czyszczenie lokalnego cache Mavena i wykonać ostateczną weryfikację na istniejącym repozytorium `~/.m2`. W skillach zapisać regułę: ostateczna weryfikacja to `-CiParity`, chyba że aktywny jest tryb `-Fast` (brak czasu). Pominięcie `-CiParity` jest odnotowywane w `warnings` raportu, ale nie blokuje statusu `PASSED`.
