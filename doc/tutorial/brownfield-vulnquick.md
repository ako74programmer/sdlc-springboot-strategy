# Tutorial: kompatybilność `vulnquick` → `vulnfix.quick`

`vulnquick` nie jest już osobnym scenariuszem biznesowym. Pozostaje aliasem dla istniejących poleceń, fixture’ów i projektów.

Nowy sposób uruchomienia:

```powershell
.\scripts\start-scenario.ps1 `
  -Scenario vulnfix `
  -VulnFixMode quick `
  -Project gekon-users
```

Tryb `quick` może zmieniać wyłącznie `pom.xml` i `.mvn/`. Nie wykonuje SonarQube i nie dopuszcza zmian w kodzie ani testach. Jeżeli aktualizacja wymaga zmiany API, konfiguracji, kodu lub testów, należy uruchomić:

```powershell
.\scripts\start-scenario.ps1 -Scenario vulnfix -VulnFixMode full -Project gekon-users
```

Domyślne polecenie bez `-VulnFixMode` używa `auto`; orchestrator wybiera tryb po analizie zależności i wpływu aktualizacji.

Canonicalne zasady znajdują się w:

- `templates/brownfield/skills/vulnfix/SKILL.md`,
- `doc/scenarios/01-vulnfix-od-raportu-xray.md`,
- `doc/scenarios/05-review-i-wybor-zakresu.md`.
