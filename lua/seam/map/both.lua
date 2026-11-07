-- The Map's both ways display: what the row is built from on the left, who
-- uses it on the right, the order of the tabs; each side gathered into
-- folders, an empty row between them, their files, each file's names after
-- it, a line from each file into the row; a side taller than its room
-- with its smallest folders closed to a line each. A function's calls and
-- callers, a folder's or a file's files across its edge with the names
-- that cross, a type's makers and takers. Pure: the items come as pieces,
-- the rows go out with what each name stands for in `meta.hits`.
local canvas = require 'seam.map.canvas'
local draw = require 'seam.draw'
local fold = require 'seam.map.fold'
local M = {}

-- the least room the names after a file get, a long file name or not: past
-- the side's room the line goes on right, the pane scrolled to it
M.NAMES = 30

local W = vim.api.nvim_strwidth

local function width(segs)
  local n = 0
  for _, s in ipairs(segs) do
    n = n + W(s[1])
  end
  return n
end

---@class seam.BothItem
---@field folder string the folder as the Map names it
---@field dir string|nil the folder's path, what its name stands for
---@field path string the file
---@field segs table[] the name's pieces `{ text, hl, hit }`

---@class seam.BothLine
---@field segs table[]
---@field join boolean a line from it into the row
---@field indent integer|nil columns before it

-- the items in folders, the most names first, the files in the order met
local function group(items)
  local out, at = {}, {}
  for _, it in ipairs(items) do
    local g = at[it.folder]
    if not g then
      g = { title = it.folder, dir = it.dir, files = {}, fat = {}, n = 0, i = #out + 1 }
      at[it.folder] = g
      out[#out + 1] = g
    end
    local f = g.fat[it.path]
    if not f then
      f = { name = it.path:match '[^/]+$', path = it.path, names = {} }
      g.fat[it.path] = f
      g.files[#g.files + 1] = f
    end
    f.names[#f.names + 1] = it.segs
    g.n = g.n + 1
  end
  table.sort(out, function(a, b)
    return a.n > b.n or (a.n == b.n and a.i < b.i)
  end)
  return out
end

-- a folder closed: its name and how many names in how many files, a line
-- into the row; l opens it
local function closed_line(g)
  local hit = { fold = g.key, label = g.title }
  local count = '  ' .. draw.plural(g.n, 'name') .. ' in ' .. draw.plural(#g.files, 'file')
  return { segs = { { '▸ ', 'SeamLabel', hit }, { g.title, 'SeamBold', hit }, { count, 'SeamLabel', hit } }, join = true }
end

--- A side's lines: a folder, then its files indented under it, each with
--- its names after it in lines of at most `room` columns, or one a line
--- when `each`, an empty row before the next folder. Past `budget` rows
--- the folders with the fewest names close to a line each (seam.map.fold),
--- never one in `open`; each opened by `side .. ':' .. its name`.
---@param items seam.BothItem[]
---@param room integer
---@param o { each: boolean|nil, budget: integer|nil, open: table<string, boolean>|nil, side: 'left'|'right' }
---@return seam.BothLine[]
function M.side(items, room, o)
  local gs = group(items)
  for _, g in ipairs(gs) do
    g.key, g.body = o.side .. ':' .. g.title, {}
    local mf = 0
    for _, f in ipairs(g.files) do
      mf = math.max(mf, W(f.name))
    end
    local nroom = math.max(room - mf - 4, M.NAMES)
    for _, f in ipairs(g.files) do
      local lines, cur = {}, nil
      for _, segs in ipairs(f.names) do
        if cur and (o.each or width(cur) + 2 + width(segs) > nroom) then
          lines[#lines + 1] = cur
          cur = nil
        end
        cur = cur and vim.list_extend(vim.list_extend(cur, { { '  ' } }), segs) or vim.list_extend({}, segs)
      end
      lines[#lines + 1] = cur
      for k, l in ipairs(lines) do
        local file = k == 1 and { f.name, 'SeamText', { kind = 'file', path = f.path } } or { '' }
        local pad = string.rep(' ', mf + 2 - W(file[1]))
        g.body[#g.body + 1] = { segs = vim.list_extend({ file, { pad } }, l), join = k == 1, indent = 2 }
      end
    end
    g.lines = 1 + #g.body
  end
  -- the empty rows between folders stay, whatever closes
  local shut = fold.closed(gs, (o.budget or math.huge) - (#gs - 1), o.open or {})
  local out = {}
  for i, g in ipairs(gs) do
    if i > 1 then
      out[#out + 1] = { segs = {}, join = false }
    end
    if shut[g.key] then
      out[#out + 1] = closed_line(g)
    else
      local head = { { g.title, 'SeamBold', g.dir and { kind = 'dir', path = g.dir } or nil } }
      out[#out + 1] = { segs = (o.open or {})[g.key] and fold.head(head, g.key) or head, join = false }
      vim.list_extend(out, g.body)
    end
  end
  return out
end

--- The room each side's names get across `w` beside a centre `cw` wide:
--- each what it needs, the narrower first, the wider the rest.
---@param need_l integer
---@param need_r integer
---@param w integer
---@param cw integer
---@return integer, integer
function M.rooms(need_l, need_r, w, cw)
  local avail = w - cw - 12
  if need_l + need_r <= avail then
    return need_l, need_r
  end
  local half = math.floor(avail / 2)
  if need_l <= half then
    return need_l, avail - need_l
  elseif need_r <= half then
    return avail - need_r, need_r
  end
  return half, avail - half
end

--- The rows: the left's lines from the left edge, a line from each that
--- joins to a column after the widest and on into the centre; the right's
--- after it the same way; the two sides centred on the centre's row.
---@param left seam.BothLine[]
---@param right seam.BothLine[]
---@param centre table[] pieces
---@return table[]
function M.draw(left, right, centre, labels)
  local lw = 0
  for _, l in ipairs(left) do
    lw = math.max(lw, (l.indent or 0) + width(l.segs))
  end
  local n = math.max(#left, #right, 1)
  -- room over the sides for what each is to the row
  local mid = math.floor(n / 2) + (labels and 2 or 0)
  local cv = canvas.new()
  local l0, r0 = mid - math.floor(#left / 2), mid - math.floor(#right / 2)
  local bus = lw + 2
  local lo, hi = mid, mid
  for j, l in ipairs(left) do
    local y = l0 + j - 1
    local x = cv:seg(l.segs, l.indent or 0, y)
    if l.join then
      cv:h(x + 1, bus, y)
      lo, hi = math.min(lo, y), math.max(hi, y)
    end
  end
  local cx = 0
  if #left > 0 then
    cv:v(bus, lo, hi)
    cv:h(bus, bus + 3, mid)
    cx = bus + 4
  end
  cv:seg(centre, cx, mid)
  local bx = cx + 1 + width(centre)
  lo, hi = mid, mid
  for j, l in ipairs(right) do
    local y = r0 + j - 1
    local x = bx + 6 + (l.indent or 0)
    if l.join then
      cv:h(bx + 3, x - 1, y)
      lo, hi = math.min(lo, y), math.max(hi, y)
    end
    cv:seg(l.segs, x, y)
  end
  if #right > 0 then
    cv:h(bx, bx + 3, mid)
    cv:v(bx + 3, lo, hi)
  end
  if labels and #left > 0 then
    cv:seg({ { labels[1], 'SeamSection' } }, 0, l0 - 2)
  end
  if labels and #right > 0 then
    cv:seg({ { labels[2], 'SeamSection' } }, bx + 6, r0 - 2)
  end
  return cv:rows(1)
end

return M
