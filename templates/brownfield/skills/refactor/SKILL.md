---
name: refactor
description: "Scenario refactor for the brownfield sdlc-orchestrator: clean up legacy code, god classes, code duplication or architectural smells without changing external behavior or API contracts. Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `refactor`

Signals: clean up legacy code, god classes, code duplication or architectural smells; external behavior and API contracts must remain strictly unchanged.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression`, `TestIntegrity` and `DiffGuard` are `PASS`.

**XrayScan is mandatory.** When `jfrog-xray.properties` exists, `XrayScan` must be `PASS`: corporate CI/CD blocks on it. Vulnerable dependencies are part of every task, also when they were already in the baseline - never "out of scope", never a separate task, never a question for the user. The final verification runs `.\tools\sdlc.ps1` without any `-Skip*` flag. Ask the user only when a finding still has no fix after upgrading to the newest patch version and re-scanning.

## Start

- Environment: MongoDB and SonarQube must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` (identifies targets: god classes, duplication, smell locations, scope) -> `test-engineer` (writes characterization tests covering existing behavior before any production code change) -> `developer` (refactors in small, verifiable steps: extract method/class, delegate, clean up) -> verify

## Rules

- **Zero behavior change:** API contracts (endpoints, request/response DTOs, JSON structure, HTTP status codes, error models) and database schemas must stay identical.
- **Characterization tests first:** Before `developer` touches production code, `test-engineer` must write tests capturing the current behavior. If existing test coverage is low, write tests first, verify they pass on the unmodified code, and only then proceed to refactoring.
- **Minimal diff:** Do not reformat untouched files or classes outside the scope. `DiffGuard` checks file and line limits.
- `pom.xml` should not change unless a new test library is required for characterization tests.

## Plan check

Review `plan.md` yourself before `developer` and send it back to `planner` when any check fails:
- every refactoring target has characterization tests scheduled before production changes;
- no API contract, endpoint path, DTO structure or database schema changes;
- tasks are split into small, verifiable batches.

## Verify

Run `.\tools\sdlc.ps1` yourself after each batch. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. When the task changed `pom.xml`, `.mvn/` or other build configuration, the final verify is `.\tools\sdlc.ps1 -CiParity` (or with `-Fast` if running out of time).

## Report

- scenario and refactoring summary (which classes/components were restructured and why)
- files changed (from `metrics.diff.changed` in the report)
- characterization tests added and code smells eliminated (SonarQube issues baseline -> now)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `analyst`
Write in `analysis.md` (in addition to sections 1-6):
Identify the specific classes, methods and patterns to refactor (e.g. god classes, high cognitive complexity, duplicate logic). Specify what behavior must be pinned down by characterization tests.

## For `test-engineer`
Write characterization tests for the classes identified in `analysis.md` BEFORE any production code is modified. Verify that all characterization tests pass on the baseline code.

## For `developer`
Refactor the target code in small steps without altering external behavior, method contracts or API schemas. Run `mvn test` after each small step.
