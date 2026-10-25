---
name: feature
description: "Scenario feature for the brownfield sdlc-orchestrator: a new requirement (endpoint, field, integration, business rule), usually a Jira story. Definition of done, flow, plan checks, verification and report."
---

# Scenario `feature`

Signals: a new requirement - endpoint, field, integration, business rule, usually a Jira story.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`.

**Xray is a measurement here, not a goal.** `XrayScan` runs and its findings are reported (`gates.XrayScan = FINDINGS`, `metrics.xray.findings`), but this scenario never changes dependency versions to remove them and they do not block `PASSED`. List every finding in the report as a follow-up `vulnfix` task. A scan that could not run (exit code 2: jf, token or server) is an environment problem and stays `FAIL`; never use `-SkipXray` for the final verification.

## Start

- Environment: SonarQube and the project database (if configured) must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` (existing conventions, affected code) -> `planner` (`plan.md`, one task per acceptance criterion) -> `developer` -> `test-engineer` (a test per acceptance criterion) -> `security-reviewer` -> verify

## Rules

If the task leaves a business decision open (contract, field names, error codes), ask the user before `planner`; do not let agents invent it. When `plan.md` is wrong, send it back to `planner` with the reason - never patch it yourself.

## Plan check

Review `plan.md` yourself before `developer` and send it back to `planner` when any check fails:
- every acceptance criterion has a task and a named test (criteria that are frontend-only are marked so);
- new endpoints answer 400 / 405 / 415 for malformed JSON, wrong method and wrong `Content-Type`, with tests;
- new dependencies were proven resolvable; Xray findings already in the baseline are not planned (follow-up `vulnfix`), but a new dependency must not add findings;
- no security behaviour of existing code changes unless the task asks for it.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. When the task changed `pom.xml`, `.mvn/` or other build configuration, the final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); each acceptance criterion with the test that covers it
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
