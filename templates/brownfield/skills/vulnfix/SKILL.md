---
name: vulnfix
description: "Scenario vulnfix for the brownfield sdlc-orchestrator: vulnerable dependencies (Xray findings, CVE ids, corporate CYB tasks); the project moves to the target versions and ends clean - Xray 0, SonarQube 0, all tests green. Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `vulnfix`

Signals: vulnerable dependencies - Xray findings, CVE ids, corporate vulnerability tasks (e.g. `CYB-...` from the corporate scan). The project ends clean: target platform versions, Xray 0, SonarQube 0, all tests green.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `XrayScan` (`metrics.xray.findings` is 0), `VulnGuard`, `SonarQube`, `SonarQube-QualityGate` and `SonarQube-Issues` (0 open issues) are `PASS`, and the report comes from a `-CiParity` run.

**XrayScan is mandatory.** When `jfrog-xray.properties` exists, `XrayScan` must be `PASS`: corporate CI/CD blocks on it. Vulnerable dependencies are part of every task, also when they were already in the baseline - never "out of scope", never a separate task, never a question for the user. The final verification runs `.\tools\sdlc.ps1` without any `-Skip*` flag. Ask the user only when a finding still has no fix after upgrading to the newest patch version and re-scanning.

## Start

- `sdlc-settings.json` `scenario` must be `vulnfix` (it enables the `VulnGuard` and `SonarQube-Issues` gates); if not, tell the user to re-run `attach-project.ps1 -Scenario vulnfix`. `migrationBootVersion` and `migrationJavaVersion` must be set there (they are the target versions, when set), and `javaHome` must point to a JDK of `migrationJavaVersion`.
- Limits: `sonarMaxOpenIssues` must be `0`; if not, tell the user to re-run `attach-project.ps1 -Scenario vulnfix`.
- Environment: MongoDB and SonarQube must run before any gate (`..\..\scripts\env-up.ps1`). SonarQube is part of the goal: if it is unavailable, stop and ask the user to start it (`sdlc.ps1` refuses a vulnfix baseline without SonarQube data and never reports PASSED without it).
- Baseline: `.\tools\sdlc.ps1 -Baseline`. It is recorded only when the Xray scan and the SonarQube analysis really ran (`sdlc.ps1` refuses it otherwise and says why): no jar because the build does not compile is a `buildfix` first; a missing `jfrog-xray.properties`, `jf`, token, Xray or SonarQube server is the user's environment - stop and tell the user.

## Flow

`analyst` (target versions, Xray findings by component with origin and fix path, breaking changes of the target versions, SonarQube issues by rule, missing tests) -> user decisions (only behaviour changes and findings without a fix) -> `planner` (`plan.md`, batches: build file -> production code -> tests -> SonarQube issues) -> `developer` (`pom.xml` + `src/main`) -> `test-engineer` (adapt moved APIs, add missing tests) -> `quality-fixer` (SonarQube issues by rule, remaining Xray) -> `security-reviewer` (when security configuration, filters or authentication changed) -> final verify with `-CiParity`

## Rules

- the focus is vulnerable dependencies, but the project ends clean: every gate green, Xray 0, SonarQube 0 open issues, all tests green and not fewer than in the baseline. Defects and gaps found on the way (a failing build, missing tests such as a test that starts the application context, SonarQube issues) are fixed in this task too;
- the source of truth for vulnerabilities is the Xray scan of `tools\sdlc.ps1` (corporate Xray, `jfrog-xray.properties`): `sdlc-baseline.json` `xrayFindings` at the start, `XrayScan` errors and `target/xray-findings.json` now. The goal is zero findings - every vulnerable component, whatever its severity, also when the task names only some of them;
- target versions: when `sdlc-settings.json` has `migrationBootVersion` / `migrationJavaVersion`, the parent and the Java version move to exactly these values, without asking (`VulnGuard` fails until `pom.xml` declares them). Code and tests are adapted as in `migration` (moved APIs, renamed properties; assertions and expected values stay); an unavoidable behaviour change is a question for the user;
- when the task lists CVE ids or corporate tasks, `analyst` maps each one to a finding of the baseline scan. One that the scan does not show (e.g. found only in the container image) is listed in the report as "not in the scanned jar" - never guessed or fixed blindly;
- fix order per remaining component, after the target parent: a Boot-managed version property (`<tomcat.version>`, `<jackson-2-bom.version>`, `<jackson-bom.version>` ...) with a one-line comment naming the CVE; then the explicit version of a direct dependency; a component embedded in another jar (shaded or bundled - `dependency:tree` does not show it) is fixed by a version of the containing library that bundles a fixed copy. Remove an existing version override when the target parent already manages that version or a newer one. Never a duplicate dependency, an exclusion that removes a needed library, or an Xray ignore rule;
- "no fix available" holds only for the scanned version: upgrade to the newest patch of the line and re-scan first. Only a finding still there with empty `fixedVersions`, or an embedded copy without a resolvable newer containing release, goes to the user - with the evidence;
- SonarQube issues follow the `sonarfix` rules (fix code, never silence it, behaviour stays the same; a fix that can change behaviour is a user decision, asked together with the other decisions in one list);
- run `.\tools\sdlc.ps1` after the build-file batch, after the code and test batches and after every 2-3 SonarQube batches; the fix loop limits count those runs.

## Plan check

Review `plan.md` yourself before `developer` and send it back to `planner` when any check fails:
- `pom.xml` tasks set the parent to `migrationBootVersion` and Java to `migrationJavaVersion` (when set) first;
- every component of the baseline `xrayFindings` has a task with a target version proven resolvable (`dependency:get`), or an open question for the user; every CVE or corporate task from `task.md` is mapped to a finding, or marked "not in the scanned jar";
- every breaking change of the target versions from `analysis.md` has a task; test tasks only adapt moved APIs or add missing tests, none changes an assertion or expected value;
- every open SonarQube issue from the baseline is in exactly one batch, and nothing that changes behaviour is planned without a user decision;
- no task adds a suppression, an exclusion, an Xray ignore rule or a weaker test.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. The final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); the versions before -> after (platform, Java), every component baseline -> now (version before -> after, its CVEs, the fix path: parent, property, direct version or containing library), each production and test change with its reason, the CVEs or corporate tasks from `task.md` with their status (fixed / not in the scanned jar / user decision), Xray findings and SonarQube open issues baseline -> now, tests and coverage baseline -> now and the user decisions
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
