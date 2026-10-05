"""Run existing Lua and Python scenarios directly, one pytest case per script."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "support"))
from harness import MANIFEST, run_case


@pytest.mark.parametrize(
    "case",
    [
        pytest.param(
            case,
            id=Path(case["file"]).stem,
            marks=[
                getattr(pytest.mark, case["suite"]),
                getattr(pytest.mark, case["language"]),
            ],
        )
        for case in MANIFEST["cases"]
    ],
)
def test_script(case, test_run_dir):
    run_case(case, test_run_dir)
