---
name: remediation
description: "Scenario remediation for the brownfield sdlc-orchestrator: fix what the last review found - the task refers to the review report or its finding ids (F01, SEC-02). Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `remediation`

Signals: fix what the last review found - the task refers to the review report or its finding ids (`F01`, `SEC-02`).

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `SonarQube`, `SonarQube-QualityGate`, `SonarQube-Issues` (0 open issues) and `TestCount` are `PASS`, the report comes from a `-CiParity` run (`"ciParity": true`), and the findings table in `plan.md` gives every in-scope finding a final status (`fixed` with its proof, `user decision` or `deferred` with the reason).

**XrayScan is mandatory.** When `jfrog-xray.properties` exists, `XrayScan` must be `PASS`: corporate CI/CD blocks on it. Vulnerable dependencies are part of every task, also when they were already in the baseline - never "out of scope", never a separate task, never a question for the user. The final verification runs `.\tools\sdlc.ps1` without any `-Skip*` flag. Ask the user only when a finding still has no fix after upgrading to the newest patch version and re-scanning.

## Start

- `sdlc-settings.json` `scenario` must be `remediation` (it enables the `SonarQube-Issues` and `TestCount` gates); if not, tell the user to re-run `attach-project.ps1 -Scenario remediation`. `reviewSource` must name the archived review (`sdlc-history/<timestamp>`); if it is empty, tell the user to run `.\scripts\start-scenario.ps1 -Scenario remediation -NewTask` after a review.
- Limits: `sonarMaxOpenIssues` must be `0`; if not, tell the user to re-run `attach-project.ps1 -Scenario remediation`.
- Environment: MongoDB and SonarQube must run before any gate (`..\..\scripts\env-up.ps1`). SonarQube is part of the goal: if it is unavailable, stop and ask the user to start it (`sdlc.ps1` never reports PASSED in remediation without it).
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

read the review report (`reviewSource`) -> scope and user decisions (one list) -> `planner` (`plan.md`: findings table + batches) -> batches: build and SonarQube configuration (`build-doctor` / `quality-fixer`) -> dependencies, Xray (`quality-fixer`) -> configuration and secrets (`developer`) -> code (`developer`) -> SonarQube issues (`quality-fixer`) -> tests (`test-engineer`), each batch verified -> `security-reviewer` (re-check of the fixed security findings) -> final verify with `-CiParity`

## Rules

- input: `analysis.md` and `security-review.md` in `reviewSource` (`sdlc-settings.json`). Never edit them; the remediation writes its own `task.md`, `plan.md` and, at the end, `security-review.md` in the project root. Finding ids (`F01`, `SEC-02`) are the language of the whole task;
- scope: what the task names (finding ids or severities); without that the default is every CRITICAL and HIGH finding of both reports, Xray to zero (every component, whatever its severity), a working SonarQube analysis and 0 open SonarQube issues. MEDIUM and LOW only when the task names them. Write the resolved scope to `task.md` as a list of ids;
- the baseline may lack SonarQube data when the review found a broken Sonar configuration: record it anyway (`sdlc.ps1` allows it in `remediation`) and plan that configuration fix as the first batch. `SonarQube-Issues` then judges the end state (0 open issues), which is what this task needs;
- user decisions, asked once before `planner`, in one list: the open questions from the review report, every in-scope fix that changes behaviour or security behaviour (authentication, authorization, `permitAll`, CSRF, CORS, exposed endpoints, removed dependencies that code or configuration may still use), and every action only the user can do (rotating a leaked credential, purging git history, filling `secrets.local.env`). Write the answers to `task.md`. A finding whose fix is a new feature (e.g. an authorization policy) without a business decision is `deferred`, never invented;
- secrets: a credential in tracked configuration is replaced by `${ENV_NAME}` without a default value; `secrets.local.env` is added to `.gitignore`; `tools\run-local.ps1` starts the application with it and `tools\sdlc.ps1` loads it for the tests. Tell the user the variable names and wait until they filled `secrets.local.env` before the next verify when a test needs them. Never write a value into any file, never read it from git history. The leaked value stays in git history: rotating it is a user action in the report, not `fixed`;
- `planner` writes in `plan.md` a findings table (id, severity, title, batch, status) and the batches in the order of the flow. Each task names its finding ids, the files, the delegate and the proof (a test, a gate or a re-scan);
- delegates follow their scenario rules for each batch: Xray as in every scenario (parent/BOM first, property override with a comment naming the CVE, re-scan before reporting "no fix"); SonarQube as in `sonarfix` (fix code, never silence, behaviour stays the same); tests never weakened (`TestIntegrity`, `TestCount`). Each delegate marks its finished tasks `[x]` and sets the status in the findings table;
- run `.\tools\sdlc.ps1` after every batch that touches the build or dependencies and after every 2-3 other batches; the fix loop limits count those runs;
- at the end `security-reviewer` re-checks every in-scope `SEC-xx` against the current code and writes `security-review.md` (fixed / still open, with evidence) plus any new finding in the diff. A still-open in-scope finding goes back to its batch or becomes `deferred` with the reason;
- final verify `.\tools\sdlc.ps1 -CiParity`. Findings out of scope stay in the review report; list them as the next tasks.

## Plan check

Review `plan.md` yourself before the first batch and send it back to `planner` when any check fails:
- every in-scope id is in the findings table exactly once and has a batch or a decision;
- new dependencies were proven resolvable, and Xray findings already in the baseline have a `pom.xml` task;
- no security behaviour of existing code changes unless the task or a user decision asks for it.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. The final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); the findings table (every in-scope id: status, proof or reason), the user decisions, the user actions still open (e.g. credential rotation, filling `secrets.local.env`), Xray and SonarQube baseline -> now, and the out-of-scope findings as next tasks
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped
