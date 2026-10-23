# Shared themes

`Space T t` opens the fuzzy theme picker. Moving through results previews only
Neovim (including its statusline, custom highlights, and open plot/image UI).
Enter remembers the selected variant and publishes matching colours to Ghostty,
tmux, and SessionX/fzf. Cancelling restores the Neovim theme without publishing.

The latest confirmed choice is shared through `stdpath('state')/theme-choice`.
New Neovim instances restore it on startup. Existing instances pull it on
`FocusGained` and before opening the picker. tmux focus events are enabled by the
shared configuration. A picker in progress is not interrupted by a focus event.

## Terminal integration

`lua/custom/theme_sync.lua` exports the palette into
`stdpath('state')/terminal-theme/`:

- `ghostty.conf`: foreground, background, selections, cursor, window appearance,
  and the active theme's 16 ANSI colours. Ghostty includes this file after its
  ordinary settings and reloads via SIGUSR2 (requires Ghostty 1.2 or newer).
- `tmux.conf`: recolours the captured status formats and window/popup/message
  styles. Existing window labels, session names, and zoom behavior are retained.
  It also refreshes SessionX's cached fzf arguments, so inherited dark colours
  from older shells cannot override SessionX's selected palette.
- `fzf.conf`: colour options read on every fzf launch through
  `FZF_DEFAULT_OPTS_FILE`. Shell layout/key options remain in `.zshrc`.
- `templates.json`: original tmux formats, SessionX options, and fzf layout
  options captured when the integration was installed.
- `enabled`: opt-in marker. Without this file the external integration is inert,
  including in isolated tests.

On this machine Ghostty's config, the end of `.tmux.conf`, and `.zshrc` contain
these links. Existing shells need `source ~/.zshrc` once after installation;
new shells inherit the setup automatically. Restart already-running Neovim
instances once to load the new picker code. Theme changes thereafter need no
manual reload. The newest confirmed selection wins globally.

Original external configs were backed up under
`~/.local/state/nvim/terminal-theme/backup-20261023-232303/`.
To disable publication, remove the `enabled` marker. To revert external wiring,
restore the backed-up Ghostty/tmux/zsh configs and reload those applications.
The marker alone stops future publication but leaves the last exported palette
active. If changing the tmux layout later, update `templates.json` so publishing
a theme retains that new layout.

Plot snapshots use the active palette for background, labels, grids, and series.
Open editor plots redraw on theme changes. Previously exported files and browser
pages remain independent snapshots.

## Verification

```sh
.test-venv/bin/python -m pytest tests/python/test_theme_sync.py tests/python/test_theme_selection.py
.test-venv/bin/python -m pytest -m kernel -k plot_renderer
```

The integration tests isolate state/cache and mock external publication; they do
not recolour the user's desktop.
