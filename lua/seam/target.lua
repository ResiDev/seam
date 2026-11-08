-- A target: a place in seam written as a string, for a link from outside
-- (a thread) to land on. `parse` reads the string once; `resolve` finds it
-- in a model and says why not when it is not there. Neither touches seam's
-- open state, so a link can be checked headless or while seam shows
-- another repo.
--
--   target  := what ['@' view ['/' display]]
--   what    := 'type:' Name | path ':' name [':' line] | path ['/']
--   view    := Code | Types | Map
local here = require 'seam.here'
local index = require 'seam.index'
local map_view = require 'seam.views.map'
local outline = require 'seam.outline'
local M = {}

---@alias seam.TargetWhat
---| { kind: 'type', name: string }
---| { kind: 'name', path: string, name: string, line: integer|nil }
---| { kind: 'path', path: string }

---@class seam.Target
---@field what seam.TargetWhat
---@field view 'Code'|'Types'|'Map'|nil
---@field display string|nil

---@class seam.TargetAt where a target is in the tree
---@field kind 'fn'|'file'|'dir'|'type'
---@field path string the file, the folder, or the file a type is declared in
---@field id string|nil a function's node id
---@field name string|nil a type's name
---@field contract table|nil the contract it names, for the lens

M.VIEWS = { 'Code', 'Types', 'Map' }
local IDENT = '^[%a_$][%w_$]*$'

local function views_of()
  local out = {}
  for _, v in ipairs(require('seam.views').list) do
    if vim.tbl_contains(M.VIEWS, v.name) then
      out[v.name] = v
    end
  end
  return out
end

