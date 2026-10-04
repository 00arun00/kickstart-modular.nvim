"""Existing Python journeys exposed as individually selectable pytest cases."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "support"))
from harness import run_case, selected


@pytest.mark.parametrize(
    "case",
    [
        pytest.param(
            case, id=Path(case["file"]).stem, marks=getattr(pytest.mark, case["suite"])
        )
        for case in selected("python")
    ],
)
def test_script(case):
    run_case(case)
