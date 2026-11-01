-- The Map view: four displays on every kind of row, tree, both ways,
-- folders and size (seam.map.*), drawn from the call graph and the types;
-- the levels, the branches opened with l h and T kept per row in st.map;
-- the keys that act on it, l h > < T J, and what is under the cursor.
local api = vim.api
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local types_view = require 'seam.views.types'
local M = {}

M.DISPLAYS = { 'tree', 'both ways', 'folders', 'size' }
M.LEVELS, M.MAX_LEVELS = 2, 8

local row = draw.row

---------------------------------------------------------------- the row

-- a name in the code through its type
local function subject(x)
  return x and x.kind == 'name' and x.as_type or x
end

--- Has the Map something for the row?
---@param m table
---@param x seam.ORow|nil
---@return boolean
function M.has(m, x)
  x = subject(x)
  if not (x and m and m.graph) then
    return false
  end
  if x.kind == 'type' then
    return m.flows ~= nil and m.flows[x.name] ~= nil
  end
  return x.kind == 'fn' or x.kind == 'file' or x.kind == 'dir'
end

local function dir_of(x)
  return outline.full(x.item)
end

local function dir_label(x)
  return (x.item.segs and table.concat(x.item.segs, '/') or dir_of(x):match '[^/]+$') .. '/'
end

--- What the Map keeps for a row: its levels, the branches opened and their ⋯ more.
---@param x seam.ORow
---@return { levels: integer, open: table<string, boolean>, more: table<string, boolean> }
function M.state(x)
  st.map = st.map or { rows = {}, types = false }
  local k = subject(x).key or ''
  st.map.rows[k] = st.map.rows[k] or { levels = M.LEVELS, open = {}, more = {} }
  return st.map.rows[k]
end

--- Is T on?
---@return boolean
function M.types_on()
  return st.map ~= nil and st.map.types == true
end

---------------------------------------------------------------- facts

-- the node ids `list` as the both ways' and the folders' crossings
local function as_cross(m, list)
  return vim.tbl_map(function(id)
    local n = m.graph.nodes[id]
    return { path = n.path, id = id, name = data.label(n) }
  end, list)
end

-- what a function takes and gives as the Map writes them: an object `{ … }`
local function sig_text(C, id)
  local f = types_view.fn_of(C, id, 'map:' .. id)
  if not f then
    return nil
  end
  local parts = {}
  for i, p in ipairs(f.sig.params) do
    local t = p.type and tv.bound(tv.simple(p.type), f.sig.tparams) or p.name
    parts[i] = t:sub(1, 1) == '{' and '{ … }' or t
  end
  local gives = f.gives
  if gives:sub(1, 1) == '{' and #gives > 30 then
    gives = '{ … }'
  end
  return table.concat(parts, ', '), gives
end

