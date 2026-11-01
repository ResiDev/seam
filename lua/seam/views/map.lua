-- The Map view: two displays on every kind of row, both ways and size
-- (seam.map.*), drawn from the call graph and the types; each row's ⋯ more
-- opened and T kept in st.map; the keys that act on it, l T J, and what is
-- under the cursor (seam.map.keys).
local api = vim.api
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local types_view = require 'seam.views.types'
local M = {}

M.DISPLAYS = { 'both ways', 'size' }

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
  st.map = st.map or { rows = {}, types = false }
  local k = subject(x).key or ''
  st.map.rows[k] = st.map.rows[k] or { more = {} }
  return st.map.rows[k]
end

--- Is T on?
---@return boolean
function M.types_on()
  return st.map ~= nil and st.map.types == true
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

---------------------------------------------------------------- the displays

local function both_display(x, m, ctx, C)
  local both = require 'seam.map.both'
  local s = M.state(x)
  local T = M.types_on() and m.sigs
  local home = x.kind == 'dir' and (dir_of(x) .. '/x') or x.kind == 'fn' and m.graph.nodes[x.id].path or x.path
  local left, right, centre = {}, {}, nil
  local function item(list, path, segs)
    list[#list + 1] = { folder = data.where(m, path, home), dir = path:match '^(.*)/[^/]*$', path = path, segs = segs }
  end
  -- a function as a side writes it: with T on, what goes in left of its
  -- name and what comes out right of it
  local function fn_item(list, id, side, dim)
    local n = m.graph.nodes[id]
    local name = { data.label(n), dim and 'SeamLabel' or 'SeamMapFn', { kind = 'fn', id = id } }
    local takes, gives
    if T then
      takes, gives = sig_text(C, id)
    end
    local segs = { name }
    if side == 'left' and takes then
      segs = cat({ { '(', 'SeamPunct' } }, tsegs(tv.cut(takes, 30)), { { ') → ', 'SeamLabel' }, name })
    elseif side == 'right' and gives then
      segs = cat({ name, { ' → ', 'SeamLabel' } }, tsegs(tv.cut(gives, 24)))
    end
    item(list, n.path, segs)
  end
  if x.kind == 'fn' then
    local callers, tests = data.callers(m, x.id)
    for _, id in ipairs(data.calls(m, x.id)) do
      fn_item(left, id, 'left')
    end
    for _, id in ipairs(callers) do
      fn_item(right, id, 'right')
    end
    for _, id in ipairs(tests) do
      fn_item(right, id, 'right', true)
    end
    centre = { { data.label(m.graph.nodes[x.id]), 'SeamMapFnBold' } }
  elseif x.kind == 'type' then
    local makers, takers = data.flow(m, x.name)
    for _, id in ipairs(makers) do
      fn_item(left, id, 'left')
    end
    for _, id in ipairs(takers) do
      fn_item(right, id, 'right')
    end
    centre = { { x.name, 'SeamTypeBold' } }
  else
    -- the files across its edge, each with the names that cross: those it
    -- calls out to, then the files calling in with what of it they call
    local into, outs = data.crossing(m, data.within(x.kind == 'dir' and dir_of(x) or x.path))
    local function across(list, edges, file_end)
      local seen = {}
      for _, e in ipairs(edges) do
        local p = m.graph.nodes[e[file_end]].path
        if not seen[p .. '\n' .. e.to] then
          seen[p .. '\n' .. e.to] = true
          item(list, p, { { data.label(m.graph.nodes[e.to]), 'SeamMapFn', { kind = 'fn', id = e.to } } })
        end
      end
    end
    across(left, outs, 'to')
    across(right, into, 'from')
    centre = { { x.kind == 'dir' and dir_label(x) or data.short(m, x.path, x.path), 'SeamBold' } }
  end
  if #left == 0 and #right == 0 then
    return { row():add(' nothing calls it and it calls nothing', 'SeamLabel') }
  end
  local function need(list)
    local probe = both.side(list, math.huge, { each = T, all = true, side = 'left' })
    local n = 0
    for _, l in ipairs(probe) do
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
  local L = both.side(left, rl, { each = T, all = s.more.left, side = 'left' })
  local R = both.side(right, rr, { each = T, all = s.more.right, side = 'right' })
  return both.draw(L, R, centre, w)
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
  local rows
  if display == 'size' then
    rows = size_display(x, m, ctx)
  else
    local C = types_view.context(m, ctx, x.kind == 'dir' and dir_of(x) or x.path)
    rows = both_display(x, m, ctx, C)
  end
  vim.list_extend(out, rows)
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
