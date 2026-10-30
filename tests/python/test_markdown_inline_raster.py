"""Optional real TeX/raster check, beyond the deterministic placement tests."""

import shutil
import warnings
from pathlib import Path

import pynvim
import pytest
from PIL import Image

pytestmark = [
    pytest.mark.integration,
    pytest.mark.python,
    pytest.mark.skipif(
        any(shutil.which(tool) is None for tool in ("tectonic", "magick", "gs")),
        reason="real inline-math raster check needs Tectonic, ImageMagick and Ghostscript",
    ),
]


def test_common_inline_scale_and_compact_fraction(tmp_path, pytestconfig):
    root = str(pytestconfig.rootpath)
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        n = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    try:
        n.ui_attach(140, 40, rgb=True)
        expressions = [r"\rho", "t", r"\mathbf{v}", r"\rho+\rho", r"\rho\to p_t(x)", r"\frac{\partial\psi}{\partial t}"]
        source = ["Before $" + expr + "$ after." for expr in expressions] + [r"$$\rho$$"]
        n.exec_lua(r"""
          local root,cache,source=...
          vim.opt.rtp:prepend(root)
          vim.opt.rtp:append(vim.fn.stdpath('data')..'/lazy/snacks.nvim')
          vim.opt.rtp:append(vim.fn.stdpath('data')..'/site')
          local spec=require('custom.plugins.snacks')[1]
          spec.config(nil,{image=vim.tbl_deep_extend('force',spec.opts.image,{enabled=false,cache=cache})})
          local terminal=Snacks.image.terminal
          terminal.env=function()return {supported=true,placeholders=true} end
          terminal.size=function()return {cell_width=10,cell_height=20,scale=1} end
          terminal.request=function()end
          vim.bo.filetype='markdown'
          vim.api.nvim_buf_set_lines(0,0,-1,false,source)
          vim.bo.modified=false
          raster_tick=vim.api.nvim_buf_get_changedtick(0)
          Snacks.image.doc.find(vim.api.nvim_get_current_buf(),function(items)raster_items=items end)
        """, root, str(tmp_path / "images"), source)
        assert n.exec_lua("return vim.wait(5000,function()return raster_items~=nil end)")
        n.exec_lua("""
          raster_images={}
          for i,item in ipairs(raster_items)do raster_images[i]=Snacks.image.image.new(item.src) end
        """)
        assert n.exec_lua("""
          return vim.wait(60000,function()
            for _,img in ipairs(raster_images)do if not img:ready() and not img:failed() then return false end end
            return true
          end)
        """)
        results = n.exec_lua("""
          local result={}
          for i,item in ipairs(raster_items)do
            local img=raster_images[i]
            assert(not img:failed(),img.src)
            local p=Snacks.image.placement.new(vim.api.nvim_get_current_buf(),item.src,{
              type='math',inline=true,conceal=true,pos=item.pos,range=item.range,
              on_update_pre=require('custom.markdown_math').prepare,
            })
            Snacks.image.placement.update(p)
            local marks=vim.api.nvim_buf_get_extmarks(p.buf,Snacks.image.placement.ns,0,-1,{details=true})
            local inline=false
            for _,m in ipairs(marks)do
              if m[2]==item.range[1]-1 and m[4].virt_text_pos=='inline' and not m[4].virt_lines then inline=true end
            end
            result[item.range[1]]={
              file=img.file,src=item.src,
              loc={width=p._state.loc.width,height=p._state.loc.height},inline=inline,
            }
          end
          return result
        """)
        inline = results[: len(expressions)]
        images = [Image.open(Path(item["file"])).convert("RGBA") for item in inline]
        assert len({image.height for image in images}) == 1, "crops no longer share a baseline/canvas"
        assert all(item["loc"]["height"] == 1 and item["inline"] for item in inline)
        assert inline[4]["loc"]["width"] > inline[0]["loc"]["width"], "longer expressions should gain width"
        assert all(image.getpixel((0, 0))[3] == 0 for image in images), "padding must stay transparent"
        rho = images[0].getchannel("A")
        repeated = images[3].getchannel("A").crop((0, 0, images[0].width, images[0].height))
        assert rho.getbbox() == repeated.getbbox(), "rho changes size/baseline inside a longer expression"
        assert results[-1]["src"].endswith(".math.tex"), "display conversion changed"
        assert list(n.current.buffer) == source
        assert n.exec_lua("return vim.api.nvim_buf_get_changedtick(0)==raster_tick and not vim.bo.modified")
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()
