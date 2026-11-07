-- The Map's keys in the pane: l opens a group closed to fit, or shows a name
-- in the tree; h on the head of one l opened closes it again, else from a
-- type l showed back to the row; T each signature or names only, by folder; J the code screen on the name. What
-- is under the cursor, for them and the status line.
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
--- `meta.map`, or the thing a drawing's cell stood for, the nearest on its
--- line off a type in a signature.
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
    if d == 0 then
      return h.item
    end
    -- off a name the row's function, not a type in its signature
    if not h.item.sig and (not dist or d < dist) then
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
    local n = m.graph.nodes[it.id]
    return data.label(n) .. (n.kind == 'value' and '' or '()')
  elseif it.kind == 'type' or it.kind == 'value' then
    return it.name
  elseif it.path then
    return it.path:match '[^/]+$' .. (it.kind == 'dir' and '/' or '')
  elseif it.fold then
    return it.label
  end
end

-- does T act: the folder display, each signature or names only
local function typed_display(_, d)
  return d == 'folder'
end

--- What each of the Map's keys would do where the pane's cursor is, nil where nothing.
---@return { l: string|nil, h: 'close'|'back'|nil, T: boolean, J: table|nil }
function M.acts()
  local x, d = shown()
  local out = { T = false }
  if not x then
    return out
  end
  local m = index.model()
  out.T = typed_display(x, d)
  local it = M.under()
  out.h = st.screen == 'tree' and st.ptype and st.ptype.pane_at and 'back' or nil
  if not it then
    return out
  end
  if it.fold then
    out.l = 'open'
  elseif it.kind == 'fn' or it.kind == 'file' or (it.kind == 'dir' and it.path) or (it.kind == 'type' and m.flows[it.name]) then
    out.l = 'show'
  end
  out.h = it.opened and 'close' or out.h
  if it.id and m.graph.nodes[it.id] and m.graph.nodes[it.id].kind ~= 'module' then
    out.J = { kind = 'fn', id = it.id }
  elseif it.kind == 'file' and it.path then
    out.J = { kind = 'file', path = it.path }
  end
  return out
end

-- the row the thing under the cursor has in the tree, shown there; a
-- type in the pane, h going back to where the pane's cursor was
local function show_in_tree(it)
  local scr = require 'seam.screen_tree'
  if st.screen ~= 'tree' then
    return
  end
  if it.kind == 'type' then
    local at = api.nvim_win_get_cursor(require('seam.pane').wins().pane)
    if scr.show_type(it.name, 'Map') then
      st.ptype.pane_at = at
    end
  else
    scr.reveal(it.id or it.path)
  end
end

-- the pane's cursor on the piece standing for `field` = `key` after a
-- redraw, which moves a group when both ways centre on the row
local function cursor_to(field, key)
  local w = require('seam.pane').wins()
  local buf = api.nvim_win_get_buf(w.pane)
  for l = 1, api.nvim_buf_line_count(buf) do
    for _, h in ipairs(draw.meta(buf, l).hits or {}) do
      if h.item[field] == key then
        api.nvim_win_set_cursor(w.pane, { l, h.s })
        return
      end
    end
  end
end

--- A Map key, `l` `h` `T` or `J`, where the pane's cursor is: true when it acted.
---@param k string
---@return boolean
function M.key(k)
  local x = shown()
  if not x then
    return false
  end
  local a = M.acts()
  local s = map_view.state(x)
  local it = M.under() or {}
  if k == 'l' and a.l == 'open' then
    s.open[it.fold] = true
    require('seam.pane').redraw()
    cursor_to('opened', it.fold)
    return true
  elseif k == 'h' and a.h == 'close' then
    s.open[it.opened] = nil
    require('seam.pane').redraw()
    cursor_to('fold', it.opened)
    return true
  elseif k == 'h' and a.h == 'back' then
    local at = st.ptype.pane_at
    require('seam.screen_tree').back()
    local w = require('seam.pane').wins()
    pcall(api.nvim_win_set_cursor, w.pane, at)
    return true
  elseif k == 'l' and a.l == 'show' then
    show_in_tree(it)
    return true
  elseif k == 'T' and a.T then
    st.map.types = not map_view.types_on()
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
    out[#out + 1] = a.l == 'open' and { 'l', 'open' } or { 'l', 'show' }
  end
  if a.h then
    out[#out + 1] = { 'h', a.h }
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
  local out = (map_view.types_on() and typed_display(x, d)) and ' · types' or ''
  local name = inside and M.under_name()
  return out .. (name and ('   › ' .. name) or '')
end

return M
