-- The Map's keys in the pane: l opens a branch of its tree a level
-- deeper, or its ⋯ more, or shows a name elsewhere in the tree; h closes a
-- branch; > < a level more or less; T inputs and outputs; J the code
-- screen on the name. What is under the cursor, for them and the status line.
local api = vim.api
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local index = require 'seam.index'
local map_view = require 'seam.views.map'
local st = require 'seam.state'
local M = {}

local subject = map_view.subject

-- the Map shown in the pane: its row and display, nil when the pane shows another view
local function shown()
  local pane = require 'seam.pane'
  local x = pane.subject()
  local v, d = require('seam.views').shown(x, st.view)
  if v and v.name == 'Map' and pane.wins() then
    return subject(x), d
  end
end
M.shown = shown

--- What the name under the pane's cursor stands for on the Map: a row's
--- `meta.map`, or the thing a drawing's cell stood for, the nearest on its line.
---@return table|nil
function M.under()
  local pane = require 'seam.pane'
  local w = pane.wins()
  if not (w and shown()) then
    return nil
  end
  local cur = api.nvim_win_get_cursor(w.pane)
  local meta = draw.meta(api.nvim_win_get_buf(w.pane), cur[1])
  if meta.map then
    return meta.map
  end
  local best, dist
  for _, h in ipairs(meta.hits or {}) do
    local d = cur[2] < h.s and h.s - cur[2] or cur[2] >= h.e and cur[2] - h.e + 1 or 0
    if not dist or d < dist then
      best, dist = h.item, d
    end
  end
  return best
end

--- The name under the cursor as the status line says it.
---@return string|nil
function M.under_name()
  local it = M.under()
  local m = index.model()
  if not it then
    return nil
  elseif it.id and m.graph.nodes[it.id] then
    return data.label(m.graph.nodes[it.id]) .. '()'
  elseif it.kind == 'type' then
    return it.name
  elseif it.path then
    return it.path:match '[^/]+$' .. (it.kind == 'dir' and '/' or '')
  end
end

-- does the display draw functions that T gives columns to?
local function typed_display(x, d)
  return (d == 'tree' and x.kind ~= 'type') or (d == 'both ways' and (x.kind == 'fn' or x.kind == 'type'))
end

--- What each of the Map's keys would do where the pane's cursor is, nil where nothing.
---@return { l: string|nil, h: boolean, levels: boolean, T: boolean, J: table|nil }
function M.acts()
  local x, d = shown()
  local out = { h = false, levels = false, T = false }
  if not x then
    return out
  end
  local m = index.model()
  out.levels = d == 'tree'
  out.T = m.sigs ~= nil and typed_display(x, d)
  local it = M.under()
  if not it then
    return out
  end
  if d == 'tree' and x.kind ~= 'type' then
    local s = map_view.state(x)
    out.l, out.h = require('seam.map.tree').can(it, s)
  elseif it.more then
    out.l = 'more'
  elseif it.box then
    out.l, out.h = it.can and 'open' or nil, it.shown == true
  elseif it.kind == 'fn' or it.kind == 'file' or (it.kind == 'dir' and it.path) or (it.kind == 'type' and m.flows[it.name]) then
    out.l = 'show'
  end
  if it.id and m.graph.nodes[it.id] and m.graph.nodes[it.id].kind ~= 'module' then
    out.J = { kind = 'fn', id = it.id }
  elseif it.kind == 'file' and it.path then
    out.J = { kind = 'file', path = it.path }
  end
  return out
end

-- the row the thing under the cursor has in the tree, shown there
local function show_in_tree(it)
  local scr = require 'seam.screen_tree'
  if st.screen ~= 'tree' then
    return
  end
  if it.kind == 'type' then
    scr.show_type(it.name, 'Map')
  else
    scr.reveal(it.id or it.path)
  end
end

--- A Map key, `l` `h` `>` `<` `T` or `J`, where the pane's cursor is: true when it acted.
---@param k string
---@return boolean
function M.key(k)
  local x, d = shown()
  if not x then
    return false
  end
  local a = M.acts()
  local s = map_view.state(x)
  local it = M.under() or {}
  if k == 'l' and a.l == 'more' then
    s.more[it.more] = true
  elseif k == 'l' and a.l == 'open' then
    s.open[it.branch] = true
  elseif k == 'l' and a.l == 'show' then
    show_in_tree(it)
    return true
  elseif k == 'h' and a.h then
    s.open[it.branch] = false
  elseif (k == '>' or k == '<') and a.levels then
    local n = math.max(1, math.min(map_view.MAX_LEVELS, s.levels + (k == '>' and 1 or -1)))
    if n == s.levels then
      return true
    end
    s.levels = n
    -- a level more or less everywhere at once: what l and h did is forgotten
    s.open = {}
  elseif k == 'T' and a.T then
    st.map.types = not st.map.types
  elseif k == 'J' and a.J then
    local sc = require 'seam.screen_code'
    if st.screen == 'code' then
      sc.go(a.J)
    else
      sc.open(a.J)
    end
    return true
  else
    return false
  end
  require('seam.pane').redraw()
  return true
end

--- The Map's keys that act where the pane's cursor is, for the status line's row group.
---@return (string|string[])[]
function M.hints()
  local a, out = M.acts(), {}
  if a.l then
    out[#out + 1] = a.l == 'more' and { 'l', 'more' } or a.l == 'show' and { 'l', 'show' } or 'l'
  end
  if a.h then
    out[#out + 1] = 'h'
  end
  if a.levels then
    out[#out + 1] = '> <'
  end
  if a.T then
    out[#out + 1] = 'T'
  end
  if a.J then
    out[#out + 1] = 'J'
  end
  return out
end

--- What the status line adds after the view on the Map: ` · types` with
--- T on where it acts, and in the pane the name under the cursor.
---@param inside boolean the cursor is in the pane
---@return string
function M.status(inside)
  local x, d = shown()
  if not x then
    return ''
  end
  local out = (map_view.types_on() and typed_display(x, d) and index.model().sigs) and ' · types' or ''
  local name = inside and M.under_name()
  return out .. (name and ('   › ' .. name) or '')
end

return M
