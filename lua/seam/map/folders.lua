-- The Map's folders display on a function, a file and a type, top to
-- bottom: what the row is built from above, who uses it below, the row in
-- a box between; a box a folder holding its files and their names, as many
-- boxes across as fit, the names wrapped to the room so none is cut; the
-- count in each box's border, tests folded to a count. On a function and a
-- file the arrows point up, at what is used; on a type they run down, from
-- its makers to its takers. Pure: rows with what each name stands for in
-- `meta.hits`.
local canvas = require 'seam.map.canvas'
local data = require 'seam.map.data'
local M = {}

-- the most files a box holds, and boxes a side, before `⋯ N more`
M.FILES, M.BOXES = 8, 6

---@class seam.MapCross
---@field path string
---@field id string the function's node id
---@field name string

---@class seam.MapFoldersOpts
---@field centre string
---@field centre_hl string
---@field sub string said dim beside the centre
---@field top seam.MapCross[] what it is built from, or a type's makers
---@field bottom seam.MapCross[] who uses it, or a type's takers
---@field top_says string|nil said beside the line up to the top
---@field bottom_says string|nil said beside the line down to the bottom
---@field tests integer|nil users in tests, folded to a count
---@field tfiles integer|nil the files they are in
---@field word { [1]: string, [2]: string } what a box's count counts, one and more
---@field flow 'up'|'down' the arrows at what is used, or from the top to the bottom
---@field home string a path the folders are named from
---@field width integer

local W = vim.api.nvim_strwidth

