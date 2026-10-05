"""Reporting must preserve failures, timeouts, skips, and absent results."""

import argparse
import importlib.util
import json
from pathlib import Path

import pytest

pytestmark = pytest.mark.fast
spec = importlib.util.spec_from_file_location(
    "ci_report", Path(__file__).resolve().parents[2] / "scripts/ci-report.py"
)
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def run_folder(root, language, exit_code=0):
    folder = root / ("run-" + language)
    folder.mkdir()
    (folder / "run.json").write_text(
        json.dumps(
            {
                "commands": [
                    {"language": language, "exit_code": exit_code, "seconds": 2.5}
                ]
            }
        )
    )
    return folder


def test_mixed_results_preserve_timeout_and_skip(tmp_path):
    lua = run_folder(tmp_path, "lua")
    (lua / "lua.json").write_text(
        json.dumps(
            [
                {"name": "lua pass", "status": "passed", "detail": ""},
                {"name": "lua skip", "status": "skipped", "detail": ""},
            ]
        )
    )
    python = run_folder(tmp_path, "python", 1)
    (python / "python.xml").write_text("""<testsuites><testsuite>
    <testcase name="pass" time="0.1"/>
    <testcase name="skip"><skipped/></testcase>
    <testcase name="broken"><failure>STAGE: open menu
    STAGE: close menu
    Stage timed out: close menu</failure></testcase>
    <testcase name="error"><error>setup assertion</error></testcase>
    </testsuite></testsuites>""")
    cases, errors, seconds = report.collect(tmp_path)
    assert [c["status"] for c in cases] == [
        "passed",
        "skipped",
        "passed",
        "skipped",
        "failed",
        "failed",
    ]
    assert cases[4]["category"] == "timeout"
    assert cases[4]["stage"] == "close menu"
    assert cases[5]["category"] == "assertion failure"
    assert errors == []
    assert seconds == 5


@pytest.mark.parametrize("with_results", [False, True])
def test_crashed_runner_cannot_look_green(tmp_path, with_results):
    folder = run_folder(tmp_path, "lua", 7)
    if with_results:
        (folder / "lua.json").write_text(
            json.dumps([{"name": "early pass", "status": "passed", "detail": ""}])
        )
    _, errors, _ = report.collect(tmp_path)
    assert len(errors) == 1
    assert "exit 7" in errors[0]


def test_setup_failure_is_distinct_from_test_failure(tmp_path, monkeypatch):
    monkeypatch.setenv("CI_STEPS", json.dumps({"setup": {"outcome": "failure"}}))
    args = argparse.Namespace(
        root=tmp_path, output=tmp_path / "reports", suite="fast", label="Fast"
    )
    result = report.job_report(args)[0]
    assert result["result"] == "failed"
    assert result["errors"] == ["Setup failure: test environment was not ready"]


def test_summary_escapes_table_and_failure_output():
    result = {
        "label": "A|<B>",
        "result": "failed",
        "seconds": 1,
        "errors": [],
        "cases": [
            {
                "name": "broken",
                "status": "failed",
                "category": "timeout",
                "stage": "close",
                "detail": "```\noutput",
            }
        ],
    }
    text = report.summary([result])
    assert "A\\|&lt;B&gt;" in text
    assert "| 0 | 1 | 1 | 0 |" in text
    assert "'''\noutput" in text


def test_missing_reports_fail_aggregate_even_when_jobs_succeeded(tmp_path, monkeypatch):
    for key, value in {
        "CI_NEEDS": json.dumps(
            {k: {"result": "success"} for k in ("format", "fast", "editor")}
        ),
        "GITHUB_SERVER_URL": "https://github.com",
        "GITHUB_API_URL": "https://api.github.com",
        "GITHUB_REPOSITORY": "owner/repo",
        "GITHUB_RUN_ID": "123",
        "GH_TOKEN": "test",
    }.items():
        monkeypatch.setenv(key, value)

    def offline(*args, **kwargs):
        raise OSError("offline")

    monkeypatch.setattr(report.urllib.request, "urlopen", offline)
    text, failed = report.aggregate(argparse.Namespace(root=tmp_path))
    assert failed
    assert text.count("suite report is missing") == 3
    assert "Job timing lookup unavailable" in text


