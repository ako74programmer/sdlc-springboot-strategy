---
name: review
description: "Scenario review for the brownfield sdlc-orchestrator: review only, nothing is changed - a code review of a change (merge request, branch against its base) or a code and security review of the whole project; the result is a report. Definition of done, flow, rules and report."
---

# Scenario `review`

Signals: review only, nothing is changed - a code review of a change (a merge request, a branch against its base) or a code and security review of the whole project; the result is a report.

## Definition of Done

Report only: `Toolchain` is `PASS` in the baseline, `analysis.md` and `security-review.md` exist, every finding has a severity and `file:line`, and no tracked file changed since the baseline (`git diff --stat refs/sdlc/baseline` is empty; a JaCoCo entry that `attach-project.ps1` added to `pom.xml` is part of the baseline). Red gates are findings, not blockers: `status` may be `FAILED`. Xray findings are reported, never fixed.

## Start

- Add a line `Review scope: changes <base>..HEAD` to `task.md` (the task names a merge request, branch or commits; `<base>` is the branch it merges into, e.g. `origin/main`) or `Review scope: project` (the whole project); if the task does not say which, ask once.
- `sdlc-settings.json` `scenario` must be `review` (it enables the `Toolchain` gate); if not, tell the user to re-run `attach-project.ps1 -Scenario review`.
- Environment: SonarQube and the project database (if configured) must run before any gate (`..\..\scripts\env-up.ps1`). Never use `-Skip*` flags: the measurement is part of the report (`Toolchain` fails on any skip).
- Baseline: `.\tools\sdlc.ps1 -Baseline`. Read `gates.Toolchain` and `toolchain` from `sdlc-report.json` right after it: when `Toolchain` is `FAIL`, stop and give the user its `errors[]` - JDK, Maven, `settings.xml`, SonarQube and Xray access are the user's environment, never something a delegate changes. When the user has fixed it (e.g. re-ran `attach-project.ps1` or `env-up.ps1`), record the baseline again: no file has changed yet. Every other red gate (including `SonarQube` failing on the project's own configuration, when `Toolchain` warns "server reached") is a finding for the report, not a reason to stop.

## Flow

baseline with `Toolchain` = `PASS` -> `.\tools\sdlc.ps1 -CiParity` once (no changes; proves the build from an empty Maven repository like CI) -> `analyst` (review report in `analysis.md`) -> `security-reviewer` (`security-review.md`, same scope) -> report. No other delegate.

## Rules

- nothing is fixed: no `planner`, `developer`, `test-engineer`, `build-doctor`, `bug-hunter` or `quality-fixer`, and no change to code, tests, `pom.xml`, configuration or SonarQube (no issue marked). The only files written are `task.md`, `analysis.md` and `security-review.md`. A red gate, an Xray finding, a SonarQube issue or a failing test is a finding with a severity, never a task of this run;
- scope `changes`: findings are about the changed lines and what they affect (`git diff <base>...HEAD`); gate results, Xray and SonarQube issues on untouched code are listed separately as context. Scope `project`: everything in the repository;
- give both delegates the scope line from `task.md`. `analyst` writes the review report into `analysis.md`; `security-reviewer` writes `security-review.md` and never edits other files. You never edit either report: when one has an error (a wrong version, property or severity), send it back to its author with the exact correction;
- one severity scale: security and dependency (Xray) findings are rated only in `security-review.md` (a component gets the highest Xray severity among its CVEs: Critical -> CRITICAL, High -> HIGH, Medium -> MEDIUM, Low -> LOW); `analysis.md` refers to them by their `SEC-xx` id without its own rating. Check that the counts in both summaries do not count the same finding twice;
- an Xray finding without `fixedVersions` has no fix only for the scanned version: the report says "not re-scanned on a newer patch" and lists the newest patch of that line as the next step. Never ask the user to accept a vulnerability - `XrayScan` is mandatory in CI/CD;
- proposed follow-up tasks use the scenario types this workflow has: `buildfix` (does not compile or start), `bugfix` (wrong behaviour, provable by a test), `sonarfix` (open SonarQube issues, needs a working analysis), `feature`, `tests`, `migration` (platform or major library versions). Fixes without a type of their own - Xray version bumps, SonarQube or build configuration, secrets moved out of configuration, removing unused dependencies, security hardening - belong to `remediation`, the task that takes this report as its input. Questions for the user are listed under the follow-up task they belong to, marked "answer when that task starts"; the review itself asks nothing;
- finish by checking that no tracked file changed since the baseline (`git diff --stat refs/sdlc/baseline`); if a delegate changed one, restore it with `git checkout refs/sdlc/baseline -- <file>` and say so in the report.

