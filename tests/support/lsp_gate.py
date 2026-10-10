"""Hold an actual LSP executable until the scenario releases its startup gate."""

import os
import sys
import time
from pathlib import Path

gate = Path(sys.argv[1])
deadline = time.monotonic() + 30
while not gate.exists():
    if time.monotonic() >= deadline:
        raise TimeoutError(f"LSP startup gate was not released: {gate}")
    time.sleep(0.02)
os.execvp(sys.argv[2], sys.argv[2:])
