# Project Home — Volt Workspace

The Workspace dashboard built with `nvzone/volt`. Open with
`:ProjectHome`, `:ProjectHomeVolt`, or `:ProjectHome volt`.
This is the sole dashboard installed by this configuration.

Requires Neovim 0.11+, the `custom.project_home` core, and `nvzone/volt` on
runtimepath. The renderer lives in `lua/custom/project_home/volt/`; the spec in
`lua/custom/plugins/project-home.lua` installs Volt and initializes the dashboard.
Volt is pinned to the revision used for validation. No other layout plugin is required.

```lua
require('custom.project_home').setup { startup = false }
require('custom.project_home.volt').setup()
require('custom.project_home.volt').open()
```

The home uses Volt grids, separators, styled chunks, and its extmark renderer.
Quiet shortcut labels, aligned sections, semantic PR status colors, and an adaptive 26/39/52-week
heatmap follow the current theme, including live colorscheme changes. A compact
header and stacked columns handle smaller windows. No enclosing floating window.

`r/p/g` focuses a section, numbers open entries, Tab/Shift-Tab changes sections,
and j/k moves within a section. `?` opens contextual help; `m` opens More.
Saved sessions, files, Git, PRs, worktrees, and persistence use the existing core.
Volt renders the home dashboard. Detail pages use the core buffer renderer
for native selection, scrolling, and searching. This configuration defaults to Volt and ignores retired layout preferences.
Existing sessions, recent files, and activity settings are preserved.

The integration intentionally uses `volt.gen_data` and `volt.redraw` directly.
Core owns window lifecycle and keyboard/mouse activation, so Volt's global
mouse-move handler and its default Escape/Tab mappings are not installed.
Real buffer text mirrors visible content for search and byte-accurate targets.
Volt namespaces/state are cleared when switching pages/layouts or wiping Home.

Validation (using Python with pynvim and Pillow):

```sh
nvim --headless -u NONE -i NONE -l tests/project_home_volt.lua
python tests/project_home.py /tmp/home-volt --volt
python tests/project_home_visual.py /tmp/home-volt-visual --volt --full-config
```
