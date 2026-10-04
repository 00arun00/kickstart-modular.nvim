"""Test the failure reporting contracts that make hooks and CI trustworthy."""

import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "support"))
from harness import MANIFEST, ROOT, environment, run_process

pytestmark = pytest.mark.fast


def test_every_legacy_script_is_classified():
    files = [case["file"] for case in MANIFEST["cases"]]
    assert len(files) == len(set(files)), "Duplicate test registration"
    assert all(
        case["suite"] in {"fast", "integration", "kernel"} for case in MANIFEST["cases"]
    )
    actual = {
        str(p.relative_to(ROOT))
        for p in (ROOT / "tests").iterdir()
        if p.suffix in {".lua", ".py", ".cjs"}
    }
    expected = (
        set(files) | {"tests/" + p for p in MANIFEST["manual"]} | {"tests/run_lua.lua"}
    )
    assert actual == expected, (
        "Classify new scripts in tests/cases.json before committing"
    )


def test_nonzero_exit_is_a_failure_with_output(tmp_path):
    with pytest.raises(AssertionError, match="deliberate failure"):
        run_process(
            [sys.executable, "-c", 'print("deliberate failure"); raise SystemExit(7)'],
            env=os.environ.copy(),
            timeout=5,
            log=tmp_path / "output.log",
        )


def test_hung_child_is_a_failure(tmp_path):
    with pytest.raises(AssertionError, match="Timed out"):
        run_process(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            env=os.environ.copy(),
            timeout=0.2,
            log=tmp_path / "output.log",
        )


def test_fast_environment_isolated_from_installed_config(tmp_path):
    artifacts = tmp_path / "artifacts"
    env = environment(artifacts, tmp_path / "config", fast=True)
    config = Path(env["XDG_CONFIG_HOME"], env.get("NVIM_APPNAME", "nvim"))
    assert config.resolve() == ROOT
    assert not config.is_relative_to(artifacts)
    assert Path(env["XDG_DATA_HOME"]).is_relative_to(tmp_path)
    assert Path(env["XDG_STATE_HOME"]).is_relative_to(tmp_path)
    assert Path(env["XDG_CACHE_HOME"]).is_relative_to(tmp_path)
