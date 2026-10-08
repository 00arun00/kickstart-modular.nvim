"""Keep each invocation's JUnit report and editor artifacts together."""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

RUN_DIR = pytest.StashKey[Path]()


@pytest.hookimpl(tryfirst=True)
def pytest_configure(config):
    if config.option.collectonly:
        return
    results = config.rootpath / ".test-results"
    results.mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="run-", dir=results))
    config.stash[RUN_DIR] = folder
    if not config.option.xmlpath:
        config.option.xmlpath = str(folder / "results.xml")


def pytest_report_header(config):
    if RUN_DIR in config.stash:
        return f"Test logs and artifacts: {config.stash[RUN_DIR]}"


def pytest_collection_finish(session):
    config = session.config
    if config.option.collectonly or not any(
        item.get_closest_marker("integration") or item.get_closest_marker("kernel")
        for item in session.items
    ):
        return

    def command(args, cwd=None):
        return subprocess.check_output(
            args, cwd=cwd, text=True, stderr=subprocess.DEVNULL, timeout=5
        ).strip()

    # CI provisions the committed lockfile. Report local drift without changing
    # installations or failing a test that intentionally exercises an upgrade.
    report = {}
    try:
        locked = json.loads(
            command(["git", "show", "HEAD:lazy-lock.json"], config.rootpath)
        )
        data = command(
            [
                "nvim",
                "--headless",
                "-u",
                "NONE",
                "-i",
                "NONE",
                "--cmd",
                "lua io.stdout:write(vim.fn.stdpath('data')); vim.cmd('qa!')",
            ]
        )
        for name, pin in locked.items():
            path = Path(data) / "lazy" / name
            try:
                actual = command(["git", "rev-parse", "HEAD"], path)
            except (OSError, subprocess.SubprocessError):
                actual = None
            report[name] = {
                "expected": pin["commit"],
                "installed": actual,
                "path": str(path),
            }
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report = {"error": str(error)}
    target = config.stash[RUN_DIR] / "dependency-revisions.json"
    target.write_text(json.dumps(report, indent=2) + "\n")
    reporter = config.pluginmanager.get_plugin("terminalreporter")
    if reporter:
        drift = [
            name
            for name, revision in report.items()
            if name != "error" and revision["expected"] != revision["installed"]
        ]
        reporter.write_line(f"Plugin revisions (committed lockfile): {target}")
        if "error" in report:
            reporter.write_line(
                f"Plugin revision inspection unavailable: {report['error']}"
            )
        elif drift:
            reporter.write_line(
                "Missing or different installed revisions: " + ", ".join(drift)
            )
        else:
            reporter.write_line(
                "Installed plugin revisions match the committed lockfile."
            )


@pytest.fixture(scope="session")
def test_run_dir(pytestconfig):
    return pytestconfig.stash[RUN_DIR]


@pytest.fixture(scope="session")
def render_viewport():
    import runpy

    helper = (
        Path(__file__).resolve().parents[2]
        / "lua/custom/python/helpers/image-viewport.py"
    )
    return runpy.run_path(str(helper))["render"]