-- text as pieces coloured as a signature is: types, builtins, the rest
local BUILTIN = { string = 1, number = 1, boolean = 1, unknown = 1, void = 1, never = 1, any = 1, undefined = 1, null = 1 }
local function tsegs(text)
  local out, i = {}, 1
  for a, w, b in text:gmatch '()([%a_$][%w_$]*)()' do
    if a > i then
      out[#out + 1] = { text:sub(i, a - 1), 'SeamText' }
    end
    out[#out + 1] = { w, BUILTIN[w] and '@type.builtin' or w:match '^%u' and 'SeamType' or 'SeamText' }
    i = b
  end
  if i <= #text then
    out[#out + 1] = { text:sub(i), 'SeamText' }
  end
  return out
end

local function cat(...)
  local out = {}
  for _, l in ipairs { ... } do
    vim.list_extend(out, l)
  end
  return out
end

-- the files across an edge, the most names first: `{ path, names }`
local function files_across(m, list, side)
  local out, at = {}, {}
  for _, e in ipairs(list) do
    local p = m.graph.nodes[e[side == 'left' and 'from' or 'to']].path
    local name = data.label(m.graph.nodes[e.to])
    local f = at[p]
    if not f then
      f = { path = p, names = {}, seen = {}, i = #out + 1 }
      at[p] = f
      out[#out + 1] = f
    end
    if not f.seen[name] then
      f.seen[name] = true
      f.names[#f.names + 1] = name
    end
  end
  table.sort(out, function(a, b)
    return #a.names > #b.names or (#a.names == #b.names and a.i < b.i)
  end)
  return out
end

---------------------------------------------------------------- the displays

local function tree_display(x, m, ctx, C)
  local s = M.state(x)
  local o = { levels = s.levels, open = s.open, more = s.more, width = ctx.width - 2 }
  if x.kind == 'type' then
    o.opened = function(name)
      return tv.is_open(ctx.open, nil, 'map|box:' .. name)
    end
    return require('seam.map.typegraph').draw(m, x.name, o)
  end
  local mt = require 'seam.map.tree'
  if M.types_on() and m.sigs then
    o.types = function(id)
      return sig_text(C, id)
    end
    o.paint = function(r, text)
      r.meta.tvn = r.meta.tvn or {}
      types_view.typed(r, text, C.known, r.meta.tvn)
    end
  end
  local root = x.kind == 'fn' and mt.fn(m, x.id) or x.kind == 'file' and mt.file(m, x.path) or mt.dir(m, dir_of(x), dir_label(x))
  local rows = mt.draw(root, o)
  if #rows == 1 then
    rows[2] = row():add('   ' .. (x.kind == 'fn' and 'it calls nothing' or 'it calls nothing outside itself'), 'SeamLabel')
  end
  for _, r in ipairs(rows) do
    if r.meta.tvn and #r.meta.tvn > 0 then
      r.meta.tv = { key = 'm' .. (r.meta.map and r.meta.map.branch or ''), id = 'l', names = r.meta.tvn, chain = {} }
    end
  end
  return rows
end

local function both_display(x, m, ctx, C)
  local both = require 'seam.map.both'
  local s = M.state(x)
  local T = M.types_on() and m.sigs
  local left, right, centre = {}, {}, nil
  -- a function as a side writes it: with T on, what goes in left of its
  -- name and what comes out right of it; a caller with where it is
  local function fn_seg(id, side, dim, where)
    local n = m.graph.nodes[id]
    local name = { data.label(n), dim and 'SeamLabel' or 'SeamMapFn', { kind = 'fn', id = id } }
    local takes, gives
    if T then
      takes, gives = sig_text(C, id)
    end
    if side == 'left' then
      if takes then
        return cat({ { '(', 'SeamPunct' } }, tsegs(tv.cut(takes, 30)), { { ') → ', 'SeamLabel' }, name })
      end
    elseif gives then
      return cat({ name, { ' → ', 'SeamLabel' } }, tsegs(tv.cut(gives, 24)))
    end
    if where then
      return { { data.short(m, n.path, x.path or n.path) .. '  ', 'SeamDim' }, name }
    end
    return { name }
  end
  if x.kind == 'fn' then
    local callers, tests = data.callers(m, x.id)
    for _, id in ipairs(data.calls(m, x.id)) do
      left[#left + 1] = fn_seg(id, 'left')
    end
    for _, id in ipairs(callers) do
      right[#right + 1] = fn_seg(id, 'right', false, true)
    end
    for _, id in ipairs(tests) do
      right[#right + 1] = fn_seg(id, 'right', true, true)
    end
    centre = { { data.label(m.graph.nodes[x.id]), 'SeamMapFnBold' } }
  elseif x.kind == 'type' then
    local makers, takers = data.flow(m, x.name)
    for _, id in ipairs(makers) do
      left[#left + 1] = fn_seg(id, 'left')
    end
    for _, id in ipairs(takers) do
      right[#right + 1] = fn_seg(id, 'right')
    end
    centre = { { x.name, 'SeamTypeBold' } }
  else
    local home = x.kind == 'dir' and dir_of(x) or x.path
    local into, outs = data.crossing(m, data.within(home))
    local hp = x.kind == 'dir' and (home .. '/x') or home
    for _, f in ipairs(files_across(m, outs, 'right')) do
      left[#left + 1] =
        { { draw.trunc(table.concat(f.names, ', '), 26) .. '  ', 'SeamLabel' }, { data.short(m, f.path, hp), 'SeamName', { kind = 'file', path = f.path } } }
    end
    for _, f in ipairs(files_across(m, into, 'left')) do
      right[#right + 1] =
        { { data.short(m, f.path, hp), 'SeamName', { kind = 'file', path = f.path } }, { '  ' .. draw.trunc(table.concat(f.names, ', '), 40), 'SeamLabel' } }
    end
    centre = { { x.kind == 'dir' and dir_label(x) or data.short(m, x.path, x.path), 'SeamBold' } }
  end
  if #left == 0 and #right == 0 then
    return { row():add(' nothing calls it and it calls nothing', 'SeamLabel') }
  end
  return both.draw(both.cut(left, 'left', s.more.left), both.cut(right, 'right', s.more.right), centre, ctx.width - 2)
end

-- a folder's folders: its folders as boxes, else its files
local function folder_graph(x, m, ctx)
  local dir = dir_of(x)
  local g = m.graph
  local files = {}
  for p in pairs(outline.files(m)) do
    if p:sub(1, #dir + 1) == dir .. '/' then
      files[#files + 1] = p
    end
  end
  table.sort(files)
  local units, at, unit_of = {}, {}, {}
  local function add(key, label, hit)
    if not at[key] then
      at[key] = { key = key, label = label, hit = hit, n = 0 }
      units[#units + 1] = at[key]
    end
    at[key].n = at[key].n + 1
    return key
  end
  local by_folder = false
  for _, p in ipairs(files) do
    if p:sub(#dir + 2):find '/' then
      by_folder = true
    end
  end
  for _, p in ipairs(files) do
    local seg = p:sub(#dir + 2):match '^([^/]+)/'
    if not by_folder then
      unit_of[p] = add(p, p:match '[^/]+$', { kind = 'file', path = p })
    elseif seg then
      unit_of[p] = add(dir .. '/' .. seg, seg .. '/', { kind = 'dir', path = dir .. '/' .. seg })
    else
      unit_of[p] = add(dir, dir_label(x) .. ' files')
    end
  end
  for _, u in ipairs(units) do
    u.sub = by_folder and draw.plural(u.n, 'file') or nil
  end
  local E, edges = {}, {}
  for id, n in pairs(g.nodes) do
    local a = not n.test and unit_of[n.path]
    for _, e in ipairs(a and g.down[id] or {}) do
      local c = g.nodes[e.to]
      local b = not c.test and unit_of[c.path]
      if b and b ~= a then
        local k = a .. '\n' .. b
        if not E[k] then
          E[k] = { from = a, to = b, n = 0 }
          edges[#edges + 1] = E[k]
        end
        E[k].n = E[k].n + 1
      end
    end
  end
  table.sort(edges, function(p, q)
    return p.from < q.from or (p.from == q.from and p.to < q.to)
  end)
  if #units == 0 then
    return { row():add(' no file here', 'SeamLabel') }
  end
  return require('seam.map.fgraph').draw(units, edges, { width = ctx.width - 2, word = { 'call', 'calls' } })
end

local function folders_display(x, m, ctx)
  if x.kind == 'dir' then
    return folder_graph(x, m, ctx)
  end
  local o = { width = ctx.width - 2, top = {}, bottom = {}, word = { 'call', 'calls' }, flow = 'up' }
  local function said(n, one, more)
    return n .. ' ' .. (n == 1 and one or more)
  end
  if x.kind == 'fn' then
    local n = m.graph.nodes[x.id]
    local callers, tests = data.callers(m, x.id)
    o.top, o.bottom = as_cross(m, data.calls(m, x.id)), as_cross(m, callers)
    local tf = {}
    for _, id in ipairs(tests) do
      tf[m.graph.nodes[id].path] = true
    end
    o.tests, o.tfiles = #tests, vim.tbl_count(tf)
    o.centre, o.centre_hl, o.home = data.label(n), 'SeamMapFnBold', n.path
    o.sub = data.where(m, n.path, n.path)
  elseif x.kind == 'file' then
    local into, outs = data.crossing(m, data.within(x.path))
    o.top = as_cross(
      m,
      vim.tbl_map(function(e)
        return e.to
      end, outs)
    )
    o.bottom = as_cross(
      m,
      vim.tbl_map(function(e)
        return e.from
      end, into)
    )
    local tests, tf = 0, {}
    for _, id in ipairs(data.fns_in(m, x.path)) do
      local _, t = data.callers(m, id)
      for _, c in ipairs(t) do
        tests = tests + 1
        tf[m.graph.nodes[c].path] = true
      end
    end
    o.tests, o.tfiles = tests, vim.tbl_count(tf)
    o.centre, o.centre_hl, o.home = x.path:match '[^/]+$', 'SeamBold', x.path
    o.sub = data.where(m, x.path, x.path)
  else
    local makers, takers = data.flow(m, x.name)
    o.top, o.bottom = as_cross(m, makers), as_cross(m, takers)
    o.centre, o.centre_hl, o.home = x.name, 'SeamTypeBold', x.path
    o.word, o.flow, o.sub = { 'function', 'functions' }, 'down', x.path:match '[^/]+$'
    o.top_says, o.bottom_says = 'made by ' .. said(#makers, 'function', 'functions'), 'taken by ' .. said(#takers, 'function', 'functions')
  end
  if x.kind ~= 'type' then
    o.top_says = said(#o.top, 'call', 'calls')
    o.bottom_says = 'called from ' .. said(#o.bottom, 'function', 'functions')
  end
  return require('seam.map.folders').draw(m, o)
end

local function size_display(x, m, ctx)
  local size = require 'seam.map.size'
  local o = { width = ctx.width, items = {}, all = M.state(x).more.size }
  local function used(id)
    return #(data.callers(m, id))
  end
  if x.kind == 'fn' then
    local home = m.graph.nodes[x.id].path
    for _, id in ipairs(data.calls(m, x.id)) do
      local n = m.graph.nodes[id]
      local r = data.reach(m, id)
      o.items[#o.items + 1] = {
        label = data.label(n),
        hl = 'SeamMapFn',
        n = r,
        text = data.count(r),
        second = n.path ~= home and data.short(m, n.path, home) or nil,
        second_hl = 'SeamDim',
        map = { kind = 'fn', id = id },
      }
    end
    o.head = 'reaches'
  elseif x.kind == 'file' then
    for _, id in ipairs(data.fns_in(m, x.path)) do
      local r = data.reach(m, id)
      local n = m.graph.nodes[id]
      o.items[#o.items + 1] =
        { label = data.label(n) .. '()', hl = 'SeamMapFn', n = r, text = data.count(r), second = tostring(used(id)), map = { kind = 'fn', id = id } }
    end
    o.head, o.second = 'reaches', 'used by'
  elseif x.kind == 'dir' then
    local dir = dir_of(x)
    for p in pairs(outline.files(m)) do
      if p:sub(1, #dir + 1) == dir .. '/' then
        local fns = data.fns_in(m, p)
        local r = data.reach_of(m, fns, function(n)
          return n.path == p
        end)
        local callers = {}
        for _, id in ipairs(fns) do
          for _, c in ipairs((data.callers(m, id))) do
            if m.graph.nodes[c].path ~= p then
              callers[c] = true
            end
          end
        end
        o.items[#o.items + 1] = {
          label = p:sub(#dir + 2),
          hl = 'SeamName',
          n = r,
          text = data.count(r),
          second = tostring(vim.tbl_count(callers)),
          map = { kind = 'file', path = p },
        }
      end
    end
    o.head, o.second = 'reaches outside itself', 'used from outside'
  else
    local f = m.flows[x.name]
    local by = {}
    for _, e in ipairs(f.decls) do
      for _, u in ipairs(e.uses or {}) do
        if not index.is_test(u.path) then
          by[u.path] = (by[u.path] or 0) + 1
        end
      end
    end
    for p, n in pairs(by) do
      o.items[#o.items + 1] = { label = data.short(m, p, x.path), hl = 'SeamName', n = n, map = { kind = 'file', path = p } }
    end
    o.title = 'the files that use it, by how many times'
  end
  table.sort(o.items, function(a, b)
    return a.n > b.n or (a.n == b.n and a.label < b.label)
  end)
  if #o.items == 0 then
    return { row():add(x.kind == 'type' and ' no file uses it' or ' it calls nothing', 'SeamLabel') }
  end
  return size.draw(o)
end

--- The Map of `x` in `display`.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param display string
---@param ctx seam.ViewCtx
function M.draw(out, x, m, display, ctx)
  x = subject(x)
  local path = x.kind == 'dir' and dir_of(x) or x.path
  local C = types_view.context(m, ctx, path)
  local rows
  if display == 'both ways' then
    rows = both_display(x, m, ctx, C)
  elseif display == 'folders' then
    rows = folders_display(x, m, ctx)
  elseif display == 'size' then
    rows = size_display(x, m, ctx)
  else
    rows = tree_display(x, m, ctx, C)
  end
  -- a type opened with + under the row naming it, a box's under the drawing
  local after = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r
    local t = r.meta.tv
    if t and #t.names > 0 then
      local names, seen = {}, {}
      for _, n in ipairs(t.names) do
        if not seen[n.name] then
          seen[n.name] = true
          names[#names + 1] = n.name
        end
      end
      local items = types_view.lay(C, { { id = t.id, names = names, path = path } }, t.key, {}, {})
      table.remove(items, 1)
      if t.after then
        vim.list_extend(after, items)
      else
        types_view.render(out, C, items)
      end
    end
  end
  -- each box's declaration under the box, its line down to it
  if #after > 0 then
    local blocks = {}
    types_view.render(blocks, C, after)
    local shift = 0
    for i, r in ipairs(blocks) do
      local t = r.meta.tv
      local name = t and t.key and t.key:match '^map|box:([^|]+)'
      local b = name and rows[1].meta.boxes and rows[1].meta.boxes[name]
      if b and (r.meta.at or i == 1) then
        shift = b.x + 3
      end
      out[#out + 1] = M.shifted(r, shift, ctx.width - 1)
    end
  end
end

--- Row `r` moved `n` columns right, cut with `…` at `width` when given.
---@param r table
---@param n integer
---@param width? integer
---@return table
function M.shifted(r, n, width)
  if n > 0 then
    M.moved(r, n)
  end
  if width and r.w > width then
    local text = draw.trunc(r:text(), width)
    local keep = #text - #'…'
    r.t, r.b, r.w = { text }, #text, vim.api.nvim_strwidth(text)
    for _, c in ipairs(r.code or {}) do
      c[5] = math.max(0, math.min(c[5], keep - c[4]))
    end
    r.h[#r.h + 1] = { keep, #text, 'SeamLabel', 200 }
  end
  return r
end

--- Row `r` moved `n` columns right, its marks, code and names with it.
---@param r table
---@param n integer
---@return table
function M.moved(r, n)
  local pad = string.rep(' ', n)
  table.insert(r.t, 1, pad)
  for _, h in ipairs(r.h) do
    h[1], h[2] = h[1] + n, h[2] + n
  end
  for _, v in ipairs(r.virt or {}) do
    v[1] = v[1] + n
  end
  for _, c in ipairs(r.code or {}) do
    c[4] = c[4] + n
  end
  for _, x in ipairs(r.meta.tv and r.meta.tv.names or {}) do
    x.s, x.e = x.s + n, x.e + n
  end
  r.b, r.w = r.b + n, r.w + n
  return r
end

--- What the pane's head says of the row in the Map.
---@param m table
---@param x seam.ORow
---@return string|nil
function M.count(m, x)
  x = subject(x)
  if not M.has(m, x) then
    return nil
  end
  if x.kind == 'fn' then
    local callers, tests = data.callers(m, x.id)
    return ('called by %d, calls %d'):format(#callers + #tests, #data.calls(m, x.id))
  elseif x.kind == 'type' then
    local makers, takers = data.flow(m, x.name)
    return ('made by %d, taken by %d'):format(#makers, #takers)
  end
  local into, outs = data.crossing(m, data.within(x.kind == 'dir' and dir_of(x) or x.path))
  local function files(list, side)
    local t = {}
    for _, e in ipairs(list) do
      t[m.graph.nodes[e[side]].path] = true
    end
    return vim.tbl_count(t)
  end
  return ('called from %s, calls %d'):format(draw.plural(files(into, 'from'), 'file'), files(outs, 'to'))
end

--- A name in the code seen through its type.
M.subject = subject

return M
