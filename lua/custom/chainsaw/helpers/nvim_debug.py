"""Local, dependency-free formatters for temporary Chainsaw statements."""
import inspect
import pprint
import sys
import traceback
from pathlib import Path


def object_log(marker, label, value):
    print(f" {marker} object │ {label}")
    for line in pprint.pformat(value, sort_dicts=False).splitlines():
        print(f"    {line}")


def stack_log(marker):
    frames = traceback.extract_stack()[:-1]
    print(f" {marker} stack │ inside {frames[-1].name}()", file=sys.stderr)
    for index, frame in enumerate(frames):
        arrow = "↳ " if index else ""
        name = frame.name if frame.name == "<module>" else frame.name + "()"
        current = "  ← current" if index == len(frames) - 1 else ""
        print(f"    {'  ' * index}{arrow}{Path(frame.filename).name}:{frame.lineno}  {name}{current}", file=sys.stderr)


_MISSING = object()


def fail(marker, condition, observed=_MISSING, *, observed_label=None, message=_MISSING):
    # Called only in the false branch: conditions and diagnostics run at most once.
    frame = inspect.currentframe().f_back
    location = f"{Path(frame.f_code.co_filename).name}:{frame.f_lineno} · {frame.f_code.co_name}()"
    print(f"🧪 {marker} assert │ condition failed", file=sys.stderr)
    print("    │", file=sys.stderr)
    print(f"    │  condition  {condition}", file=sys.stderr)
    if observed is not _MISSING:
        details = pprint.pformat(observed, sort_dicts=False).splitlines()
        label = f"{observed_label} → " if observed_label else ""
        print(f"    │  observed   {label}{details[0]}", file=sys.stderr)
        for line in details[1:]:
            print(f"    │             {line}", file=sys.stderr)
    if message is not _MISSING:
        details = str(message).splitlines() or [""]
        print(f"    │  message    {details[0]}", file=sys.stderr)
        for line in details[1:]:
            print(f"    │             {line}", file=sys.stderr)
    print(f"    │  location   {location}", file=sys.stderr)
    print("    ╰─ FAILED", file=sys.stderr)
    del frame
    if message is not _MISSING:
        raise AssertionError(message)
    raise AssertionError(condition)
