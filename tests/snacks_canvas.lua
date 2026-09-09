vim.opt.rtp:prepend(vim.fn.getcwd())
local placements = {}
_G.Snacks = {
  image = {
    placement = {
      new = function(buf, path, opts)
        local p = { buffer = buf, path = path, opts = opts, closed = false }
        function p:close() self.closed = true end
        table.insert(placements, p)
        return p
      end,
    },
    util = { fit = function() return { width = 50, height = 20 } end },
  },
}
local canvas = require 'custom.python.snacks_canvas'
local a, b = vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true)
canvas.from_file('/tmp/plot.png', { id = 'inline', buffer = a, x = 0, y = 2 })
canvas.from_file('/tmp/plot.png', { id = 'float', buffer = b, x = 0, y = 1 })
canvas.render 'inline'
canvas.render 'float'
assert(#placements == 2 and placements[1].buffer ~= placements[2].buffer)
canvas.clear 'float'
assert(placements[2].closed and not placements[1].closed)
canvas.render 'float'
assert(#placements == 3)
canvas.from_file('/tmp/plot.png', { id = 'inline', buffer = a, x = 0, y = 8 })
assert(placements[1].closed)
canvas.render 'inline'
assert(placements[4].opts.pos[1] == 8)
local markdown = Snacks.image.placement.new(a, '/tmp/markdown.png', {})
canvas.clear_all()
for _, p in ipairs(placements) do
  assert(p == markdown or p.closed)
end
assert(not markdown.closed)
canvas.clear_all()
print 'PASS: independent inline/float IDs, hide/reopen, reposition and full cleanup'
