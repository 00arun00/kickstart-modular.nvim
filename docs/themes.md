# Shared themes

`:ThemePicker` (also mapped to `Space T t`) opens the fuzzy theme picker. Moving
through results previews only Neovim, including the statusline, custom highlights,
and open plot/image UI.
Enter remembers the selected variant. Cancelling restores the original theme, then adopts any newer shared selection.

## Favorites and browsing

`Space T t` / `:ThemePicker` remembers whether you last used **Favorites** or
**All**, including across Neovim restarts. Press `Tab` to change views; the choice
is saved immediately, even if you cancel the theme preview. On the first use,
the picker opens Favorites if you already have favorites, otherwise All.
`:ThemePicker all` and `:ThemePicker favorites` explicitly open and remember that
view. The saved view lives in `stdpath('state')/theme-picker-view`.

| Key (insert or normal mode) | Action |
| --- | --- |
| `Ctrl-N` / `Ctrl-P` | Next / previous result; stop at the bottom / top without wrapping |
| `Tab` | Switch Favorites / All, keeping the search text and background filter |
| `Ctrl-S` | Star/unstar the highlighted variant immediately, keeping the picker open |
| `Ctrl-L` | Cycle background filter: Any → Dark → Light → Any |
| `Enter` | Confirm, save, and apply the highlighted variant |
| `Esc` | Close and restore the original theme; favorite edits remain saved |

`★` marks a favorite. `●` marks the confirmed theme from when the picker opened,
so the marker does not follow temporary previews. The title shows the view,
background filter, and matching count out of the entire collection. Empty views
explain how to return to browsing. Applying or starring an empty result does nothing.

Favorites refer to individual variants, not entire theme families. Starring keeps
the highlighted row in place; unstarring in Favorites selects the nearest remaining
result. Lists sort alphabetically by theme label without a query and use
standard fuzzy relevance while searching, with alphabetical order breaking equal
scores. Only the displayed theme name is searched; the background suffix,
internal ID, favorite star, and current-theme marker do not affect matching.
Use `Ctrl-L` to filter backgrounds. Both view changes and favorite edits retain the
query and preserve the highlighted variant when it is still available.
Typing or editing a search selects and previews the first, highest-ranked match.
The opening theme is selected when the query is empty.

Favorites are shared between Neovim instances through individual marker files in
`stdpath('state')/theme-favorites/`. Each added marker is written atomically, and
editing one variant cannot overwrite edits to other variants from another instance.
Open pickers watch this directory and refresh on changes. Reopening or toggling a
view also reads the current favorites. Same-variant edits use the last completed
action. Favorites never publish terminal colors or change the confirmed theme;
only confirming a picker selection does that.

The latest confirmed choice is stored in `stdpath('state')/theme-choice`. New
Neovim instances restore it on startup. Existing instances watch the state
directory for confirmed changes and apply them locally, then redraw even when
unfocused. This uses filesystem events, not periodic polling. Focus and opening
the picker remain fallback checks. A picker in progress is not interrupted by
external changes; cancellation adopts the latest shared choice, while confirmation
saves your selected theme. Instances using different state directories have
independent choices. Receiving instances never republish terminal colors.

## Installed themes

The picker includes 60 choices across 19 families. Each light/dark variant is an
explicit entry, so previewing, cancelling, saving, and restoring retain the exact
variant and background.

| Family | Variants |
| --- | --- |
| Catppuccin | Latte (light), Frappé, Macchiato, Mocha |
| Rosé Pine | Default, Moon, Dawn (light) |
| One Dark Pro | Dark, Light, Vivid, Dark Dark, Vaporwave |
| Ayu | Dark, Mirage, Light |
| Tokyo Night | Night, Storm, Moon, Day (light) |
| Vesper | Dark |
| Kansō | Zen, Ink, Mist, Pearl (light) |
| Vague | Dark |
| Flexoki | Dark, Light |
| Kanagawa Paper | Ink, Canvas (light) |
| Mélange | Dark, Light |
| Oxocarbon | Dark, Light |
| Evergarden | Winter, Fall, Spring, Summer (light) |
| Mellow | Dark, Light |
| OldWorld | Default, Cooler, OLED |
| Mellifluous | Original Dark, Original Light, Alduin, Mountain, Tender, Kanagawa Dragon |
| Poimandres | Main (dark) |
| Nightfox | Nightfox, Dayfox (light), Dawnfox (light), Duskfox, Nordfox, Terafox, Carbonfox |
| Flow | Dark, Light, Mono Dark, Mono Light |

All variants ship with their family's plugin; no separate variant installation
is needed. The new families have adapters in `lua/custom/theme_palettes.lua`
that read their native palettes on each colorscheme change. Custom statusline
accents, Markdown task progress, math, folds, navigation, plots, and enabled
terminal exports therefore use the selected family's colors. The dashboard
also derives its colors from the active theme's highlight groups.

Mélange and Oxocarbon use one native colorscheme name for both backgrounds; the
picker gives them separate stable IDs. Evergarden's selected season is configured
before loading its colorscheme, keeping its native palette API in sync too.
Kansō's reduced-color and saturation settings remain ordinary plugin options;
the four named variants appear in the picker.

Mellow and OldWorld configure their palette variants before loading. OldWorld's
cached palette-derived highlights are rebuilt when switching variants. Mellifluous
includes all five colorsets; only its original colorset provides a light mode.
Poimandres currently implements only its main palette in the Neovim port.
Flow's standard and Mono palettes each have explicit dark and light entries;
contrast and fluorescent accent settings remain ordinary plugin options.

Kanagawa Paper is installed from `thesimonho/kanagawa-paper` on its `neovim`
distribution branch. Its `main` branch contains development source rather than
the loadable Neovim runtime. Plugin revisions are recorded in `lazy-lock.json`.

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
