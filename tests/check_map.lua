-- The Map, driven through its keys, from tests/check.lua: on a function,
-- its file, its folder and a type, reached with gm, each of the four displays on <C-Tab>,
-- the head listing them, no row wider than the pane; on the tree > and <,
-- l and h on a branch, T; on a type's tree + and - on a box.
local api = vim.api
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local map_view = require 'seam.views.map'
local pane = require 'seam.pane'
local tree_screen = require 'seam.screen_tree'
local views = require 'seam.views'

---@param t { key: fun(k: string), fail: fun(msg: string), where: fun(w: string), st: table }
return function(t)
  local key, fail, st = t.key, t.fail, t.st
  local m = st.models[st.cur]
  local g = m.graph
  t.where 'map setup'
  -- the function calling the most functions that call on
  local f, fn_n
  for id, n in pairs(g and g.nodes or {}) do
    if n.kind == 'function' and not n.test then
      local k = 0
      for _, c in ipairs(data.calls(m, id)) do
        if #data.calls(m, c) > 0 then
          k = k + 1
        end
      end
      if k > 0 and (not f or k > fn_n or (k == fn_n and id < f.id)) then
        f, fn_n = n, k
      end
    end
  end
  if not f then
    return fail 'no function that calls a function calling on'
  end
  -- the type made and taken by the most
  local ty, ty_n
  for name in pairs(m.flows or {}) do
    local mk, tk = data.flow(m, name)
    if #mk > 0 and #tk > 0 and (not ty or #mk + #tk > ty_n or (#mk + #tk == ty_n and name < ty)) then
      ty, ty_n = name, #mk + #tk
    end
  end

  local function lines()
    return api.nvim_buf_get_lines(st.obuf.pane, 0, -1, false)
  end
  local function shown()
    local v, d = views.shown(pane.subject(), st.view)
    return v and v.name == 'Map' and d
  end
  local function tree_win()
    api.nvim_set_current_win(st.owin.tree)
  end
  -- every display on <C-Tab> from the tree, back to the first
  local function displays(what)
    t.where('map displays ' .. what)
    tree_win()
    -- gm from the tree, the Map aside
    if (views.shown(pane.subject(), st.view) or {}).name ~= 'Map' then
      key 'gm'
    end
    st.view.display.Map = 'tree'
    pane.redraw()
    if shown() ~= 'tree' then
      return fail('the Map is not shown on ' .. what)
    end
    local width = api.nvim_win_get_width(st.owin.pane)
    for i, d in ipairs(map_view.DISPLAYS) do
      if shown() ~= d then
        fail(('%s: display %d is %s, not %s'):format(what, i, tostring(shown()), d))
      end
      local ls = lines()
      if #ls < 2 then
        fail(('%s %s: %d rows'):format(what, d, #ls))
      end
      for j, l in ipairs(ls) do
        if vim.fn.strdisplaywidth(l) > width then
          fail(('%s %s: row %d is wider than the pane, %d > %d: %s'):format(what, d, j, vim.fn.strdisplaywidth(l), width, l))
          break
        end
      end
      local head = table.concat(api.nvim_buf_get_lines(st.obuf.phead, 0, -1, false), ' ')
      if not head:find(table.concat(map_view.DISPLAYS, ' · '), 1, true) then
        fail(('%s %s: the head does not list the displays: %s'):format(what, d, head))
      end
      key '<C-Tab>'
    end
    if shown() ~= 'tree' then
      fail(what .. ': <C-Tab> did not come back to the tree')
    end
  end
  -- the pane's cursor on the first row `pred` takes
  local function pane_on(pred)
    for i = 1, api.nvim_buf_line_count(st.obuf.pane) do
      local col = pred(draw.meta(st.obuf.pane, i), i)
      if col then
        api.nvim_set_current_win(st.owin.pane)
        api.nvim_win_set_cursor(st.owin.pane, { i, col == true and 0 or col })
        return true
      end
    end
  end

  -- the function: its tree a level deeper and back, a branch opened and closed, T
  tree_screen.show(f.id)
  displays('function ' .. f.name)
  t.where 'map levels'
  local s = map_view.state(pane.subject())
  local two = #lines()
  key '>'
  if s.levels ~= map_view.LEVELS + 1 or #lines() < two then
    fail(('> did not add a level: %d levels, %d rows from %d'):format(s.levels, #lines(), two))
  end
  key '<lt>'
  if s.levels ~= map_view.LEVELS or #lines() ~= two then
    fail(('< did not take the level away: %d levels, %d rows, not %d'):format(s.levels, #lines(), two))
  end
  t.where 'map branches'
  local mt = require 'seam.map.tree'
  if not pane_on(function(meta)
    return meta.map and mt.can(meta.map, s) == 'open'
  end) then
    fail('no branch of ' .. f.name .. "'s tree opens")
  else
    key 'l'
    if #lines() <= two then
      fail 'l did not open the branch'
    end
    key 'h'
    if #lines() ~= two then
      fail(('h did not close the branch: %d rows, not %d'):format(#lines(), two))
    end
  end
  if m.sigs then
    t.where 'map types'
    tree_win()
    local before = table.concat(lines(), '\n')
    key 'T'
    if not st.map.types or table.concat(lines(), '\n') == before then
      fail 'T did not give the functions their types'
    end
    key 'T'
    if st.map.types or table.concat(lines(), '\n') ~= before then
      fail 'T again did not take the types away'
    end
  end

  -- its file, and the folder above it
  tree_screen.reveal(f.path)
  if (tree_screen.at() or {}).kind ~= 'file' then
    fail('reveal did not put the cursor on ' .. f.path)
  else
    displays('file ' .. f.path)
    local _, i = tree_screen.at()
    local depth = st.orows[i].depth
    for j = i - 1, 1, -1 do
      if st.orows[j].kind == 'dir' and st.orows[j].depth < depth then
        api.nvim_win_set_cursor(st.owin.tree, { j, 0 })
        key 'j'
        key 'k'
        displays('folder ' .. st.orows[j].key)
        break
      end
    end
  end

  -- the type: its boxes, + on one opens its declaration under it, - closes it
  if ty then
    tree_win()
    tree_screen.show_type(ty, 'Map')
    displays('type ' .. ty)
    t.where 'map type box'
    local n = #lines()
    if
      not pane_on(function(meta)
        for _, b in ipairs(meta.tv and meta.tv.names or {}) do
          if b.name == ty then
            return b.s
          end
        end
      end)
    then
      fail('no box of ' .. ty .. ' to open')
    else
      key '+'
      local decl = m.flows[ty].decls[1]
      local first = vim.trim(require('seam.code').file(decl.path).lines[decl.line] or '')
      if #lines() <= n or not table.concat(lines(), '\n'):find(first, 1, true) then
        fail(('+ on the box did not open %s under it: %s:%d %q'):format(ty, decl.path, decl.line, first))
      end
      pane_on(function(meta)
        for _, b in ipairs(meta.tv and meta.tv.names or {}) do
          if b.name == ty then
            return b.s
          end
        end
      end)
      key '-'
      if #lines() ~= n then
        fail(('- did not close the declaration: %d rows, not %d'):format(#lines(), n))
      end
    end
    tree_win()
    key 'j'
    key 'k'
  end
  st.view.at, st.view.aside = 'Code', nil
  tree_win()
  pane.redraw()
end
