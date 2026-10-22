---
name: vulnquick
description: "Scenario vulnquick for the brownfield sdlc-orchestrator: quick version fix from a Jira filter of corporate CYB tasks - every version in pom.xml and the parent to the newest version in the company repository, pom.xml consistency fixes, build files only, no code, no SonarQube. Definition of done, flow, rules and report."
---

# Scenario `vulnquick`

Signals: the task gives a Jira filter (JQL) or a list of corporate vulnerability tasks and asks only for the version fix: version numbers in the build file, no code, no SonarQube. Speed matters - a few minutes plus the builds.

The goal is simple: **every version in `pom.xml` and the parent goes to the newest version in the company repository**, and `pom.xml` is reviewed. Xray findings are reported before -> after; a higher number of findings after the upgrade is reported, never a reason to keep or restore an older version.

**Nothing is removed from `pom.xml`.** No dependency, exclusion, plugin, profile, repository or configuration block is deleted in this task - whatever the tool, the review or a finding suggests. A removal is always a proposal for the user in the report; the user decides. Allowed changes are only: version numbers, the property a version comes from (e.g. `${jackson-bom.version}` instead of an own `<version>`), a CVE comment, a `<dependencyManagement>` entry for a transitive version, and `<java.version>` for the Java level `pom.xml` already declares.

## Definition of Done

- the report comes from a `.\tools\sdlc.ps1 -SkipSonar` run after the last change (`.\tools\sdlc.ps1 -CheckReport` exit 0);
- `Compilation`, `Tests`, `Regression`, `TestIntegrity` and `VulnGuard` are `PASS`;
- every row of the fix list with a `target` has that version in `pom.xml`, unless the build or a test failed with it (status `needs vulnfix (code change)`);
- every issue of `pom-consistency.json` with `action` = `change` is fixed; every issue with `action` = `proposal` is in the report as a proposal for the user and `pom.xml` still has what it names;
- `analysis.md` has `## Pom review`; each of its version findings is fixed, each removal or other non-version finding is in the report as a proposal;
- nothing was removed from `pom.xml` (`git diff refs/sdlc/baseline -- pom.xml` deletes no dependency, exclusion, plugin or configuration block).

`XrayScan` may be `FAIL`, and `status` may be `FAILED` for that reason only.

## Start

- `sdlc-settings.json` `scenario` must be `vulnquick` (it enables the `VulnGuard` gate); if not, tell the user to re-run `attach-project.ps1 -Scenario vulnquick`.
- Environment: SonarQube is not used. Every run is `.\tools\sdlc.ps1 -SkipSonar`; never `-SkipXray`.
- Baseline: `.\tools\sdlc.ps1 -Baseline -SkipSonar`; it needs a real Xray scan.
- No questions to the user after the start.

## Flow

Jira filter -> baseline (`-Baseline -SkipSonar`) -> `.\tools\xray-candidates.ps1` (versions + `pom.xml` consistency) -> fix list in `task.md` (you) -> `developer` (one delegation: versions and consistency fixes, build files only) -> verify `-SkipSonar` -> `analyst` (short `pom.xml` review) -> `developer` for its findings -> verify -> report. No `planner`, `test-engineer`, `quality-fixer` or `security-reviewer`, no `plan.md`.

## Rules

