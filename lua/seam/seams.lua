-- Used by and Built from as data, from the index alone: the places that
-- use a row (a function, a file, a folder, a repo type) and the places it
-- draws on, each with the name it is about and the function or type it
-- sits in; then grouped as each display shows them, tests after the rest.
local index = require 'seam.index'
local M = {}

---@class seam.SeamPlace
---@field path string the file the place is in
---@field line integer
---@field col integer|nil 1-based
---@field name string the name used there
---@field kind 'fn'|'type'|'value' what that name is
---@field decl { path: string, line: integer }|nil where the name is declared
---@field id string|nil the name's own id: a node of the call graph, an export
---@field top { name: string, kind: 'fn'|'type', id: string|nil, line: integer }|nil what the place sits in
---@field test boolean the place is in a test

--- The places shown in full in a file's group before `⋯ N more`.
M.MORE = 4

local CALLABLE = { ['function'] = true, component = true }
local TYPE = { interface = true, type = true, enum = true }

-- what the name with `id` is: a function of the call graph, a type, else a value
local function kind_of(m, id)
  local n = m.graph and m.graph.nodes[id]
  local e = m.byid[id]
  -- a class is read as the type it makes
  if (e and TYPE[e.kind]) or (n and n.kind == 'class') or (e and e.kind == 'class') then
    return 'type'
  end
  if n and n.kind ~= 'module' then
    return 'fn'
  end
  return e and CALLABLE[e.kind] and 'fn' or 'value'
end

