---
name: vulnfix
description: "Scenario vulnfix for the brownfield sdlc-orchestrator: fix vulnerable dependencies and only the code/tests required by that fix. The orchestrator may choose quick or full execution after review; SonarQube and unrelated cleanup are separate scenarios."
---

# Scenario `vulnfix`

`vulnfix` is the user-facing scenario for vulnerable dependencies. It is not a general project cleanup and it does not silently include SonarQube remediation, coverage work, refactoring or migration.

## Definition of Done

`sdlc-report.json` written after the last change has `status: PASSED`, `VulnGuard = PASS`, `XrayScan` ran against the final artifact, and `Regression` and `TestIntegrity` are `PASS` when a baseline exists. `Compilation` and `Tests` are `PASS`. The report lists every baseline Xray component before -> after, the fix path and any item that still requires a follow-up task or user decision.

In `quick` mode only build files may change. In `full` mode production code and tests may change only when required by the dependency update. Neither mode fixes unrelated SonarQube issues or increases coverage as a separate goal.

## Start

- `sdlc-settings.json` `scenario` must be `vulnfix`. If it is not, re-run `attach-project.ps1 -Scenario vulnfix`.
- Read `sdlc-settings.json.vulnfixMode`: `auto`, `quick` or `full`. `auto` is the default and is resolved after the initial analysis.
- Run a baseline with a real Xray scan: `.	ools\sdlc.ps1 -Baseline -SkipSonar`. A missing Xray configuration, token, client or server is an environment blocker; do not guess and do not report success.
- SonarQube is not a vulnfix gate. If the user also wants SonarQube issues fixed, stop this task and propose a separate `sonarfix` task.

## Mode selection

Use `auto` unless the user explicitly constrains the scope.

Choose `quick` when the evidence shows that the fix is limited to `pom.xml` and/or `.mvn/`, compilation and tests pass, and no API or configuration migration is needed. The quick mode is equivalent to the former `vulnquick` behavior, but it is an execution mode, not a user-facing scenario.

Choose `full` when the dependency update requires production-code changes, test changes, API adaptation, configuration changes, a Spring Boot/JDK migration, or when the quick attempt fails. The orchestrator must record the decision and reason in `task.md` before delegating changes.

If the user explicitly says “only update versions in pom.xml” or “do not touch code/tests”, force `quick`; if that cannot satisfy the vulnerability fix, stop with a precise report instead of expanding the scope.

## Flow

1. `analyst`: inspect the baseline Xray findings, dependency tree, current versions and possible fix paths. In `auto`, classify the work as quick or full. Do not fix anything.
2. `planner` (full only): create `plan.md` with build-file work first, followed by only the production and test changes required by the upgrade.
3. `developer`: update `pom.xml`/`.mvn/` and, in full mode, adapt production code required by the new versions.
4. `test-engineer` (full only): adapt tests to moved APIs or add tests needed to prove the upgrade; do not broaden the task into coverage remediation.
5. `quality-fixer` is not used for unrelated SonarQube findings. It may be used only for a defect directly introduced by the dependency upgrade.
6. Run `.	ools\sdlc.ps1 -SkipSonar` after each meaningful batch and finish with the Xray scan and the scenario-appropriate verification.

## Rules

- The source of truth is the corporate Xray scan of the built artifact, not an unverified pasted report. Map each CVE or corporate task to a scanned component, or report `not in the scanned jar`.
- Update only dependencies and the code/tests necessary for the vulnerability fix. Do not repair pre-existing SonarQube issues, add unrelated tests, refactor unrelated code, or migrate the platform unless the dependency fix requires it.
- Never add an Xray ignore rule, suppress a finding, weaken a test, remove a needed dependency or create a duplicate dependency.
- Upgrade to the newest resolvable patch version of the relevant line and re-scan before declaring that no fix exists. Embedded copies require an upgrade of their containing library.
- In quick mode, any changed file outside `pom.xml` and `.mvn/` is a failure and must be reverted or the task must be explicitly restarted in full mode.
- In full mode, every production/test change must cite the upgraded component or API in `plan.md` and the final report.
- An unrelated red SonarQube gate is a follow-up `sonarfix`, not a reason to expand this task.

## Plan check (full mode)

- Every baseline Xray component has one fix path and target, or an evidence-based user decision.
- The plan separates build-file changes from API adaptation and test adaptation.
- No task changes expected business behavior without a user decision.
- No task includes general SonarQube cleanup, coverage targets or unrelated refactoring.

## Verify

Run `.	ools\sdlc.ps1 -SkipSonar` yourself. For full mode, also run the project’s required parity/build verification after the dependency adaptation. Verify `sdlc-report.json` and `sdlc-report.json -CheckReport` before reporting success.

## Report

- selected mode (`quick`/`full`) and the evidence for the choice;
- vulnerability/CVE/task mapping and component versions before -> after;
- files changed and why each code/test change was required;
- Xray findings before -> after and unresolved findings with evidence;
- compilation, tests, regression, test integrity and VulnGuard results;
- explicit follow-ups: `sonarfix`, `tests`, `migration`, `refactor`, `remediation` or user decision.

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `analyst`

Read-only. Use the baseline Xray data, `dependency:tree`, `pom.xml` and the task text. Produce the component/finding table, origin, target version, fix path, expected API/configuration impact and a quick/full recommendation. Do not edit `pom.xml`, code or tests.

## For `planner`

Full mode only. Create a minimal plan for the dependency fix: build files first, then only the production and test adaptations proven necessary. Mark unrelated findings as follow-up scenarios; do not turn them into work items for this task.

## For `developer`

Apply only the plan’s dependency and required production-code changes. Preserve behavior. Do not touch tests unless the plan explicitly assigns a production/API adaptation that requires a later test change.

## For `test-engineer`

Full mode only. Adapt tests to the upgraded API/configuration and add only tests needed to prove the dependency fix. Never reduce assertions, disable tests or change expected business behavior.

## For `quality-fixer`

Only fix a build or test defect directly caused by the dependency update. Do not fix pre-existing SonarQube findings in a vulnfix task; those belong to `sonarfix`.