-- the items in folders, the most first: `{ title, dir, files = { name, path, names = { { name, id } } }, n }`
local function group(m, items, home)
  local out, at = {}, {}
  for _, it in ipairs(items) do
    local d = data.where(m, it.path, home)
    local g = at[d]
    if not g then
      g = { title = d, dir = it.path:match '^(.*)/[^/]*$', files = {}, fat = {}, n = 0, i = #out + 1 }
      at[d] = g
      out[#out + 1] = g
    end
    local f = g.fat[it.path]
    if not f then
      f = { name = it.path:match '[^/]+$', path = it.path, names = {}, seen = {} }
      g.fat[it.path] = f
      g.files[#g.files + 1] = f
    end
    if not f.seen[it.name] then
      f.seen[it.name] = true
      f.names[#f.names + 1] = { name = it.name, id = it.id }
      g.n = g.n + 1
    end
  end
  table.sort(out, function(a, b)
    return a.n > b.n or (a.n == b.n and a.i < b.i)
  end)
  return out
end

-- a file's names in lines of at most `w` columns
local function wrap(names, w)
  local lines, cur, cw = {}, {}, 0
  for _, x in ipairs(names) do
    local nw = W(x.name)
    if #cur > 0 and cw + 2 + nw > w then
      lines[#lines + 1] = cur
      cur, cw = {}, 0
    end
    cw = cw + (#cur > 0 and 2 or 0) + nw
    cur[#cur + 1] = x
  end
  lines[#lines + 1] = cur
  return lines
end

local function lines_w(line)
  local n = 0
  for i, x in ipairs(line) do
    n = n + W(x.name) + (i > 1 and 2 or 0)
  end
  return n
end

local function count(k, word)
  return k .. ' ' .. (k == 1 and word[1] or word[2])
end

-- a box's files, cut to FILES, each with its names wrapped to what is left
-- of `room` after the file's column
local function laid(g, room, word)
  local files = vim.list_slice(g.files, 1, M.FILES)
  local mf = 0
  for _, f in ipairs(files) do
    mf = math.max(mf, W(f.name))
  end
  local rows, lw = 0, 0
  for _, f in ipairs(files) do
    f.lines = wrap(f.names, math.max(room - mf - 8, 12))
    rows = rows + #f.lines
    for _, l in ipairs(f.lines) do
      lw = math.max(lw, lines_w(l))
    end
  end
  local more = #g.files - #files
  if more > 0 then
    rows = rows + 1
  end
  local says = count(g.n, word)
  return { files = files, more = more, h = rows + 3, w = math.max(mf + 4 + lw + 4, W(g.title) + W(says) + 9), mf = mf, says = says }
end

local function box(cv, g, L, x, y)
  cv:box(x, y, L.w, L.h)
  local at = cv:put(x + 2, y, ' ' .. g.title .. ' ', 'SeamBold', g.dir and { kind = 'dir', path = g.dir } or nil)
  cv:put(at, y, ' ' .. L.says .. ' ', 'SeamMapCount')
  local j = 0
  for _, f in ipairs(L.files) do
    cv:put(x + 2, y + 2 + j, f.name, 'SeamText', { kind = 'file', path = f.path })
    for _, line in ipairs(f.lines) do
      local nx = x + 4 + L.mf
      for i, nm in ipairs(line) do
        nx = cv:put(nx + (i > 1 and 2 or 0), y + 2 + j, nm.name, 'SeamMapFn', { kind = 'fn', id = nm.id })
      end
      j = j + 1
    end
  end
  if L.more > 0 then
    cv:put(x + 2, y + 2 + j, '⋯ ' .. L.more .. ' more', 'SeamLabel')
  end
end

-- a side's boxes, cut to BOXES, with the names they leave out
local function side(m, items, o)
  local list = group(m, items, o.home)
  local shown = vim.list_slice(list, 1, M.BOXES)
  local more = 0
  for i = M.BOXES + 1, #list do
    more = more + list[i].n
  end
  for _, g in ipairs(shown) do
    g.L = laid(g, o.width - 1, o.word)
  end
  local note = more > 0 and ('⋯ %d more in %d folders'):format(more, #list - #shown) or nil
  return shown, note
end

-- the boxes laid from row `y`, as many across as fit; the row after them
-- and the boxes of their last line
local function band(cv, boxes, y, w)
  local x, h, last = 0, 0, {}
  for _, g in ipairs(boxes) do
    if x > 0 and x + g.L.w > w then
      y, x, h, last = y + h + 1, 0, 0, {}
    end
    box(cv, g, g.L, x, y)
    g.x, g.y = x, y
    last[#last + 1] = g
    x, h = x + g.L.w + 2, math.max(h, g.L.h)
  end
  return y + h, last
end

-- the box of `boxes` whose side at row `y` is crossed by column `x`
local function crossed(boxes, x, y, bottom)
  for _, g in ipairs(boxes) do
    local edge = bottom and g.y + g.L.h - 1 or g.y
    if edge == y and x > g.x and x < g.x + g.L.w - 1 then
      return g
    end
  end
end

--- The rows of the folders display.
---@param m table
---@param o seam.MapFoldersOpts
---@return table[]
function M.draw(m, o)
  local cv = canvas.new(o.width)
  local ts, tnote = side(m, o.top, o)
  local bs, bnote = side(m, o.bottom, o)
  local cx = 4
  local tx = cx + 2 + math.floor(W(o.centre) / 2)
  local up = o.flow ~= 'down'
  -- above: what it is built from, then the line down to the row
  local cy, y = 0, 0
  if #ts > 0 then
    local last
    y, last = band(cv, ts, 0, o.width)
    if tnote then
      cv:put(2, y + 1, tnote, 'SeamLabel')
      y = y + 2
    end
    local y0 = (not tnote and crossed(last, tx, y - 1, true)) and y - 1 or y + 1
    cy = y + 3
    cv:v(tx, y0, cy)
    cv:put(tx, up and y + 1 or y + 2, up and '▲' or '▼', 'SeamMapLine')
    cv:put(tx + 2, up and y + 2 or y + 1, o.top_says or '', 'SeamLabel')
  end
  cv:box(cx, cy, W(o.centre) + 4, 3)
  cv:put(cx + 2, cy + 1, o.centre, o.centre_hl)
  cv:put(cx + W(o.centre) + 6, cy + 1, o.sub, 'SeamLabel')
  y = cy + 2
  -- below: who uses it, the line down to them
  if #bs > 0 then
    local by = y + 3
    cv:put(tx + 2, up and y + 2 or y + 1, o.bottom_says or '', 'SeamLabel')
    local yb = band(cv, bs, by, o.width)
    cv:v(tx, y, crossed(bs, tx, by) and by or by - 1)
    cv:put(tx, up and y + 1 or y + 2, up and '▲' or '▼', 'SeamMapLine')
    y = yb
  end
  local notes = { bnote }
  if (o.tests or 0) > 0 then
    notes[#notes + 1] = ('⋯ %d in tests, %d files'):format(o.tests, o.tfiles or 0)
  end
  for _, n in ipairs(notes) do
    y = y + 1
    cv:put(2, y, n, 'SeamLabel')
  end
  return cv:rows(1)
end

return M
