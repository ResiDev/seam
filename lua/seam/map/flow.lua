-- The Map's flow: what the row calls above, gathered under heads (a folder,
-- or the type each gives), a line down the left through the heads into the
-- row, written as what it takes → its name → what it gives; from there on
-- to its callers below, gathered the same way, set off where the row's line
-- ends. Each item a line of columns, aligned down its side; the line of each
-- call in the gutter. Pure: pieces in, rows out with what each name stands
-- for in `meta.hits`.
local canvas = require 'seam.map.canvas'
local M = {}

-- the most items a side lists before `⋯ N more`, opened with l
M.CAP = 40

-- the gutter: a line number right-aligned, then a space; the line runs down after it
M.G = 5

---@class seam.FlowItem
---@field gutter string|nil the line of the call, in the gutter
---@field cols table[][] each column's pieces `{ text, hl, hit }`

---@class seam.FlowGroup
---@field head table[] pieces
---@field items seam.FlowItem[]

local function width(segs)
  local n = 0
  for _, s in ipairs(segs) do
    n = n + vim.fn.strchars(s[1])
  end
  return n
end

-- the side cut to CAP items unless `all`, and how many were left out
local function capped(groups, all)
  if all then
    return groups, 0
  end
  local out, n, more = {}, 0, 0
  for _, g in ipairs(groups) do
    local keep = {}
    for _, it in ipairs(g.items) do
      if n < M.CAP then
        keep[#keep + 1] = it
        n = n + 1
      else
        more = more + 1
      end
    end
    if #keep > 0 then
      out[#out + 1] = { head = g.head, items = keep }
    end
  end
  return out, more
end

-- each column as wide as its widest down the side
local function widths(groups)
  local ws = {}
  for _, g in ipairs(groups) do
    for _, it in ipairs(g.items) do
      for k, c in ipairs(it.cols) do
        ws[k] = math.max(ws[k] or 0, width(c))
      end
    end
  end
  return ws
end

-- a head's join to the line down at `x`: the line's branch, then a stroke
local function join(cv, x, y)
  cv:bit(x, y, 2, 'SeamMapLine')
  cv:put(x + 1, y, '─', 'SeamMapLine')
end

local function put_cols(cv, it, ws, x, y)
  for k, c in ipairs(it.cols) do
    cv:seg(c, x, y)
    x = x + ws[k] + 2
  end
end

--- The rows: `top` above, a line down from its heads into `centre`, from
--- the centre's end a line on down to `bottom`'s heads.
---@param top seam.FlowGroup[]
---@param centre { segs: table[], gutter: string|nil }
---@param bottom seam.FlowGroup[]
---@param o { width: integer, all_top: boolean|nil, all_bottom: boolean|nil }
---@return table[]
function M.draw(top, centre, bottom, o)
  local G = M.G
  local cv = canvas.new(o.width)
  local tops, tmore = capped(top, o.all_top)
  local bots, bmore = capped(bottom, o.all_bottom)
  local ws = widths(tops)
  local y, first = 0, nil
  for _, g in ipairs(tops) do
    first = first or y
    join(cv, G, y)
    cv:seg(g.head, G + 3, y)
    y = y + 1
    for _, it in ipairs(g.items) do
      if it.gutter then
        cv:put(G - 1 - #it.gutter, y, it.gutter, 'SeamGutter')
      end
      put_cols(cv, it, ws, G + 5, y)
      y = y + 1
    end
  end
  if tmore > 0 then
    cv:put(G + 5, y, '⋯ ' .. tmore .. ' more', 'SeamLabel', { more = 'left' })
    y = y + 1
  end
  local cx = 0
  if first then
    -- a row of the line alone between the calls and the row
    y = y + 1
    cv:v(G, first, y)
    cv:bit(G, y, 2, 'SeamMapLine')
    cv:put(G + 1, y, '──▶', 'SeamMapLine')
    cx = G + 5
  end
  local yc = y
  if centre.gutter then
    cv:put(G - 1 - #centre.gutter, yc, centre.gutter, 'SeamGutter')
  end
  local e = cv:seg(centre.segs, cx, yc)
  if #bots > 0 then
    local bx = e + 3
    cv:put(e + 1, yc, '──', 'SeamMapLine')
    cv:bit(bx, yc, 8, 'SeamMapLine')
    local bws = widths(bots)
    local last = yc
    y = yc + 1
    for _, g in ipairs(bots) do
      join(cv, bx, y)
      cv:seg(g.head, bx + 3, y)
      last = y
      y = y + 1
      for _, it in ipairs(g.items) do
        put_cols(cv, it, bws, bx + 5, y)
        y = y + 1
      end
    end
    cv:v(bx, yc, last)
    if bmore > 0 then
      cv:put(bx + 5, y, '⋯ ' .. bmore .. ' more', 'SeamLabel', { more = 'right' })
    end
  end
  return cv:rows(1)
end

return M
