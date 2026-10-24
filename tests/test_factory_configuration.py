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


if __name__ == "__main__":
    test_local_override_contract()
    test_scenario_has_no_machine_specific_task()
    test_scripts_use_shared_loader()
    print("factory configuration smoke tests: PASS")
