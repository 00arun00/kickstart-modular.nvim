# Project home

The dashboard is provided by `custom.project_home.volt`, backed by `custom.project_home`
for Git, navigation, sessions, and persisted project state. The only additional
UI dependency is `nvzone/volt`, pinned in the lazy.nvim specification.

| Command | Opens |
| --- | --- |
| `:ProjectHome` / `:ProjectHomeVolt` / `:ProjectHome volt` | Volt Workspace |
| `:ProjectHomeActivity` | Show/hide the activity graph for this checkout |
| `:ProjectHomeSessionSave` | Save the project's file windows and split geometry |

Volt is the startup default. Saved preferences from the retired Workspace,
Navigator, and Atelier versions do not select those removed renderers. Existing
recent files, shortcuts, sessions, and activity preferences are retained.
Set `vim.g.project_home_startup = false` to disable automatic startup.
The dashboard follows the active Neovim theme, including live theme changes.
See [Volt Workspace](project-home-volt.md) for implementation details.

Workspace uses an open, centered layout with two columns, file metadata,
and a heatmap beside its controls. It adapts spacing to the window height; at
80 columns it retains the two-column overview, while smaller windows stack.
The background matches the editor, without an enclosing panel or chrome bars.
A three-row NVIM block wordmark uses the theme accent above the project name
and path. Short or narrow windows retain the compact text header; the wordmark
uses existing header space and adds no scrolling.
Project titles, section headings, filenames, and metadata use theme-derived
color and weight for hierarchy; terminal Neovim uses one fixed font size.
Selection surfaces and activity intensities are derived from the active theme.
When a saved session exists, `u Resume` appears first in the action bar. Recent
Files contains only files. The activity graph expands from 26 to 39 to 52 weeks
as available width increases; its count covers exactly the displayed period.
Switching Repository/Yours preserves that period.

Workspace keyboard navigation:

- `r`, `x`, `p`, and `g` focus Recent Files, Start Exploring, Pull Requests, and
  Git Workspace. Press the same key again for the full list or section action.
- `1–9` opens a numbered entry in the focused section. `j`/`k` moves only within
  that section; Enter opens the selection. Headings and metadata are skipped.
- Tab / Shift-Tab moves between sections; Escape leaves the focused section.
- `?` opens contextual keyboard help. Escape, `q`, or `?` closes the popup and
  restores focus. `m` opens More actions.
- Find, search, browse, new file, and Resume retain their immediate shortcuts.

The footer follows the focused section, and background updates preserve the
selected item. Child pages retain their normal Backspace/Escape navigation.

Starting `nvim` without files or `nvim .` opens Home. Explicit file arguments,
stdin, and requested sessions keep their normal behavior. Opening Home from an
editing window preserves it in its tab. Worktree selection opens another tab
with a tab-local working directory; it does not checkout, reset, stash, or
modify Git state. Modified buffers remain in memory. Quit/save prompts still
apply when leaving Neovim.

## Navigation and views

Outside Workspace's section navigation, use `j`/`k` or arrows to move between actions, including actions in the second
column; Enter opens the selection. On diff/commit text views, normal movement
and horizontal scrolling are available. Backspace or Escape goes back, `H`
returns Home, and `q` closes Home. Direct keys are shown beside actions:
`f` find, `/` search, `e` browse, `n` new file, `r` recents, `s` edit shortcuts,
`g` changes, `c` latest commit, `p` PRs, `w` worktrees, `a` activity scope,
`h` history, `?` help, `m` More, and
`R` refresh. Not every action is shown when its data is absent.

Find/Search use Telescope when installed. Find has a native filename prompt
fallback; search requires ripgrep when Telescope is unavailable. Browse uses
Oil when installed, otherwise the normal Neovim directory editor. New file
opens an unsaved buffer; nested directories are created on the explicit action.
The file itself is written only when you save it.

Recent files are recorded when project files are opened. Home shows five and
provides the full recent-file list. Each checkout has its own history. The
dashboard does not import an existing global recent-file list, so the first launch
may have an empty section.

