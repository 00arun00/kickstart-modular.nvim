"""Distance priority against real editor events, with forced conversion ordering."""

import warnings

import pynvim
import pytest

pytestmark = [pytest.mark.fast, pytest.mark.python]


@pytest.fixture
def scheduler(pytestconfig):
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        n = pynvim.attach("child", argv=["nvim", "--embed", "-n", "-u", "NONE", "-i", "NONE"])
    try:
        n.ui_attach(100, 20, rgb=True)
        n.exec_lua("assert(loadfile(... .. '/tests/support/markdown_prepare.lua'))(...)", str(pytestconfig.rootpath))
        yield n
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()


def wait(n, condition):
    assert n.exec_lua("return vim.wait(5000,function()return " + condition + " end)"), condition


def buffer(n, matches, lines=1000):
    return n.exec_lua("return prepare_fixture.buffer(...)", matches, lines)


def jump(n, line):
    n.current.window.cursor = (line, 0)
    n.command("normal! zt")


def starts(n):
    return n.exec_lua("return prepare_fixture.starts")


def finish(n):
    n.exec_lua("prepare_fixture.finish()")


def test_reprioritize_pending_work_after_jump_without_conversion_backlog(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "near"], [400, "middle"], [850, "far"]])
    jump(n, 10)
    n.exec_lua("prepare_fixture.query(...,true)", buf)
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["near"]
    # A running conversion finishes; pending work is selected using the NEW view.
    jump(n, 850)
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["near", "far"]
    finish(n)
    wait(n, "#prepare_fixture.starts==3")
    assert starts(n) == ["near", "far", "middle"]
    finish(n)
    assert n.exec_lua("return prepare_fixture.peak") == 1


def test_repeated_equations_share_preparation_and_background_does_not_upload(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "repeated"], [400, "middle"], [850, "repeated"]])
    jump(n, 850)
    # Full-buffer table discovery and ordinary math feed the same source queue.
    n.exec_lua("prepare_fixture.query(...,false)", buf)
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["repeated"]
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["repeated", "middle"]
    finish(n)
    assert n.exec_lua("return vim.tbl_count(prepare_fixture.images)") == 0
    # Later viewport placement takes the already prepared cache path immediately.
    n.exec_lua("Snacks.image.image.new('repeated')")
    assert n.exec_lua("return prepare_fixture.delivered.repeated")
    assert starts(n) == ["repeated", "middle"]


def test_visible_request_during_background_conversion_reuses_completed_files(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "shared"]])
    n.exec_lua("prepare_fixture.query(...,false)", buf)
    wait(n, "#prepare_fixture.starts==1")
    n.exec_lua("Snacks.image.image.new('shared')")
    assert not n.exec_lua("return prepare_fixture.delivered.shared or false")
    finish(n)
    assert n.exec_lua("return prepare_fixture.delivered.shared")
    assert starts(n) == ["shared"]


def test_edits_and_closed_buffers_drop_unstarted_work(scheduler):
    n = scheduler
    first = buffer(n, [[10, "running"], [400, "obsolete"]])
    n.exec_lua("prepare_fixture.query(...,false)", first)
    wait(n, "#prepare_fixture.starts==1")
    n.exec_lua("""
      local buf=...
      vim.api.nvim_buf_set_lines(buf,0,1,false,{'edited'})
      prepare_fixture.matches[buf]={{src='replacement',type='math',id='new',range={850,0,850,3}}}
      prepare_fixture.query(buf,false)
    """, first)
    jump(n, 850)
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["running", "replacement"]
    other = buffer(n, [[10, "other"]])
    n.exec_lua("prepare_fixture.query(...,false)", other)
    n.api.buf_delete(first, {"force": True})
    finish(n)
    wait(n, "#prepare_fixture.starts==3")
    assert starts(n) == ["running", "replacement", "other"]


def test_discovery_is_chunked_and_starts_near_the_viewport(scheduler):
    n = scheduler
    buffer(n, [[10, "top"], [850, "visible"]])
    jump(n, 850)
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["visible"]
    scan = n.exec_lua("return prepare_fixture.scans[1]")
    assert scan[0] <= 850 <= scan[1]
    assert scan[1] - scan[0] < 128
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["visible", "top"]


