-- The Map's flow: what the row calls above, gathered under heads (a folder,
-- or the type each gives), a line down the left through the heads into the
-- row, written as what it takes → its name → what it gives; from what it
-- gives a line on down to its callers, gathered the same way. Each item
-- where it is and its name in columns, then its signature straight after;
-- nothing is cut: a line too long for the pane goes on under itself, and
-- a flow taller than the pane has its smallest groups closed to a line
-- each. An empty row between groups and where an item asks, between files.
-- Pure: pieces in, rows out with what each name stands for in `meta.hits`.
local canvas = require 'seam.map.canvas'
local draw = require 'seam.draw'
local fold = require 'seam.map.fold'
local M = {}

-- the column the line down the left runs in
M.G = 1

-- the rows the line falls from the row's output before it turns to its
-- callers, so they stand apart from it
M.DROP = 2

---@class seam.FlowItem
---@field cols table[][] each column's pieces `{ text, hl, hit }`, aligned down the side
---@field tail table[]|nil pieces straight after the columns, going on under themselves past the pane's edge
---@field gap boolean|nil an empty row before it

---@class seam.FlowGroup
---@field head table[] pieces
---@field items seam.FlowItem[]
---@field key string|nil what it is opened by, else its head's text
---@field files integer|nil the files its items are in, for its closed line

local function width(segs)
  local n = 0
  for _, s in ipairs(segs) do
    n = n + vim.fn.strchars(s[1])
  end
  return n
end

-- what a group is opened by: its key, else its head's text
local function key_of(g)
  if g.key then
    return g.key
  end
  local t = {}
  for _, s in ipairs(g.head) do
    t[#t + 1] = s[1]
  end
  return table.concat(t)
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
      -- the mark of where the row's output starts kept on its first letter
      cur.pieces[#cur.pieces + 1] = { text, s[2], s[3], out = i == 1 and s.out or nil }
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
      l[#l] = { (last[1]:gsub(' +$', '')), last[2], last[3], out = last.out }
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
    if cv then
      cv:seg(c, x, y)
    end
    x = x + ws[k] + 2
  end
  x = x + 1
  local lines = it.tail and M.wrap(it.tail, width - x - 2) or {}
  for k, l in ipairs(lines) do
    if cv then
      cv:seg(l, k == 1 and x or x + 2, y + k - 1)
    end
  end
  return y + math.max(#lines, 1)
end

-- the rows a group takes open from column `x`, its head among them
local function rows_of(g, ws, x, width)
  local y = 1
  for _, it in ipairs(g.items) do
    y = put_item(nil, it, ws, x, y, width)
  end
  return y
end

-- a group closed at `x`, `y`: its head after ▸, how many names in how many
-- files, all of it opening it with l
local function put_closed(cv, g, k, x, y)
  local hit = { fold = k, label = key_of(g) }
  local segs = { { '▸ ', 'SeamLabel', hit } }
  for _, s in ipairs(g.head) do
    segs[#segs + 1] = { s[1], s[2], hit }
  end
  local count = draw.plural(#g.items, 'name') .. (g.files and (' in ' .. draw.plural(g.files, 'file')) or '')
  segs[#segs + 1] = { '  ' .. count, 'SeamLabel', hit }
  cv:seg(segs, x, y)
end

--- The rows: `top` above, a line down from its heads into `centre`, from
--- the centre's output (`centre.out`, the piece it starts at), else its
--- end, a line on down to `bottom`'s heads. Past `height` rows the groups
--- of both sides with the fewest names close to a line each
--- (seam.map.fold), never one in `open`; each opened by `left:` above or
--- `right:` below, then its key.
---@param top seam.FlowGroup[]
---@param centre { segs: table[], out: integer|nil }
---@param bottom seam.FlowGroup[]
---@param o { width: integer, height: integer|nil, open: table<string, boolean>|nil }
---@return table[]
function M.draw(top, centre, bottom, o)
  local G = M.G
  local cv = canvas.new(o.width)
  local ws, bws = widths(top), widths(bottom)
  local cx = #top > 0 and G + 5 or 0
  -- the centre, going on under itself; where its output starts and it ends
  local segs = { unpack(centre.segs) }
  local o_ = centre.out and segs[centre.out]
  if o_ then
    segs[centre.out] = { o_[1], o_[2], o_[3], out = true }
  end
  local lines = M.wrap(segs, o.width - cx - 2)
  local ox, oline, e
  for li, l in ipairs(lines) do
    local x = li == 1 and cx or cx + 2
    for _, s in ipairs(l) do
      if s.out then
        ox, oline = x, li
      end
      x = x + vim.fn.strchars(s[1])
    end
    e = x
  end
  local bx = ox and math.min(ox, cx + 2) or e + 3
  -- what closes: the rows left once the row, the line alone and the empty
  -- rows between groups are taken, shared by both sides
  local keys, gs = {}, {}
  local function measure(list, side, ws_, x)
    for _, g in ipairs(list) do
      keys[g] = side .. ':' .. key_of(g)
      gs[#gs + 1] = { key = keys[g], lines = rows_of(g, ws_, x, o.width), n = #g.items }
    end
  end
  measure(top, 'left', ws, G + 5)
  measure(bottom, 'right', bws, bx + 5)
  local fixed = #lines + #top + (#bottom > 0 and M.DROP + #bottom or 0)
  local shut = fold.closed(gs, (o.height or math.huge) - fixed, o.open or {})
  -- the columns as wide as the open groups need; narrower, they take no
  -- more rows than measured
  local function open_of(list)
    return vim.tbl_filter(function(g)
      return not shut[keys[g]]
    end, list)
  end
  ws, bws = widths(open_of(top)), widths(open_of(bottom))
  -- a side's groups from `y` on the line down at `x`: each head, its items
  -- under it, or its closed line; the last head's row and the row after
  local function side(list, ws_, x, y)
    local last
    for gi, g in ipairs(list) do
      if gi > 1 then
        y = y + 1
      end
      join(cv, x, y)
      last = y
      if shut[keys[g]] then
        put_closed(cv, g, keys[g], x + 3, y)
        y = y + 1
      else
        cv:seg(g.head, x + 3, y)
        y = y + 1
        for _, it in ipairs(g.items) do
          y = put_item(cv, it, ws_, x + 5, y, o.width)
        end
      end
    end
    return last, y
  end
  local y = 0
  if #top > 0 then
    -- a row of the line alone between the calls and the row
    y = select(2, side(top, ws, G, 0)) + 1
    cv:v(G, 0, y)
    cv:bit(G, y, 2, 'SeamMapLine')
    cv:put(G + 1, y, '──▶', 'SeamMapLine')
  end
  local oy
  for li, l in ipairs(lines) do
    local x = li == 1 and cx or cx + 2
    if li == oline then
      oy = y
    end
    cv:seg(l, x, y)
    y = y + 1
  end
  y = y - 1
  if #bottom > 0 then
    local top_y
    if ox then
      -- from under what it gives down a while, left, then down under the row
      local turn = y + M.DROP
      top_y = turn
      cv:v(ox, oy, turn)
      if bx < ox then
        cv:h(bx, ox, turn)
      else
        top_y = oy
      end
      y = turn + 1
    else
      top_y = y
      cv:put(e + 1, y, '──', 'SeamMapLine')
      cv:bit(bx, y, 8, 'SeamMapLine')
      y = y + M.DROP
    end
    local last = side(bottom, bws, bx, y + 1)
    cv:v(bx, top_y, last)
  end
  return cv:rows(1)
end

return M
