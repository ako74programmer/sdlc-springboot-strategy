---
name: remediation
description: "Scenario remediation for the brownfield sdlc-orchestrator: fix what the last review found - the task refers to the review report or its finding ids (F01, SEC-02). Definition of done, flow, rules, plan checks, verification and report."
---

# Scenario `remediation`

Signals: fix what the last review found - the task refers to the review report or its finding ids (`F01`, `SEC-02`).

## Definition of Done

`sdlc-report.json` (written after your last change) has `"status": "PASSED"`, every gate is `PASS` or `SKIPPED`, and - when a baseline exists - `Regression` and `TestIntegrity` are `PASS`. Also `SonarQube`, `SonarQube-QualityGate`, `SonarQube-Issues` (0 open issues) and `TestCount` are `PASS`, the report comes from a `-CiParity` run (`"ciParity": true`), and the findings table in `plan.md` gives every in-scope finding a final status (`fixed` with its proof, `user decision` or `deferred` with the reason).

**Xray is a measurement here, not a goal.** `XrayScan` runs and its findings are reported (`gates.XrayScan = FINDINGS`, `metrics.xray.findings`), but this scenario never changes dependency versions to remove them and they do not block `PASSED`. List every finding in the report as a follow-up `vulnfix` task. A scan that could not run (exit code 2: jf, token or server) is an environment problem and stays `FAIL`; never use `-SkipXray` for the final verification.

## Start

- `sdlc-settings.json` `scenario` must be `remediation` (it enables the `SonarQube-Issues` and `TestCount` gates); if not, tell the user to re-run `attach-project.ps1 -Scenario remediation`. `reviewSource` must name the archived review (`sdlc-history/<timestamp>`); if it is empty, tell the user to run `.\scripts\start-scenario.ps1 -Scenario remediation -NewTask` after a review.
- Limits: `sonarMaxOpenIssues` must be `0`; if not, tell the user to re-run `attach-project.ps1 -Scenario remediation`.
- Environment: SonarQube and the project database (if configured) must run before any gate (`..\..\scripts\env-up.ps1`). SonarQube is part of the goal: if it is unavailable, stop and ask the user to start it (`sdlc.ps1` never reports PASSED in remediation without it).
- Baseline: `.\tools\sdlc.ps1 -Baseline`.

## Flow

read the review report (`reviewSource`) -> scope and user decisions (one list) -> `planner` (`plan.md`: findings table + batches) -> batches: build and SonarQube configuration (`build-doctor` / `quality-fixer`) -> configuration and secrets (`developer`) -> code (`developer`) -> SonarQube issues (`quality-fixer`) -> tests (`test-engineer`), each batch verified -> `security-reviewer` (re-check of the fixed security findings) -> final verify with `-CiParity`

## Rules

- input: `analysis.md` and `security-review.md` in `reviewSource` (`sdlc-settings.json`). Never edit them; the remediation writes its own `task.md`, `plan.md` and, at the end, `security-review.md` in the project root. Finding ids (`F01`, `SEC-02`) are the language of the whole task;
- scope: what the task names (finding ids or severities); without that the default is every CRITICAL and HIGH finding of both reports whose follow-up type is `remediation` (findings marked `vulnfix`, `tests`, `migration`, `feature`, `bugfix` or `buildfix` stay follow-up tasks of their own type; `sonarfix` items are covered by the SonarQube goal below), a working SonarQube analysis and 0 open SonarQube issues. MEDIUM and LOW only when the task names them. Write the resolved scope to `task.md` as a list of ids. A review report without `Fxx`/`SEC-xx` ids (an older format) is not guessed: stop and ask the user to repeat the review;
- the baseline may lack SonarQube data when the review found a broken Sonar configuration: record it anyway (`sdlc.ps1` allows it in `remediation`) and plan that configuration fix as the first batch. `SonarQube-Issues` then judges the end state (0 open issues), which is what this task needs;
- user decisions, asked once before `planner`, in one list: the open questions from the review report, every in-scope fix that changes behaviour or security behaviour (authentication, authorization, `permitAll`, CSRF, CORS, exposed endpoints, removed dependencies that code or configuration may still use), and every action only the user can do (rotating a leaked credential, purging git history, filling `secrets.local.env`). Write the answers to `task.md`. A finding whose fix is a new feature (e.g. an authorization policy) without a business decision is `deferred`, never invented;
- secrets: a credential in tracked configuration is replaced by `${ENV_NAME}` without a default value; `secrets.local.env` is added to `.gitignore`; `tools\run-local.ps1` starts the application with it and `tools\sdlc.ps1` loads it for the tests. Tell the user the variable names and wait until they filled `secrets.local.env` before the next verify when a test needs them. Never write a value into any file, never read it from git history. The leaked value stays in git history: rotating it is a user action in the report, not `fixed`;
- `planner` writes in `plan.md` a findings table (id, severity, title, batch, status) and the batches in the order of the flow. Each task names its finding ids, the files, the delegate and the proof (a test, a gate or a re-scan);
- delegates follow their scenario rules for each batch: SonarQube as in `sonarfix` (fix code, never silence, behaviour stays the same); tests never weakened (`TestIntegrity`, `TestCount`). Each delegate marks its finished tasks `[x]` and sets the status in the findings table;
- run `.\tools\sdlc.ps1` after every batch that touches the build or dependencies and after every 2-3 other batches; the fix loop limits count those runs;
- at the end `security-reviewer` re-checks every in-scope `SEC-xx` against the current code and writes `security-review.md` (fixed / still open, with evidence) plus any new finding in the diff. A still-open in-scope finding goes back to its batch or becomes `deferred` with the reason;
- final verify `.\tools\sdlc.ps1 -CiParity`. Findings out of scope stay in the review report; list them as the next tasks.

