-- The Map's folders display on a folder, top to bottom: its folders (else
-- its files) as boxes in bands, each band after everything its boxes call,
-- what calls nothing here first, so what is used stands above what uses
-- it and the arrows between the bands point up at it. Each box lists what
-- it calls in the folder and how often, so no line has to cross the
-- picture. Pure: rows with what each box and name stands for in
-- `meta.hits`.
local canvas = require 'seam.map.canvas'
local M = {}

local W = vim.api.nvim_strwidth

---@class seam.MapUnit
---@field key string
---@field label string
---@field sub string|nil said dim beside its name
---@field hit table|nil what it stands for

---@class seam.MapEdge
---@field from string a unit's key
---@field to string
---@field n integer

--- Each unit's band: 0 when it calls nothing here, else one after the
--- furthest of what it calls; a call back round a cycle is not counted.
---@param units seam.MapUnit[]
---@param edges seam.MapEdge[]
---@return table<string, integer>
function M.bands(units, edges)
  local out = {}
  for _, e in ipairs(edges) do
    out[e.from] = out[e.from] or {}
    table.insert(out[e.from], e.to)
  end
  local band, on = {}, {}
  local function height(k)
    if band[k] then
      return band[k]
    end
    on[k] = true
    local h = 0
    for _, t in ipairs(out[k] or {}) do
      if not on[t] then
        h = math.max(h, height(t) + 1)
      end
    end
    on[k] = nil
    band[k] = h
    return h
  end
  for _, u in ipairs(units) do
    height(u.key)
  end
  return band
end

local function count(n, word)
  return n .. ' ' .. (n == 1 and word[1] or word[2])
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
  local band = M.bands(units, edges)
  local by, calls = {}, {}
  for _, u in ipairs(units) do
    by[u.key] = u
    calls[u.key] = {}
  end
  for _, e in ipairs(edges) do
    table.insert(calls[e.from], e)
  end
  local top = 0
  for _, u in ipairs(units) do
    top = math.max(top, band[u.key])
    table.sort(calls[u.key], function(a, b)
      return a.n > b.n or (a.n == b.n and by[a.to].label < by[b.to].label)
    end)
  end
  -- each box: its name and sub in the top border, a line a unit it calls
  local NONE = 'calls nothing here'
  local function laid(u)
    local list = calls[u.key]
    local lw, cw = 0, 0
    for _, e in ipairs(list) do
      lw, cw = math.max(lw, W(by[e.to].label)), math.max(cw, W(count(e.n, o.word)))
    end
    local inner = #list > 0 and lw + 2 + cw or W(NONE)
    local title = W(u.label) + (u.sub and W(u.sub) + 2 or 0)
    return { w = math.max(inner + 4, title + 6), h = math.max(#list, 1) + 2, lw = lw }
  end
  local cv = canvas.new(o.width)
  local y, tx = 0, 6
  for b = 0, top do
    local here = vim.tbl_filter(function(u)
      return band[u.key] == b
    end, units)
    if #here > 0 then
      if y > 0 then
        cv:put(tx, y, '▲', 'SeamMapLine')
        cv:put(tx, y + 1, '│', 'SeamMapLine')
        y = y + 2
      end
      local x, h = 0, 0
      for _, u in ipairs(here) do
        local L = laid(u)
        if x > 0 and x + L.w > o.width then
          y, x, h = y + h + 1, 0, 0
        end
        cv:box(x, y, L.w, L.h)
        local at = cv:put(x + 2, y, ' ' .. u.label .. ' ', 'SeamBold', u.hit)
        if u.sub then
          cv:put(at, y, u.sub .. ' ', 'SeamLabel')
        end
        if #calls[u.key] == 0 then
          cv:put(x + 2, y + 1, NONE, 'SeamLabel')
        end
        for j, e in ipairs(calls[u.key]) do
          local t = by[e.to]
          cv:put(x + 2, y + j, t.label, 'SeamText', t.hit)
          cv:put(x + 4 + L.lw, y + j, count(e.n, o.word), 'SeamMapCount')
        end
        x, h = x + L.w + 2, math.max(h, L.h)
      end
      y = y + h
    end
  end
  return cv:rows(1)
end

return M
