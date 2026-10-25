---
name: buildfix
description: "Scenario buildfix for the brownfield sdlc-orchestrator: the project does not compile, has dependency errors or does not start. Definition of done, flow, verification and report."
---

# Scenario `buildfix`

Signals: does not compile, dependency errors, does not start.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`.

**Xray is a measurement here, not a goal.** `XrayScan` runs and its findings are reported (`gates.XrayScan = FINDINGS`, `metrics.xray.findings`), but this scenario never changes dependency versions to remove them and they do not block `PASSED`. List every finding in the report as a follow-up `vulnfix` task. A scan that could not run (exit code 2: jf, token or server) is an environment problem and stays `FAIL`; never use `-SkipXray` for the final verification.

## Start

- Environment: SonarQube and the project database (if configured) must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` -> `build-doctor` -> verify

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. When the task changed `pom.xml`, `.mvn/` or other build configuration, the final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

Add `security-reviewer` after the fix only when the change touches input handling, queries, authentication or logging.

## Report

- scenario and what was wrong (one or two sentences)
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
