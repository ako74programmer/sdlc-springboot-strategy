# Tutorial: podatne zależności (Xray) — scenariusz `vulnfix`

`vulnfix` jest jednym scenariuszem biznesowym do naprawy podatności. Nie obejmuje automatycznie napraw SonarQube, zwiększania coverage, ogólnej refaktoryzacji ani migracji platformy. Te zakresy uruchamia się osobno.

Po analizie orchestrator wybiera tryb:

- `quick` — tylko `pom.xml` i `.mvn/`;
- `full` — także konieczne zmiany kodu i testów;
- `auto` — wybór na podstawie wpływu aktualizacji.

Dawny `vulnquick` jest tylko aliasem kompatybilnościowym do `vulnfix.quick`.

## 1. Co sprawdza pipeline

Źródłem prawdy o podatnościach jest `XrayScan` zbudowanego JAR-a. Raport końcowy pokazuje komponenty i CVE przed → po, sposób wprowadzenia zależności, wersję docelową oraz nierozwiązane przypadki z dowodami.

Przepływ:

1. `review` albo analiza `vulnfix` odczytuje `pom.xml`, dependency tree i baseline Xray.
2. `analyst` określa fix path oraz rekomenduje `quick` albo `full`.
3. W trybie `quick` developer zmienia tylko pliki builda.
4. W trybie `full` developer i test-engineer adaptują tylko kod/testy wymagane przez aktualizację.
5. Pipeline wykonuje testy, regresję, integralność testów i końcowy skan Xray.

Bramki `vulnfix`:

- `XrayScan` — skan musi rzeczywiście się wykonać;
- `VulnGuard` — podatności są obsłużone, a liczba testów nie spada;
- `Compilation`, `Tests`, `Regression`, `TestIntegrity`;
- w trybie `quick` każdy plik poza `pom.xml` i `.mvn/` powoduje `FAIL`.

SonarQube jest raportowany jako osobny obszar lub follow-up `sonarfix`, ale nie jest warunkiem ukończenia `vulnfix`.

## 2. Konfiguracja

Konfigurację stanowiska wykonuje się raz w `config/project-config.local.yaml`. Bieżący projekt i scenariusz podaje się poleceniem:

```powershell
.\scripts\start-scenario.ps1 `
  -Scenario vulnfix `
  -VulnFixMode auto `
  -RepoUrl https://git.example.corp/team/service.git `
  -Project service
```

Dla jawnego zakresu:

```powershell
.\scripts\start-scenario.ps1 -Scenario vulnfix -VulnFixMode quick -Project service
.\scripts\start-scenario.ps1 -Scenario vulnfix -VulnFixMode full -Project service
```

## 3. Prompt użytkownika

```text
Napraw podatności z Xray. Nie naprawiaj przy okazji problemów SonarQube,
coverage ani niezwiązanej jakości kodu. Wybierz vulnfix.quick, jeśli wystarczą
zmiany w pom.xml/.mvn; w przeciwnym razie użyj vulnfix.full. Raportuj decyzję.
```

Jeśli potrzeba kompleksowej diagnozy, zacznij od [review i wyboru zakresu](../scenarios/05-review-i-wybor-zakresu.md).

## 4. Kryteria zakończenia

```text
scenario       = vulnfix
vulnfixMode    = auto | quick | full
XrayScan       = PASS albo jawnie opisany blocker
VulnGuard      = PASS
Compilation    = PASS
Tests          = PASS
Regression     = PASS
TestIntegrity  = PASS
```

W raporcie musi być jasno wskazane:

- wybrany tryb i powód wyboru;
- komponent/CVE i wersja przed → po;
- pliki zmienione oraz uzasadnienie każdej zmiany kodu/testów;
- podatności nierozwiązane i następny krok;
- osobne follow-upy `sonarfix`, `tests`, `migration`, `refactor` lub `remediation`.
