-- The Map's folders display on a function, a file and a type: the row in a
-- box in the middle, who uses it on the left and what it uses on the
-- right, gathered into a box a folder holding the files and their names,
-- the count on each arrow; tests folded to a count. On a function and a
-- file every arrow points at the row; on a type they run left to right.
-- Pure: rows with what each name stands for in `meta.hits`.
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
---@field sub string said dim under the centre
---@field left seam.MapCross[]
---@field right seam.MapCross[]
---@field tests integer|nil callers in tests, folded to a count
---@field tfiles integer|nil the files they are in
---@field word { [1]: string, [2]: string } what a count counts, one and more
---@field heads 'in'|'right' every arrow at the row, or left to right
---@field wrap integer|nil the names a box line holds before the next, in columns
---@field left_counts boolean|nil the count on each arrow from the left too
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

-- a box's files, cut to FILES, each with its wrapped lines
local function laid(g, ww)
  local files = vim.list_slice(g.files, 1, M.FILES)
  local rows, mf, lw = 0, 0, 0
  for _, f in ipairs(files) do
    f.lines = wrap(f.names, ww)
    rows = rows + #f.lines
    mf = math.max(mf, W(f.name))
    for _, l in ipairs(f.lines) do
      lw = math.max(lw, lines_w(l))
    end
  end
  local more = #g.files - #files
  if more > 0 then
    rows = rows + 1
  end
  return { files = files, more = more, h = rows + 3, w = math.max(mf + 4 + lw + 4, W(g.title) + 8), mf = mf }
end

local function box(cv, g, L, x, y)
  cv:box(x, y, L.w, L.h)
  cv:put(x + 2, y, ' ' .. g.title .. ' ', 'SeamBold', g.dir and { kind = 'dir', path = g.dir } or nil)
  local j = 0
  for _, f in ipairs(L.files) do
    cv:put(x + 2, y + 2 + j, f.name, 'SeamText', { kind = 'file', path = f.path })
    for _, line in ipairs(f.lines) do
      local at = x + 4 + L.mf
      for i, nm in ipairs(line) do
        at = cv:put(at + (i > 1 and 2 or 0), y + 2 + j, nm.name, 'SeamMapFn', { kind = 'fn', id = nm.id })
      end
      j = j + 1
    end
  end
  if L.more > 0 then
    cv:put(x + 2, y + 2 + j, '⋯ ' .. L.more .. ' more', 'SeamLabel')
  end
end

--- The rows of the folders display.
---@param m table
---@param o seam.MapFoldersOpts
---@return table[]
function M.draw(m, o)
  local ww = o.wrap or math.huge
  local L, R = group(m, o.left, o.home), group(m, o.right, o.home)
  local function side(list)
    local shown = vim.list_slice(list, 1, M.BOXES)
    local more = 0
    for i = M.BOXES + 1, #list do
      more = more + list[i].n
    end
    for _, g in ipairs(shown) do
      g.L = laid(g, ww)
    end
    return shown, more
  end
  local ls, lmore = side(L)
  local rs, rmore = side(R)
  local function lab(k)
    return ' ' .. k .. ' ' .. (k == 1 and o.word[1] or o.word[2]) .. ' '
  end
  local notes = {}
  if lmore > 0 then
    notes[#notes + 1] = '⋯ ' .. lmore .. ' more in ' .. (#L - #ls) .. ' folders'
  end
  if (o.tests or 0) > 0 then
    notes[#notes + 1] = ('⋯ %d in tests, %d files'):format(o.tests, o.tfiles or 0)
  end
  local rh, lh = -1, #notes * 2
  for _, g in ipairs(rs) do
    rh = rh + g.L.h + 1
  end
  if rmore > 0 then
    rh = rh + 2
  end
  for _, g in ipairs(ls) do
    lh = lh + g.L.h + 1
  end
  local H = math.max(rh, lh, 3)
  local mid = math.floor(H / 2)
  local lw = 0
  for _, g in ipairs(ls) do
    lw = math.max(lw, g.L.w)
  end
  for _, n in ipairs(notes) do
    lw = math.max(lw, W(n) + 2)
  end
  local cw = W(o.centre)
  local cx = (#ls + #notes > 0) and lw + 15 or 0
  local cv = canvas.new(o.width)
  cv:box(cx, mid - 1, cw + 4, 3)
  cv:put(cx + 2, mid, o.centre, o.centre_hl)
  cv:put(cx + 2, mid + 2, o.sub, 'SeamLabel')
  -- the left: who uses it, a box a folder, then the notes
  local lys = {}
  local y = mid - math.floor(lh / 2)
  for _, g in ipairs(ls) do
    box(cv, g, g.L, 0, y)
    lys[#lys + 1] = { y + 2, g.L.w, g.n }
    y = y + g.L.h + 1
  end
  for _, n in ipairs(notes) do
    cv:put(2, y, n, 'SeamLabel')
    lys[#lys + 1] = { y, W(n) + 2, 0 }
    y = y + 2
  end
  local lbus = cx - 4
  for _, a in ipairs(lys) do
    cv:h(a[2], lbus, a[1])
    if o.left_counts and a[3] > 0 then
      cv:put(a[2] + 2, a[1], lab(a[3]), 'SeamMapCount')
    end
  end
  if #lys > 0 then
    local lo, hi = mid, mid
    for _, a in ipairs(lys) do
      lo, hi = math.min(lo, a[1]), math.max(hi, a[1])
    end
    cv:v(lbus, lo, hi)
    cv:h(lbus, cx - 2, mid)
    cv:put(cx - 1, mid, '▶', 'SeamMapLine')
  end
  -- the right: what it uses, a box a folder, the count on each arrow
  local rbus = cx + cw + 6
  local labw = 0
  for _, g in ipairs(rs) do
    labw = math.max(labw, W(lab(g.n)))
  end
  local bx = rbus + labw + 5
  y = mid - math.floor(rh / 2)
  local tops = {}
  if #rs > 0 then
    cv:h(cx + cw + 4, rbus, mid)
  end
  for _, g in ipairs(rs) do
    box(cv, g, g.L, bx, y)
    local ay = y + 2
    tops[#tops + 1] = ay
    cv:h(rbus, bx - 2, ay)
    if o.heads == 'in' then
      cv:put(rbus + 1, ay, '◀', 'SeamMapLine')
    else
      cv:put(bx - 1, ay, '▶', 'SeamMapLine')
    end
    cv:put(rbus + 2, ay, lab(g.n), 'SeamMapCount')
    y = y + g.L.h + 1
  end
  if rmore > 0 then
    cv:put(bx, y, '⋯ ' .. rmore .. ' more in ' .. (#R - #rs) .. ' folders', 'SeamLabel')
  end
  if #tops > 0 then
    local lo, hi = mid, mid
    for _, t in ipairs(tops) do
      lo, hi = math.min(lo, t), math.max(hi, t)
    end
    cv:v(rbus, lo, hi)
  end
  return cv:rows(1)
end

return M
