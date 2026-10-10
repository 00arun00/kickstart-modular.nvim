"""Bounded, observable waits for Python integration scenarios.

Runs inside harness.run_process, which owns the timeout and descendant cleanup.
Do not retry exceptions: RPC/configuration failures must retain their traceback.
"""

import json
import os
import time
import warnings
from pathlib import Path

import pynvim


class Editor:
    def __enter__(self):
        with warnings.catch_warnings():
            warnings.filterwarnings(
                "ignore",
                message="'get_child_watcher' is deprecated",
                category=DeprecationWarning,
            )
            self.nvim = pynvim.attach(
                "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE"]
            )
        self.step = "startup"
        self.nvim.ui_attach(120, 35, rgb=True)
        self.lua("""
          _G.test_notifications = {}
          vim.notify = function(msg, level)
            table.insert(_G.test_notifications, {message=tostring(msg), level=level})
          end
          vim.lsp.log.set_level('debug')
        """)
        return self

    def lua(self, code, *args):
        return self.nvim.exec_lua(code, *args)

    def wait(self, label, code, *args, seconds=20):
        self.step = label
        deadline = time.monotonic() + seconds
        last = None
        while time.monotonic() < deadline:
            last = self.lua(code, *args)
            if last:
                return last
            time.sleep(0.02)
        raise AssertionError(
            f"Timed out waiting for {label}; last observation: {last!r}"
        )

    def edit(self, path):
        self.nvim.command("edit " + self.nvim.funcs.fnameescape(str(path)))
        self.buffer = self.nvim.current.buffer.number

    def key(self, key):
        # Execute the actual mapping synchronously; asynchronous plugin work is
        # still awaited separately. This avoids queued nvim_input false positives.
        self.step = f"mapping {key!r}"
        self.lua(
            "vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(..., true, false, true), 'mx', false)",
            key,
        )

    def observe_runs(self):
        # Installed before FileType loads Neotest. Observe its consumer boundary,
        # without replacing the adapter, runner, UI consumers or execution.
        self.lua("""
          local plugin = require('lazy.core.config').plugins.neotest
          local original = plugin.opts
          plugin.opts = function(p, inherited)
          local opts = original(p, inherited)
          opts.consumers.test_observer = function(client)
            _G.test_runs = {serial=0, adapters={}, discovered={}}
            client.listeners.discover_positions = function(adapter, tree)
              local found = _G.test_runs.discovered[adapter] or {}
              _G.test_runs.discovered[adapter] = found
              for _, node in tree:iter_nodes() do found[node:data().id] = true end
            end
            client.listeners.run = function(adapter, root, ids)
              local s = _G.test_runs
              s.serial = s.serial + 1
              local a = s.adapters[adapter] or {results={}, started={}}
              s.adapters[adapter] = a
              for _, id in ipairs(ids) do
                a.started[id] = s.serial
                a.results[id] = nil
              end
            end
            client.listeners.results = function(adapter, results, partial)
              if partial then return end
              local a = _G.test_runs.adapters[adapter]
              if not a then return end
              for id, result in pairs(results) do
                a.results[id] = {generation=a.started[id], status=result.status, short=result.short, errors=result.errors}
              end
            end
            return {}
          end
          return opts
          end
        """)

    def run(self, key, project, expected):
        if key != " ta":
            self.discovered(project, expected)
        baseline = self.lua("return _G.test_runs.serial")
        self.key(key)
        self.results(project, expected, baseline)
        return baseline

    def discovered(self, project, expected):
        self.wait(
            "test positions discovered",
            """
          local adapter, expected = ...
          local found = _G.test_runs.discovered[adapter] or {}
          for id in pairs(expected) do if not found[id] then return false end end
          return true
        """,
            "neotest-python:" + str(project),
            expected,
        )

    def results(self, project, expected, baseline):
        adapter = "neotest-python:" + str(project)
        return self.wait(
            "new completed results for " + adapter,
            """
          local adapter, expected, baseline = ...
          local a = _G.test_runs.adapters[adapter]
          if not a then return false end
          for id, status in pairs(expected) do
            local r = a.results[id]
            if not r or not r.generation or r.generation <= baseline or r.status ~= status then return false end
          end
          return a.results
        """,
            adapter,
            expected,
            baseline,
        )

    def snapshot(self):
        report = {"step": self.step}
        probes = {
            "messages": "return vim.api.nvim_exec2('messages', {output=true}).output",
            "notifications": "return _G.test_notifications",
            "editor": "return {buffer=vim.api.nvim_buf_get_name(0), mode=vim.fn.mode(), cursor=vim.api.nvim_win_get_cursor(0), windows=vim.api.nvim_list_wins()}",
            "clients": "local r={}; for _,c in ipairs(vim.lsp.get_clients({_uninitialized=true})) do r[#r+1]={name=c.name,id=c.id,initialized=c.initialized,root=c.root_dir,settings=c.settings} end; return r",
            "runs": "return _G.test_runs",
            "dap": "local d=package.loaded.dap; local s=d and d.session(); return s and {config=s.config,thread=s.stopped_thread_id,frame=s.current_frame} or {}",
        }
        for name, code in probes.items():
            try:
                report[name] = self.lua(code)
            except (pynvim.api.common.NvimError, EOFError, OSError) as error:
                report[name] = str(error)
        target = Path(os.environ["PYTHON_TOOLS_ARTIFACTS"]) / "editor-state.json"
        target.write_text(json.dumps(report, indent=2, default=str) + "\n")
        return target

    def __exit__(self, kind, error, traceback):
        try:
            target = self.snapshot()
            if error:
                print(f"Failed at {self.step}. Editor state: {target}", flush=True)
        finally:
            try:
                self.nvim.command("qa!")
            except (EOFError, OSError):
                pass
            self.nvim.close()
