---
name: migration
description: "Scenario migration for the brownfield sdlc-orchestrator: move the project to a new platform version (Spring Boot / Spring Framework major, Java version); production code changes only as far as the new versions require. Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `migration`

Signals: move the project to a new platform version - Spring Boot / Spring Framework major, Java version; production code changes only as far as the new versions require.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `MigrationGuard` is `PASS`.

**Xray is a measurement here, not a goal.** `XrayScan` runs and its findings are reported (`gates.XrayScan = FINDINGS`, `metrics.xray.findings`), but this scenario never changes dependency versions to remove them and they do not block `PASSED`. List every finding in the report as a follow-up `vulnfix` task. A scan that could not run (exit code 2: jf, token or server) is an environment problem and stays `FAIL`; never use `-SkipXray` for the final verification.

## Start

- `sdlc-settings.json` `scenario` must be `migration` (it enables the `MigrationGuard` gate); if not, tell the user to re-run `attach-project.ps1 -Scenario migration`. `migrationBootVersion` and `migrationJavaVersion` must be set there, and `javaHome` must point to a JDK of `migrationJavaVersion`.
- Environment: SonarQube and the project database (if configured) must run before any gate (`..\..\scripts\env-up.ps1`). If SonarQube is unavailable, continue with `-SkipSonar` and say so in the final report.
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` (breaking-change inventory) -> `planner` (`plan.md`, ordered: build file, production code, configuration, tests) -> `developer` (`pom.xml` + `src/main`) -> `test-engineer` (adapt tests to changed APIs only) -> `security-reviewer` (when security configuration, filters or authentication changed) -> verify

## Rules

- the analysis covers the parent/BOM version, every explicitly pinned version in `pom.xml` (they usually block the new BOM), company libraries (find a version built for the target platform with the Maven commands of the orchestrator; if none exists, stop and ask the user - never fork or copy them), Java version and annotation processors (Lombok, QueryDSL, MapStruct), renamed configuration properties, moved packages and removed APIs (including test annotations), and the build plugins;
- tests are adapted only where an API or package moved (imports, annotations, mock setup); assertions, cases and expected values stay - `TestIntegrity` checks it;
- an unavoidable behaviour change (e.g. different JSON or error format) is not hidden by changing the expected value in a test: stop and ask the user;
- `MigrationGuard` fails until `pom.xml` declares `migrationBootVersion` and `migrationJavaVersion`, or when fewer tests run or pass than in the baseline;
- the scope is the version change only. SonarQube issues that the new Java level or library annotations raise on untouched code are reported by `Regression` as warnings; do not fix them in this task - list them in the report and propose a separate `sonarfix` task. Only issues on lines changed by this task block;
- when fewer tests run than in the baseline, find out which ones before changing anything (e.g. a contract-test generator that skips up-to-date tests: Spring Cloud Contract `incrementalContractTests`).

## Plan check

Review `plan.md` yourself before `developer` and send it back to `planner` when any check fails:
- every breaking change from `analysis.md` has a task; the order is build file -> production code -> configuration -> tests; Xray findings that remain after the migration are a follow-up `vulnfix`;
- every company library has a target-platform version proven resolvable, or the plan stops with a question for the user;
- test tasks only adapt moved APIs; none changes an assertion or expected value.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. The final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); the versions before -> after (platform, Java, every changed dependency) and each production change with its reason
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `analyst`

Write in `analysis.md` (in addition to sections 1-6):

**Scenario `migration` only** - target versions from `sdlc-settings.json` (`migrationBootVersion`, `migrationJavaVersion`); a table of every dependency and plugin with an explicit version (current -> needed, managed by the new BOM yes/no, company library yes/no); known breaking changes that hit this code base with `file:line` (moved packages, removed APIs, renamed properties, JSON library change, persistence provider, security configuration, test annotations); annotation processors; test infrastructure that the upgrade can change silently (in-memory database version, contract-test generators that skip up-to-date tests, test client JSON mappers); open decisions for the user (company libraries without a target-platform release, unavoidable behaviour changes). Do not list SonarQube rules that the new Java level activates on untouched code as work items - they belong to a later `sonarfix` task.

## For `developer`

- `vulnfix` is a separate dependency-remediation scenario. Do not apply migration rules or move the parent/Java version during migration work unless the user explicitly starts `migration`.
- You own `pom.xml` and `src/main`. Follow the order in `plan.md`: build file first, then compile errors, then configuration properties.
- Remove explicit version pins that the new BOM manages; keep a pin only with a comment saying why (CVE, missing release).
- Replace removed or moved APIs with their documented successors; keep behaviour identical. If identical behaviour is impossible, stop and report.
- Do not touch `src/test`: `test-engineer` adapts tests in the next step. Verify with `.\tools\sdlc.ps1 -SkipSonar -SkipXray`; failing tests caused by moved test APIs are expected at this point and must be listed in your report.

## For `test-engineer`

- Adapt tests only where an API or package moved: imports, annotations (e.g. `@MockBean` -> `@MockitoBean`, new test auto-configuration packages), mock and context setup.
- Never change assertions, expected values, test data or the number of cases. If a test fails because production behaviour changed, report it to the orchestrator instead of adjusting the expectation.
