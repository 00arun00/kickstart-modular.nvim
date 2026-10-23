# Terminal typography

`Space T f` or `:FontPicker` opens the fuzzy typography picker:

- JetBrains Mono (baseline): no font overrides; use your existing Ghostty configuration.
- iA Writer Mono: 15pt, 12% extra cell height, 20pt horizontal / 14pt vertical padding.
- Lilex: the same spacious settings with Lilex.
- Maple Mono, Recursive Mono Casual, IBM Plex Mono, and Commit Mono: the same
  spacious settings, available to install from the picker after confirmation.

Recursive Mono Casual uses the `Rec Mono Casual` face from Homebrew's
`font-recursive-code` package, which also installs the other Recursive Code faces.

The preview pane describes each font's intended use, character, ligature support,
italics, and customization, with links to its documentation. **Font supports**
describes capabilities of the selected distribution; **Our preset** describes
what the generated config actually sets. Ligatures, alternate glyphs, and variable
axes are inherited from Ghostty, not explicitly switched on or off by the picker.
Italic faces are available, but the colour theme decides which text uses them.
The specimen always renders in the active terminal font, not the highlighted
candidate. Preview text wraps; use Telescope's preview scrolling for long profiles.

Enter applies and remembers the preset across Ghostty. Browsing or cancelling
does not alter fonts. Typography is independent of the theme picker. Font changes
affect the terminal grid, including Neovim, tmux, and other running terminal apps.
New terminals read the latest confirmed preset. Existing window-specific zoom may
need to be reset using Ghostty's reset font size action.

## Setup

Missing fonts show `[not installed]` in the picker. On macOS with Homebrew,
press Enter to see a confirmation showing the font and install command, with No
selected by default. Confirm Install to run in the background; the list refreshes when it completes.
Press Enter again to apply. Installation never changes the active preset by itself.
Duplicate installs are suppressed, and errors point to a saved installation log.
Closing the picker does not cancel an installation already in progress.
While installing, the preview shows recent Homebrew output and the live log path.
An open or reopened picker refreshes on progress and completion. Installations
have a five-minute timeout and close standard input so prompts cannot wait unseen.

Alternatively, install the fonts separately:

```sh
brew install --cask font-ia-writer-mono font-lilex
```

Run `:FontSetup!` once before using the picker. It detects Ghostty >= 1.2 and its existing config,
backs it up, and appends a managed include. The baseline stays active until you choose
a preset. `:FontSetup` explains the operation without writing anything. Startup
does not install or change terminal settings. Missing fonts are marked in the
picker. On systems without macOS/Homebrew, install them with your system font
manager and reopen the picker.

If multiple configs exist, set `vim.g.font_sync = { ghostty_config = '/path/to/config' }`.
Existing config symlinks are preserved. State, selected preset, and backups live
under `stdpath('state')/terminal-font`; instances sharing this directory share the
selection. Keep the managed include last so later settings do not override it.

`:FontUninstall!` removes the exact managed block and reloads Ghostty, preserving
unrelated edits. It refuses removal if the block or symlink target changed.
Backups and installed font files are retained. `:FontUninstall` explains this
without making changes. The baseline reflects your underlying config, including any
edits you make to it later; the setup-time config is preserved in the backup.
Its label uses the font-family declared in that backup, or Ghostty's bundled
JetBrains Mono when no family is declared. The saved `original` identifier remains
compatible with earlier selections.

Font sources: [iA Writer](https://github.com/iaolo/iA-Fonts) and
[Lilex](https://github.com/mishamyrt/Lilex). Font files are not bundled in this repo.
