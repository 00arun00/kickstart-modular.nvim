"""Shared theme exports preserve UI behavior and render safe, usable colours."""

import json
import os
import runpy
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.fast, pytest.mark.python]


def test_terminal_exports_preserve_layout_and_sessionx_options(tmp_path):
    script = tmp_path / "export.lua"
    output = tmp_path / "exports.json"
    script.write_text("""
vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)
local c = {
 base='#fafafa', mantle='#eeeeee', text='#242424', surface0='#dddddd', surface1='#bbbbbb',
 overlay1='#666666', subtext0='#555555', red='#aa1122', green='#228833', yellow='#997700',
 blue='#114499', lavender='#774499', sky='#117788', teal='#227766', peach='#994411',
}
local result = require('custom.theme_sync').render(c, 'light', {}, {
 options = { ['window-status-current-format'] = '#[fg=colour232,bg=#fab387] #I #[fg=colour255,bg=colour237] #W #{?window_zoomed_flag,ZOOM,}' },
 sessionx = { '--style=full', '--header=space and "quotes"' },
 fzf_base = '--layout=reverse',
})
vim.fn.writefile({vim.json.encode(result)}, vim.env.THEME_TEST_OUTPUT)
-- Without an enable marker, ordinary Neovim/test startup must have no external effects.
require('custom.theme_sync').publish()
vim.cmd 'qa!'
""")
    env = dict(
        os.environ,
        THEME_TEST_ROOT=str(ROOT),
        THEME_TEST_OUTPUT=str(output),
        XDG_STATE_HOME=str(tmp_path / "state"),
        XDG_CACHE_HOME=str(tmp_path / "cache"),
    )
    subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-l", str(script)],
        env=env,
        check=True,
        timeout=15,
    )
    files = json.loads(output.read_text())
    assert "background = #fafafa" in files["ghostty"]
    assert "window-theme = light" in files["ghostty"]
    assert sum(line.startswith("palette = ") for line in files["ghostty"]) == 31
    extended = {int(line.split("=", 2)[1]): line.split("=", 2)[2]
                for line in files["ghostty"] if line.startswith("palette = ")
                and int(line.split("=", 2)[1]) >= 16}
    assert set(extended) == {22, 52, 58, 75, 81, 114, 141, 168, 173, 180, 237, 238, 244, 245, 250}
    assert extended[141] == "#774499"
    assert extended[22] == "#e0ece2"
    tmux = "\n".join(files["tmux"])
    assert "#I" in tmux and "#W" in tmux and "#{?window_zoomed_flag,ZOOM,}" in tmux
    assert "colour232" not in tmux and "colour255" not in tmux and "#fab387" not in tmux
    assert "@sessionx-_built-fzf-opts" in tmux and "--style=full" in tmux
    assert "--color=light,bg:#fafafa" in files["fzf"][0]
    assert not (tmp_path / "state/nvim/terminal-theme").exists()


def test_plot_uses_palette_without_changing_data(tmp_path):
    pytest.importorskip("vl_convert")
    renderer = runpy.run_path(str(ROOT / "lua/custom/python/helpers/render-plot.py"))
    data = {
        "style": "scatter",
        "caption": "Example",
        "x_label": "x",
        "records": [{"x": 1, "y": 2, "series": "#181825"}],
    }
    palette = {
        "mantle": "#fafafa",
        "text": "#242424",
        "subtext0": "#555555",
        "blue": "#114499",
    }
    files = renderer["render"](
        {"data": data, "settings": {}, "palette": palette}, tmp_path
    )
    spec = json.loads(Path(files["json"]).read_text())
    html = Path(files["html"]).read_text()
    assert spec["background"] == "#fafafa"
    assert spec["config"]["axis"]["titleColor"] == "#242424"
    assert spec["config"]["range"]["category"][0] == "#114499"
    assert spec["data"]["values"] == data["records"]
    assert "body{background:#fafafa;color:#242424;" in html
    assert "#181825" in html  # a data label must not be recoloured
    assert renderer["theme_colors"]({"text": "</style><script>"})["text"] == "#cdd6f4"
