-- The Map's flow: what the row calls above, gathered under heads (a folder,
-- or the type each gives), a line down the left through the heads into the
-- row, written as what it takes → its name → what it gives; from what it
-- gives a line on down to its callers, gathered the same way. Each item
-- where it is and its name in columns, then its signature straight after;
-- nothing is cut: a line too long for the pane goes on under itself. An
-- empty row between groups and where an item asks, between files. Pure:
-- pieces in, rows out with what each name stands for in `meta.hits`.
local canvas = require 'seam.map.canvas'
local M = {}

-- the most items a side lists before `⋯ N more`, opened with l
M.CAP = 40

-- the column the line down the left runs in
M.G = 1

---@class seam.FlowItem
---@field cols table[][] each column's pieces `{ text, hl, hit }`, aligned down the side
---@field tail table[]|nil pieces straight after the columns, going on under themselves past the pane's edge
---@field gap boolean|nil an empty row before it

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

-- pieces as words, each its pieces up to and taking a space, so a line
-- breaks only between them; an arrow keeps to the word after it
local function words(segs)
  local out, cur = {}, { pieces = {}, w = 0 }
  local function close()
    local text = ''
    for _, p in ipairs(cur.pieces) do
      text = text .. p[1]
    end
    if vim.trim(text) == '→' then
      return
    end
    if #cur.pieces > 0 then
      out[#out + 1] = cur
    end
    cur = { pieces = {}, w = 0 }
  end
  for _, s in ipairs(segs) do
    local i = 1
    while i <= #s[1] do
      local sp = s[1]:find(' ', i, true)
      local e = sp or #s[1]
      local text = s[1]:sub(i, e)
      cur.pieces[#cur.pieces + 1] = { text, s[2], s[3] }
      cur.w = cur.w + vim.fn.strchars(text)
      if sp then
        close()
      end
      i = e + 1
    end
  end
  close()
  return out
end

--- Pieces in lines of at most `room` columns, broken between words; a word
--- longer than a line has a line of its own and goes past it.
---@param segs table[]
---@param room integer
---@return table[][]
function M.wrap(segs, room)
  room = math.max(room, 8)
  local lines, cur, w = {}, {}, 0
  for _, wd in ipairs(words(segs)) do
    local bare = wd.w - #(wd.pieces[#wd.pieces][1]:match ' *$')
    -- a line goes on from its first letter
    if not (w == 0 and #lines > 0 and bare == 0) then
      if w > 0 and w + bare > room then
        lines[#lines + 1], cur, w = cur, {}, 0
      end
      vim.list_extend(cur, wd.pieces)
      w = w + wd.w
    end
  end
  if #cur > 0 then
    lines[#lines + 1] = cur
  end
  -- no spaces at a line's end, to run past the pane
  for _, l in ipairs(lines) do
    while #l > 0 and l[#l][1]:match '^ *$' do
      l[#l] = nil
    end
    local last = l[#l]
    if last then
      l[#l] = { (last[1]:gsub(' +$', '')), last[2], last[3] }
    end
  end
  return lines
end

-- an item's rows from `y`: its columns, then its tail from after them,
-- going on two columns in under itself, after an empty row with `gap`;
-- the row after it
local function put_item(cv, it, ws, x, y, width)
  if it.gap then
    y = y + 1
  end
  for k, c in ipairs(it.cols) do
    cv:seg(c, x, y)
    x = x + ws[k] + 2
  end
  x = x + 1
  local lines = it.tail and M.wrap(it.tail, width - x - 2) or {}
  for k, l in ipairs(lines) do
    cv:seg(l, k == 1 and x or x + 2, y + k - 1)
  end
  return y + math.max(#lines, 1)
end

--- The rows: `top` above, a line down from its heads into `centre`, from
--- the centre's output (`centre.out`, the piece it starts at), else its
--- end, a line on down to `bottom`'s heads.
---@param top seam.FlowGroup[]
---@param centre { segs: table[], out: integer|nil }
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
  for gi, g in ipairs(tops) do
    if gi > 1 then
      y = y + 1
    end
    first = first or y
    join(cv, G, y)
    cv:seg(g.head, G + 3, y)
    y = y + 1
    for _, it in ipairs(g.items) do
      y = put_item(cv, it, ws, G + 5, y, o.width)
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
  -- the centre, going on under itself; where its output starts
  local ox, oy, e
  local k = 0
  for li, l in ipairs(M.wrap(centre.segs, o.width - cx - 2)) do
    local x = li == 1 and cx or cx + 2
    for _, s in ipairs(l) do
      k = k + 1
      if k == centre.out then
        ox, oy = x, y
      end
      x = cv:put(x, y, s[1], s[2], s[3])
    end
    e = x
    y = y + 1
  end
  y = y - 1
  if #bots > 0 then
    local bx, top_y
    if ox then
      -- from under what it gives a step down and left, then down under the row
      bx, top_y = math.min(ox, cx + 2), oy + 1
      if bx < ox then
        cv:v(ox, oy, oy + 1)
        cv:h(bx, ox, oy + 1)
      else
        top_y = oy
      end
      y = y + 1
    else
      bx, top_y = e + 3, y
      cv:put(e + 1, y, '──', 'SeamMapLine')
      cv:bit(bx, y, 8, 'SeamMapLine')
    end
    local bws = widths(bots)
    local last = top_y
    y = y + 1
    for gi, g in ipairs(bots) do
      if gi > 1 then
        y = y + 1
      end
      join(cv, bx, y)
      cv:seg(g.head, bx + 3, y)
      last = y
      y = y + 1
      for _, it in ipairs(g.items) do
        y = put_item(cv, it, bws, bx + 5, y, o.width)
      end
    end
    cv:v(bx, top_y, last)
    if bmore > 0 then
      cv:put(bx + 5, y, '⋯ ' .. bmore .. ' more', 'SeamLabel', { more = 'right' })
    end
  end
  return cv:rows(1)
end

return M
