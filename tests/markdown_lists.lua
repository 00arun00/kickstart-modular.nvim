-- Run with: nvim --headless -n -u NONE -i NONE -l tests/markdown_lists.lua
-- Requires bullets.nvim and the Markdown Tree-sitter parser.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/bullets.nvim')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
vim.cmd 'filetype plugin indent on'
vim.g.mapleader = ' '
vim.o.swapfile = false
vim.keymap.set('i', '<Tab>', 'TAB-SENTINEL')
vim.keymap.set('i', '<S-Tab>', 'BACKTAB-SENTINEL')
vim.keymap.set('n', '<leader>xx', 'TROUBLE-SENTINEL')
local spec = require('custom.plugins.bullets')[1]
spec.config(nil, spec.opts)

local function reset(lines, row, ft)
  vim.cmd.enew { bang = true }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = ft or 'markdown'
  vim.bo.expandtab, vim.bo.shiftwidth, vim.bo.tabstop = true, 2, 2
  vim.api.nvim_win_set_cursor(0, { row or #lines, 0 })
end

local function keys(value) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), 'xt', false) end

local function expect(lines)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(actual, lines), vim.inspect { expected = lines, actual = actual })
end

-- Every state used by the renderer continues with a fresh unchecked task.
local renderer = require('custom.plugins.render-markdown')[1].opts.checkbox
local states = { ' ', 'x', 'X' }
for _, state in pairs(renderer.custom) do
  table.insert(states, state.raw:sub(2, 2))
end
for _, state in ipairs(states) do
  reset { '- [' .. state .. '] item' }
  keys 'A<CR>new<Esc>'
  expect { '- [' .. state .. '] item', '- [ ] new' }
end
reset { '1. item' }
keys 'A<CR>next<Esc>'
expect { '1. item', '2. next' }
reset { '- item', '  continuation' }
keys 'A<CR>next<Esc>'
expect { '- item', '  continuation', '- next' }
reset { '- ' }
keys 'A<CR>paragraph<Esc>'
expect { 'paragraph' }
reset { '- item:' }
keys 'A<CR>next<Esc>'
expect { '- item:', '- next' }

-- Mid-item Enter continues the same item and positions typing before its tail.
for _, case in ipairs {
  { '- first second', 7, '- first', '  typed second' },
  { '10. first second', 9, '10. first', '    typed second' },
  { '- [>] first second', 11, '- [>] first', '      typed second' },
} do
  reset { case[1] }
  keys(('0%dli<CR>typed <Esc>'):format(case[2]))
  expect { case[3], case[4] }
end
reset({ '- parent', '  - first second' }, 2)
keys '09li<CR>typed <Esc>'
expect { '- parent', '  - first', '    typed second' }
reset({ '- first line', '  second third' }, 2)
keys '08li<CR>typed <Esc>'
expect { '- first line', '  second', '  typed third' }
reset { 'plain first second' }
keys '011li<CR>typed <Esc>'
expect { 'plain first', 'typed second' }
reset({ '- parent', '  - child' }, 2)
keys 'A<CR>next<Esc>'
expect { '- parent', '  - child', '  - next' }

-- Ancestors complete bottom-up; sibling states and unrelated lists survive.
reset({ '- [ ] Root', '  - [ ] Parent', '    - [X] First', '    - [ ] Last', '', '- [!] Other list' }, 4)
keys ' ct'
expect { '- [x] Root', '  - [x] Parent', '    - [X] First', '    - [x] Last', '', '- [!] Other list' }
keys ' ct'
expect { '- [ ] Root', '  - [ ] Parent', '    - [X] First', '    - [ ] Last', '', '- [!] Other list' }
reset({ '- [>] Parent', '  - [ ] First', '  - [!] Blocked', '  - [~] Cancelled' }, 2)
keys ' ct'
expect { '- [>] Parent', '  - [x] First', '  - [!] Blocked', '  - [~] Cancelled' }
reset({ '1. [>] Parent', '   1. [x] First', '   2. [ ] Last' }, 3)
keys ' ct'
expect { '1. [x] Parent', '   1. [x] First', '   2. [x] Last' }

-- Toggling a parent affects only that parent, never its descendants.
reset({ '- [ ] Parent', '  - [!] Child' }, 1)
keys ' ct'
expect { '- [x] Parent', '  - [!] Child' }

-- Ancestor updates form one undo step with the explicitly toggled task.
reset({ '- [ ] Parent', '  - [ ] Child' }, 2)
keys 'i<C-g>u<Esc>'
keys ' ct'
expect { '- [x] Parent', '  - [x] Child' }
keys 'u'
expect { '- [ ] Parent', '  - [ ] Child' }
keys '<C-r>'
expect { '- [x] Parent', '  - [x] Child' }

-- A sibling with any custom state remains unchanged when another task toggles.
for _, state in pairs(renderer.custom) do
  reset({ '- [ ] Parent', '  - [ ] First', '  - ' .. state.raw .. ' Special' }, 2)
  keys ' ct'
  expect { '- [ ] Parent', '  - [x] First', '  - ' .. state.raw .. ' Special' }
end

reset { '1. first', '3. second', '8. third' }
keys 'gN'
expect { '1. first', '2. second', '3. third' }

-- Ordinary indentation keeps existing marker types, including numbered lists.
reset({ '- parent', '- child' }, 2)
keys '>>'
expect { '- parent', '  - child' }
keys '<<'
expect { '- parent', '- child' }
reset({ '1. parent', '1. child' }, 2)
keys 'A<C-t><Esc>'
expect { '1. parent', '  1. child' }

-- Fence examples and blank lines use native newline/open behavior.
reset({ '```markdown', '- [ ] example', '```' }, 2)
keys 'A<CR>text<Esc>'
expect { '```markdown', '- [ ] example', 'text', '```' }
reset({ '```markdown', '- [ ] example', '```' }, 2)
keys 'otext<Esc>'
expect { '```markdown', '- [ ] example', 'text', '```' }
reset({ '```markdown', '- [ ] example', '```' }, 2)
keys ' ct'
expect { '```markdown', '- [ ] example', '```' }
reset({ '```text', '', '```' }, 2)
keys 'A<CR>text<Esc>'
expect { '```text', '', 'text', '```' }

-- Existing global controls survive; list mappings never leak to Python.
assert(vim.fn.maparg('<Tab>', 'i') == 'TAB-SENTINEL')
assert(vim.fn.maparg('<S-Tab>', 'i') == 'BACKTAB-SENTINEL')
assert(vim.fn.maparg('<leader>xx', 'n') == 'TROUBLE-SENTINEL')
assert(vim.fn.maparg('<leader>x', 'n') == '')
reset({ '# Python' }, 1, 'python')
assert(vim.fn.maparg('<CR>', 'i') == '')
assert(vim.fn.maparg('o', 'n') == '')
assert(vim.fn.maparg('<leader>ct', 'n') == '')
print 'PASS: Markdown lists, custom task states, ancestor completion, nesting, fences, and mapping isolation'
vim.cmd 'qa!'
