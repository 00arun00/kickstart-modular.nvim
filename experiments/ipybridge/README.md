# ipybridge / Molten compatibility experiment

Tested upstream `ok97465/ipybridge.nvim` at
`26a4bcdc968a6b8344f7c909c74f5aea33112afb` against this configuration.
This is an isolated feasibility probe, not an installed explorer or a new mapping.

## Results

- A separate Jupyter client can inspect the exact kernel launched by Molten.
  Variables created and subsequently changed through Molten were visible.
- The standalone `ipybridge_ns.py` helper can generate namespace snapshots without
  loading ipybridge's debugger/bootstrap helpers.
- The upstream Neovim variable explorer rendered the real snapshot successfully.
- pandas preview paging returned the requested five rows starting at row 10.
- The notebook buffer remained unchanged. Silent inspection requests did not
  advance IPython's execution count.
- PyTorch support is incomplete: a tensor with shape `(3, 4)` was reported as
  shape `[3]`, with no dtype or device field. Its preview was plain object text,
  not a tensor table. This follows upstream's generic `len()` fallback.

The probe deliberately verifies this upstream limitation; it is not claiming the
incorrect shape is acceptable for a finished explorer.

## Integration decision

Do not enable the complete plugin as a Molten add-on yet. Its documented public
workflow owns its console/kernel. Its explorer refresh and preview callbacks call
back into that workflow. Reusing the UI would require adapting those callbacks
and providing exact per-buffer Molten kernel selection, lifecycle handling,
timeouts, and stale-response protection.

The normal Python bootstrap also installs control-channel handlers and debug
services. The experiment avoided that bootstrap entirely. No existing project
environment or installed plugin was changed.

For this PyTorch-focused setup, a dedicated inspection adapter is needed even if
the upstream UI is reused. It should provide full shape, dtype, device, and
requires-grad metadata; only request small value samples explicitly. Upstream
calls `repr()` before truncating, and materializes some containers before
sampling, so its small display limits do not guarantee small inspection costs.
GPU transfer and arbitrary object repr should not happen on automatic refresh.

Production kernel discovery must not pick the newest connection file. This test
obtains the exact connection path from its own disposable Molten-executed cell;
that fixture technique is not a production integration.

## Reproduce

Clone the pinned upstream revision into a temporary directory. Create a
disposable project whose `.venv` contains `ipykernel`, `numpy`, `pandas`, and
`torch`. Then, from the config repository:

```sh
~/.local/share/nvim/python/bin/python experiments/ipybridge/probe.py \
  /tmp/nvim-ipybridge-eval /tmp/nvim-ipybridge-project
```

The test writes `explorer-probe.ipynb`, `results.json`, `explorer-ui.txt`, and a
connection-path file inside the disposable project. It starts its own Neovim,
executes the fixture through Molten, inspects that kernel, opens the upstream
explorer UI, and shuts down the Neovim session and client afterward. It does not
exercise the upstream refresh/Enter callbacks or claim those are integrated.
