"""Summarize mini.test/pytest results locally and on the GitHub run overview."""

import argparse
import json
import os
import re
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path


def classify(detail):
    return (
        "timeout"
        if re.search(
            r"timed out after \d+(?:\.\d+)?s|stage timed out: [^{]|timeout \(\d",
            detail,
            re.I,
        )
        else "assertion failure"
    )


def collect(root, suite=None):
    cases, errors, elapsed = [], [], 0.0
    for path in sorted(root.glob("run-*/run.json")):
        try:
            meta = json.loads(path.read_text())
            if suite and meta.get("suite") != suite:
                continue
            for command in meta["commands"]:
                language = command["language"]
                elapsed += command["seconds"]
                results = []
                if language == "lua" and (path.parent / "lua.json").exists():
                    results = json.loads((path.parent / "lua.json").read_text())
                elif language == "python" and (path.parent / "python.xml").exists():
                    for case in ET.parse(path.parent / "python.xml").iter("testcase"):
                        failure = case.find("failure")
                        error = case.find("error")
                        node = failure if failure is not None else error
                        results.append(
                            {
                                "name": case.get("name"),
                                "status": "failed"
                                if node is not None
                                else "skipped"
                                if case.find("skipped") is not None
                                else "passed",
                                "seconds": float(case.get("time", "0")),
                                "detail": ""
                                if node is None
                                else "".join(node.itertext()),
                            }
                        )
                for case in results:
                    case["language"] = language
                    if case["status"] == "failed":
                        case["category"] = classify(case["detail"])
                        stages = re.findall(r"STAGE: ([^\r\n]+)", case["detail"])
                        case["stage"] = stages[-1] if stages else "Not recorded"
                    cases.append(case)
                if not results or (
                    command["exit_code"]
                    and not any(c["status"] == "failed" for c in results)
                ):
                    errors.append(
                        f"{language} runner: exit {command['exit_code']}; no complete case result"
                    )
        except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as error:
            errors.append(
                f"Runner report unreadable: {path.parent.name} ({type(error).__name__})"
            )
    return cases, errors, elapsed