## Plan check

Review `plan.md` yourself before the first batch and send it back to `planner` when any check fails:
- every in-scope id is in the findings table exactly once and has a batch or a decision;
- new dependencies were proven resolvable; no batch upgrades dependencies for Xray findings (follow-up `vulnfix`);
- no security behaviour of existing code changes unless the task or a user decision asks for it.

## Verify

Run `.\tools\sdlc.ps1` yourself. If it fails, delegate to `quality-fixer` with the failing gate and its `errors[]`, then verify again. The final verify is `.\tools\sdlc.ps1 -CiParity`: like CI it starts from an empty local Maven repository (slow), because some plugin conflicts appear only while downloading.

## Report

- scenario and what was wrong (one or two sentences); the findings table (every in-scope id: status, proof or reason), the user decisions, the user actions still open (e.g. credential rotation, filling `secrets.local.env`), SonarQube baseline -> now, Xray findings as a measurement for the follow-up `vulnfix`, and the out-of-scope findings as next tasks
- files changed (from `metrics.diff.changed` in the report)
- the final gate table, tests and coverage with `delta` against the baseline
- `warnings` from the report (DiffGuard, pom.xml changes) and anything skipped

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `developer`

- Work only on the batch and finding ids the orchestrator gives you (`plan.md`, findings table); set their status there and mark the tasks `[x]`. You own `src/main`, `pom.xml` and `.gitignore` for those tasks; `src/test` (including test resources) belongs to `test-engineer`.
- Secrets: replace a credential in configuration by `${ENV_NAME}` without a default value and add `secrets.local.env` to `.gitignore`. Never write a value anywhere, never read `secrets.local.env`, never copy a value from git history. Report the variable names; the user fills the file. `tools\sdlc.ps1` loads it for the tests.
- Keep behaviour unless `task.md` records a user decision for that finding. Removing a dependency: prove with `mvn dependency:tree` and a code search that nothing uses it.
- Verify each batch with `.\tools\sdlc.ps1 -SkipSonar -SkipXray`; the orchestrator runs the full pipeline.

## For `planner`

- the input is the review report (`analysis.md`, `security-review.md` in `reviewSource` from `sdlc-settings.json`) and the scope and decisions in `task.md`; there is no `analysis.md` of this task. Check every in-scope finding against the current code first (line numbers may have moved). `plan.md` starts with a findings table: id, severity, title, batch, delegate, proof, status (`open` -> `fixed` / `user decision` / `deferred` + reason). Then batches in this order: build and SonarQube configuration -> configuration and secrets (`${ENV_NAME}` without default, `secrets.local.env` in `.gitignore`, the variable names for the user) -> production code -> SonarQube issues by rule (after the configuration batch made the analysis work) -> tests (`src/test` incl. test resources). Every in-scope id is in exactly one batch or marked `user decision` / `deferred` with the decision from `task.md`; nothing behaviour- or security-changing without such a decision. No new features: a fix that needs one (e.g. an authorization policy) is `deferred`.

## For `quality-fixer`

- Work only on the batch and finding ids the orchestrator gives you (`plan.md`, findings table); set their status there and mark the tasks `[x]`. Xray findings are not part of this task (follow-up `vulnfix`); SonarQube batches follow `SonarQube-Issues (sonarfix scenario)` - the gate also requires 0 open issues here. A SonarQube configuration fix goes into `pom.xml` (never `sonar-project.properties`, which belongs to the tools).
- Never read `secrets.local.env` or write a secret value anywhere.

(`SonarQube-Issues` is the gate strategy in your agent file.)

## For `test-engineer`

- Work only on the batch and finding ids the orchestrator gives you (`plan.md`, findings table); set their status there and mark the tasks `[x]`. You own `src/test`, including test resources.
- Secrets in test configuration: replace the value by `${ENV_NAME}` (the same name as in `src/main`), never write or read a value, never read `secrets.local.env`. A test that needs an external system (e.g. a real database over VPN) stays as it is unless `task.md` records a user decision; a hermetic replacement is an added test, never a weaker one.
- New tests for fixed findings (e.g. an error path that was untested) follow the project's test style; existing cases and assertions stay (`TestIntegrity`, `TestCount`).
