# Shared themes

`:ThemePicker` (also mapped to `Space T t`) opens the fuzzy theme picker. Moving
through results previews only Neovim, including the statusline, custom highlights,
and open plot/image UI.
Enter remembers the selected variant. Cancelling restores the original theme, then adopts any newer shared selection.

The latest confirmed choice is stored in `stdpath('state')/theme-choice`. New
Neovim instances restore it on startup. Existing instances watch the state
directory for confirmed changes and apply them locally, then redraw even when
unfocused. This uses filesystem events, not periodic polling. Focus and opening
the picker remain fallback checks. A picker in progress is not interrupted by
external changes; cancellation adopts the latest shared choice, while confirmation
saves your selected theme. Instances using different state directories have
independent choices. Receiving instances never republish terminal colors.

## Opt-in terminal setup

The Neovim picker works without terminal integration. No external config is
changed until setup is explicitly installed.

| Command | Behavior |
| --- | --- |
| `:ThemeSyncSetup` | Read-only detection and preview of exact config additions |
| `:ThemeSyncSetup!` | Back up configs, install managed blocks, and apply the current palette |
| `:ThemeSyncStatus` | Show enabled integrations, config paths, and backup location |
| `:ThemeSyncUninstall` | Preview removal and check for conflicts |
| `:ThemeSyncUninstall!` | Remove managed wiring, restore captured tmux settings, and reload Ghostty |

After installation, confirmed picker choices update the enabled terminal apps.
Previews remain inside Neovim. Open a new shell or source its config once to
activate the fzf wrapper. The wrapper reads the latest palette each time `fzf`
is invoked; it preserves existing option variables and explicit command-line
arguments. It replaces any existing shell function named `fzf`. Programs that
bypass shell functions with `command fzf` do not use that wrapper; SessionX has
its own integration.

Detection supports:

- **macOS and Linux.** Windows skips external integration; Neovim themes still work.
- **Ghostty >= 1.2:** executable on `PATH`, or the standard system/user macOS app
  bundle. Setup considers the XDG config and native macOS config locations.
  Multiple existing configs require an explicit path. Ghostty reloads via
  `pkill -USR2 -x ghostty`; if `pkill` is unavailable, the file is updated but
  Ghostty must be reloaded manually. Signals are not sent to unsupported versions.
- **tmux >= 3.2:** a running server is required to capture its actual status
  layout. Setup considers `~/.tmux.conf` and the XDG tmux config. The captured
  server socket is remembered for publication and uninstall. Separate tmux
  servers are not enumerated or modified automatically.
- **SessionX:** enabled only when the expected cached fzf option declaration is
  detected on that tmux server. Otherwise tmux still works without SessionX.
- **fzf with bash or zsh:** setup adds a wrapper to `.bashrc` or
  `${ZDOTDIR:-$HOME}/.zshrc`. Other shells are skipped. Bash login sessions must
  source `.bashrc` or use a custom shell config path.

Missing apps and ambiguous paths are reported and skipped. Install dependencies,
start tmux, or specify paths, then preview again. Re-running setup after a
successful install is a no-op; uninstall first to change the integration set.

To override detection, set this before running setup (only include needed keys):

```lua
vim.g.theme_sync = {
  ghostty = true, -- false disables this integration
  tmux = true,
  fzf = true,
  ghostty_config = '/path/to/ghostty/config',
  tmux_config = '/path/to/tmux.conf',
  shell = 'zsh', -- or bash
  shell_config = '/path/to/.zshrc',
}
```

Paths are expanded and symlinked dotfiles retain their links. Ghostty include
files and tmux source files are appended after existing configuration so the
selected palette wins. The installer preserves status labels, format conditions,
and commands. Embedded tmux colour styles are normalized to semantic palette
roles rather than assuming the previous theme was Catppuccin.

## Backups and uninstall

Setup stores complete original config files in a private, timestamped directory
under `stdpath('state')/terminal-theme/backup-*`. Its manifest records actual
paths, managed blocks, and original tmux settings. A failed install rolls back
config edits. Backups are retained after uninstall.

Uninstall removes only its own blocks and preserves later edits elsewhere in
the files. If a managed block or a config symlink was changed, uninstall stops
before modifying anything and reports the affected file and backup. Restore the
managed block from that installation's manifest (or reconcile the file manually)
and retry. It does not overwrite your intervening edits with a whole-file backup.
Files created by setup are removed only if no user content remains.

Uninstall leaves the Neovim picker and saved selection available. Restart shells
(or `unset -f fzf`) to remove their already-loaded wrapper. Ghostty reads the
remaining configuration; tmux restores settings captured at installation, not
factory defaults. If its server is unavailable, restart/reload tmux normally.

The earlier manual installation is supported: setup adopts its exact generated
file links and replaces them with managed blocks. Earlier backups are retained.
Uninstall then removes those links too; it does not reintroduce the manual setup.

## Generated state

`lua/custom/theme_sync.lua` exports into `stdpath('state')/terminal-theme/`:

- `ghostty.conf`: background, foreground, selections, cursor, window appearance,
  the active theme's 16 ANSI colours, and the extended slots documented below.
- `tmux.conf`: status/window/popup styles, focus events, and compatible SessionX
  arguments. Explicit SessionX colours override old inherited fzf colours.
- `fzf.conf`: colour arguments consumed by the managed shell wrapper.
- `templates.json`: captured tmux formats and fzf options.
- `installation.json`: detected targets and uninstall/backup metadata.
- `enabled`: opt-in marker; without it publication is inert.


### Extended terminal palette

Ghostty also receives 15 stable palette slots, populated from the active Neovim
highlight groups. Missing highlight colors use the theme's normalized palette.

| Slots | Roles |
| --- | --- |
| 22, 52, 58 | Added-line background, deleted-line background, search background |
| 75, 81, 114 | Function, operator, string |
| 141, 168, 173, 180 | Keyword, tag, constant, type |
| 237, 238 | Cursor-line background, selection background |
| 244, 245, 250 | Border, muted text, punctuation |

Search backgrounds are blended toward the normal background to retain readable
syntax text. These slots are shared by every application in the terminal and
override their usual extended-palette colors. Applications can map their own
roles to these slots; no application-specific discovery manifest is generated.
Changing a theme updates the colors while slot numbers remain stable.

Only opted-in targets are exported and reloaded. Removing `enabled` disables
future publication but leaves the last palette active and config links intact;
use the uninstall command for a complete removal. Generated files are retained
for recovery and are not hand-edited sources of truth.

Open editor plots redraw with the active palette. Previously exported files and
browser pages remain independent snapshots.

## Verification

```sh
.test-venv/bin/python -m pytest tests/python/test_theme_setup.py tests/python/test_theme_sync.py tests/python/test_theme_selection.py
.test-venv/bin/python -m pytest -m kernel -k plot_renderer
```

Installer tests use disposable homes, fake app detection, and isolated state.
They exercise backups, rollback, symlinks, migration, conflict refusal, and
preservation of later edits. Integration tests locate plugins using Neovim's
actual data directory; set `NVIM_TEST_PLUGIN_ROOT` for a custom Lazy plugin root.
They mock external publication and do not recolour the user's desktop.