## Report

- the scope, the toolchain actually used (`toolchain` in `sdlc-report.json`: Java, `javaHome`, Maven vs CI, Maven settings), the gate table of the baseline and of the `-CiParity` run, the findings by severity (CRITICAL and HIGH first, from `analysis.md` and `security-review.md`), SonarQube issues by rule and Xray findings as numbers, the proposed follow-up tasks with their scenario type, and the proof that no tracked file changed;
- no "files changed" or `delta` section;
- `warnings` from the report and anything skipped.

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `analyst`

**Scenario `review` only** - `analysis.md` is the review report and nothing in it is a plan: sections 3-6 do not apply. The scope is the `Review scope:` line in `task.md` (`changes <base>..HEAD`: review `git diff <base>...HEAD` and what it affects; `project`: the whole repository). Write:
    - **Scope** - the scope line; for `changes` the commits and files (`git log --oneline <base>..HEAD`, `git diff --stat <base>...HEAD`);
    - **Toolchain** - `toolchain` from `sdlc-report.json` (Java used vs `pom.xml`, `javaHome`, Maven used vs CI `mavenExpected`, Maven Wrapper, settings file) and the `Toolchain` gate with its warnings;
    - **Gates** - the gate table of the baseline and of the `-CiParity` run; for each red gate the cause (`file:line`, error text) and whether it is code, project configuration or environment;
    - **Findings** - code review against `.github/copilot-instructions.md` and the project's own conventions: correctness risks, error handling, logging of personal data, configuration and secrets in the repository, dead or duplicated code, test quality (empty or missing assertions, `@Disabled`, tests that need external systems), build hygiene (pinned versions overriding the BOM, unused dependencies, plugins). For `changes` also: does the change do what its commits say, is it tested, does it follow the conventions. Each finding: severity CRITICAL / HIGH / MEDIUM / LOW, `file:line`, why it matters, suggested fix. Security and dependency findings are rated by `security-reviewer` in `security-review.md`: name them here with a reference (`see SEC-xx` or "security, rated in security-review.md") and no severity of your own, so no finding is counted twice;
    - **SonarQube and Xray** - open issues by rule from `metrics.sonar.byRule` (count, severity, type, example locations), `metrics.sonar.hotspotsToReview`, coverage; Xray findings from `target/xray-findings.json` by component (CVE count per Xray severity, fixed version). A CVE without `fixedVersions` has no fix only for the scanned version: write "not re-scanned on a newer patch" and the newest patch of that line you resolved with `dependency:get` - never propose accepting it. For `changes`, mark which of them are on changed lines;
    - **Follow-up tasks** - findings grouped into proposed tasks with a scenario type this workflow has: `buildfix` (does not compile or start), `bugfix` (wrong behaviour, provable by a test), `sonarfix` (open SonarQube issues, needs a working analysis), `feature`, `tests`, `migration` (platform or major library versions). Fixes without a type of their own (Xray version bumps, SonarQube or build configuration, secrets moved out of configuration, removing unused dependencies, security hardening) belong to `remediation`, the next task that takes this report as its input. Open questions go under the task they belong to, marked "answer when that task starts". Nothing is fixed in a review.