- input: the Jira filter (JQL) or the issue keys from the task. Fetch them with `erste-intranet-mcp` `jira_issue_search` (read only; `jira_issue_get` only when a summary does not name the component and its version or the affected path). Write under `## Source` in `task.md` one line per issue: key, component (Maven coordinates and version), CVE, affected path(s). No filter and no keys in the task: ask once;
- scope: every version `pom.xml` declares and the parent, plus every component of the baseline Xray scan - each to the newest version in the company repository, also when it has no finding;
- target versions: run `.\tools\xray-candidates.ps1` once after the baseline (about 20 s). It lists every component of the scan (place in the jar, the version that fixes every finding), the parent of `pom.xml` and every version `pom.xml` declares (dependency versions and overrides of the parent's version properties), each with the newest version in the company repository as `target`. Every row with a `target` goes into the fix list under `## Fix list` in `task.md` (one row per component: version from -> to, fix path, its findings and the CYB issues that point at it, status) - also rows without findings and rows whose newest version does not fix every finding. Do not check versions one by one with `dependency:get` and never run `versions-maven-plugin` yourself. A newer line is still a version bump (the build and the tests prove it);
- consistency: the same call writes `sdlc-tmp\pom-consistency.json` (one Java level, one version source per library family, Lombok, add-ons the main library contains). An issue with `action` = `change` is a row of the fix list and is fixed in the same delegation, with the fix the tool names; an issue with `action` = `proposal` (e.g. a dependency the main library already contains) is never applied - it goes to the report as a proposal for the user. Both result files stay in `sdlc-tmp\` for the whole task (`mvn clean` does not touch them);
- fix path order: the parent first, to its `target`. Every version override and explicit version in `pom.xml` is set to its `target`; an override is removed only when the new parent itself manages exactly that newest version. A Boot-managed version property (`<tomcat.version>`, `<jackson-2-bom.version>`, `<jackson-bom.version>` ...) gets a one-line comment naming the CVE when it fixes one; a transitive library gets a `<dependencyManagement>` entry (never a second `<dependency>`, never an exclusion or an Xray ignore rule). The Java level stays the one `pom.xml` declares (no upgrade), but the build must really use it: when `pom-consistency.json` reports it, add `<java.version>` with that level; `maven.compiler.*` stays (its removal is a proposal);
- an affected path naming a jar that the scanned jar no longer contains in that version (the corporate scan saw an older image) gets status `already fixed in code` with the version now in the jar - it closes after the next deployment;
- a component embedded in another jar (`xray-candidates.ps1` says "embedded in <library>") changes only with the containing library: its row has no `target`; the containing library's row decides. Status `embedded in <library>` with the version of the library after this task;
- one delegation to `developer` with the exact table (property or dependency, from -> to, comment) and the consistency fixes. Only build files (`pom.xml`, `.mvn/`) change; `VulnGuard` fails on any other file;
- the only reason to restore an older version: the build or a test fails with the new one. Then have `developer` restore that one version and set status `needs vulnfix (code change)`; never adapt code or tests;
- verify `.\tools\sdlc.ps1 -SkipSonar` after the delegation. When `Compilation`, `Tests`, `Regression`, `TestIntegrity` and `VulnGuard` are `PASS`, delegate the final `pom.xml` review once to `analyst` (read only, scenario `vulnquick`: it appends `## Pom review` to `analysis.md`; give it the fix list from `task.md`). Version findings it reports (a version older than `target`, a version from the wrong property) go to `developer` in one more delegation, then verify again; findings that would remove something (a dependency, an exclusion, a property block) or need code go to the report as proposals for the user - never applied. At most 3 verify runs after the baseline. No `-CiParity`.

## Report

Short, no other sections except cost:
- the fix list table (component, version from -> to or the reason, its CVEs, the CYB issues pointing at it, status: fixed / already fixed in code / embedded / no fix version in the repository / needs vulnfix);
- Xray findings baseline -> now, by component;
- the consistency issues and the `pom.xml` review findings with what was done;
- **Proposals for the user** - every removal or other non-version change the tool or the review suggested (e.g. `hazelcast-kubernetes`, an exclusion that does not work), each with the reason and what the user should check before deciding (e.g. cluster discovery on the target environment);
- the gate table.

# Rules for delegates

The orchestrator gives each delegate this file; each one follows only its own section.

## For `analyst`

**Scenario `vulnquick` only - short `pom.xml` review, nothing else.** Read only, a few minutes. Do not write sections 1-6; append `## Pom review` to `analysis.md` with one row per finding (`pom.xml:line`, problem, kind: `version` - a fix that changes only a version or the property it comes from - or `proposal` - anything that would remove or restructure something, decided by the user - or "needs vulnfix" when it needs code). Check the final `pom.xml` and `git diff refs/sdlc/baseline -- pom.xml` for: one Java level that the build really uses (`java.version` vs `maven.compiler.*` vs the compiler plugin configuration); one version source per library family (a BOM property such as `jackson-bom.version` / `jackson-2-bom.version`, the parent's property such as `hazelcast.version` / `lombok.version`, not own versions on single modules; `annotationProcessorPaths` included); libraries of one family on one release line (e.g. `hazelcast` and `hazelcast-spring`); add-ons the main library already contains (e.g. `hazelcast-kubernetes` with `hazelcast` 5); exclusions that do not work because the library arrives through another path (prove with `mvn -q dependency:tree "-Dincludes=<groupId>:<artifactId>"`); versions older than `target` in `sdlc-tmp\xray-candidates.json`; issues of `sdlc-tmp\pom-consistency.json` that are still there. No finding without a line in `pom.xml` or the tree output.

## For `developer`

- Input: the version table from the orchestrator (`task.md`, `## Fix list`), the consistency issues with `action` = `change` (`sdlc-tmp\pom-consistency.json`) and, in a second delegation, the version findings of `## Pom review` in `analysis.md`. Apply exactly those - nothing else, no other clean-up.
- **Never remove anything from `pom.xml`**: no dependency, exclusion, plugin, profile, repository or configuration block, even when a list or a finding says so - report it back as a proposal for the user instead. Allowed: version numbers, the property a version comes from, a CVE comment, a `<dependencyManagement>` entry, `<java.version>`.
- You change only `pom.xml` (and `.mvn/` when the table says so); never `src/main`, `src/test` or configuration. Order: the parent version first, then every version the table lists (an override is removed only when the new parent itself manages exactly the newest version), Boot-managed version property, explicit version of a direct dependency, `<dependencyManagement>` entry for a transitive one. Each changed line gets a one-line comment naming the CVE. Never a second `<dependency>`, an exclusion or an Xray ignore rule.
- Verify only that the versions resolve: `mvn -q -s <mavenSettings from sdlc-settings.json> dependency:tree "-Dincludes=<groupId>:<artifactId>"` per changed component (after `.\tools\use-java.ps1`). Do not run `tools\sdlc.ps1`: the orchestrator runs it once for the whole change.
- When asked to revert a bump, restore that line to its baseline value (`git diff refs/sdlc/baseline -- pom.xml`).
- Report: one line per changed property or dependency (from -> to, CVE).
