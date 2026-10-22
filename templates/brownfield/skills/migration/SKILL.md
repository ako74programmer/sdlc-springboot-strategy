---
name: migration
description: "Scenario migration for the brownfield sdlc-orchestrator: move the project to a new platform version (Spring Boot / Spring Framework major, Java version); production code changes only as far as the new versions require. Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `migration`

Signals: move the project to a new platform version - Spring Boot / Spring Framework major, Java version; production code changes only as far as the new versions require.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `MigrationGuard` is `PASS`.

**XrayScan is mandatory.** When `jfrog-xray.properties` exists, `XrayScan` must be `PASS`: corporate CI/CD blocks on it. Vulnerable dependencies are part of every task, also when they were already in the baseline - never "out of scope", never a separate task, never a question for the user. The final verification runs `.\tools\sdlc.ps1` without any `-Skip*` flag. Ask the user only when a finding still has no fix after upgrading to the newest patch version and re-scanning.

## Start

- `sdlc-settings.json` `scenario` must be `migration` (it enables the `MigrationGuard` gate); if not, tell the user to re-run `attach-project.ps1 -Scenario migration`. `migrationBootVersion` and `migrationJavaVersion` must be set there, and `javaHome` must point to a JDK of `migrationJavaVersion`.
- Environment: MongoDB and SonarQube must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` (breaking-change inventory) -> `planner` (`plan.md`, ordered: build file, production code, configuration, tests, Xray) -> `developer` (`pom.xml` + `src/main`) -> `test-engineer` (adapt tests to changed APIs only) -> `security-reviewer` (when security configuration, filters or authentication changed) -> verify

## Rules

- the analysis covers the parent/BOM version, every explicitly pinned version in `pom.xml` (they usually block the new BOM), company libraries (find a version built for the target platform with the Maven commands of the orchestrator; if none exists, stop and ask the user - never fork or copy them), Java version and annotation processors (Lombok, QueryDSL, MapStruct), renamed configuration properties, moved packages and removed APIs (including test annotations), and the build plugins;
- tests are adapted only where an API or package moved (imports, annotations, mock setup); assertions, cases and expected values stay - `TestIntegrity` checks it;
- an unavoidable behaviour change (e.g. different JSON or error format) is not hidden by changing the expected value in a test: stop and ask the user;
- `MigrationGuard` fails until `pom.xml` declares `migrationBootVersion` and `migrationJavaVersion`, or when fewer tests run or pass than in the baseline;
- the scope is the version change only. SonarQube issues that the new Java level or library annotations raise on untouched code are reported by `Regression` as warnings; do not fix them in this task - list them in the report and propose a separate `sonarfix` task. Only issues on lines changed by this task block;
- when fewer tests run than in the baseline, find out which ones before changing anything (e.g. a contract-test generator that skips up-to-date tests: Spring Cloud Contract `incrementalContractTests`).

## Plan check

Review `plan.md` yourself before `developer` and send it back to `planner` when any check fails:
- every breaking change from `analysis.md` has a task; the order is build file -> production code -> configuration -> tests -> Xray;
- every company library has a target-platform version proven resolvable, or the plan stops with a question for the user;
- test tasks only adapt moved APIs; none changes an assertion or expected value.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. The final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); the versions before -> after (platform, Java, every changed dependency) and each production change with its reason
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
