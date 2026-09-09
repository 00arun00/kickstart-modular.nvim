"""Capture actual Neovim redraw grids as PNGs for repeatable visual review."""

import os
import sys
import time
from pathlib import Path
import nbformat
import pynvim
from PIL import Image, ImageDraw, ImageFont

out = Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
width = int(sys.argv[2]) if len(sys.argv) > 2 else 140
path = (
    Path(os.environ.get("NVIM_REVIEW_PROJECT", "/tmp/nvim pde project"))
    / "ui-review.ipynb"
)
path.parent.mkdir(parents=True, exist_ok=True)
nb = nbformat.v4.new_notebook(
    cells=[
        nbformat.v4.new_markdown_cell(
            "# Exploring word vectors\n\nCompare **semantic relationships** in a two-dimensional embedding space."
        ),
        nbformat.v4.new_markdown_cell(
            "Find two groups of words that cluster together. Explain the relationship within each group."
        ),
        nbformat.v4.new_markdown_cell(
            '### Your observations\n\n<font color="red">Write your answer here.</font>'
        ),
        nbformat.v4.new_code_cell(
            'import numpy as np\n\nwords = ["king", "queen", "man", "woman"]\nvectors = np.array([[1, 2], [2, 3], [3, 1], [4, 2]])\nprint(f"Loaded {len(words)} word vectors")'
        ),
        nbformat.v4.new_markdown_cell(
            "## Prediction-based word vectors\n\nThe next section compares GloVe embeddings with the co-occurrence model. Longer prose should wrap naturally without running outside an arbitrary box.\n\n- Inspect the nearest neighbors\n- Compare the resulting clusters"
        ),
        nbformat.v4.new_code_cell(
            'def nearest_neighbors(word, model):\n    return model.most_similar(word, topn=5)\n\nnearest_neighbors("king", model)'
        ),
        nbformat.v4.new_raw_cell("Unformatted reference notes stay editable."),
    ]
)
for i, c in enumerate(nb.cells):
    c.id = f"a-long-notebook-cell-identifier-0123456789-{i}"
nbformat.write(nb, path)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
)
grid = {}
attrs = {}
defaults = [0xCDD6F4, 0x1E1E2E]
cursor = None
try:
    n.ui_attach(width, 48, rgb=True, ext_linegrid=True)
    time.sleep(0.4)
    source = n.current.buffer[:]
    for i, line in enumerate(source):
        if line.startswith("# %%"):
            source[i] = (
                line
                + ' id="long-marker-metadata-0123456789-abcdefghijklmnopqrstuvwxyz"'
            )
    n.current.buffer[:] = source
    target = next(i for i, s in enumerate(source, 1) if s.startswith("words ="))
    if len(sys.argv) > 3:
        target = next(i for i, s in enumerate(source, 1) if s.startswith(sys.argv[3]))
    n.current.window.cursor = (target, 0)
    n.exec_lua(
        "require('custom.python.markdown').update(); require('custom.python.cells_ui').update(nil,true)"
    )
    n.funcs.winrestview(
        {"topline": next(i for i, s in enumerate(source, 1) if s.startswith("# %%"))}
    )
    n.current.window.cursor = (target, 0)
    n.exec_lua(
        "local ns=vim.api.nvim_create_namespace('review-output'); vim.api.nvim_buf_set_extmark(0,ns,...,0,{virt_lines={{{'Out[1]: ✓ Done  0.1s','Comment'}},{{'Loaded 4 word vectors','Normal'}}}})",
        next(i for i, s in enumerate(source) if s.startswith("print(")),
    )
    if len(sys.argv) > 4 and sys.argv[4] == "concealed":
        n.exec_lua(
            "local ns=vim.api.nvim_create_namespace('review-concealed'); local row=...; vim.api.nvim_buf_set_extmark(0,ns,row,0,{end_row=row+1,conceal_lines='' }); require('custom.python.cells_ui').update(nil,true)",
            next(i for i, s in enumerate(source) if s.startswith("# # Exploring")),
        )
    n.command("redraw!")
    n.exec_lua(
        'local chan=...; vim.defer_fn(function() vim.rpcnotify(chan,"capture_done") end,150)',
        n.channel_id,
    )

    def event(name, args):
        global cursor
        if name == "capture_done":
            n.stop_loop()
            return
        if name != "redraw":
            return
        for ev in args:
            for data in ev[1:]:
                if ev[0] == "hl_attr_define":
                    attrs[data[0]] = data[1]
                elif ev[0] == "default_colors_set":
                    defaults[:] = data[:2]
                elif ev[0] == "grid_clear":
                    grid.clear()
                elif ev[0] == "grid_cursor_goto":
                    cursor = (data[2], data[1])
                elif ev[0] == "grid_line":
                    gid, row, col, cells, *_ = data
                    hl = 0
                    for cell in cells:
                        if len(cell) > 1:
                            hl = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            grid[row, col] = (cell[0], hl)
                            col += 1

    n.run_loop(None, event)
    font = ImageFont.truetype(
        os.environ.get(
            "NVIM_REVIEW_FONT",
            str(Path.home() / "Library/Fonts/FiraCodeNerdFontMono-Regular.ttf"),
        ),
        16,
    )
    cw, ch = 10, 22
    im = Image.new("RGB", (width * cw, 48 * ch))
    d = ImageDraw.Draw(im)

    def color(v):
        return "#%06x" % max(0, v)

    for r in range(48):
        for c in range(width):
            txt, hl = grid.get((r, c), (" ", 0))
            a = attrs.get(hl, {})
            fg, bg = a.get("foreground", defaults[0]), a.get("background", defaults[1])
            if a.get("reverse"):
                fg, bg = bg, fg
            d.rectangle((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch), fill=color(bg))
            d.text((c * cw, r * ch), txt, font=font, fill=color(fg))
    im.save(out)
    print(out)
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
