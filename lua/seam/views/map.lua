-- The Map view: two displays on every kind of row, folder and type, each
-- what the row calls above, the row, its callers below (seam.map.flow),
-- drawn from the call graph and the types; folder with T off today's both
-- ways, names only (seam.map.both). Each row's ⋯ more opened and T kept in
-- st.map; the keys that act on it, l T J, and what is under the cursor
-- (seam.map.keys); the name under the cursor told at the foot (seam.map.foot).
local api = vim.api
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local outline = require 'seam.outline'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local types_view = require 'seam.views.types'
local M = {}

M.DISPLAYS = { 'folder', 'type' }

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

--- What the Map keeps for a row: the sides and bars opened past ⋯ more.
---@param x seam.ORow
---@return { more: table<string, boolean> }
function M.state(x)
  st.map = st.map or { rows = {}, types = true }
  local k = subject(x).key or ''
  st.map.rows[k] = st.map.rows[k] or { more = {} }
  return st.map.rows[k]
end

--- Is T on: the folder display with each signature, as it opens, or
--- names only?
---@return boolean
function M.types_on()
  return not (st.map and st.map.types == false)
end

---------------------------------------------------------------- facts

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
-- with `dim`, all but the types dim, as what a function takes is written
local function tsegs(text, dim, hit)
  local out, i = {}, 1
  local rest = dim and 'SeamLabel' or 'SeamText'
  for a, w, b in text:gmatch '()([%a_$][%w_$]*)()' do
    if a > i then
      out[#out + 1] = { text:sub(i, a - 1), rest, hit }
    end
    local hl = BUILTIN[w] and (dim and 'SeamLabel' or '@type.builtin') or w:match '^%u' and 'SeamType' or rest
    out[#out + 1] = { w, hl, hit }
    i = b
  end
  if i <= #text then
    out[#out + 1] = { text:sub(i), rest, hit }
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

---------------------------------------------------------------- the sides

-- the line `from` calls `to` on, its first
local function call_line(m, from, to)
  for _, c in ipairs(m.graph.down[from] or {}) do
    if c.to == to then
      return c.line
    end
  end
end

---@class seam.MapEntry
---@field id string the function named
---@field path string the file it is gathered under
---@field at { path: string, line: integer, inside: string }|nil the call, where it is and what it sits in
---@field dim boolean|nil a test

-- where the call `from` → `to` is
local function at_of(m, from, to)
  local line = call_line(m, from, to)
  local n = m.graph.nodes[from]
  return line and { path = n.path, line = line, inside = data.label(n) } or nil
end

--- What the row calls or makes, above, and who calls or takes it, below:
--- a function's calls and callers, tests last and dim; a type's makers and
--- takers; a folder's or a file's calls out across its edge, then the calls
--- in, each with what of it they call, under the caller's file.
---@param x seam.ORow
---@param m table
---@return seam.MapEntry[], seam.MapEntry[]
local function sides(x, m)
  local g = m.graph
  local top, bottom = {}, {}
  if x.kind == 'fn' then
    for _, id in ipairs(data.calls(m, x.id)) do
      top[#top + 1] = { id = id, path = g.nodes[id].path, at = at_of(m, x.id, id) }
    end
    local callers, tests = data.callers(m, x.id)
    for _, list in ipairs { { callers }, { tests, true } } do
      for _, id in ipairs(list[1]) do
        bottom[#bottom + 1] = { id = id, path = g.nodes[id].path, at = at_of(m, id, x.id), dim = list[2] }
      end
    end
  elseif x.kind == 'type' then
    local makers, takers = data.flow(m, x.name)
    for _, id in ipairs(makers) do
      top[#top + 1] = { id = id, path = g.nodes[id].path }
    end
    for _, id in ipairs(takers) do
      bottom[#bottom + 1] = { id = id, path = g.nodes[id].path }
    end
  else
    local into, outs = data.crossing(m, data.within(x.kind == 'dir' and outline.full(x.item) or x.path))
    local function across(list, edges, file_end)
      local seen = {}
      for _, e in ipairs(edges) do
        local p = g.nodes[e[file_end]].path
        if not seen[p .. '\n' .. e.to] then
          seen[p .. '\n' .. e.to] = true
          list[#list + 1] = { id = e.to, path = p, at = at_of(m, e.from, e.to) }
        end
      end
    end
    across(top, outs, 'to')
    across(bottom, into, 'from')
  end
  return top, bottom
end

-- the file the Map's folders are named from
local function home_of(x, m)
  if x.kind == 'dir' then
    return outline.full(x.item) .. '/x'
  end
  return x.kind == 'fn' and m.graph.nodes[x.id].path or x.path
end

-- a folder as a head writes it: a package's top without ` files`
local function folder_text(f)
  return (f:gsub(' files$', ''))
end

---------------------------------------------------------------- the displays

-- folder with T off: today's both ways, names only, each side by folder
-- and file
local function names_display(x, m, ctx, top, bottom, centre)
  local both = require 'seam.map.both'
  local s = M.state(x)
  local home = home_of(x, m)
  local function items(list)
    local out = {}
    for _, e in ipairs(list) do
      local n = m.graph.nodes[e.id]
      out[#out + 1] = {
        folder = data.where(m, e.path, home),
        dir = e.path:match '^(.*)/[^/]*$',
        path = e.path,
        segs = { { data.label(n), e.dim and 'SeamLabel' or 'SeamMapFn', { kind = 'fn', id = e.id, at = e.at } } },
      }
    end
    return out
  end
  local left, right = items(top), items(bottom)
  local function need(list)
    local n = 0
    for _, l in ipairs(both.side(list, math.huge, { all = true, side = 'left' })) do
      local w = 0
      for _, sg in ipairs(l.segs) do
        w = w + api.nvim_strwidth(sg[1])
      end
      n = math.max(n, w + (l.indent or 0))
    end
    return n
  end
  local w = ctx.width - 2
  local cw = api.nvim_strwidth(centre[1][1])
  local rl, rr = both.rooms(need(left), need(right), w, cw)
  local L = both.side(left, rl, { all = s.more.left, side = 'left' })
  local R = both.side(right, rr, { all = s.more.right, side = 'right' })
  return both.draw(L, R, centre, w)
end

-- what a type's head stands for: the first type of the repo it names
local function type_hit(m, text)
  for w in text:gmatch '[%a_$][%w_$]*' do
    if m.flows and m.flows[w] then
      return { kind = 'type', name = w }
    end
  end
end

-- the rank of a type's head: the repo's types first, builtins, nothing last
local function type_rank(m, k)
  if k == 'void' or k == '?' then
    return 2
  end
  return type_hit(m, k) and 0 or 1
end

-- the room between what a function takes and what it gives
local GAP = '   '

--- folder and type: the row's calls above, gathered under a folder or the
--- type each gives, the row, its callers below gathered the same way.
local function flow_display(x, m, ctx, C, by, top, bottom, centre_name)
  local flow = require 'seam.map.flow'
  local s = M.state(x)
  local home = home_of(x, m)
  local fn = x.kind == 'fn'
  local sigs = {}
  local function sig(id)
    if sigs[id] == nil then
      local t, g = sig_text(C, id)
      sigs[id] = { t, g }
    end
    return sigs[id][1], sigs[id][2]
  end
  local function name(e)
    return { data.label(m.graph.nodes[e.id]), e.dim and 'SeamLabel' or 'SeamMapFn', { kind = 'fn', id = e.id, at = e.at } }
  end
  local function takes(e)
    local t = sig(e.id)
    return t and tsegs('(' .. t .. ')', true) or {}
  end
  local function gives(e)
    local _, g = sig(e.id)
    if not g then
      return {}
    elseif g == 'void' then
      return { { GAP .. 'nothing', 'SeamLabel' } }
    end
    return cat({ { GAP .. '→  ', 'SeamLabel' } }, tsegs(g))
  end
  local function place(e)
    return { { folder_text(data.where(m, e.path, home)), 'SeamLabel' }, { e.path:match '[^/]+$', 'SeamText', { kind = 'file', path = e.path } } }
  end
  local function at_text(e)
    return e.at and { { e.at.path:match '[^/]+$', 'SeamText', { kind = 'file', path = e.at.path } }, { ':' .. e.at.line, 'SeamLabel' } } or place(e)
  end
  local function line_of(e)
    return e.at and e.at.line or m.graph.nodes[e.id].line
  end
  -- the side's entries in groups: by folder, the one with the most first,
  -- each in file then line order; by type, the repo's first, each in the
  -- order the body calls them
  local function groups(list, is_top)
    local out, at = {}, {}
    for _, e in ipairs(list) do
      local k
      if by == 'type' then
        local _, g = sig(e.id)
        k = g or '?'
      else
        k = data.where(m, e.path, home)
      end
      local grp = at[k]
      if not grp then
        grp = { key = k, list = {}, i = #out + 1, dir = e.path:match '^(.*)/[^/]*$' }
        at[k] = grp
        out[#out + 1] = grp
      end
      table.insert(grp.list, e)
    end
    table.sort(out, function(a, b)
      if by == 'type' then
        local ra, rb = type_rank(m, a.key), type_rank(m, b.key)
        if ra ~= rb then
          return ra < rb
        end
      end
      return #a.list > #b.list or (#a.list == #b.list and a.i < b.i)
    end)
    local res = {}
    for _, grp in ipairs(out) do
      table.sort(grp.list, function(a, b)
        if by == 'folder' and a.path ~= b.path then
          return a.path < b.path
        end
        if a.dim ~= b.dim then
          return not a.dim
        end
        return line_of(a) < line_of(b)
      end)
      local head
      if by == 'type' then
        head = grp.key == 'void' and { { 'nothing', 'SeamLabel' } }
          or grp.key == '?' and { { '?', 'SeamLabel' } }
          or tsegs(grp.key, false, type_hit(m, grp.key))
      else
        head = { { folder_text(grp.key), 'SeamBold', grp.dir and { kind = 'dir', path = grp.dir } or nil } }
      end
      -- where it is and its name in columns, its signature straight after
      local items, prev = {}, nil
      for _, e in ipairs(grp.list) do
        local cols, tail
        if by == 'folder' and is_top then
          local f = e.path ~= prev and { { e.path:match '[^/]+$', 'SeamText', { kind = 'file', path = e.path } } } or {}
          cols, tail = { f, { name(e) } }, cat(takes(e), gives(e))
        elseif by == 'folder' then
          cols, tail = { at_text(e), { name(e) } }, cat(takes(e), gives(e))
        elseif is_top then
          cols, tail = { place(e), { name(e) } }, takes(e)
        else
          cols, tail = { at_text(e), { name(e) } }, takes(e)
        end
        -- by folder an empty row between the files the calls are in
        local gap = by == 'folder' and is_top and prev ~= nil and e.path ~= prev
        prev = e.path
        items[#items + 1] = { cols = cols, tail = tail, gap = gap, gutter = is_top and fn and e.at and tostring(e.at.line) or nil }
      end
      res[#res + 1] = { head = head, items = items }
    end
    return res
  end
  local centre
  if fn then
    local t, g = sig(x.id)
    local n = m.graph.nodes[x.id]
    local segs, out = {}, nil
    if t then
      segs = cat(tsegs('(' .. t .. ')'), { { ' → ', 'SeamLabel' } })
    end
    segs[#segs + 1] = { centre_name, 'SeamMapFnBold' }
    if g then
      segs = cat(segs, { { ' → ', 'SeamLabel' } })
      out = #segs + 1
      segs = cat(segs, tsegs(g))
    end
    centre = { segs = segs, gutter = tostring(n.line), out = out }
  else
    centre = { segs = { { centre_name, x.kind == 'type' and 'SeamTypeBold' or 'SeamBold' } } }
  end
  return flow.draw(groups(top, true), centre, groups(bottom, false), { width = ctx.width - 2, all_top = s.more.left, all_bottom = s.more.right })
end

--- The Map of `x` in `display`, rows under it left for the foot to stand
--- over.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param display string
---@param ctx seam.ViewCtx
function M.draw(out, x, m, display, ctx)
  x = subject(x)
  local top, bottom = sides(x, m)
  if #top == 0 and #bottom == 0 then
    out[#out + 1] = row():add(' nothing calls it and it calls nothing', 'SeamLabel')
    return
  end
  local label
  if x.kind == 'fn' then
    label = data.label(m.graph.nodes[x.id])
  elseif x.kind == 'type' then
    label = x.name
  else
    label = x.kind == 'dir' and dir_label(x) or data.short(m, x.path, x.path)
  end
  local rows
  if display == 'folder' and not M.types_on() then
    local hl = x.kind == 'fn' and 'SeamMapFnBold' or x.kind == 'type' and 'SeamTypeBold' or 'SeamBold'
    rows = names_display(x, m, ctx, top, bottom, { { label, hl } })
  else
    local C = types_view.context(m, ctx, x.kind == 'dir' and dir_of(x) or x.path)
    rows = flow_display(x, m, ctx, C, display == 'type' and 'type' or 'folder', top, bottom, label)
  end
  vim.list_extend(out, rows)
  for _ = 1, require('seam.map.foot').MAX do
    out[#out + 1] = row()
  end
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
