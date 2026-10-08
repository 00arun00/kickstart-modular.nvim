"""Test the failure reporting contracts that make hooks and CI trustworthy."""

import os
import select
import signal
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "support"))
from harness import MANIFEST, ROOT, environment, run_process

pytestmark = [pytest.mark.fast, pytest.mark.python]


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
    expected = set(files) | {"tests/" + p for p in MANIFEST["manual"]}
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


@pytest.mark.parametrize(
    "timeout", [False, True], ids=["parent-exits", "parent-times-out"]
)
def test_descendants_are_terminated(tmp_path, timeout):
    # A pipe reaches EOF only once the child closes its writer. Unlike a PID
    # check, this also works while a killed child remains briefly as a zombie.
    fifo, ready = tmp_path / "pipe", tmp_path / "ready"
    os.mkfifo(fifo)
    reader = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
    child = (
        "import os,time; from pathlib import Path; "
        f"fd=os.open({str(fifo)!r},os.O_WRONLY); "
        "os.write(fd,b'ready'); "
        f"Path({str(ready)!r}).write_text(str(os.getpid())); time.sleep(60)"
    )
    parent = (
        "import subprocess,sys,time; from pathlib import Path\n"
        f"subprocess.Popen([sys.executable,'-c',{child!r}])\n"
        "deadline=time.monotonic()+3\n"
        f"while not Path({str(ready)!r}).exists():\n"
        "    assert time.monotonic()<deadline, 'child did not start'\n"
        "    time.sleep(.01)\n" + ("time.sleep(60)\n" if timeout else "")
    )

    def run():
        run_process(
            [sys.executable, "-c", parent],
            env=os.environ.copy(),
            timeout=5,
            log=tmp_path / "output.log",
        )

    terminated = False
    try:
        if timeout:
            with pytest.raises(AssertionError, match="Timed out"):
                run()
        else:
            run()
        assert os.read(reader, 1024) == b"ready", "child never reached readiness"
        assert select.select([reader], [], [], 5)[0], (
            "descendant still holds the pipe open"
        )
        assert os.read(reader, 1024) == b"", "expected EOF after descendant termination"
        terminated = True
    finally:
        os.close(reader)
        # Also clean up if the assertion detects a broken harness.
        if not terminated and ready.exists():
            try:
                os.kill(int(ready.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_fast_environment_isolated_from_installed_config(tmp_path):
    artifacts = tmp_path / "artifacts"
    env = environment(artifacts, tmp_path / "config", fast=True)
    config = Path(env["XDG_CONFIG_HOME"], env.get("NVIM_APPNAME", "nvim"))
    assert config.resolve() == ROOT
    assert not config.is_relative_to(artifacts)
    assert Path(env["XDG_DATA_HOME"]).is_relative_to(tmp_path)
    assert Path(env["XDG_STATE_HOME"]).is_relative_to(tmp_path)
    assert Path(env["XDG_CACHE_HOME"]).is_relative_to(tmp_path)
    runtime = Path(env["JUPYTER_RUNTIME_DIR"])
    assert runtime.is_relative_to(artifacts)
    assert runtime == Path(env["JUPYTER_DATA_DIR"]) / "runtime"
    assert runtime.is_dir()
    assert runtime.stat().st_mode & 0o777 == 0o700