-- 'a, b or c'
local function either(list)
  if #list < 2 then
    return list[1] or ''
  end
  return table.concat(list, ', ', 1, #list - 1) .. ' or ' .. list[#list]
end

--- Read a target string.
---@param s string
---@return seam.Target|nil target
---@return string|nil why
function M.parse(s)
  s = vim.trim(s or '')
  local what, view, display = s, nil, nil
  -- the last '@' starts the view, unless what follows is a path's (@scope/pkg.ts)
  local at = s:match '^.*()@'
  if at then
    local tail = s:sub(at + 1)
    local v, d = tail:match '^(%a*)/?(%a*)$'
    if v then
      what, view, display = s:sub(1, at - 1), v, d ~= '' and d or nil
    end
  end
  if what == '' then
    return nil, 'the target is empty: write a path, path:name or type:Name, then @Code, @Types or @Map if it needs one'
  end
  if view then
    local v = views_of()[view]
    if not v then
      return nil, ("no view '%s': %s"):format(view, either(M.VIEWS))
    end
    if display and not vim.tbl_contains(v.displays, display) then
      return nil, ("%s has no display '%s': %s"):format(view, display, either(v.displays))
    end
  end
  local t = { view = view, display = display }
  local ty = what:match '^type:(.*)$'
  if ty then
    if not ty:match(IDENT) then
      return nil, ("'%s' is no type's name: type:Card"):format(ty)
    end
    t.what = { kind = 'type', name = ty }
    return t
  end
  if what:sub(1, 1) == '/' then
    return nil, ('%s: a path is relative to the repo root, as src/store.ts'):format(what)
  end
  what = what:gsub('^%./', '')
  local path, name, line = what:match '^([^:]+):([^:]+):(%d+)$'
  if not path then
    path, name = what:match '^([^:]+):([^:]+)$'
  end
  if path then
    if not name:match(IDENT) then
      return nil, ("'%s' is no function's or contract's name: write %s:name, or %s:name:line when the file has several"):format(name, path, path)
    end
    t.what = { kind = 'name', path = path, name = name, line = tonumber(line) }
    return t
  end
  if what:find(':', 1, true) then
    return nil, ("'%s' does not read: write a path, path:name, path:name:line or type:Name"):format(what)
  end
  t.what = { kind = 'path', path = (what:gsub('/+$', '')) }
  return t
end

-- the edits from a to b
local function distance(a, b)
  local prev = {}
  for j = 0, #b do
    prev[j] = j
  end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

-- the few of `list` nearest `word`, nearest first, and '…' when there are
-- more; `score` how far one is, the edits by default
local function nearest(word, list, n, score)
  local lw = word:lower()
  score = score or function(x)
    return distance(lw, x:lower())
  end
  local scored = {}
  for i, x in ipairs(list) do
    scored[i] = { x = x, d = score(x), i = i }
  end
  table.sort(scored, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    return a.i < b.i
  end)
  local out = {}
  for i = 1, math.min(n, #scored) do
    out[i] = scored[i].x
  end
  if #scored > n then
    out[#out + 1] = '…'
  end
  return table.concat(out, ', ')
end

-- the folders holding the tree's files
local function dirs(files)
  local out = {}
  for path in pairs(files) do
    local d = vim.fs.dirname(path)
    while d ~= '.' and d ~= '' and not out[d] do
      out[d] = true
      d = vim.fs.dirname(d)
    end
  end
  return out
end

local function sorted_keys(t)
  local list = vim.tbl_keys(t)
  table.sort(list)
  return list
end

-- the names a file has rows or contracts for, in the file's order
local function names_in(m, path)
  local seen, list = {}, {}
  local function add(name, line)
    if name and name ~= '' and not seen[name] then
      seen[name] = true
      list[#list + 1] = { name = name, line = line }
    end
  end
  for _, n in ipairs(m.graph and outline.by_file(m.graph)[path] or {}) do
    add(n.name, n.line)
  end
  for _, e in ipairs(m.exports or {}) do
    if e.path == path and #(e.all_uses or e.uses or {}) > 0 then
      add(e.name, e.line)
    end
  end
  table.sort(list, function(a, b)
    return a.line < b.line
  end)
  return vim.tbl_map(function(x)
    return x.name
  end, list)
end

-- where a file or folder's path is, or why it is not
local function find_path(m, path)
  if index.is_test(path) then
    return nil, path .. " is a test: seam's tree leaves tests out"
  end
  local files = outline.files(m)
  if files[path] then
    return 'file'
  end
  local ds = dirs(files)
  if ds[path] then
    return 'dir'
  end
  local all = vim.list_extend(sorted_keys(files), sorted_keys(ds))
  -- a file moved keeps its name: the name counts more than the folders
  local base = path:match '[^/]*$'
  local function score(x)
    return distance(base, x:match '[^/]*$') * 3 + distance(path, x)
  end
  return nil, ('no file or folder %s in the repo; nearest: %s'):format(path, nearest(path, all, 3, score))
end

local WHAT = { fn = 'a function', file = 'a file', dir = 'a folder', type = 'a type' }

-- the views a row of `kind` has; a folder's Code is only the diff's
local function has(m, at, view)
  if view == 'Map' then
    return map_view.has(m, { kind = at.kind, name = at.name })
  end
  return view == 'Types' or at.kind ~= 'dir'
end

--- Where `t` is in the model `m`, or why it is nothing seam can show,
--- written for whoever wrote the target to fix it.
---@param m table a model, as index.read makes it
---@param t seam.Target
---@return seam.TargetAt|nil at
---@return string|nil why
function M.resolve(m, t)
  local w, at = t.what, nil
  if w.kind == 'type' then
    if not m.flows then
      return nil, 'seam has no types of this repo yet: open it with :Seam and let the TypeScript server answer'
    end
    local f = m.flows[w.name]
    local e = f and f.decls[1]
    if not e then
      return nil, ('no type %s in the repo; nearest: %s'):format(w.name, nearest(w.name, sorted_keys(m.flows), 3))
    end
    at = { kind = 'type', path = e.path, name = w.name }
  elseif w.kind == 'path' then
    local kind, why = find_path(m, w.path)
    if not kind then
      return nil, why
    end
    at = { kind = kind, path = w.path }
  else
    local kind, why = find_path(m, w.path)
    if not kind then
      return nil, why
    elseif kind == 'dir' then
      return nil, ('%s is a folder: a name goes after a file, as %s/file.ts:%s'):format(w.path, w.path, w.name)
    end
    -- as here resolves a word, but only what is declared in that file
    local c = here.contract(m, w.name, w.path, w.line)
    c = c and c.path == w.path and c or nil
    local node = c and m.graph and m.graph.nodes[c.id]
    if not node and m.graph then
      local n, _, mine = here.node(m.graph, w.name, w.path, w.line)
      node = mine and n or nil
    end
    local f = m.flows and m.flows[w.name]
    if node then
      at = { kind = 'fn', path = w.path, id = node.id, contract = c }
    elseif f and vim.iter(f.decls):any(function(e)
      return e.path == w.path
    end) then
      at = { kind = 'type', path = w.path, name = w.name, contract = c }
    elseif c then
      at = { kind = 'file', path = w.path, contract = c }
    else
      local names = names_in(m, w.path)
      if #names == 0 then
        return nil, ('%s has no function, value or contract named %s, nor any other: its row is %s'):format(w.path, w.name, w.path)
      end
      return nil, ('%s has no function, value or contract named %s; it has %s'):format(w.path, w.name, nearest(w.name, names, 5))
    end
  end
  if t.view and not has(m, at, t.view) then
    local ok = vim.tbl_filter(function(v)
      return has(m, at, v)
    end, M.VIEWS)
    return nil, ('%s has no %s view: %s'):format(WHAT[at.kind], t.view, either(ok))
  end
  if t.display and t.view == 'Map' then
    local ds = map_view.displays { kind = at.kind }
    if not vim.tbl_contains(ds, t.display) then
      return nil, ("%s's Map has no display '%s': %s"):format(WHAT[at.kind], t.display, either(ds))
    end
  end
  return at
end

--- What `/` holds for a target that does not resolve.
---@param t seam.Target
---@return string
function M.query(t)
  return t.what.name or t.what.path:match '[^/]*$'
end

return M
