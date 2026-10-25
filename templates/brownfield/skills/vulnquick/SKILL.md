---
name: vulnquick
description: "Deprecated compatibility alias. Use business scenario vulnfix with execution mode quick."
---

# Deprecated alias: `vulnquick`

`vulnquick` is no longer a business scenario. It is kept only so older commands and already-created projects can be recognized.

Use:

```powershell
.\scripts\start-scenario.ps1 -Scenario vulnfix -VulnFixMode quick
```

The canonical rules, gates and report contract are in `.github/skills/vulnfix/SKILL.md`. The canonical project setting is:

```json
{
  "scenario": "vulnfix",
  "vulnfixMode": "quick"
}
```

Quick mode may change only `pom.xml` and `.mvn/`. If the update needs production-code or test changes, stop and restart the task as `vulnfix` with `-VulnFixMode full` (or use `auto`).
