---
name: tests
description: "Scenario tests for the brownfield sdlc-orchestrator: work on tests only - add missing tests, raise coverage, migrate the test framework (e.g. Spock/Groovy -> JUnit 5); production code stays as it is. Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `tests`

Signals: work on tests only - add missing tests, raise coverage, migrate the test framework (e.g. Spock/Groovy -> JUnit 5); production code stays as it is.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `TestMigration` is `PASS`.

**XrayScan is mandatory.** When `jfrog-xray.properties` exists, `XrayScan` must be `PASS`: corporate CI/CD blocks on it. Vulnerable dependencies are part of every task, also when they were already in the baseline - never "out of scope", never a separate task, never a question for the user. The final verification runs `.\tools\sdlc.ps1` without any `-Skip*` flag. Ask the user only when a finding still has no fix after upgrading to the newest patch version and re-scanning.

## Start

- `sdlc-settings.json` `scenario` must be `tests` (it enables the `TestMigration` gate); if not, tell the user to re-run `attach-project.ps1 -Scenario tests`.
- Environment: MongoDB and SonarQube must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` (inventory of existing tests and a mapping old test -> new test) -> `planner` (`plan.md`, one task per test class) -> `test-engineer` (in batches, the old file is deleted only after its replacement passes) -> verify

## Rules

`src/main` must not change. `pom.xml` may change in test-scope dependencies and test plugins (surefire, test compilers, contract generators), and in runtime dependency versions needed to fix Xray findings (delegate those to `quality-fixer`, with a comment naming the CVE). No `developer` and no `security-reviewer`. If the analysis shows production code is untestable without a change, stop and ask the user. `TestMigration` fails when fewer tests run or pass than in the baseline (Spock container entries of unrolled features are not counted) or when `src/main` changed; `TestIntegrity` then only warns about replaced test files, but disabled tests and fewer assertions still fail it.

## Plan check

Review `plan.md` yourself before the first batch and send it back to `planner` when any check fails:
- every existing test method that is replaced has a named successor in the mapping table (parameterised cases keep all data rows);
- the test runner configuration (e.g. surefire `includes`) will pick up the new test classes;
- no task touches `src/main`; `pom.xml` tasks are limited to test scope and to runtime version bumps for Xray findings.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. When the task changed `pom.xml`, `.mvn/` or other build configuration, the final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); the executed test count and coverage baseline -> now and where the mapping table is
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
