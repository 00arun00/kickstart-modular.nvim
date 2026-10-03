# Project home implementation review

Three separate layout plugins—Workspace, Navigator, and Atelier—share a core
for live data, navigation, persistence, and semantic rendering primitives.
The active Neovim colorscheme supplies all dashboard colors.

## Workspace reference-fidelity correction

User feedback rejected the initial visual implementation as too far from the
approved concept. The scores below measured functional completeness too heavily
and are not evidence of design fidelity.

Workspace has since been rebuilt against the original reference: a centered,
bounded canvas; opposing project and branch header; inset action bar; padded
Resume card; two-line recent-file metadata; two-column shortcuts; separated Git
and PR content; and activity controls beside a complete square-cell heatmap.
Selection highlights individual entries rather than unrelated full-width rows.

The follow-up comparison uses populated actual Neovim redraw captures at
166×50, 120×52, and 80×45, plus sparse content and Catppuccin Mocha/Latte theme
changes. The complete populated overview fits the usable viewport at all three
sizes. Reference-fidelity review now uses concrete structural checks rather
than numerical scores. See `tests/project_home_visual.py` to reproduce it.

The accepted version was checkpointed in `1c895f0`. A subsequent refinement
removes the contrasting outer background and chrome bars, widens the content
limit from 124 to 144 columns, and removes redundant header labels. Designer
review prompted softer section accents beneath the stronger project title.
The same wide, narrow, sparse, and light-theme captures verify the open layout;
font hierarchy uses weight and semantic color within Neovim's fixed-size grid.

## Initial implementation review

The product manager reviewed workflow contracts and reliability. The designer
reviewed actual Neovim captures as a visual critic, and the interaction designer
reviewed behavior and regression tests. Scores below are their review judgments,
not user-study measurements. Order within each score cell is Workspace /
Navigator / Atelier.

| Review | PM | Visual critique | Technical critique |
| --- | --- | --- | --- |
| First acceptance attempt | 8.8 / 8.9 / 8.7 | 7.8 / 7.9 / 7.6 | Changes required |
| First threshold reached | 9.1 / 9.0 / 9.0 | 9.1 / 9.0 / 9.0 | 9.2 / 9.1 / 9.1 |
| Extra refinement 1 | 9.2 / 9.1 / 9.1 | 9.1 / 9.1 / 9.1 | 9.3 / 9.2 / 9.2 |
| Extra refinement 2 | 9.3 / 9.2 / 9.2 | 9.2 / 9.1 / 9.1 | 9.4 / 9.3 / 9.3 |
| Extra refinement 3 — final | 9.4 / 9.3 / 9.3 | 9.2 / 9.2 / 9.1 | 9.5 / 9.4 / 9.4 |

All three required additional rounds after the first ≥9 threshold are complete.

## Improvements driven by review

Before acceptance: removed duplicate file paths and headings, exposed More,
layout selection and activity visibility, replaced an unsupported icon, added
activity date anchors and a legend, and corrected status/error distinctions.
Full-config testing caught Oil rewriting the directory startup argument and
window options leaking into worktree tabs and restored sessions. Both were fixed.

Extra round 1: actionable initial focus, selection preservation during async
updates, restored selection after Back, accurate layout buffer names, and
Git-count wrapping in narrower panels.

Extra round 2: unusual CI failure outcomes no longer appear passed; failures use
the current theme's warning colors. Malformed saved fields degrade safely,
project paths remain scoped, and session metadata is bounded and validated.
Missing files refuse restoration before opening a tab. Ordinary non-Git folders,
missing author identity, provider failure, and empty results remain distinct.

Extra round 3: consolidated identical rendering helpers into the core while
keeping three independently registered layout plugins. Navigator detail pages
focus their main content action. Removed remembered layouts fall back to an
installed layout. Checked the 89/90-column rail transition, Unicode action
positions, narrow layouts, and both dark and light themes.

## Evidence and limits

The tests use real temporary Git repositories and real Neovim UI events.
GitHub responses are controlled fixtures: no remote PRs are created or changed.
The full installed configuration is also exercised with Oil and Telescope,
covering no-argument, directory, and explicit-file startup.

Final results: **82 UI assertions passed**, all **five headless suites passed**,
and the installed-configuration startup smoke test passed all three cases.
StyLua and whitespace checks passed. UI captures cover Catppuccin Mocha,
Habamax, and Morning. Renderer tests cover 40, 60, 80, 89, 90, and 120 columns.

An unrestricted-by-test full-config run encountered an unrelated Mason
`ENOTCONN` callback during automatic tool installation. The reproducible smoke
test disables only that automatic installer check within its test process;
the production Mason configuration is unchanged. Oil and Telescope remain real.

Regression coverage includes multiple PRs and PR-specific navigation, staged
and unstaged diffs, commit views, project recents, shortcut save/cancel,
activity scope and visibility, worktree isolation, unsaved-buffer preservation,
session geometry, malformed data, and unavailable providers. Rendering checks
cover terminal widths, Unicode paths, and colorscheme changes.

See [Project home](project-home.md) for commands, reproducible validation,
provider limits, and installation instructions.
