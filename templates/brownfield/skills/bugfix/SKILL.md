---
name: bugfix
description: "Scenario bugfix for the brownfield sdlc-orchestrator: a bug description, a stack trace or a named failing test. Definition of done (reproduction test red then green), flow, verification and report."
---

# Scenario `bugfix`

Signals: a bug description, a stack trace or a named failing test.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `ReproTest` is `PASS`.

**Xray is a measurement here, not a goal.** `XrayScan` runs and its findings are reported (`gates.XrayScan = FINDINGS`, `metrics.xray.findings`), but this scenario never changes dependency versions to remove them and they do not block `PASSED`. List every finding in the report as a follow-up `vulnfix` task. A scan that could not run (exit code 2: jf, token or server) is an environment problem and stays `FAIL`; never use `-SkipXray` for the final verification.

## Start

- Environment: SonarQube and the project database (if configured) must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` -> `bug-hunter` (reproduction test, red) -> `developer` (fix from `analysis.md`) -> verify with `-ReproTest <id>`

## Verify

Run `.\tools\sdlc.ps1 -ReproTest <id>` yourself, using the id from `analysis.md` (once recorded in `sdlc-repro.json`, subsequent `.\tools\sdlc.ps1` runs check it automatically). If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. When the task changed `pom.xml`, `.mvn/` or other build configuration, the final verify is `.\tools\sdlc.ps1 -CiParity` (or `.\tools\sdlc.ps1 -CiParity -Fast` if running out of time).

Add `security-reviewer` after the fix only when the change touches input handling, queries, authentication or logging.

## Report

- scenario and what was wrong (one or two sentences)
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
