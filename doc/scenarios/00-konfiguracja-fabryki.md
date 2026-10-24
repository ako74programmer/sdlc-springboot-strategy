# Konfiguracja fabryki — test użytkownika

## Cel

Potwierdzić, że użytkownik konfiguruje środowisko tylko raz. Dane zależne od komputera i korporacji nie powinny trafiać do `project-config.yaml`.

## Kroki

1. Otwórz PowerShell w katalogu repozytorium fabryki.
2. Skopiuj przykład konfiguracji lokalnej:

   ```powershell
   Copy-Item config/project-config.local.example.yaml config/project-config.local.yaml
   ```

3. Otwórz `config/project-config.local.yaml`.
4. Uzupełnij:
   - ścieżkę do firmowego `settings.xml`,
   - katalog JDK, jeśli fabryka ma wybierać JDK na podstawie `pom.xml`,
   - katalog Mavenów, jeśli ma być używany Maven zgodny z CI,
   - adres Xray i nazwę watcha,
   - typ, host i port bazy używanej przez projekt.
5. Sprawdź, że plik nie jest śledzony przez Git:

   ```powershell
   git status --short -- config/project-config.local.yaml
   ```

   Oczekiwany rezultat: brak wyniku.
6. Nie wpisuj repozytorium ani bieżącego scenariusza do `scenario-config.yaml`. Te dane podajesz parametrami albo przekazuje je orchestrator.

## Oczekiwany rezultat

- `project-config.yaml` zawiera neutralne wartości bazowe.
- `project-config.local.yaml` zawiera lokalne ścieżki i adresy korporacyjne.
- Skrypty automatycznie ładują konfigurację lokalną jako override.
- Użytkownik nie musi modyfikować YAML przed każdym zadaniem.