Start Exploring is a stable shortcut list. On first use, existing README,
project configuration, source, tests, and documentation paths supply up to five
suggestions. These are not continually reordered. Edit shortcuts lets you add,
remove, reorder, restore suggestions, save, or discard changes. Paths must be
inside the project. Missing shortcuts are hidden from Home but remain editable;
explicit restoration of suggestions rebuilds the defaults.

Resume restores saved file windows, cursor positions, and proportional splits in
a new tab. Sessions are saved when opening Home from files, leaving a tab, or
exiting. They do not serialize terminal processes, plugin scratch windows,
unsaved text to disk, or a language/kernel process. Existing unsaved buffers are
reused safely; missing saved files cause a clear refusal without replacing the
current workspace.

## Git and GitHub

Git reads are asynchronous. A first paint can show loading states, and local
features stay usable when remote status fails. Refresh updates all providers.
Opening Home does not automatically fetch; upstream counts reflect local refs.
No-upstream, clean, unavailable, and loading states are distinct.

Changes list staged/unstaged/untracked paths. Tracked diffs show both staged and
unstaged hunks; untracked entries open the file. LazyGit is offered when the
executable exists for staging/committing. The dashboard itself does not stage,
commit, push, merge, or create PRs.

The PR list reads up to 100 open PRs from the current repository. Current-branch
PRs, review requests for the authenticated user, and the user's other PRs sort
first. Home shows three; View all shows the returned list. A PR opens its
overview, checks, changed-file diff, and browser link. Check-log links appear
when GitHub returns a URL. This is GitHub integration, not a generic Git-host API.

Workspace activity covers up to the last 364 days of commits reachable from local refs, including
locally available remote-tracking refs, with duplicate commits counted once.
Repository shows all authors. Yours matches configured `git user.email` against
commit author email (with Git mailmap handling); it is not GitHub's account-wide
contribution graph. Multiple historical email identities are not combined
automatically. The graph uses commit dates. Missing identity is shown explicitly.
History returns the latest 100 commits for the selected author scope; it is not
restricted to the graph's date window.

## Configuration layout

The core lives in `lua/custom/project_home/`, with its Volt renderer in the
`volt/` subdirectory. Both load from this configuration's normal runtimepath.
`lua/custom/plugins/project-home.lua` installs the pinned rendering dependency
and initializes the custom modules:

```lua
{
  'nvzone/volt',
  commit = '620de1321f275ec9d80028c68d1b88b409c0c8b1',
  lazy = false,
  config = function()
    require('custom.project_home.volt').setup()
    require('custom.project_home').setup { default = 'volt', startup = vim.g.project_home_startup ~= false }
  end,
}
```

## Verification

```sh
nvim --headless -u NONE -i NONE -l tests/project_home_providers.lua
nvim --headless -u NONE -i NONE -l tests/project_home_core.lua
nvim --headless -u NONE -i NONE -l tests/project_home_failures.lua
nvim --headless -u NONE -i NONE -l tests/project_home_keyboard.lua
nvim --headless -u NONE -i NONE -l tests/project_home_workspace_ui.lua
nvim --headless -u NONE -i NONE -l tests/project_home_workspace_activity.lua
nvim --headless -u NONE -i NONE -l tests/project_home_volt.lua
python tests/project_home.py /tmp/project-home-review
python tests/project_home_full_config.py
python tests/project_home_visual.py /tmp/project-home-fidelity
```

The Python integration test needs `pynvim` and Pillow (available in this
configuration's editor Python environment). It uses real temporary Git repos,
actual Neovim UI events, and controlled GitHub response fixtures. It does not
create or mutate remote PRs. Screenshots and assertion results go to the supplied
output directory. Live GitHub access depends on your existing CLI authentication.
The full-config smoke test additionally requires this configuration and its
existing plugins to be installed; it exercises Oil and Telescope integration.
It disables Mason's unrelated automatic tool-install check within the test
process so the smoke test does not depend on registry network availability.
