"""Independent Trouble deletion/export workflows against installed plugins."""

import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "support"))
from harness import ROOT, environment, run_process

pytestmark = [pytest.mark.integration, pytest.mark.python]


@pytest.mark.parametrize("scenario", ["row", "group", "empty", "folded", "roundtrip"])
def test_trouble_deletion_export(scenario, tmp_path):
    with tempfile.TemporaryDirectory(prefix="trouble-config-") as config:
        env = environment(tmp_path, Path(config))
        env["TROUBLE_TEST_PROJECT"] = str(tmp_path)
        env["TROUBLE_TEST_SCENARIO"] = scenario
        run_process(
            [
                "nvim",
                "--headless",
                "-n",
                "-u",
                "NONE",
                "-i",
                "NONE",
                "-l",
                ROOT / "tests/support/trouble_deletion.lua",
            ],
            env=env,
            timeout=30,
            log=tmp_path / "output.log",
        )
