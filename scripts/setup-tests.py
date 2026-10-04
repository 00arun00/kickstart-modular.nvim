"""Install test-only dependencies; normal test commands never install packages."""

import argparse
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", action="store_true")
    args = parser.parse_args()
    for tool in ("uv", "git", "nvim"):
        if not shutil.which(tool):
            parser.error(f"{tool} is required on PATH")
    env = ROOT / (".test-kernel" if args.kernel else ".test-venv")
    requirements = "kernel-requirements.txt" if args.kernel else "requirements.txt"
    run("uv", "venv", "--python", "3.12", "--allow-existing", str(env))
    run(
        "uv",
        "pip",
        "sync",
        "--require-hashes",
        "--python",
        str(env / "bin/python"),
        str(ROOT / "tests" / requirements),
    )
    if not args.kernel:
        target = ROOT / ".test-deps/mini.nvim"
        commit = json.loads((ROOT / "lazy-lock.json").read_text())["mini.nvim"][
            "commit"
        ]
        if not target.exists():
            target.parent.mkdir(exist_ok=True)
            run(
                "git",
                "clone",
                "--filter=blob:none",
                "--no-checkout",
                "https://github.com/nvim-mini/mini.nvim.git",
                str(target),
            )
        if subprocess.run(
            ["git", "-C", str(target), "cat-file", "-e", commit],
            capture_output=True,
            check=False,
        ).returncode:
            run("git", "-C", str(target), "fetch", "origin", commit)
        run("git", "-C", str(target), "checkout", "--detach", commit)
    print("Ready: " + ("make test-kernel" if args.kernel else "make test"))


if __name__ == "__main__":
    main()
