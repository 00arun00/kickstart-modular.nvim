# Adding and changing tests

- Prefer native pytest tests in `tests/python/test_*.py` for new Python tests.
  Put suite and language markers directly on the test or module. These tests do
  not need entries in `tests/cases.json`.
- Register standalone scripts in the root of `tests/` (`.lua`, `.py`, `.cjs`) in
  `tests/cases.json`, with language, suite, timeout, and any required arguments or
  setup. Mark genuinely manual tools under `manual` with a reason. The inventory
  check rejects unclassified scripts so newly added tests cannot silently miss CI.
- Use `fast` for tests that require no installed Neovim plugins or external
  services, `integration` for installed editor/plugin workflows, and `kernel`
  for live Jupyter/debugger/scientific-rendering workflows. In particular, the
  Trouble/Telescope round-trip test belongs to `integration`.
- Exercise new standalone tests through the harness as well as directly:
  `make test-lua SUITE=integration FILE=trouble` is an example. Run
  `make test-python SUITE=fast FILE=every_legacy_script_is_classified` after adding,
  renaming, or deleting standalone scripts. Use `make test-list` to inspect suite
  collection. Direct script success alone does not verify CI registration.
- For asynchronous regressions, control event ordering and wait for observable
  state transitions. A delay or longer timeout is not a race fix. Keep an ordinary
  workflow test alongside a forced-order regression where useful.
- Test user-visible contracts (selection, focus, locations, metadata, isolation).
  Avoid assertions that merely repeat configuration values without behavior.
- Preserve uncommitted user changes and installed dependency revisions. Report
  local dependency drift; CI provisions the committed lockfile.

See `docs/testing.md` for setup, artifacts, and the full workflow.
