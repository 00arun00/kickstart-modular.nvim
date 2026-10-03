# Project Home — Atelier

A local Neovim project dashboard layout. Requires Neovim 0.11+ and the sibling `project-home-core` plugin on `runtimepath`. No network requests or file mutations are performed by this renderer.

```lua
-- Add both local plugin directories through your plugin manager, then:
require('project_home_atelier').setup()
require('project_home').open('atelier')
-- Or register and open together:
require('project_home_atelier').open()
```

The core supplies real project files, saved sessions, Git state, pull requests,
worktrees, and activity. Missing or loading data has an explicit empty state.
All colors inherit semantic `ProjectHome*` highlight groups from your active
colorscheme; this package defines no palette.

Use `j`/`k` and Enter to select actions, or displayed shortcut keys. Recent files
and editable Start Exploring shortcuts are separate. The activity scope toggle
switches repository commits and your commits over the same history window.

`render(model, width)` is a pure layout entry point returning lines, semantic
highlights and action locations. Layouts adapt to narrow terminal widths.

Only the home layout differs between packages. Secondary screens use the
shared core's consistent navigation and action handling.