def test_malformed_report_is_runner_failure(tmp_path):
    folder = run_folder(tmp_path, "python")
    (folder / "python.xml").write_text("<unfinished")
    _, errors, _ = report.collect(tmp_path)
    assert "Runner report unreadable" in errors[0]


@pytest.mark.parametrize("job_result,failed", [("success", False), ("failure", True)])
def test_aggregate_links_timings_and_upstream_status(
    tmp_path, monkeypatch, job_result, failed
):
    import io

    labels = {
        "fast": "Fast · Lua & Python",
        "integration": "Editor · plugins & navigation",
        "kernel": "Python · kernels & rendering",
    }
    for suite, label in labels.items():
        (tmp_path / f"{suite}.json").write_text(
            json.dumps(
                {
                    "suite": suite,
                    "label": label,
                    "result": "passed",
                    "cases": [{"status": "passed"}],
                    "errors": [],
                    "seconds": 3,
                }
            )
        )
    for key, value in {
        "CI_NEEDS": json.dumps(
            {
                k: {"result": job_result if k == "editor" else "success"}
                for k in ("format", "fast", "editor")
            }
        ),
        "GITHUB_SERVER_URL": "https://github.com",
        "GITHUB_API_URL": "https://api.github.com",
        "GITHUB_REPOSITORY": "owner/repo",
        "GITHUB_RUN_ID": "123",
        "GH_TOKEN": "test",
    }.items():
        monkeypatch.setenv(key, value)
    jobs = [
        {
            "name": label,
            "html_url": f"https://github.com/owner/repo/actions/runs/123/job/{suite}",
            "steps": [
                {
                    "name": "setup",
                    "started_at": "2026-10-05T00:00:00Z",
                    "completed_at": "2026-10-05T00:00:12Z",
                },
                {"name": "Run Lua tests"},
            ],
        }
        for suite, label in labels.items()
    ]
    monkeypatch.setattr(
        report.urllib.request,
        "urlopen",
        lambda *a, **k: io.StringIO(json.dumps({"jobs": jobs})),
    )
    text, actual_failed = report.aggregate(argparse.Namespace(root=tmp_path))
    assert actual_failed == failed
    assert text.count("12.0s") == 3
    assert "[Logs](https://github.com/owner/repo/actions/runs/123/job/fast)" in text


def test_lua_reporter_preserves_framework_outcomes(tmp_path):
    import os
    import subprocess

    root = Path(__file__).resolve().parents[2]
    (tmp_path / ".test-deps").symlink_to(root / ".test-deps", target_is_directory=True)
    fixtures = tmp_path / "tests/lua"
    fixtures.mkdir(parents=True)
    (fixtures / "test_report.lua").write_text("""
local T = MiniTest.new_set()
T['pass'] = function() MiniTest.expect.equality(1, 1) end
T['fail'] = function() error('deliberate reporter failure') end
T['skip'] = function() MiniTest.skip('deliberate skip') end
return T
""")
    result = subprocess.run(
        [
            "nvim",
            "--headless",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "-l",
            str(root / "tests/run_lua.lua"),
        ],
        cwd=tmp_path,
        env={
            **os.environ,
            "NVIM_TEST_RUN_DIR": str(tmp_path),
            "NVIM_TEST_SUITE": "fast",
            "NVIM_TEST_MATCH": "",
        },
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 1, result.stdout + result.stderr
    cases = json.loads((tmp_path / "lua.json").read_text())
    assert sorted(c["status"] for c in cases) == ["failed", "passed", "skipped"]
    assert "deliberate reporter failure" in next(
        c["detail"] for c in cases if c["status"] == "failed"
    )


def test_traceback_source_does_not_count_as_timeout():
    detail = """except subprocess.TimeoutExpired:
    raise AssertionError(f"Timed out after {timeout}s")
AssertionError: Exit 1. Screen assertion failed"""
    assert report.classify(detail) == "assertion failure"
    assert (
        report.classify("AssertionError: Timed out after 90s. Log: output.log")
        == "timeout"
    )
