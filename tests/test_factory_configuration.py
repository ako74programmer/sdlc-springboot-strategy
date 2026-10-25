"""Static contract tests for the factory configuration split.

These tests do not require PowerShell or corporate services. They protect the
repository-level contract; the user scenarios under doc/scenarios cover the
runtime checks on a configured Windows workstation.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def flat_values(path: Path):
    values = {}
    sections = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#") or line.lstrip().startswith("-"):
            continue
        m = re.match(r"^(\s*)([A-Za-z][\w-]*)\s*:\s*(.*)$", line)
        if not m:
            continue
        indent, key, raw = len(m.group(1)), m.group(2), m.group(3).strip()
        while sections and sections[-1][0] >= indent:
            sections.pop()
        if not raw:
            sections.append((indent, key))
            continue
        prefix = ".".join(item[1] for item in sections)
        full_key = f"{prefix}.{key}" if prefix else key
        value = raw.strip('"\'')
        values[full_key] = value
        values.setdefault(key, value)
    return values


def test_local_override_contract():
    base = flat_values(ROOT / "config/project-config.yaml")
    example = flat_values(ROOT / "config/project-config.local.example.yaml")
    assert base["settingsFile"] == ""
    assert base["jdksDir"] == ""
    assert base["mavensDir"] == ""
    assert base["xrayUrl"] == ""
    assert example["settingsFile"].startswith("C:\\Users\\")
    assert example["jdksDir"].startswith("C:\\Users\\")
    assert example["mavensDir"].startswith("C:\\Users\\")
    assert example["xrayUrl"].startswith("https://")


def test_scenario_has_no_machine_specific_task():
    values = flat_values(ROOT / "config/scenario-config.yaml")
    assert values["scenarioType"] == ""
    assert values["scenarioProject"] == ""
    assert values["scenarioRepoUrl"] == ""
    assert values["scenarioBaseBranch"] == ""
    assert values["vulnfixMode"] == "auto"
    assert values["diffGuardMode"] == "fail"


def test_scripts_use_shared_loader():
    expected = [
        "scripts/generate-project.ps1",
        "scripts/attach-project.ps1",
        "scripts/start-scenario.ps1",
        "scripts/fetch-project.ps1",
        "scripts/new-fixture.ps1",
        "scripts/env-up.ps1",
        "scripts/env-down.ps1",
    ]
    for relative in expected:
        text = (ROOT / relative).read_text(encoding="utf-8")
        assert "config-loader.ps1" in text, relative
        assert "Read-FactoryConfig" in text, relative


def test_business_scenario_contract():
    start = (ROOT / "scripts/start-scenario.ps1").read_text(encoding="utf-8")
    orchestrator = (ROOT / "templates/brownfield/agents/sdlc-orchestrator.agent.md").read_text(encoding="utf-8")
    pipeline = (ROOT / "templates/brownfield/sdlc.ps1").read_text(encoding="utf-8")
    review = (ROOT / "templates/brownfield/skills/review/SKILL.md").read_text(encoding="utf-8")
    review_doc = (ROOT / "doc/scenarios/05-review-i-wybor-zakresu.md").read_text(encoding="utf-8")
    review_tutorial = (ROOT / "doc/tutorial/brownfield-review.md").read_text(encoding="utf-8")
    assert '"vulnfix", "refactor"' in start
    assert '"vulnquick"' not in start.split('$scenarios =', 1)[1].split('\n', 1)[0]
    assert "vulnfixMode" in start
    assert "vulnquick` is only a backward-compatible command alias" in orchestrator
    assert "classify by meaning" in orchestrator
    assert "add `Review scope: project`" in orchestrator
    assert "otherwise add `Review scope: project`" in review
    assert "Przejrzyj projekt i powiedz, co wymaga naprawy." in review_doc
    assert "orchestrator uruchomi SonarQube" in review_doc
    assert "Nie uruchamiaj ręcznie `env-up.ps1`" in review_tutorial
    assert '$sonarClean = ($settings.scenario -in @("sonarfix", "remediation"))' in pipeline
    assert "$vulnfixQuick" in pipeline
    assert "VulnFix mode:" in pipeline
    assert "vulnfix mode not decided" in pipeline


def test_xray_is_measurement_outside_vulnfix():
    pipeline = (ROOT / "templates/brownfield/sdlc.ps1").read_text(encoding="utf-8")
    assert '$script:gateStatus.gates["XrayScan"] = "FINDINGS"' in pipeline
    skills = ROOT / "templates/brownfield/skills"
    for skill in skills.glob("*/SKILL.md"):
        text = skill.read_text(encoding="utf-8")
        assert "XrayScan is mandatory" not in text, skill
        if skill.parent.name not in ("vulnfix", "vulnquick", "review"):
            assert "Xray is a measurement here" in text, skill
    tests_skill = (skills / "tests/SKILL.md").read_text(encoding="utf-8")
    assert "not even a minimal change for testability" in tests_skill
    assert "runtime version bumps" not in tests_skill


def test_agents_and_skills_are_ascii():
    base = ROOT / "templates/brownfield"
    files = list((base / "agents").glob("*.md")) + list((base / "skills").glob("*/SKILL.md")) + [base / "copilot-instructions.md"]
    for path in files:
        assert path.read_text(encoding="utf-8").isascii(), path


def test_review_feeds_remediation():
    base = ROOT / "templates/brownfield"
    review = (base / "skills/review/SKILL.md").read_text(encoding="utf-8")
    remediation = (base / "skills/remediation/SKILL.md").read_text(encoding="utf-8")
    security = (base / "agents/security-reviewer.agent.md").read_text(encoding="utf-8")
    orchestrator = (base / "agents/sdlc-orchestrator.agent.md").read_text(encoding="utf-8")
    attach = (ROOT / "scripts/attach-project.ps1").read_text(encoding="utf-8")
    assert "an id `F01`, `F02`" in review
    assert "Summary by area" in review
    assert "Number findings `SEC-01`" in security
    assert "`F01`, `SEC-02`" in remediation
    assert "whose follow-up type is `remediation`" in remediation
    assert "Scenario: review" in orchestrator and "-Scenario remediation -NewTask" in orchestrator
    assert "Scenario:\\s*review" in attach


if __name__ == "__main__":
    test_local_override_contract()
    test_scenario_has_no_machine_specific_task()
    test_scripts_use_shared_loader()
    print("factory configuration smoke tests: PASS")
