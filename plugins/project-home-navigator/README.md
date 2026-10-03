# Project Home — Navigator

A local Neovim project dashboard layout. Requires Neovim 0.11+ and the sibling `project-home-core` plugin on `runtimepath`. No network requests or file mutations are performed by this renderer.

```lua
-- Add both local plugin directories through your plugin manager, then:
require('project_home_navigator').setup()
require('project_home').open('navigator')
-- Or register and open together:
require('project_home_navigator').open()
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

Navigator keeps its navigation rail on both home and secondary screens when
the terminal is at least 90 columns wide. Narrow windows use the core's
Back/Home navigation. File and diff contents remain complete; long lines can
be scrolled horizontally.
