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


@pytest.mark.parametrize("prepare_ahead", [False, True])
def test_common_inline_scale_and_compact_fraction(tmp_path, pytestconfig, prepare_ahead):
    root = str(pytestconfig.rootpath)
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        n = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    try:
        n.ui_attach(140, 40, rgb=True)
        expressions = [r"\rho", "t", r"\mathbf{v}", r"\rho+\rho", r"\rho\to p_t(x)", r"\frac{\partial\psi}{\partial t}"]
        source = ["Before $" + expr + "$ after." for expr in expressions] + [r"$$\rho$$"]
        n.exec_lua(r"""
          local root,cache,source,prepare_ahead=...
          vim.opt.rtp:prepend(root)
          vim.opt.rtp:append(vim.fn.stdpath('data')..'/lazy/snacks.nvim')
          vim.opt.rtp:append(vim.fn.stdpath('data')..'/site')
          local spec=require('custom.plugins.snacks')[1]
          spec.config(nil,{image=vim.tbl_deep_extend('force',spec.opts.image,{enabled=false,cache=cache})})
          local terminal=Snacks.image.terminal
          terminal.env=function()return {supported=true,placeholders=true} end
          terminal.size=function()return {cell_width=10,cell_height=20,scale=1} end
          raster_uploads=0
          terminal.request=function(request) if request.t=='f' then raster_uploads=raster_uploads+1 end end
          if prepare_ahead then require('custom.markdown_prepare').setup() end
          vim.bo.filetype='markdown'
          vim.api.nvim_buf_set_lines(0,0,-1,false,source)
          vim.bo.modified=false
          raster_tick=vim.api.nvim_buf_get_changedtick(0)
          Snacks.image.doc.find(vim.api.nvim_get_current_buf(),function(items)raster_items=items end)
        """, root, str(tmp_path / "images"), source, prepare_ahead)
        assert n.exec_lua("return vim.wait(5000,function()return raster_items~=nil end)")
        if prepare_ahead:
            # Wait for background cache preparation WITHOUT constructing image
            # objects or placements; that work must not upload to the terminal.
            n.exec_lua("""
              raster_files={}
              for _,item in ipairs(raster_items)do
                raster_files[#raster_files+1]=Snacks.image.convert.convert({src=item.src}).file
              end
            """)
            assert n.exec_lua("""
              return vim.wait(60000,function()
                for _,file in ipairs(raster_files)do
                  if not vim.uv.fs_stat(file) or not vim.uv.fs_stat(file..'.info') then return false end
                end
                return true
              end)
            """)
            assert n.exec_lua("return raster_uploads") == 0
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
        if prepare_ahead:
            # The actual table renderer and normal document controller share the
            # scheduler. Neither creates an independent eager conversion path.
            table_source = [r"Before $z_0$ after."] + [""] * 200 + [
                "| Quantity | Equation |", "| --- | --- |",
                r"| $w$ | $$a+b=c$$ |",
            ]
            uploads_before = n.exec_lua("return raster_uploads")
            n.exec_lua("""
              local source=...
              vim.opt.rtp:append(vim.fn.stdpath('data')..'/lazy/render-markdown.nvim')
              vim.api.nvim_buf_set_lines(0,0,-1,false,source)
              vim.bo.modified=false
              local spec=require('custom.plugins.render-markdown')[1]
              spec.config(nil,vim.tbl_deep_extend('force',spec.opts,{debounce=0}))
              vim.cmd('runtime plugin/render-markdown.lua')
              raster_controller=Snacks.image.inline.new(vim.api.nvim_get_current_buf())
              Snacks.image.doc.find(vim.api.nvim_get_current_buf(),function(items)
                table_files={}
                for _,item in ipairs(items)do
                  table_files[#table_files+1]=Snacks.image.convert.convert({src=item.src}).file
                end
              end)
            """, table_source)
            assert n.exec_lua("""
              return vim.wait(60000,function()
                local document=false
                for _,p in pairs(raster_controller.imgs)do
                  if p.opts.type=='math' and p.opts.range[1]==1 and p._state then document=true end
                end
                if not table_files then return false end
                for _,file in ipairs(table_files)do
                  if not vim.uv.fs_stat(file..'.info')then return false end
                end
                return document
              end)
            """)
            # Only the visible prose equation uploaded; the distant table's
            # images exist on disk but have no image objects/placements yet.
            assert n.exec_lua("return raster_uploads") == uploads_before + 1
            n.current.window.cursor = (len(table_source), 0)
            n.command("normal! zt")
            n.exec_lua("require('render-markdown').render{buf=vim.api.nvim_get_current_buf()}")
            assert n.exec_lua("""
              local row=...
              return vim.wait(60000,function()
                local table=false
                for _,m in ipairs(vim.api.nvim_buf_get_extmarks(0,require('render-markdown.core.ui').ns,0,-1,{details=true}))do
                  if m[2]==row-1 and m[4].conceal=='' then table=true end
                end
                return table
              end)
            """, len(table_source))
            assert list(n.current.buffer) == table_source
            assert not n.current.buffer.options["modified"]
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()
