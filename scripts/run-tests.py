"""One entry point for mini.test and pytest; never installs dependencies."""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/support"))
from harness import MANIFEST, environment, selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--suite", choices=("fast", "integration", "kernel", "all"), default="fast"
    )
    parser.add_argument("--language", choices=("lua", "python", "both"), default="both")
    parser.add_argument("--match", default="")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("pytest_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    cases = selected(
        None if args.language == "both" else args.language, args.suite, args.match
    )
    languages = {case["language"] for case in cases}
    for language, suffix in [("lua", "lua"), ("python", "py")]:
        if args.language not in ("both", language):
            continue
        native = [
            p
            for p in (ROOT / "tests" / language).glob("test_*." + suffix)
            if p.name != "test_scripts." + suffix
            and args.match in str(p.relative_to(ROOT))
        ]
        if native and (language == "python" or args.suite in ("fast", "all")):
            languages.add(language)
    if args.list:
        for case in cases:
            print(f"{case['suite']:12} {case['language']:7} {case['file']}")
        print("\nManual/tools (not part of test-all):")
        for file, reason in MANIFEST["manual"].items():
            print(f"  tests/{file}: {reason}")
        return 0
    if not languages:
        parser.error("No tests matched")
    python = ROOT / ".test-venv/bin/python"
    if (
        not python.exists()
        or not (ROOT / ".test-deps/mini.nvim/lua/mini/test.lua").exists()
    ):
        parser.error("Test dependencies missing. Run make test-setup first.")
    if not shutil.which("nvim"):
        parser.error("nvim is required on PATH")
    revision = json.loads((ROOT / "lazy-lock.json").read_text())["mini.nvim"]["commit"]
    installed = subprocess.check_output(
        ["git", "-C", str(ROOT / ".test-deps/mini.nvim"), "rev-parse", "HEAD"],
        text=True,
    ).strip()
    if installed != revision:
        parser.error(
            "mini.test revision differs from lazy-lock.json. Run make test-setup."
        )
    results = ROOT / ".test-results"
    results.mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="run-", dir=results))
    with tempfile.TemporaryDirectory(prefix="nvim-test-config-") as config_root:
        env = environment(folder, Path(config_root), fast=args.suite == "fast")
        env.update(
            NVIM_TEST_SUITE=args.suite,
            NVIM_TEST_MATCH=args.match,
            NVIM_TEST_RUN_DIR=str(folder),
            PYTEST_DISABLE_PLUGIN_AUTOLOAD="1",
        )
        print(f"Test logs and artifacts: {folder}", flush=True)
        codes = []
        metadata = {"suite": args.suite, "commands": []}

        def run(command):
            language = "python" if str(command[0]) == str(python) else "lua"
            started = time.monotonic()
            code = subprocess.call(command, cwd=ROOT, env=env)
            metadata["commands"].append(
                {
                    "language": language,
                    "exit_code": code,
                    "seconds": time.monotonic() - started,
                }
            )
            (folder / "run.json").write_text(json.dumps(metadata))
            return code

        if "lua" in languages:
            codes.append(
                run(
                    [
                        "nvim",
                        "--headless",
                        "-n",
                        "-u",
                        "NONE",
                        "-i",
                        "NONE",
                        "-l",
                        "tests/run_lua.lua",
                    ],
                )
            )
        if "python" in languages:
            extra = args.pytest_args
            if extra[:1] == ["--"]:
                extra = extra[1:]
            codes.append(
                run(
                    [
                        str(python),
                        "-m",
                        "pytest",
                        "tests/python",
                        "--junitxml",
                        str(folder / "python.xml"),
                        *extra,
                    ],
                )
            )
        return 1 if any(codes) else 0


if __name__ == "__main__":
    raise SystemExit(main())
