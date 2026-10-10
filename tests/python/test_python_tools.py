"""Independent Python workflows; each gets a disposable editor and process group."""

import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "support"))
from harness import ROOT, environment, run_process


@pytest.mark.python
@pytest.mark.parametrize(
    "scenario",
    [
        pytest.param("lsp", marks=pytest.mark.integration),
        pytest.param("lsp-delayed", marks=pytest.mark.integration),
        pytest.param("pytest", marks=pytest.mark.integration),
        pytest.param("unittest", marks=pytest.mark.integration),
        pytest.param("summary-output", marks=pytest.mark.integration),
        pytest.param("file-output", marks=pytest.mark.integration),
        pytest.param("real-gutter", marks=pytest.mark.integration),
        pytest.param("debug-file", marks=pytest.mark.kernel),
        pytest.param("debug-test", marks=pytest.mark.kernel),
    ],
)
def test_python_tools(scenario, test_run_dir):
    folder = Path(
        tempfile.mkdtemp(prefix=f"python-tools-{scenario}-", dir=test_run_dir)
    )
    # Keep projects out of the checkout: its pyproject and .git change discovery.
    with (
        tempfile.TemporaryDirectory(prefix="python-tools-project-") as directory,
        tempfile.TemporaryDirectory(prefix="python-tools-config-") as config,
    ):
        project = Path(directory).resolve()
        (project / "pyproject.toml").write_text(
            '[project]\nname="fixture"\nversion="0.0.0"\n'
        )
        (project / ".venv").symlink_to(ROOT / ".test-venv", target_is_directory=True)
        # Keep the config symlink outside the uploaded artifact tree; otherwise
        # upload-artifact can follow it back into the checkout and its results.
        env = environment(folder, Path(config))
        env["PYTHON_TOOLS_ARTIFACTS"] = str(folder)
        run_process(
            [
                ROOT / ".test-venv/bin/python",
                ROOT / "tests/support/python_scenarios.py",
                scenario,
                project,
            ],
            env=env,
            timeout=120,
            log=folder / "output.log",
        )
