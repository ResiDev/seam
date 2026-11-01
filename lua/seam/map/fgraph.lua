-- The Map's folders display on a folder: its folders as boxes, an arrow
-- where one calls into another with the count on it. The boxes stand in
-- ranks left to right, each a step from the ones nothing calls, those that
-- call nothing last. An arrow leaves a box on its right and enters the
-- next rank's on their left; over the top when it skips a rank, under the
-- bottom when it goes back; within a rank it turns in the gap after it and
-- comes back into the box's right, `◀`. Pure: rows with what each box
-- stands for in `meta.hits`.
local canvas = require 'seam.map.canvas'
local draw = require 'seam.draw'
local M = {}

local W = vim.api.nvim_strwidth

-- the most boxes drawn: those with the most calls in and out, the rest said under them
M.MAX = 8

---@class seam.MapUnit
---@field key string
---@field label string
---@field sub string|nil said dim under it
---@field hit table|nil what it stands for

---@class seam.MapEdge
---@field from string a unit's key
---@field to string
---@field n integer

--- Each unit's rank: the fewest arrows from a unit nothing calls (else
--- from the one calling out most), a unit calling nothing after the rest.
---@param units seam.MapUnit[]
---@param edges seam.MapEdge[]
---@return table<string, integer>
function M.ranks(units, edges)
  local out, ins, weight = {}, {}, {}
  for _, u in ipairs(units) do
    out[u.key], ins[u.key], weight[u.key] = {}, 0, 0
  end
  for _, e in ipairs(edges) do
    table.insert(out[e.from], e.to)
    ins[e.to] = ins[e.to] + 1
    weight[e.from] = weight[e.from] + e.n
  end
  local rank, queue = {}, {}
  local function from(k)
    rank[k] = 0
    queue[#queue + 1] = k
  end
  for _, u in ipairs(units) do
    if ins[u.key] == 0 and #out[u.key] > 0 then
      from(u.key)
    end
  end
  local i = 1
  while true do
    while i <= #queue do
      local k = queue[i]
      i = i + 1
      for _, t in ipairs(out[k]) do
        if not rank[t] then
          rank[t] = rank[k] + 1
          queue[#queue + 1] = t
        end
      end
    end
    -- what no start reaches: from the one of it calling out most
    local best
    for _, u in ipairs(units) do
      if not rank[u.key] and #out[u.key] > 0 and (not best or weight[u.key] > weight[best]) then
        best = u.key
      end
    end
    if not best then
      break
    end
    from(best)
  end
  local last = 0
  for _, u in ipairs(units) do
    if #out[u.key] > 0 then
      last = math.max(last, rank[u.key] or 0)
    end
  end
  for _, u in ipairs(units) do
    if #out[u.key] == 0 then
      rank[u.key] = ins[u.key] > 0 and last + 1 or 0
    end
  end
  return rank
end

-- only the MAX units with the most calls, and the arrows between them
local function cut(units, edges)
  if #units <= M.MAX then
    return units, edges, nil
  end
  local weight = {}
  for _, e in ipairs(edges) do
    weight[e.from] = (weight[e.from] or 0) + e.n
    weight[e.to] = (weight[e.to] or 0) + e.n
  end
  local order = {}
  for i, u in ipairs(units) do
    order[i] = { u = u, i = i, w = weight[u.key] or 0 }
  end
  table.sort(order, function(a, b)
    return a.w > b.w or (a.w == b.w and a.i < b.i)
  end)
  local keep = {}
  for i = 1, M.MAX do
    keep[order[i].u.key] = true
  end
  return vim.tbl_filter(function(u)
    return keep[u.key]
  end, units),
    vim.tbl_filter(function(e)
      return keep[e.from] and keep[e.to]
    end, edges),
    #units - M.MAX
end

--- The rows of a folder's folders.
---@param units seam.MapUnit[]
---@param edges seam.MapEdge[]
---@param o { width: integer, word: { [1]: string, [2]: string } }
---@return table[]
function M.draw(units, edges, o)
  edges = vim.tbl_filter(function(e)
    return e.from ~= e.to
  end, edges)
  local left_out
  units, edges, left_out = cut(units, edges)
  local rank = M.ranks(units, edges)
  local cols, at = {}, {}
  local ncol = 0
  for _, u in ipairs(units) do
    ncol = math.max(ncol, rank[u.key] + 1)
  end
  for c = 1, ncol do
    cols[c] = {}
  end
  for i, u in ipairs(units) do
    local c = rank[u.key] + 1
    table.insert(cols[c], u)
    at[u.key] = { u = u, col = c, i = i, lrows = {}, rrows = {} }
  end
  -- within a rank, by where the units calling them stand
  for c = 2, ncol do
    local pos = {}
    for j, u in ipairs(cols[c - 1]) do
      pos[u.key] = j
    end
    for _, u in ipairs(cols[c]) do
      local s, n = 0, 0
      for _, e in ipairs(edges) do
        if e.to == u.key and pos[e.from] then
          s, n = s + pos[e.from], n + 1
        end
      end
      at[u.key].b = n > 0 and s / n or math.huge
    end
    table.sort(cols[c], function(a, b)
      local ba, bb = at[a.key].b, at[b.key].b
      return ba < bb or (ba == bb and at[a.key].i < at[b.key].i)
    end)
  end
  local function lab(n)
    return ' ' .. n .. ' ' .. (n == 1 and o.word[1] or o.word[2]) .. ' '
  end
  -- each gap: the labels of the arrows turning within the rank before it,
  -- its verticals, the labels of the arrows entering the rank after it
  local slots, inlab, turnlab = {}, {}, {}
  for g = 1, ncol + 1 do
    slots[g], inlab[g], turnlab[g] = 0, 0, 0
  end
  local tops, bottoms = 0, 0
  -- a gap's verticals, those with lines only to their left first and only
  -- to their right last, so a line leaving a box never runs along one
  -- entering a box on the same row
  local wants = {}
  for g = 1, ncol + 1 do
    wants[g] = {}
  end
  local function take(g, e, field, side)
    table.insert(wants[g], { e = e, field = field, side = side })
  end
  for _, e in ipairs(edges) do
    local a, b = at[e.from], at[e.to]
    e.gx, e.ge = a.col + 1, b.col
    table.insert(a.rrows, e)
    if b.col == a.col then
      e.turn = true
      take(e.gx, e, 's1', 1)
      table.insert(b.rrows, { into = e })
      turnlab[e.gx] = math.max(turnlab[e.gx], W(lab(e.n)))
    else
      table.insert(b.lrows, e)
      inlab[e.ge] = math.max(inlab[e.ge], W(lab(e.n)))
      if b.col ~= a.col + 1 then
        take(e.gx, e, 's1', 1)
        take(e.ge, e, 's2', 3)
        if b.col < a.col then
          bottoms = bottoms + 1
          e.track = -bottoms
        else
          tops = tops + 1
          e.track = tops
        end
      else
        take(e.gx, e, 's1', 2)
      end
    end
  end
  for g = 1, ncol + 1 do
    local list = wants[g]
    for i, w in ipairs(list) do
      w.i = i
    end
    table.sort(list, function(p, q)
      return p.side < q.side or (p.side == q.side and p.i < q.i)
    end)
    for i, w in ipairs(list) do
      w.e[w.field] = i
    end
    slots[g] = #list
  end
  -- across: each gap, then its rank's boxes
  local gx, bw, sx = {}, {}, {}
  local x = 0
  for g = 1, ncol + 1 do
    gx[g] = x
    sx[g] = x + (turnlab[g] > 0 and turnlab[g] + 1 or 0)
    x = sx[g] + (slots[g] > 0 and 2 + 2 * slots[g] or 0)
    if g <= ncol then
      x = x + (inlab[g] > 0 and inlab[g] + 3 or (x > gx[g] and 2 or 0))
      local wmax = 18
      for _, u in ipairs(cols[g]) do
        wmax = math.max(wmax, W(u.label) + 8, W(u.sub or '') + 6)
      end
      bw[g] = wmax
      for _, u in ipairs(cols[g]) do
        at[u.key].x = x
      end
      x = x + wmax
    end
  end
  -- down: the tracks over the top, the boxes centred in their ranks, the tracks under
  local function height(u)
    local a = at[u.key]
    return 2 + math.max(2, #a.lrows, #a.rrows)
  end
  local function col_h(c)
    local h = -3
    for _, u in ipairs(cols[c]) do
      h = h + height(u) + 3
    end
    return h
  end
  local hmax = 0
  for c = 1, ncol do
    hmax = math.max(hmax, col_h(c))
  end
  local top = tops > 0 and tops + 1 or 0
  for c = 1, ncol do
    local y = top + math.floor((hmax - col_h(c)) / 2)
    for _, u in ipairs(cols[c]) do
      at[u.key].y, at[u.key].h = y, height(u)
      y = y + height(u) + 3
    end
  end
  local bottom = top + hmax + 1
  -- the row each arrow leaves and enters by, in the order of the other end
  local function other(r, side)
    local e = r.into or r
    return at[(side == 'l' or r.into) and e.from or e.to]
  end
  for _, a in pairs(at) do
    for _, side in ipairs { 'l', 'r' } do
      local list = a[side .. 'rows']
      table.sort(list, function(p, q)
        local pa, qa = other(p, side), other(q, side)
        return pa.y < qa.y or (pa.y == qa.y and pa.x < qa.x)
      end)
      for j, r in ipairs(list) do
        if side == 'l' then
          r.ey = a.y + j
        elseif r.into then
          r.into.ey = a.y + j
        else
          r.ry = a.y + j
        end
      end
    end
  end
  local cv = canvas.new(o.width)
  for _, u in ipairs(units) do
    local a = at[u.key]
    cv:box(a.x, a.y, bw[a.col], a.h)
    cv:put(a.x + 2, a.y + 1, u.label, 'SeamBold', u.hit)
    if u.sub then
      cv:put(a.x + 2, a.y + 2, u.sub, 'SeamLabel')
    end
  end
  local function slot(g, s)
    return sx[g] + 2 * s
  end
  for _, e in ipairs(edges) do
    local a, b = at[e.from], at[e.to]
    local right = a.x + bw[a.col] - 1
    local v1 = slot(e.gx, e.s1)
    cv:h(right, v1, e.ry)
    if e.turn then
      cv:v(v1, e.ry, e.ey)
      local br = b.x + bw[b.col] - 1
      cv:h(br + 2, v1, e.ey)
      cv:put(br + 1, e.ey, '◀', 'SeamMapLine')
      cv:put(right + 1, e.ry, lab(e.n), 'SeamMapCount')
    else
      local v2 = v1
      if e.track then
        local ty = e.track > 0 and (e.track - 1) or (bottom - e.track - 1)
        v2 = slot(e.ge, e.s2)
        cv:v(v1, e.ry, ty)
        cv:h(v1, v2, ty)
        cv:v(v2, ty, e.ey)
      else
        cv:v(v1, e.ry, e.ey)
      end
      cv:h(v2, b.x - 2, e.ey)
      cv:put(b.x - 1, e.ey, '▶', 'SeamMapLine')
      local lx = sx[e.ge] + (slots[e.ge] > 0 and 2 + 2 * slots[e.ge] or 0) + 1
      cv:put(lx, e.ey, lab(e.n), 'SeamMapCount')
    end
  end
  local rows = cv:rows(1)
  if left_out then
    rows[#rows + 1] = draw.row()
    rows[#rows + 1] = draw.row():add(' ⋯ ' .. left_out .. ' more with fewer calls, not drawn', 'SeamLabel')
  end
  return rows
end

return M
