-- The Map, driven through its keys, from tests/check.lua: on a function,
-- its file, its folder and a type, reached with gm, each of its displays on
-- <C-Tab>, the head listing them, no row wider than the pane; T on the
-- folder display, each signature or names only.
local api = vim.api
local data = require 'seam.map.data'
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
    local first = map_view.DISPLAYS[1]
    st.view.display.Map = first
    pane.redraw()
    if shown() ~= first then
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
    if shown() ~= first then
      fail(what .. ': <C-Tab> did not come back to ' .. first)
    end
  end
  -- the function, and T on its folder display: names only, and back
  tree_screen.show(f.id)
  displays('function ' .. f.name)
  t.where 'map T'
  tree_win()
  st.view.display.Map = 'folder'
  pane.redraw()
  local before = table.concat(lines(), '\n')
  key 'T'
  if map_view.types_on() or table.concat(lines(), '\n') == before then
    fail 'T did not take the signatures away'
  end
  key 'T'
  if not map_view.types_on() or table.concat(lines(), '\n') ~= before then
    fail 'T again did not give the signatures back'
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

  -- the type
  if ty then
    tree_win()
    tree_screen.show_type(ty, 'Map')
    displays('type ' .. ty)
    tree_win()
    key 'j'
    key 'k'
  end
  st.view.at, st.view.aside = 'Code', nil
  tree_win()
  pane.redraw()
end
