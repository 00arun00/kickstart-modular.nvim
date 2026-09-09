-- Molten's SnacksCanvas RPC interface, with independent placements per output.
local M = {}
local images = {}

function M.clear(id)
  local img = images[id]
  if img and img.placement then
    img.placement:close()
    img.placement = nil
  end
end

function M.from_file(path, opts)
  local id = opts.id
  local previous = images[id]
  if previous and previous.path == path and previous.buffer == opts.buffer and previous.x == opts.x and previous.y == opts.y then return id end
  M.clear(id)
  images[id] = { path = path, buffer = opts.buffer, x = opts.x, y = opts.y }
  return id
end

function M.render(id)
  local img = images[id]
  if not img or not vim.api.nvim_buf_is_valid(img.buffer) then return end
  if not img.placement or img.placement.closed then
    img.placement = Snacks.image.placement.new(img.buffer, img.path, {
      inline = true,
      pos = { img.y, img.x },
      max_width = 100,
      max_height = 20,
    })
  end
end

function M.image_size(id) return Snacks.image.util.fit(images[id].path, { width = 100, height = 20 }) end

function M.clear_all()
  for id in pairs(images) do
    M.clear(id)
  end
  images = {}
end

return M
