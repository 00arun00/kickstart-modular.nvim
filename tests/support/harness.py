"""Shared subprocess isolation for the native Lua and Python test runners."""

import json
import os
import signal
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = json.loads((ROOT / "tests/cases.json").read_text())


def selected(language=None, suite=None, match=None):
    suite = suite or os.environ.get("NVIM_TEST_SUITE", "fast")
    match = match if match is not None else os.environ.get("NVIM_TEST_MATCH", "")
    return [
        case
        for case in MANIFEST["cases"]
        if (language is None or case["language"] == language)
        and (suite == "all" or case["suite"] == suite)
        and match in case["file"]
    ]


def environment(folder, config_root, fast=False):
    env = os.environ.copy()
    app = env.get("NVIM_APPNAME", "nvim")
    if Path(app).is_absolute() or ".." in Path(app).parts:
        raise RuntimeError("NVIM_APPNAME must be a relative config name")
    config = config_root / app
    config.parent.mkdir(parents=True, exist_ok=True)
    config.symlink_to(ROOT, target_is_directory=True)
    env.update(
        XDG_CONFIG_HOME=str(config_root),
        XDG_STATE_HOME=str(folder / "state"),
        XDG_CACHE_HOME=str(folder / "cache"),
        NVIM_LOG_FILE=str(folder / "nvim.log"),
        PYTHONDONTWRITEBYTECODE="1",
        MPLCONFIGDIR=str(folder / "matplotlib"),
    )
    # Fast tests must not accidentally depend on the user's plugin installation.
    if fast:
        env["XDG_DATA_HOME"] = str(folder / "data")
    env.pop("VIRTUAL_ENV", None)
    env.pop("PYTHONHOME", None)
    env.pop("PYTHONPYCACHEPREFIX", None)
    return env


def run_process(command, *, env, timeout, log):
    """Bound the entire child process group, including kernels/debug adapters."""
    with log.open("ab") as output:
        output.write(("\n$ " + " ".join(map(str, command)) + "\n").encode())
        output.flush()
        proc = subprocess.Popen(
            list(map(str, command)),
            cwd=ROOT,
            env=env,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            raise AssertionError(
                f"Timed out after {timeout}s. Log: {log}\n{log.read_text(errors='replace')}"
            ) from None
        finally:
            # A script can leave descendants behind even after exiting normally.
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
    if code:
        raise AssertionError(
            f"Exit {code}. Log: {log}\n{log.read_text(errors='replace')}"
        )


def run_case(case):
    run_dir = Path(os.environ.get("NVIM_TEST_RUN_DIR", ROOT / ".test-results"))
    run_dir.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix=Path(case["file"]).stem + "-", dir=run_dir))
    with (
        tempfile.TemporaryDirectory(prefix="nvim-test-project-") as project,
        tempfile.TemporaryDirectory(prefix="nvim-test-config-") as config_root,
    ):
        env = environment(folder, Path(config_root), fast=case["suite"] == "fast")
        return _run_case(case, folder, env, Path(project))


def _run_case(case, folder, env, project):
    log = folder / "output.log"
    if case["language"] == "lua":
        command = [
            "nvim",
            "--headless",
            "-n",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "-l",
            case["file"],
        ]
    else:
        name = Path(case["file"]).stem
        python = ROOT / ".test-venv/bin/python"
        output = folder / "artifacts"
        output.mkdir()
        args = []
        kernel = ROOT / ".test-kernel/bin/python"
        value_tests = {
            "variable_values",
            "image_values",
            "plot_values",
            "plot_renderer",
        }
        project_tests = {
            "cells_ui",
            "notebook_markdown",
            "notebook",
            "output",
            "plots",
            "python_tools",
            "variables",
            "variables_workspace",
            "plot_workspace",
            "image_viewer",
        }
        if case["suite"] == "kernel":
            if not kernel.exists():
                raise AssertionError(
                    "Missing kernel test environment. Run make test-setup-kernel."
                )
            (project / ".venv").symlink_to(
                kernel.parent.parent, target_is_directory=True
            )
            (project / "pyproject.toml").write_text(
                '[project]\nname="nvim-test-fixture"\nversion="0.0.0"\n'
            )
        if name in value_tests:
            python = kernel if name != "plot_renderer" else python
        if name in project_tests:
            args.append(project)
        if name in {"variables_workspace", "plot_workspace", "image_viewer"}:
            args.append(output)
        if name in {"project_home", "project_home_visual"}:
            args.extend([output, "--volt"])
        if name == "project_home_visual":
            args.append("--full-config")
        if name == "plot_values":
            args.append(output)
        if name == "plot_renderer":
            run_process(
                [kernel, "tests/plot_values.py", output],
                env=env,
                timeout=case["timeout"],
                log=log,
            )
            args.append(output)
        command = [python, case["file"], *args]
    run_process(command, env=env, timeout=case["timeout"], log=log)
    return folder