def cell(text):
    return (
        str(text)
        .replace("|", "\\|")
        .replace("\n", " ")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def summary(reports):
    lines = [
        "## Test overview",
        "",
        "| Suite | Result | Passed | Failed | Timeouts¹ | Skipped | Setup | Tests | Details |",
        "|---|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for report in reports:
        cases = report["cases"]
        count = lambda status: sum(c["status"] == status for c in cases)
        link = f"[Logs]({report['url']})" if report.get("url") else ""
        if report.get("artifact"):
            link += f" · [Artifacts]({report['artifact']})"
        lines.append(
            f"| {cell(report['label'])} | {cell(report['result'])} | {count('passed')} | {count('failed')} | {sum(c.get('category') == 'timeout' for c in cases)} | {count('skipped')} | {report.get('setup_duration', '—')} | {report['seconds']:.1f}s | {link} |"
        )
    for report in reports:
        failures = [c for c in report["cases"] if c["status"] == "failed"]
        if not failures and not report["errors"]:
            continue
        lines += ["", f"### {cell(report['label'])}: failures", ""]
        lines.extend(f"- **{cell(error)}**" for error in report["errors"])
        for case in failures:
            lines += [
                f"- **{cell(case['name'])}** — {case['category']}; last stage: {cell(case['stage'])}",
                "",
                "<details><summary>Failure output</summary>",
                "",
                "```text",
                case["detail"][-8000:].replace("```", "'''"),
                "```",
                "",
                "</details>",
                "",
            ]
    lines += [
        "",
        "¹ Timeouts are included in Failed. Counts are framework cases (legacy scripts are one case each), not assertion or line coverage. Terminal/browser-only tests remain manual.",
    ]
    return "\n".join(lines) + "\n"


def job_report(args):
    cases, errors, elapsed = collect(args.root, args.suite)
    steps = json.loads(os.environ.get("CI_STEPS", "{}"))
    setup_ok = steps.get("setup", {}).get("outcome") == "success"
    test_steps = [
        steps.get(language, {}).get("outcome") for language in ("lua", "python")
    ]
    if not setup_ok:
        errors.insert(0, "Setup failure: test environment was not ready")
    elif any(outcome != "success" for outcome in test_steps) and not any(
        c["status"] == "failed" for c in cases
    ):
        errors.append(
            "Runner failure: one or more language steps did not complete successfully"
        )
    if setup_ok:
        for language in ("lua", "python"):
            if not any(c["language"] == language for c in cases):
                errors.append(
                    f"Runner failure: no {language} case results were produced"
                )
    if setup_ok and not cases:
        errors.append("Runner failure: no test reports were produced")
    report = {
        "label": args.label,
        "suite": args.suite,
        "cases": cases,
        "errors": errors,
        "seconds": elapsed,
        "artifact": os.environ.get("CI_ARTIFACT_URL", ""),
        "result": "failed"
        if errors or any(c["status"] == "failed" for c in cases)
        else "passed",
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / f"{args.suite}.json").write_text(json.dumps(report, indent=2))
    return [report]


def aggregate(args):
    reports = [json.loads(p.read_text()) for p in sorted(args.root.glob("*.json"))]
    needs = json.loads(os.environ["CI_NEEDS"])
    names = {
        "format": "Formatting · Lua",
        "fast": "Fast · Lua & Python",
        "editor": "Editor · plugins & navigation",
        "kernel": "Python · kernels & rendering",
    }
    expected = {
        "fast": "Fast · Lua & Python",
        "integration": "Editor · plugins & navigation",
        "kernel": "Python · kernels & rendering",
    }
    for suite, label in expected.items():
        if not any(r.get("suite") == suite for r in reports):
            reports.append(
                {
                    "suite": suite,
                    "label": label,
                    "result": "failed",
                    "cases": [],
                    "seconds": 0,
                    "errors": [
                        "Runner failure: suite report is missing; inspect setup/test logs"
                    ],
                }
            )
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    request = urllib.request.Request(
        f"{os.environ['GITHUB_API_URL']}/repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}/jobs?per_page=100",
        headers={
            "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
            "Accept": "application/vnd.github+json",
        },
    )
    warning = ""
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            jobs = json.load(response)["jobs"]
    except (OSError, ValueError, KeyError) as error:
        jobs = []
        warning = f"Job timing lookup unavailable ({type(error).__name__}); links open the workflow run.\n\n"

    for report in reports:
        job = next((j for j in jobs if j["name"] == report["label"]), None)
        report["url"] = job["html_url"] if job else run_url
        if job:
            setup_seconds = 0
            for step in job["steps"]:
                if step["name"] == "Run Lua tests":
                    break
                if step.get("started_at") and step.get("completed_at"):
                    setup_seconds += (
                        datetime.fromisoformat(step["completed_at"])
                        - datetime.fromisoformat(step["started_at"])
                    ).total_seconds()
            report["setup_duration"] = f"{setup_seconds:.1f}s"
    formatting = next((j for j in jobs if j["name"] == names["format"]), None)
    header = (
        f"**Formatting:** {needs['format']['result']}"
        + (f" · [Logs]({formatting['html_url']})" if formatting else "")
        + "\n\n"
    )
    outcomes = (
        " · ".join(
            f"**{names[name]}:** {need['result']}" for name, need in needs.items()
        )
        + "\n\n"
    )
    return header + outcomes + warning + summary(reports), any(
        n["result"] != "success" for n in needs.values()
    ) or any(r["result"] != "passed" for r in reports)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(".test-results"))
    parser.add_argument("--output", type=Path, default=Path(".ci-reports"))
    parser.add_argument("--suite")
    parser.add_argument("--label")
    parser.add_argument("--aggregate", action="store_true")
    args = parser.parse_args()
    if args.aggregate:
        text, failed = aggregate(args)
    else:
        text, failed = summary(job_report(args)), False
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        with open(target, "a") as out:
            out.write(text)
    else:
        print(text)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