def test_theme_change_rejects_a_delayed_old_parse(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "old-color"]])
    n.exec_lua("prepare_fixture.hold=true;prepare_fixture.query(...,false)", buf)
    wait(n, "#prepare_fixture.held>0")
    n.exec_lua("""
      prepare_fixture.hold=false
      prepare_fixture.matches[...]={{src='new-color',type='math',id='new',range={10,0,10,3}}}
      vim.api.nvim_exec_autocmds('ColorScheme',{})
      prepare_fixture.query(...,false)
    """, buf)
    # Discovery itself is serialized now. Complete the old parse so the new
    # request can run; its result must be rejected before any conversion starts.
    n.exec_lua("for _,callback in ipairs(prepare_fixture.held)do callback()end")
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["new-color"]


def test_typing_defers_new_preparation_until_normal_mode(scheduler):
    n = scheduler
    n.input("i")
    wait(n, "vim.fn.mode()=='i'")
    # The parser result can arrive during Insert; conversion waits for Escape.
    n.exec_lua("""
      local buf=vim.api.nvim_get_current_buf()
      vim.bo.filetype='markdown'
      prepare_fixture.matches[buf]={{src='typing',type='math',id='1',range={1,0,1,0}}}
      prepare_fixture.query(buf,false)
      return buf
    """)
    assert starts(n) == []
    n.input("<Esc>")
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["typing"]


def test_priority_uses_nearest_visible_split_and_preserves_source(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "top"], [400, "middle"], [850, "bottom"]])
    before = list(n.current.buffer)
    tick = n.exec_lua("return vim.api.nvim_buf_get_changedtick(0)")
    jump(n, 10)
    n.command("vsplit")
    jump(n, 850)
    n.exec_lua("prepare_fixture.query(...,false)", buf)
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n)[0] in ("top", "bottom")
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert set(starts(n)) == {"top", "bottom"}
    assert list(n.current.buffer) == before
    assert n.exec_lua("return vim.api.nvim_buf_get_changedtick(0)") == tick
    assert not n.current.buffer.options["modified"]


def test_hidden_buffers_wait_and_pending_image_cache_entries_can_resume(scheduler):
    n = scheduler
    first = buffer(n, [[10, "running"], [850, "parked"]])
    n.exec_lua("prepare_fixture.query(...,true)", first)
    wait(n, "#prepare_fixture.starts==1")
    other = buffer(n, [[10, "other"]])
    n.exec_lua("prepare_fixture.query(...,false)", other)
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["running", "other"]
    # Reopen the hidden buffer: its pending Image object must remain usable.
    n.current.buffer = n.buffers[first]
    jump(n, 850)
    finish(n)
    wait(n, "#prepare_fixture.starts==3")
    assert starts(n) == ["running", "other", "parked"]
    finish(n)
    assert n.exec_lua("return prepare_fixture.delivered.parked")


def test_failed_background_work_releases_queue_without_repeated_retries(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "invalid"], [400, "valid"]])
    n.exec_lua("prepare_fixture.query(...,false)", buf)
    wait(n, "#prepare_fixture.starts==1")
    n.exec_lua("prepare_fixture.finish(true)")
    # Repeated discovery must not keep retrying the bad background formula.
    n.exec_lua("prepare_fixture.query(...,false)", buf)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["invalid", "valid"]
    finish(n)


def test_table_discovery_uses_the_same_distance_queue(scheduler):
    n = scheduler
    buf = buffer(n, [[10, "visible"], [850, "table"]])
    n.exec_lua("""
      local buf=...
      require('custom.markdown.prepare').find(buf,850,850,function(items)
        for _,item in ipairs(items)do Snacks.image.image.new(item.src)end
      end)
      prepare_fixture.query(buf,true)
    """, buf)
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["visible"]
    jump(n, 850)
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["visible", "table"]
    finish(n)
    wait(n, "prepare_fixture.delivered.table==true")
    assert n.exec_lua("return prepare_fixture.peak") == 1


