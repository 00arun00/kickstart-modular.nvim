"""One bounded, history-free query to an explicitly identified local kernel."""

import ast
import json
import sys
import time
import uuid
from pathlib import Path

from jupyter_client import BlockingKernelClient


def main():
    registry_path, generation, request_json = sys.argv[1:]
    registry = json.loads(Path(registry_path).read_text())
    if registry["generation"] != generation:
        raise RuntimeError("Kernel restarted; refresh the explorer")
    helper = str(Path(__file__).with_name("inspect-namespace.py"))
    request = json.loads(request_json)
    expression = (
        "__import__('json').dumps(__import__('runpy').run_path("
        f"{helper!r})['inspect_namespace'](get_ipython().user_ns, {request!r}))"
    )
    client = BlockingKernelClient(connection_file=registry["connection"])
    client.session.session = "nvim-inspector-" + uuid.uuid4().hex
    client.load_connection_file()
    client.start_channels(iopub=False, stdin=False, hb=False, control=False)
    try:
        msg_id = client.execute(
            "",
            silent=True,
            store_history=False,
            allow_stdin=False,
            user_expressions={"inspection": expression},
        )
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            reply = client.get_shell_msg(timeout=max(0.01, deadline - time.monotonic()))
            if reply["parent_header"].get("msg_id") != msg_id:
                continue
            result = reply["content"]["user_expressions"]["inspection"]
            if result["status"] != "ok":
                raise RuntimeError(result.get("evalue", "Inspection failed"))
            data = json.loads(ast.literal_eval(result["data"]["text/plain"]))
            if json.loads(Path(registry_path).read_text())["generation"] != generation:
                raise RuntimeError("Kernel restarted; refresh the explorer")
            print(json.dumps({"ok": True, "data": data}))
            return
        raise TimeoutError()
    finally:
        client.stop_channels()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 -- subprocess protocol must always return JSON
        from queue import Empty

        message = (
            "Kernel busy or unavailable; refresh when idle"
            if isinstance(exc, (Empty, TimeoutError))
            else str(exc)
        )
        print(json.dumps({"ok": False, "error": message}))
