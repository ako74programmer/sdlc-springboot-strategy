# Scenariusz użytkownika: parametryzacja bazy danych

## Cel

Potwierdzić, że fabryka nie zakłada MongoDB dla każdego projektu i poprawnie obsługuje różne typy baz.

## Kroki

1. W `config/project-config.local.yaml` ustaw kolejno jeden z wariantów:

   ```yaml
   databaseType: mongodb
   databaseHost: localhost
   databasePort: 27017
   ```

   albo:

   ```yaml
   databaseType: postgresql
   databaseHost: localhost
   databasePort: 5432
   ```

   albo:

   ```yaml
   databaseType: db2
   databaseHost: db2-host
   databasePort: 50000
   ```

   albo:

   ```yaml
   databaseType: none
   databaseHost: localhost
   databasePort: 0
   ```

2. Uruchom środowisko:

   ```powershell
   .\scripts\env-up.ps1
   ```

3. Dla MongoDB sprawdź, że skrypt uruchomił lub wykrył MongoDB.
4. Dla PostgreSQL i DB2 sprawdź, że skrypt potwierdził dostępność wskazanego hosta i portu.
5. Dla `none` sprawdź, że baza została pominięta.
6. Zatrzymaj środowisko:

   ```powershell
   .\scripts\env-down.ps1
   ```

## Oczekiwany rezultat

- Typ bazy, host i port pochodzą z konfiguracji lokalnej.
- `env-up.ps1` nie uruchamia MongoDB dla PostgreSQL, DB2 ani `none`.
- Niedostępna wymagana baza nie może zostać przedstawiona jako gotowa.
- `env-down.ps1` zatrzymuje tylko zasoby zarządzane przez fabrykę.
- Zmiana typu bazy nie wymaga edycji skryptów PowerShell.
