# Project home core

Runtime for the Volt Workspace dashboard (`project-home-volt`).

Requires Neovim 0.11+ and Git for repository features. GitHub CLI (`gh`) with an
existing login enables pull requests; no remote configuration or credentials are
changed. GitHub Enterprise works when supported by your configured `gh` client.
Other hosts and unavailable authentication leave local features available.

For installation and behavior, see [the configuration guide](../../docs/project-home.md).

The core never sets a colorscheme. `ProjectHome*` highlight groups inherit the
active theme's `Normal`, `Title`, `Comment`, `Special`, `Visual`, `DiagnosticWarn`,
and `DiagnosticOk`. Workspace surfaces blend those theme colors for subtle
backgrounds and selection. ColorScheme events refresh visible dashboards.
User-defined highlight overrides remain supported.

Data lives under `stdpath('state')/project-home`, keyed by canonical checkout
path. Preferences, recent files, shortcuts, and saved split trees use JSON;
project-local session scripts are never sourced. The Volt renderer uses the same persisted
state as earlier dashboard versions. All Git and GitHub subprocesses use argument arrays and bounded timeouts.

Developer interface:

```lua
require('project_home').register('custom', function(model, width)
  return {
    lines = { 'Find a file' },
    highlights = { { line = 1, start_col = 0, group = 'ProjectHomeAccent' } },
    items = { { line = 1, col = 0, label = 'Find a file', action = 'find', key = 'f' } },
  }
end)
```

Line numbers are one-based; columns are zero-based byte offsets. Renderers should
use display width to fit text, with byte offsets for highlights and selection.
