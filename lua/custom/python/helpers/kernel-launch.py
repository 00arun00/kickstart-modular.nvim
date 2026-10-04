"""Launch ipykernel in the resolved project root, independent of Neovim's cwd."""

import json
import os
import sys
import uuid
from pathlib import Path

from ipykernel.ipkernel import IPythonKernel
from ipykernel.kernelapp import IPKernelApp


class NotebookKernel(IPythonKernel):
    """Keep inspector-only status traffic out of Molten's execution stream."""

    def _publish_status(self, status, channel, parent=None):
        request = parent or self.get_parent(channel)
        session = request.get("header", {}).get("session", "")
        if session.startswith("nvim-inspector-"):
            return
        return super()._publish_status(status, channel, parent)


os.chdir(sys.argv.pop(1))
# A per-launch path supplied by our Neovim session identifies this exact kernel.
# It contains only the connection-file path, never a copy of its credentials.
registry = os.environ.get("NVIM_MOLTEN_REGISTRY")
generation = uuid.uuid4().hex
if registry:
    connection = sys.argv[sys.argv.index("-f") + 1]
    payload = {"connection": str(Path(connection).resolve()), "generation": generation}
    with open(
        registry, "w", opener=lambda path, flags: os.open(path, flags, 0o600)
    ) as stream:
        json.dump(payload, stream)
try:
    IPKernelApp.launch_instance(kernel_class=NotebookKernel)
finally:
    if registry:
        try:
            if json.loads(Path(registry).read_text())["generation"] == generation:
                Path(registry).unlink()
        except (OSError, ValueError, KeyError):
            pass