local function inside(dir)
  return function(p)
    return p:sub(1, #dir + 1) == dir .. '/'
  end
end

local function by_place(a, b)
  if a.test ~= b.test then
    return b.test
  end
  if a.path ~= b.path then
    return a.path < b.path
  end
  if a.line ~= b.line then
    return a.line < b.line
  end
  return (a.col or 0) < (b.col or 0)
end
M.by_place = by_place

-- add `p` unless a place at the same spot naming the same is there
local function adder(out)
  local seen = {}
  return function(p)
    local k = p.path .. ':' .. p.line .. ':' .. (p.col or 0) .. ':' .. p.name
    if not seen[k] then
      seen[k] = true
      p.test = index.is_test(p.path)
      out[#out + 1] = p
    end
  end
end

-- each use of export `e` as a place, those `keep` lets through
local function uses_of(m, e, add, keep)
  local kind = kind_of(m, e.id)
  for _, u in ipairs(e.uses or {}) do
    if not keep or keep(u.path) then
      add { path = u.path, line = u.line, col = u.col, name = e.name, kind = kind, decl = { path = e.path, line = e.line }, id = e.id }
    end
  end
end

-- the subject's exports: a file's, a folder's, a function's or type's own
local function exports_of(m, x, dir)
  local out = {}
  if x.kind == 'fn' then
    out[1] = m.byid[x.id]
  elseif x.kind == 'type' then
    out[1] = m.bykey[x.path .. ':' .. x.name]
  else
    for _, e in ipairs(m.exports or {}) do
      if (dir and inside(dir)(e.path)) or (not dir and e.path == x.path) then
        out[#out + 1] = e
      end
    end
  end
  return out
end

--- Who uses row `x`: for a function each place that calls or names it,
--- in its own file too; for a file or a type each place another file names
--- it; for a folder each place outside it naming what it exports. Through
--- the lens. `dir` is a folder's whole path.
---@param m table
---@param x seam.ORow
---@param dir? string
---@return seam.SeamPlace[]
function M.used(m, x, dir)
  local out = {}
  local add = adder(out)
  local keep = dir and function(p)
    return not inside(dir)(p)
  end
  for _, e in ipairs(exports_of(m, x, dir)) do
    uses_of(m, e, add, keep)
  end
  local g = m.graph
  if x.kind == 'fn' and g and g.nodes[x.id] then
    local n = g.nodes[x.id]
    for _, c in ipairs(g.up[x.id] or {}) do
      local from = g.nodes[c.from]
      if not m.visible or m.visible(from.path, 'used') then
        add { path = from.path, line = c.line, col = c.col, name = n.name, kind = 'fn', decl = { path = n.path, line = n.line }, id = x.id }
      end
    end
  end
  return out
end

--- What row `x` draws on: for a function each name in it that lives at the
--- top of a file, its own included (an export's names, else what it calls
--- and the types `types_in` finds); for a type the types its fields are
--- made of; for a file or a folder each such name in it that lives outside
--- it. Through the lens.
---@param m table
---@param x seam.ORow
---@param dir? string
---@param types_in? fun(node: table): seam.SeamPlace[] the types a function names, for one that is no export
---@return seam.SeamPlace[]
function M.built(m, x, dir, types_in)
  local out = {}
  local add = adder(out)
  local g = m.graph
  local outside = dir and function(p)
    return not inside(dir)(p)
  end or x.kind == 'file' and function(p)
    return p ~= x.path
  end or function()
    return true
  end
  local function dep(e, d)
    local p = index.id_path(d.target)
    if p and outside(p) then
      add {
        path = e.path,
        line = d.line,
        col = d.col,
        name = d.name,
        kind = kind_of(m, d.target),
        decl = { path = p, line = index.id_line(d.target) },
        id = d.target,
      }
    end
  end
  local function calls(n)
    for _, c in ipairs(g and g.down[n.id] or {}) do
      local to = g.nodes[c.to]
      if outside(to.path) and (not m.visible or m.visible(to.path, 'built')) then
        add { path = n.path, line = c.line, col = c.col, name = to.name, kind = 'fn', decl = { path = to.path, line = to.line }, id = c.to }
      end
    end
  end
  local exs = exports_of(m, x, dir)
  for _, e in ipairs(exs) do
    for _, d in ipairs(e.deps or {}) do
      dep(e, d)
    end
  end
  if x.kind == 'fn' then
    local n = g and g.nodes[x.id]
    if n and #exs == 0 then
      calls(n)
      for _, p in ipairs(types_in and types_in(n) or {}) do
        add(p)
      end
    end
  elseif x.kind ~= 'type' and g then
    local keep = dir and inside(dir) or function(p)
      return p == x.path
    end
    for path, list in pairs(require('seam.outline').by_file(g)) do
      if keep(path) then
        for _, n in ipairs(list) do
          calls(n)
        end
      end
    end
  end
  return out
end

--- Hang on each place what it sits in, as `top(path, line)` says.
---@param places seam.SeamPlace[]
---@param top fun(path: string, line: integer): table|nil
---@return seam.SeamPlace[]
function M.place_in(places, top)
  for _, p in ipairs(places) do
    p.top = top(p.path, p.line)
  end
  return places
end

--- The innermost of `decls` (each `{ name, kind, line, end_line }`)
--- holding `line`.
---@param decls table[]
---@param line integer
---@return table|nil
function M.innermost(decls, line)
  local best
  for _, d in ipairs(decls) do
    if d.line <= line and line <= (d.end_line or d.line) and (not best or d.line >= best.line) then
      best = d
    end
  end
  return best
end

---------------------------------------------------------------- counts

--- How many files and how many places: a place a line.
---@param places seam.SeamPlace[]
---@return integer files, integer places
function M.count(places)
  local files, lines = {}, {}
  for _, p in ipairs(places) do
    files[p.path] = true
    lines[p.path .. ':' .. p.line] = true
  end
  return vim.tbl_count(files), vim.tbl_count(lines)
end

--- How many files the names come from, and how many names.
---@param places seam.SeamPlace[]
---@return integer files, integer names
function M.count_names(places)
  local files, names = {}, {}
  for _, p in ipairs(places) do
    if p.decl then
      files[p.decl.path] = true
    end
    names[p.name .. '\0' .. (p.id or '')] = true
  end
  return vim.tbl_count(files), vim.tbl_count(names)
end

---------------------------------------------------------------- grouping

-- the names in `places` in their order, each once
local function names_of(places)
  local out, seen = {}, {}
  for _, p in ipairs(places) do
    if not seen[p.name] then
      seen[p.name] = true
      out[#out + 1] = { name = p.name, kind = p.kind, decl = p.decl, id = p.id }
    end
  end
  return out
end

-- the places one a line, the first on each line kept, in order
local function a_line(places)
  local out, seen = {}, {}
  for _, p in ipairs(places) do
    local k = p.path .. ':' .. p.line
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = p
    end
  end
  return out
end
M.a_line = a_line

---@class seam.FileGroup
---@field path string
---@field places seam.SeamPlace[] one a line, in the file's order
---@field names table[] the names used, first used first
---@field test boolean

--- Used by, by file: each file and its places a line each, the files with
--- most places first, tests after the rest.
---@param places seam.SeamPlace[]
---@return seam.FileGroup[]
function M.by_file(places)
  local groups, list = {}, {}
  local sorted = vim.list_slice(places)
  table.sort(sorted, by_place)
  for _, p in ipairs(sorted) do
    local gp = groups[p.path]
    if not gp then
      gp = { path = p.path, all = {}, test = p.test }
      groups[p.path] = gp
      list[#list + 1] = gp
    end
    gp.all[#gp.all + 1] = p
  end
  for _, gp in ipairs(list) do
    gp.places = a_line(gp.all)
    gp.names = names_of(gp.all)
    gp.all = nil
  end
  table.sort(list, function(a, b)
    if a.test ~= b.test then
      return b.test
    end
    if #a.places ~= #b.places then
      return #a.places > #b.places
    end
    return a.path < b.path
  end)
  return list
end

--- The first of `list` to show, `MORE` unless `all`, and how many are left.
---@generic T
---@param list T[]
---@param all? boolean
---@return T[], integer
function M.cut(list, all)
  if all or #list <= M.MORE then
    return list, 0
  end
  return vim.list_slice(list, 1, M.MORE), #list - M.MORE
end

---@class seam.NameGroup
---@field name string
---@field kind 'fn'|'type'|'value'
---@field decl table|nil
---@field id string|nil
---@field places seam.SeamPlace[] one a line, tests after the rest
---@field files integer
---@field test boolean every place is in a test

--- Used by, by name: each name handed out, the functions first in the
--- order they are declared, then the rest by most places; a name only
--- tests use after the rest of its kind.
---@param places seam.SeamPlace[]
---@return seam.NameGroup[]
function M.by_name(places)
  local groups, list = {}, {}
  local sorted = vim.list_slice(places)
  table.sort(sorted, by_place)
  for _, p in ipairs(sorted) do
    local k = p.name .. '\0' .. (p.id or '')
    local gp = groups[k]
    if not gp then
      gp = { name = p.name, kind = p.kind, decl = p.decl, id = p.id, all = {}, test = true }
      groups[k] = gp
      list[#list + 1] = gp
    end
    gp.all[#gp.all + 1] = p
    gp.test = gp.test and p.test
  end
  for _, gp in ipairs(list) do
    gp.places = a_line(gp.all)
    local files = {}
    for _, p in ipairs(gp.places) do
      files[p.path] = true
    end
    gp.files = vim.tbl_count(files)
    gp.all = nil
  end
  table.sort(list, function(a, b)
    local fa, fb = a.kind == 'fn', b.kind == 'fn'
    if fa ~= fb then
      return fa
    end
    if a.test ~= b.test then
      return b.test
    end
    if fa then
      local da, db = a.decl or { path = '', line = 0 }, b.decl or { path = '', line = 0 }
      if da.path ~= db.path then
        return da.path < db.path
      end
      if da.line ~= db.line then
        return da.line < db.line
      end
    elseif #a.places ~= #b.places then
      return #a.places > #b.places
    end
    return a.name < b.name
  end)
  return list
end

---@class seam.UserGroup
---@field path string
---@field top table|nil what the places sit in; nil for a file's top level
---@field names table[] what it uses, first used first
---@field places seam.SeamPlace[]
---@field test boolean

--- Used by, by user: each function or type the places sit in, with what it
--- uses; the functions first, then the types, then a file's top level,
--- tests after the rest of each, by file and line.
---@param places seam.SeamPlace[]
---@return seam.UserGroup[]
function M.by_user(places)
  local groups, list = {}, {}
  local sorted = vim.list_slice(places)
  table.sort(sorted, by_place)
  for _, p in ipairs(sorted) do
    local t = p.top
    local k = p.path .. '\0' .. (t and (t.name .. ':' .. t.line) or '')
    local gp = groups[k]
    if not gp then
      gp = { path = p.path, top = t, all = {}, test = p.test }
      groups[k] = gp
      list[#list + 1] = gp
    end
    gp.all[#gp.all + 1] = p
  end
  for _, gp in ipairs(list) do
    gp.names = names_of(gp.all)
    gp.places = gp.all
    gp.all = nil
  end
  local RANK = { fn = 1, type = 2 }
  table.sort(list, function(a, b)
    local ra, rb = a.top and RANK[a.top.kind] or 3, b.top and RANK[b.top.kind] or 3
    if ra ~= rb then
      return ra < rb
    end
    if a.test ~= b.test then
      return b.test
    end
    if a.path ~= b.path then
      return a.path < b.path
    end
    return (a.top and a.top.line or 0) < (b.top and b.top.line or 0)
  end)
  return list
end

-- the places by first use: by line and column in a file, the files in
-- order, tests after the rest
local function first_use(places)
  local sorted = vim.list_slice(places)
  table.sort(sorted, by_place)
  return sorted
end

--- Built from, by name: each name once, at its first use, in the order the
--- code first uses them.
---@param places seam.SeamPlace[]
---@return seam.SeamPlace[]
function M.first_uses(places)
  local out, seen = {}, {}
  for _, p in ipairs(first_use(places)) do
    local k = p.name .. '\0' .. (p.id or '')
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = p
    end
  end
  return out
end

---@class seam.FromGroup
---@field path string the file the names live in
---@field home boolean it is the subject's own file
---@field uses seam.SeamPlace[] each name once, at its first use, first used first
---@field test boolean

--- Built from, by file: each file it draws on, its own (`home`) first,
--- then by path, tests after the rest; each name in it once, at its first
--- use, in the order first used.
---@param places seam.SeamPlace[]
---@param home? string
---@return seam.FromGroup[]
function M.from_files(places, home)
  local groups, list = {}, {}
  for _, p in ipairs(M.first_uses(places)) do
    local path = p.decl and p.decl.path or '?'
    local gp = groups[path]
    if not gp then
      gp = { path = path, home = path == home, uses = {}, test = index.is_test(path) }
      groups[path] = gp
      list[#list + 1] = gp
    end
    gp.uses[#gp.uses + 1] = p
  end
  table.sort(list, function(a, b)
    if a.home ~= b.home then
      return a.home
    end
    if a.test ~= b.test then
      return b.test
    end
    return a.path < b.path
  end)
  return list
end

--- Built from as signature lines: the functions it calls, each once, in
--- the order it calls them; then the types it names, then the values.
---@param places seam.SeamPlace[]
---@return seam.SeamPlace[] fns, seam.SeamPlace[] types, seam.SeamPlace[] values
function M.signatures(places)
  local fns, tys, vals = {}, {}, {}
  for _, p in ipairs(M.first_uses(places)) do
    local into = p.kind == 'fn' and fns or p.kind == 'type' and tys or vals
    into[#into + 1] = p
  end
  return fns, tys, vals
end

--- The shortest way to write each of `paths` that keeps them apart: each
--- relative to the folder they all share.
---@param paths string[]
---@return fun(path: string): string
function M.shortener(paths)
  local common
  for _, p in ipairs(paths) do
    local dir = p:match '^(.*/)' or ''
    if not common then
      common = dir
    else
      while common ~= '' and dir:sub(1, #common) ~= common do
        common = common:match '^(.*/)[^/]+/$' or ''
      end
    end
  end
  common = common or ''
  return function(path)
    return path:sub(1, #common) == common and path:sub(#common + 1) or path
  end
end

return M
