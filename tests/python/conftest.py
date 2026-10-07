"""Keep each invocation's JUnit report and editor artifacts together."""

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
