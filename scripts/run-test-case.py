"""Execute one legacy script in an isolated subprocess (used by mini.test)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests/support"))
from harness import MANIFEST, run_case

if __name__ == "__main__":
    case = next(case for case in MANIFEST["cases"] if case["file"] == sys.argv[1])
    run_case(case)