def test_inactive_tabs_do_not_count_as_visible_viewports(scheduler):
    n = scheduler
    first = buffer(n, [[10, "first-tab"]])
    n.exec_lua("prepare_fixture.query(...,false)", first)
    n.command("tabnew")
    second = buffer(n, [[10, "current-tab"]])
    n.exec_lua("prepare_fixture.query(...,false)", second)
    wait(n, "#prepare_fixture.starts==1")
    assert starts(n) == ["current-tab"]
    n.command("tabprevious")
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    assert starts(n) == ["current-tab", "first-tab"]


@pytest.fixture
def progress(scheduler):
    n = scheduler
    n.exec_lua("""
      progress_fixture = { handles = {}, cleared = {} }
      local f = progress_fixture
      package.loaded['fidget.progress'] = { handle = { create = function(opts)
        local h = { opts = opts, reports = {} }
        function h:report(props)
          self.reports[#self.reports + 1] = props
          self.message, self.percentage = props.message, props.percentage
        end
        function h:finish() self.finished = true end
        function h:cancel() self.cancelled = true end
        f.handles[#f.handles + 1] = h
        return h
      end } }
      package.loaded['fidget.notification'] = { clear = function(group)
        f.cleared[#f.cleared + 1] = group
      end }
      require('custom.markdown.progress').setup()
    """)
    return n


def test_progress_unique_totals_completion_and_failures(progress):
    n = progress
    buffer(n, [[1, "one"], [2, "one"], [3, "two"]], lines=10)
    wait(n, "#prepare_fixture.starts==1")
    wait(n, "#progress_fixture.handles==1")
    assert n.exec_lua("return progress_fixture.handles[1].percentage") == 0
    finish(n)
    wait(n, "#prepare_fixture.starts==2")
    wait(n, "progress_fixture.handles[1].percentage==50")
    n.exec_lua("prepare_fixture.finish(true)")
    wait(n, "progress_fixture.handles[1].finished")
    assert n.exec_lua("return progress_fixture.handles[1].message") == "1 ready, 1 failed"


def test_progress_discovery_has_no_misleading_percentage(progress):
    n = progress
    n.exec_lua("prepare_fixture.hold=true")
    buffer(n, [[1, "one"]], lines=10)
    wait(n, "#prepare_fixture.held==1")
    wait(n, "#progress_fixture.handles==1")
    assert n.exec_lua("return progress_fixture.handles[1].message") == "0 prepared, discovering…"
    assert n.exec_lua("return progress_fixture.handles[1].percentage") is None
    n.exec_lua("prepare_fixture.hold=false; table.remove(prepare_fixture.held,1)()")
    wait(n, "#prepare_fixture.starts==1")
    finish(n)
    wait(n, "progress_fixture.handles[1].finished")
    assert n.exec_lua("return progress_fixture.handles[1].message") == "Ready · 1 prepared"


def test_progress_quick_cache_is_silent(progress):
    n = progress
    n.exec_lua("prepare_fixture.cached.one=true")
    buffer(n, [[1, "one"]], lines=10)
    wait(n, "require('custom.markdown.prepare').status(vim.api.nvim_get_current_buf()).done")
    # Let the scheduled presentation check observe completion before its delay.
    n.exec_lua("vim.wait(1300, function() return #progress_fixture.handles>0 end)")
    assert n.exec_lua("return #progress_fixture.handles") == 0


def test_progress_switch_and_edit_cancel_only_own_notification(progress):
    n = progress
    buffer(n, [[1, "one"]], lines=10)
    wait(n, "#progress_fixture.handles==1")
    n.command("enew!")
    wait(n, "progress_fixture.handles[1].cancelled")
    assert n.exec_lua("return progress_fixture.cleared") == ["Markdown math"]
    n.command("buffer #")
    wait(n, "#progress_fixture.handles==2")
    n.exec_lua("vim.api.nvim_buf_set_lines(0,0,1,false,{'changed'}); vim.api.nvim_exec_autocmds('TextChanged',{buffer=0})")
    wait(n, "progress_fixture.handles[2].cancelled")
    assert n.exec_lua("return progress_fixture.cleared") == ["Markdown math", "Markdown math"]
