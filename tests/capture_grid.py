"""Rasterize an attached Neovim UI's actual redraw grid for visual review."""

from pathlib import Path

_states = {}


def capture(n, path, width=150, height=48):
    from PIL import Image, ImageDraw, ImageFont

    grid, attrs, defaults = _states.setdefault(id(n), ({}, {}, [0xCDD6F4, 0x1E1E2E]))

    def event(name, args):
        if name == "capture_done":
            n.stop_loop()
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
                elif ev[0] == "grid_scroll":
                    _, top, bottom, left, right, rows, cols = data
                    previous = dict(grid)
                    for row in range(top, bottom):
                        for col in range(left, right):
                            source = (row + rows, col + cols)
                            grid[row, col] = (previous.get(source, (" ", 0))
                                              if top <= source[0] < bottom and left <= source[1] < right
                                              else (" ", 0))
                elif ev[0] == "grid_line":
                    _, row, col, cells, *_ = data
                    hl = 0
                    for cell in cells:
                        if len(cell) > 1:
                            hl = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            grid[row, col] = (cell[0], hl)
                            col += 1

    n.command("redraw!")
    n.exec_lua(
        'local c=...; vim.defer_fn(function() vim.rpcnotify(c,"capture_done") end,150)',
        n.channel_id,
    )
    n.run_loop(None, event)
    font = ImageFont.truetype(
        str(Path.home() / "Library/Fonts/FiraCodeNerdFontMono-Regular.ttf"), 16
    )
    bold_font = ImageFont.truetype(
        str(Path.home() / "Library/Fonts/FiraCodeNerdFontMono-Bold.ttf"), 16
    )
    image = Image.new("RGB", (width * 10, height * 22))
    draw = ImageDraw.Draw(image)
    for row in range(height):
        for col in range(width):
            text, hl = grid.get((row, col), (" ", 0))
            attr = attrs.get(hl, {})
            fg, bg = (
                attr.get("foreground", defaults[0]),
                attr.get("background", defaults[1]),
            )
            if attr.get("reverse"):
                fg, bg = bg, fg
            draw.rectangle(
                (col * 10, row * 22, (col + 1) * 10, (row + 1) * 22),
                fill=f"#{max(bg, 0):06x}",
            )
            draw.text((col * 10, row * 22), text, font=bold_font if attr.get('bold') else font,
                      fill=f"#{max(fg, 0):06x}")
    image.save(path)
