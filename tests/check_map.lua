-- The Map, driven through its keys, from tests/check.lua: on a function,
-- its file, its folder and a type, reached with gm, each of its displays on
-- <S-Tab>, the head listing them, no row cut, the pane unwrapped; T on the
-- folder display, each signature or names only; on the folder, its groups
-- closed to fit a small room and l opening one.
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
  -- every display on <S-Tab> from the tree, back to the first
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
    for i, d in ipairs(map_view.DISPLAYS) do
      if shown() ~= d then
        fail(('%s: display %d is %s, not %s'):format(what, i, tostring(shown()), d))
      end
      local ls = lines()
      if #ls < 2 then
        fail(('%s %s: %d rows'):format(what, d, #ls))
      end
      -- nothing cut: a row past the pane goes on right, unwrapped
      if vim.wo[st.owin.pane].wrap then
        fail(('%s %s: the pane wraps the Map'):format(what, d))
      end
      for j, l in ipairs(ls) do
        if l:match '…$' then
          fail(('%s %s: row %d is cut: %s'):format(what, d, j, l))
          break
        end
      end
      local head = table.concat(api.nvim_buf_get_lines(st.obuf.phead, 0, -1, false), ' ')
      if not head:find(table.concat(map_view.DISPLAYS, ' · '), 1, true) then
        fail(('%s %s: the head does not list the displays: %s'):format(what, d, head))
      end
      key '<S-Tab>'
    end
    if shown() ~= first then
      fail(what .. ': <S-Tab> did not come back to ' .. first)
    end
  end
  -- a side taller than its room: its smallest groups closed to a line, ▸,
  -- each named; l on one opens it, and it stays open for the row. The room
  -- made small by the foot's share
  local function folds(what)
    t.where('map folds ' .. what)
    local foot = require 'seam.map.foot'
    local share = foot.SHARE
    foot.SHARE = 0.95
    for _, d in ipairs { 'folder', 'type' } do
      tree_win()
      st.view.display.Map = d
      pane.redraw()
      local function closed()
        local n, at, name = 0, nil, nil
        for i, l in ipairs(lines()) do
          local s = l:find('▸ ', 1, true)
          if s then
            n = n + 1
            if not at then
              at, name = { i, s + 3 }, l:sub(s + 4):match '^(%S+)'
            end
          end
        end
        return n, at, name
      end
      local n, at, name = closed()
      if n > 0 then
        api.nvim_set_current_win(st.owin.pane)
        api.nvim_win_set_cursor(st.owin.pane, at)
        key 'l'
        local after = closed()
        local shown_open = false
        for _, l in ipairs(lines()) do
          if l:find(name, 1, true) and not l:find('▸ ' .. name, 1, true) then
            shown_open = true
          end
        end
        if after ~= n - 1 or not shown_open then
          fail(('%s %s: l on ▸ %s did not open it (%d closed, then %d)'):format(what, d, name, n, after))
        end
        tree_win()
        key 'j'
        key 'k'
        if closed() ~= after then
          fail(('%s %s: %s did not stay open for the row'):format(what, d, name))
        end
      end
    end
    foot.SHARE = share
    st.view.display.Map = map_view.DISPLAYS[1]
    pane.redraw()
  end

  -- the function, and T on its folder display: each signature, and back
  tree_screen.show(f.id)
  displays('function ' .. f.name)
  t.where 'map T'
  tree_win()
  st.view.display.Map = 'folder'
  pane.redraw()
  local before = table.concat(lines(), '\n')
  key 'T'
  if not map_view.types_on() or table.concat(lines(), '\n') == before then
    fail 'T did not give the signatures'
  end
  key 'T'
  if map_view.types_on() or table.concat(lines(), '\n') ~= before then
    fail 'T again did not take the signatures away'
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
        folds('folder ' .. st.orows[j].key)
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
