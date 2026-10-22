---
name: sonarfix
description: "Scenario sonarfix for the brownfield sdlc-orchestrator: SonarQube issues or the Quality Gate to fix, target sonarMaxOpenIssues. Definition of done, flow, rules (fix code, never silence, behaviour stays), plan checks, verification and report."
---

# Scenario `sonarfix`

Signals: SonarQube issues / Quality Gate to fix.

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `SonarQube-Issues` and `TestCount` are `PASS`.

**XrayScan is mandatory.** When `jfrog-xray.properties` exists, `XrayScan` must be `PASS`: corporate CI/CD blocks on it. Vulnerable dependencies are part of every task, also when they were already in the baseline - never "out of scope", never a separate task, never a question for the user. The final verification runs `.\tools\sdlc.ps1` without any `-Skip*` flag. Ask the user only when a finding still has no fix after upgrading to the newest patch version and re-scanning.

## Start

- Limits: `sdlc-settings.json` `sonarMaxOpenIssues` must be `0`; if not, tell the user to re-run `attach-project.ps1 -Scenario sonarfix`.
- Environment: MongoDB and SonarQube must run before any gate (`..\..\scripts\env-up.ps1`). SonarQube is part of the goal: if it is unavailable, stop and ask the user to start it (`sdlc.ps1` refuses a sonarfix baseline without SonarQube data and never reports PASSED without it).
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

`analyst` (open issues grouped by rule, risk of each fix) -> user decisions -> `planner` (`plan.md`, batches by rule) -> `quality-fixer` (one batch per delegation) -> verify

## Rules

- the baseline lists every open issue (`sonarIssueKeys`); the goal is `sonarMaxOpenIssues` from `sdlc-settings.json` (0 = clean). Security hotspots are not counted by the gate; mention them in the report: `metrics.sonar.hotspotsToReview` in `sdlc-report.json` (baseline: `sonarHotspotsToReview`). Do not query SonarQube yourself; the company SonarQube (MCP) is a different server and does not know this project;
- fix code, never silence it: no `NOSONAR`, `@SuppressWarnings`, exclusions, changes to `sonar-project.properties`, and no marking issues as "won't fix" / "false positive" in SonarQube. If an issue is a real false positive, list it for the user - only the user may resolve it in the SonarQube UI;
- behaviour stays the same. A fix that can change behaviour - names that reach external systems by reflection or serialization (JSON, IBM i / DCICBS request fields, JPA columns), time zones and clocks, null handling, public API signatures, request mappings - is a decision for the user before `planner`. Ask once, with all such groups in one list;
- tests may be restructured only where a rule asks for it (e.g. merge similar tests into a parameterized one, split a test with too many assertions); every original case and assertion value must survive. `TestCount` fails when fewer tests run or pass than in the baseline;
- one batch = one rule (or a few small rules) in one delegation; `quality-fixer` proves each batch with `mvn test` and marks it `[x]` in `plan.md`. Run `.\tools\sdlc.ps1` after every 2-3 batches and at the end; the fix loop limits count those runs.

## Plan check

Review `plan.md` yourself before the first batch and send it back to `planner` when any check fails:
- every open issue from the baseline is in exactly one batch (count per rule matches `analysis.md`);
- every user decision from `task.md` is applied to its batch; nothing that changes behaviour is planned without one;
- no task adds a suppression, an exclusion or a weaker test.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. When the task changed `pom.xml`, `.mvn/` or other build configuration, the final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

Add `security-reviewer` after the fix only when the change touches input handling, queries, authentication or logging.

## Report

- scenario and what was wrong (one or two sentences); open issues baseline -> now per rule, each user decision and the hotspot count
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `analyst`

Write in `analysis.md` (in addition to sections 1-6):

**Scenario `sonarfix` only** - open issues from `sdlc-report.json` (`SonarQube-Issues` errors) grouped by rule: count, severity/type, files, and for each rule the planned fix and its risk. Mark every group whose fix can change behaviour: names that reach external systems by reflection or serialization (check how the library maps them - annotation name or Java field name; Lombok builder/getter names change with the field name), time zones and clocks, null handling, public API signatures, request mappings, test restructuring (merge/split). Those groups go to the list of decisions for the user. Real false positives are listed separately with the reason.

## For `planner`

- no new features or tests - plan batches, one rule (or a few small rules) per batch, ordered from mechanical fixes (unused imports, final fields) to risky ones (renames, test restructuring). Each batch lists the issue count, the files and the user decision that applies; every open issue from `analysis.md` is in exactly one batch.
