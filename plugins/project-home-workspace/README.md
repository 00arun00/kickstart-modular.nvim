# Project Home — Workspace

A local Neovim project dashboard layout. Requires Neovim 0.11+ and the sibling `project-home-core` plugin on `runtimepath`. No network requests or file mutations are performed by this renderer.

```lua
-- Add both local plugin directories through your plugin manager, then:
require('project_home_workspace').setup()
require('project_home').open('workspace')
-- Or register and open together:
require('project_home_workspace').open()
```

The core supplies real project files, saved sessions, Git state, pull requests,
worktrees, and activity. Missing or loading data has an explicit empty state.
All colors inherit semantic `ProjectHome*` highlight groups from your active
colorscheme; this package defines no palette.

Use `r`/`x`/`p`/`g` to focus a section, then its numbered keys to open entries.
Tab moves between sections; `j`/`k` and Enter navigate inside one. `?` opens
contextual keyboard help, and `m` opens More actions. Recent files
and editable Start Exploring shortcuts are separate. The activity scope toggle
switches repository commits and your commits over the same history window.

`render(model, width, height)` is a pure layout entry point returning lines,
semantic highlights and action locations. The centered canvas adapts its spacing
to terminal height and keeps two columns where they fit.

Only the home layout differs between packages. Secondary screens use the
shared core's consistent navigation and action handling.
