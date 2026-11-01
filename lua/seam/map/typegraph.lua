-- The Map's tree display on a type: types as boxes, the functions that
-- turn one into another on the arrows. On the left what makes it, from the
-- types its makers take; on the right what its takers give, a box an
-- output, each box on into what takes it, as many levels as asked, `l`
-- `h` a box's branch alone; a function that gives back what it takes
-- written above the box, `↺`. Pure: rows with what each name stands for
-- in `meta.hits`, a box's name in `meta.tv` for `+`.
local canvas = require 'seam.map.canvas'
local data = require 'seam.map.data'
local M = {}

-- the most outputs a box shows past the first level, and makers on the left
M.CAP, M.MAKERS = 3, 6
-- the most boxes drawn: past it a box's outputs are left as ⋯ more
M.BUDGET = 40

local W = vim.api.nvim_strwidth

-- the takers of `name` by what they give, in the order met, and those giving it back
local function takers(m, name)
  local _, list = data.flow(m, name)
  local groups, at, loops = {}, {}, {}
  for _, id in ipairs(list) do
    local out, repo = data.gives(m, id)
    local f = { id = id, label = data.label(m.graph.nodes[id]) }
    if repo and out == name then
      loops[#loops + 1] = f
    else
      local g = at[out]
      if not g then
        g = { out = out, repo = repo, fns = {} }
        at[out] = g
        groups[#groups + 1] = g
      end
      g.fns[#g.fns + 1] = f
    end
  end
  return groups, loops
end

local function loop_text(loops, name)
  if #loops <= 2 then
    return table.concat(
      vim.tbl_map(function(f)
        return f.label
      end, loops),
      ', '
    )
  end
  return #loops .. ' that give ' .. name .. ' back'
end

---@class seam.MapTypeOpts
---@field levels integer
---@field open table<string, boolean>
---@field more table<string, boolean>
---@field width integer
---@field opened fun(name: string): boolean|nil is a box's declaration open under the drawing?

--- The rows of a type's tree.
---@param m table
---@param name string
---@param o seam.MapTypeOpts
---@return table[]
function M.draw(m, name, o)
  -- the right: a box a type, its takers' outputs under it
  local boxes = 0
  local function build(t, repo, depth, branch, above)
    boxes = boxes + 1
    local nd = { name = t, repo = repo, depth = depth, branch = branch, kids = {} }
    if not repo or above[t] then
      nd.seen = above[t]
      return nd
    end
    local groups, loops = takers(m, t)
    nd.can = #groups > 0
    local open = o.open[branch]
    if not (open == true or (open ~= false and depth < o.levels)) then
      return nd
    end
    nd.shown, nd.loops = true, loops
    local cap = (depth == 0 or o.more[branch]) and #groups or M.CAP
    if boxes >= M.BUDGET then
      cap = 0
    end
    above[t] = true
    for i = 1, math.min(cap, #groups) do
      local g = groups[i]
      local k = build(g.out, g.repo, depth + 1, branch .. '\n' .. g.out, above)
      k.fns = g.fns
      nd.kids[#nd.kids + 1] = k
    end
    above[t] = nil
    nd.more = #groups - #nd.kids
    return nd
  end
  local root = build(name, true, 0, '', {})
  root.loops = root.loops or {}
  -- the left: the makers, each with the types it takes
  local makers = {}
  local mk = data.flow(m, name)
  for _, id in ipairs(mk) do
    local f = { id = id, label = data.label(m.graph.nodes[id]) }
    local ins = vim.tbl_filter(function(t)
      return t ~= name
    end, data.takes(m, id))
    if #ins < #data.takes(m, id) then
      if not vim.tbl_contains(
        vim.tbl_map(function(x)
          return x.id
        end, root.loops),
        id
      ) then
        root.loops[#root.loops + 1] = f
      end
    else
      f.inputs = vim.list_slice(ins, 1, 3)
      makers[#makers + 1] = f
    end
  end
  local lmore = math.max(0, #makers - M.MAKERS)
  makers = vim.list_slice(makers, 1, M.MAKERS)
  if lmore > 0 then
    makers[#makers + 1] = { label = '⋯ ' .. lmore .. ' more', inputs = {}, more = true }
  end
  local LW, LL, LH = 0, 0, -1
  for _, f in ipairs(makers) do
    for _, t in ipairs(f.inputs) do
      LW = math.max(LW, W(t) + 4)
    end
    LL = math.max(LL, W(f.label))
    f.h = #f.inputs > 0 and #f.inputs * 4 - 1 or 1
    LH = LH + f.h + 1
  end
  local lbx = LW > 0 and LW + 2 or 0
  local mbx = lbx + LL + 8
  local tx = #makers > 0 and mbx + 3 or 0
  -- each level's column: as wide as its widest box, after room for its arrows' names
  local BW, LBL = {}, {}
  local function sizes(nd)
    nd.w = W(nd.name) + 4
    nd.h = math.max(3, (nd.fns and #nd.fns or 1) + 2)
    BW[nd.depth] = math.max(BW[nd.depth] or 0, nd.w)
    for _, k in ipairs(nd.kids) do
      for _, f in ipairs(k.fns) do
        LBL[k.depth] = math.max(LBL[k.depth] or 0, W(f.label))
      end
      sizes(k)
    end
    if (nd.more or 0) > 0 then
      LBL[nd.depth + 1] = math.max(LBL[nd.depth + 1] or 0, W('⋯ ' .. nd.more .. ' more'))
    end
  end
  root.fns = nil
  sizes(root)
  local X = { [0] = tx }
  local d = 1
  while BW[d] do
    X[d] = X[d - 1] + BW[d - 1] + (LBL[d] or 0) + 12
    d = d + 1
  end
  -- each box at the first free row of its column, its first output level with it
  local free = {}
  local function place(nd, ymin)
    local reserve = (nd.loops and #nd.loops > 0) and 2 or 0
    local y = math.max(ymin, (free[nd.depth] or 0) + reserve)
    nd.y = y
    free[nd.depth] = y + nd.h + 1
    for i, k in ipairs(nd.kids) do
      place(k, i == 1 and y or 0)
    end
    if (nd.more or 0) > 0 then
      nd.more_y = math.max(y + 1, free[nd.depth + 1] or 0)
      free[nd.depth + 1] = nd.more_y + 2
    end
  end
  place(root, math.max(0, math.floor((LH + 1) / 2) - 1))
  local cv = canvas.new(o.width)
  -- where each box stands across, for its declaration opened under the drawing
  local at = {}
  local function draw_box(nd)
    local x, y = X[nd.depth], nd.y
    if nd.repo and not at[nd.name] then
      at[nd.name] = { x = x, bottom = y + nd.h - 1 }
    end
    cv:box(x, y, nd.w, nd.h)
    local hl = nd.seen and 'SeamDim' or nd.depth == 0 and 'SeamTypeBold' or 'SeamType'
    local hit = nd.repo and { kind = 'type', name = nd.name, box = true, branch = nd.branch, can = nd.can and not nd.shown, shown = nd.shown and nd.depth > 0 }
      or nil
    cv:put(x + 2, y + 1, nd.name, hl, hit)
    if nd.loops and #nd.loops > 0 then
      local ids = #nd.loops == 1 and { kind = 'fn', id = nd.loops[1].id } or nil
      cv:put(x, y - 2, '↺ ' .. loop_text(nd.loops, nd.name), 'SeamMapFn', ids)
      cv:v(x + 3, y - 1, y)
    end
    if #nd.kids == 0 and (nd.more or 0) == 0 then
      return
    end
    local cy = y + 1
    local bx = x + BW[nd.depth] + 2
    local nx = X[nd.depth + 1]
    cv:h(x + nd.w - 1, bx, cy)
    local last = cy
    for _, k in ipairs(nd.kids) do
      for j, f in ipairs(k.fns) do
        local ar = k.y + j
        cv:h(bx, nx - 2, ar)
        cv:put(nx - 1, ar, '▶', 'SeamMapLine')
        cv:put(bx + 2, ar, ' ' .. f.label .. ' ', 'SeamMapFn', { kind = 'fn', id = f.id })
        last = math.max(last, ar)
      end
      draw_box(k)
    end
    if (nd.more or 0) > 0 then
      cv:h(bx, bx + 1, nd.more_y)
      cv:put(bx + 2, nd.more_y, ' ⋯ ' .. nd.more .. ' more', 'SeamLabel', { more = nd.branch })
      last = math.max(last, nd.more_y)
    end
    cv:v(bx, cy, last)
  end
  draw_box(root)
  -- the makers on the left, a bus joining them to the type
  if #makers > 0 then
    local cy = root.y + 1
    local gy = math.max(0, cy - math.floor((LH + 1) / 2))
    local lo, hi = cy, cy
    for _, f in ipairs(makers) do
      local ar = gy + math.floor(f.h / 2)
      local centres = {}
      for j, t in ipairs(f.inputs) do
        local by = gy + (j - 1) * 4
        cv:box(0, by, W(t) + 4, 3)
        cv:put(2, by + 1, t, 'SeamType', { kind = 'type', name = t })
        cv:h(W(t) + 3, lbx, by + 1)
        centres[#centres + 1] = by + 1
      end
      if #centres > 1 then
        cv:v(lbx, centres[1], centres[#centres])
      end
      cv:h(#centres > 0 and lbx or lbx + 1, mbx, ar)
      cv:put(lbx + 2, ar, ' ' .. f.label .. ' ', f.more and 'SeamLabel' or 'SeamMapFn', f.id and { kind = 'fn', id = f.id } or nil)
      lo, hi = math.min(lo, ar), math.max(hi, ar)
      gy = gy + f.h + 1
    end
    cv:v(mbx, lo, hi)
    cv:h(mbx, tx - 2, cy)
    cv:put(tx - 1, cy, '▶', 'SeamMapLine')
  end
  -- a line down from the first box opened to its declaration
  for _, nd in ipairs(o.opened and { root } or {}) do
    local function first(n)
      if o.opened(n.name) then
        return n
      end
      for _, k in ipairs(n.kids) do
        local f = first(k)
        if f then
          return f
        end
      end
    end
    local f = first(nd)
    if f then
      local b = at[f.name]
      local h = cv.H
      cv:v(b.x + 3, b.bottom, h)
      -- on into the declaration's bar under the drawing
      cv:bit(b.x + 3, h, 4)
    end
  end
  local rows = cv:rows(1)
  if rows[1] then
    rows[1].meta.boxes = at
  end
  for _, r in ipairs(rows) do
    local names = {}
    for _, h in ipairs(r.meta.hits) do
      if h.item.box then
        names[#names + 1] = { s = h.s, e = h.e, name = h.item.name }
      end
    end
    if #names > 0 then
      r.meta.tv = { key = 'map', id = 'box', names = names, chain = {}, after = true }
    end
  end
  return rows
end

return M
