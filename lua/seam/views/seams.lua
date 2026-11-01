-- Used by and Built from, drawn: by file, each file then each place with
-- its line of code and what it sits in, `⋯ N more` past four; by name,
-- each name with its signature then its places; Used by by user, each
-- function or type that uses it as a signature line then what it uses;
-- Built from as the signature lines of what it calls, then the types it
-- names. Every fact from the index (seam.seams), the lines from the files.
local api = vim.api
local code = require 'seam.code'
local code_view = require 'seam.views.code'
local draw = require 'seam.draw'
local outline = require 'seam.outline'
local seams = require 'seam.seams'
local tv = require 'seam.typesview'
local types_view = require 'seam.views.types'
local written = require 'seam.written'
local M = {}

local row, plural = draw.row, draw.plural

M.USED = { 'by file', 'by name', 'by user' }
M.BUILT = { 'by file', 'by name', 'as signatures' }

local function width(s)
  return api.nvim_strwidth(s)
end

-- a folder row's whole path, nil for any other row
local function dir_of(x)
  return x.kind == 'dir' and outline.full(x.item) or nil
end

-- the file a row is in: a function's, a file, a type's
local function home_of(m, x)
  if x.kind == 'fn' then
    local n = m.graph and m.graph.nodes[x.id]
    return n and n.path
  end
  return x.path
end

---------------------------------------------------------------- the places

-- the functions and types declared at the top of each file, for what a
-- place sits in
local function tops(m)
  local cache = {}
  return function(path, line)
    local decls = cache[path]
    if not decls then
      decls = {}
      for _, n in ipairs(outline.functions(m, path)) do
        decls[#decls + 1] = { name = n.name, kind = 'fn', id = n.id, line = n.line, end_line = n.end_line }
      end
      for _, t in ipairs(written.types(path)) do
        decls[#decls + 1] = { name = t.name, kind = 'type', decl_kind = t.kind, line = t.line, end_line = t.end_line }
      end
      cache[path] = decls
    end
    return seams.innermost(decls, line)
  end
end

-- the repo's types a function's lines name, for one the index has no
-- names for: declared in its file, else the repo's of that name
local function types_in(m)
  return function(n)
    local out = {}
    local function decl(name)
      local t = written.type_in(n.path, name)
      if t then
        return t
      end
      local f = m.flows and m.flows[name]
      return f and f.decls[1]
    end
    local P, inside = code.file(n.path), false
    for l = math.max(1, n.line), math.max(n.end_line or n.line, n.line) do
      local src
      src, inside = tv.code_part(P.lines[l] or '', inside)
      for _, t in
        ipairs(tv.names(src, function(w)
          return decl(w) ~= nil
        end))
      do
        local d = decl(t.name)
        out[#out + 1] = {
          path = n.path,
          line = l,
          col = t.s,
          name = t.name,
          kind = 'type',
          decl = { path = d.path, line = d.line },
          id = d.path .. ':' .. d.line .. ':' .. t.name,
        }
      end
    end
    return out
  end
end

-- the places for a row, kept while the model and its lens are the same
local cache = setmetatable({}, { __mode = 'k' })

--- The places of `which` ('used' or 'built') for row `x`, each with what
--- it sits in.
---@param m table
---@param x seam.ORow
---@param which 'used'|'built'
---@return seam.SeamPlace[]
function M.places(m, x, which)
  local c = cache[m]
  if not c or c.visible ~= m.visible then
    c = { visible = m.visible, used = {}, built = {}, tops = tops(m) }
    cache[m] = c
  end
  local list = c[which][x.key]
  if not list then
    local dir = dir_of(x)
    if which == 'used' then
      list = seams.used(m, x, dir)
    else
      list = seams.built(m, x, dir, types_in(m))
    end
    seams.place_in(list, c.tops)
    c[which][x.key] = list
  end
  return list
end

--- What the pane's head says of the row in Used by.
---@param m table
---@param x seam.ORow
---@return string
function M.used_count(m, x)
  local f, p = seams.count(M.places(m, x, 'used'))
  return ('used by %s, %s'):format(plural(f, 'file'), plural(p, 'place'))
end

--- What the pane's head says of the row in Built from.
---@param m table
---@param x seam.ORow
---@return string
function M.built_count(m, x)
  local f, n = seams.count_names(M.places(m, x, 'built'))
  return ('built from %s, %s'):format(plural(f, 'file'), plural(n, 'name'))
end

---------------------------------------------------------------- pieces

-- a name coloured as its declaration is, bold when `bold`
local function name(r, p, bold, room)
  local s0 = r.b
  if p.kind == 'type' then
    r:add(draw.trunc(p.name, room or 60), 'SeamType')
  else
    code.add_name(r, p.decl and p.decl.path, p.decl and p.decl.line, p.name, 'SeamName', room or 60)
  end
  if bold then
    r.h[#r.h + 1] = { s0, r.b, 'SeamBold', 80 }
  end
  return r
end

-- names a comma between, cut where the row ends
local function names(r, list, w, sep)
  sep = sep or ', '
  for i, n in ipairs(list) do
    local more = (i > 1 and #sep or 0) + width(n.name)
    -- room for the name and, after it, for what says some are left out
    if r.w + more > w - (i < #list and #sep + 1 or 0) then
      r:add(i > 1 and (sep .. '…') or '…', 'SeamLabel')
      break
    end
    if i > 1 then
      r:add(sep, 'SeamLabel')
    end
    name(r, n, false)
  end
  return r
end

-- `text` dim after a row, cut to what is left of `W`, or left out
local function after(r, text, W)
  local room = W - r.w - 3
  if room >= 6 then
    r:add('   ' .. draw.trunc(text, room), 'SeamLabel')
  end
  return r
end

-- the place's line of code from its first letter, cut with … at `room`,
-- each name of `marks` on it marked where it lives, `lit` lit
local function code_line(r, m, p, room, marks, lit)
  local src = code.file(p.path).lines[p.line] or ''
  local lead = #src:match '^%s*'
  local text = src:sub(lead + 1)
  local start = r.b - lead
  if width(text) > room then
    code.add(r, p.path, p.line, true, math.max(1, room - 1))
    r:add('…', 'SeamLabel')
  else
    code.add(r, p.path, p.line, true)
  end
  for _, q in ipairs(marks or { p }) do
    local hl = q.decl and code_view.under(m, q.path, q.decl.path)
    if hl then
      code.underline(r, start, src, q.name, q.col, hl)
    end
  end
  if lit and lit.col and src:sub(lit.col, lit.col + #lit.name - 1) == lit.name then
    r.h[#r.h + 1] = { start + lit.col - 1, start + lit.col - 1 + #lit.name, 'SeamLit', 325 }
  end
  return r
end

-- `in <what it sits in>`, for the right of a place's row
local function in_of(p)
  return p.top and ('in ' .. p.top.name) or nil
end

-- a stop for n and N, going to the place with gf
local function place_row(p, more)
  return row { at = { path = p.path, line = p.line, col = p.col and p.col - 1 }, place = true, less = more }
end

-- a place's row: its line number, its line of code, `right` at the pane's
-- right edge
local function numbered(out, m, p, W, right, marks, lit, more)
  local r = place_row(p, more):add('   '):add(string.format('%4d', p.line), 'SeamGutter'):add '  '
  local room = W - r.w - (right and width(right) + 2 or 0)
  code_line(r, m, p, room, marks, lit)
  if right then
    r:to(W - width(right)):add(right, 'SeamLabel')
  end
  out[#out + 1] = r
  return r
end

-- the `⋯ N more` row under a group, `+` showing them
local function more_row(out, n, key, col)
  out[#out + 1] = row({ more = key }):add(string.rep(' ', col) .. '⋯ ' .. n .. ' more', 'SeamLabel')
end

local function blank(out)
  if #out > 0 then
    out[#out + 1] = row()
  end
end

-- the places of `list` on each line, to mark every name used there
local function on_lines(list)
  local t = {}
  for _, p in ipairs(list) do
    local k = p.path .. ':' .. p.line
    t[k] = t[k] or {}
    table.insert(t[k], p)
  end
  return function(p)
    return t[p.path .. ':' .. p.line]
  end
end

local function shortener(list, x)
  local paths = { x.path or '' }
  for _, p in ipairs(list) do
    paths[#paths + 1] = p.path
    if p.decl then
      paths[#paths + 1] = p.decl.path
    end
  end
  return seams.shortener(paths)
end

-- a function's takes → gives, cut to fit
local function signature(r, C, p, room)
  local f = p.kind == 'fn' and p.id and types_view.fn_of(C, p.id, 'n:' .. p.id)
  if not f then
    return false
  end
  room = math.max(room, 20)
  local takes = tv.cut(f.takes, math.floor(room * 0.6))
  types_view.typed(r, takes, C.known, {}, nil)
  r:add(' → ', 'SeamLabel')
  types_view.typed(r, tv.cut(f.gives, room - width(takes) - 3), C.known, {}, nil)
  return true
end

-- the room a function line leaves for what it gives
local function gives_room(cols, W)
  return math.max(8, W - (1 + cols.pw + 3 + cols.nw + 3))
end

---------------------------------------------------------------- Used by

local function used_by_file(out, m, list, x, ctx, W)
  local short, marks = shortener(list, x), on_lines(list)
  for _, g in ipairs(seams.by_file(list)) do
    blank(out)
    local key = 'more:f:' .. g.path
    local h = row({ at = { path = g.path, line = g.places[1].line } }):add(' '):add(short(g.path), 'SeamBold')
    h:add('   ' .. plural(#g.places, 'place') .. '   ', 'SeamLabel')
    out[#out + 1] = names(h, g.names, W)
    local shown, more = seams.cut(g.places, ctx.open[key])
    for _, p in ipairs(shown) do
      numbered(out, m, p, W, in_of(p), marks(p), nil, ctx.open[key] and key or nil)
    end
    if more > 0 then
      more_row(out, more, key, 9)
    end
  end
end

-- each name's places: where, what it sits in, the line
local function name_places(out, m, places, short, marks, W, key, open, lw, tw)
  local shown, more = seams.cut(places, open[key])
  for _, p in ipairs(shown) do
    local at = ':' .. p.line
    local r = place_row(p, open[key] and key or nil):add '   '
    r:add(draw.trunc(short(p.path), lw - #at) .. at, 'SeamPath')
    r:to(3 + lw + 2):add(draw.trunc(p.top and p.top.name or '', tw), 'SeamLabel'):to(3 + lw + 2 + tw + (tw > 0 and 2 or 0))
    code_line(r, m, p, W - r.w, marks(p))
    out[#out + 1] = r
  end
  if more > 0 then
    more_row(out, more, key, 3)
  end
end

local function used_by_name(out, m, list, x, ctx, W, C)
  local short, marks = shortener(list, x), on_lines(list)
  -- one column for where and one for what it sits in, down the whole view
  local lw, tw = 0, 0
  for _, p in ipairs(list) do
    lw = math.max(lw, width(short(p.path) .. ':' .. p.line))
    tw = math.max(tw, width(p.top and p.top.name or ''))
  end
  lw, tw = math.min(lw, math.floor(W * 0.3)), math.min(tw, 24)
  for _, g in ipairs(seams.by_name(list)) do
    blank(out)
    local h = row({ at = g.decl and { path = g.decl.path, line = g.decl.line, name = g.name } }):add ' '
    name(h, g, true)
    local count = plural(#g.places, 'place') .. ' in ' .. plural(g.files, 'file')
    h:add '   '
    if signature(h, C, g, W - h.w - 3 - width(count)) then
      h:add '   '
    end
    out[#out + 1] = h:add(draw.trunc(count, W - h.w), 'SeamLabel')
    name_places(out, m, g.places, short, marks, W, 'more:n:' .. g.name, ctx.open, lw, tw)
  end
end

local function used_by_user(out, m, list, x, W, C)
  local short = shortener(list, x)
  local groups = seams.by_user(list)
  local fs = {}
  for _, g in ipairs(groups) do
    local f = g.top and g.top.kind == 'fn' and types_view.fn_of(C, g.top.id, 'u:' .. g.top.id)
    g.f = f or nil
    fs[#fs + 1] = g.f
  end
  local cols = types_view.columns(C, fs, 34)
  for _, g in ipairs(groups) do
    blank(out)
    local first = g.places[1]
    if g.f then
      local i = #out + 1
      cols.gw = math.max(8, gives_room(cols, W) - 3 - math.min(width(short(g.path)), 30))
      types_view.fn_rows(out, C, g.f, cols, false)
      after(out[i], short(g.path), W)
      out[i].meta.place = true
    else
      local r = row({ at = { path = g.path, line = g.top and g.top.line or first.line }, place = true }):add ' '
      if g.top and g.top.kind == 'type' then
        r:add((g.top.decl_kind or 'type') .. ' ', '@keyword.type')
        code.add_name(r, g.path, g.top.line, g.top.name, 'SeamType', 60)
      elseif g.top then
        code.add_name(r, g.path, g.top.line, g.top.name, 'SeamName', 60)
        r:add('()', 'SeamPunct')
      else
        r:add('top level', 'SeamText')
      end
      out[#out + 1] = after(r, short(g.path), W)
    end
    local u = row({ at = { path = first.path, line = first.line, col = first.col and first.col - 1 } }):add('   uses ', 'SeamLabel')
    out[#out + 1] = names(u, g.names, W)
  end
end

---------------------------------------------------------------- Built from

local function built_by_file(out, m, list, x, W)
  local short, marks = shortener(list, x), on_lines(list)
  local far = x.kind == 'dir' or x.kind == 'file'
  local nw = 0
  for _, p in ipairs(list) do
    nw = math.max(nw, width(p.name))
  end
  for _, g in ipairs(seams.from_files(list, home_of(m, x))) do
    blank(out)
    local h = row({ at = g.uses[1].decl and { path = g.path, line = 1 } }):add(' '):add(short(g.path), 'SeamBold')
    if g.home then
      h:add('   this file', 'SeamLabel')
    end
    out[#out + 1] = h
    for _, p in ipairs(g.uses) do
      local r = place_row(p):add '   '
      name(r, p, false, nw)
      r:to(3 + nw + 2):add(string.format('%4d', p.line), 'SeamGutter'):add '  '
      local right = far and in_of(p) or nil
      code_line(r, m, p, W - r.w - (right and width(right) + 2 or 0), marks(p), p)
      if right then
        r:to(W - width(right)):add(right, 'SeamLabel')
      end
      out[#out + 1] = r
    end
  end
end

-- what a name is when it has no signature to show: its declaration's kind
local function kind_word(m, p)
  local e = p.id and m.byid[p.id]
  if e then
    return e.kind
  end
  return p.kind == 'type' and 'type' or p.kind == 'fn' and 'function' or 'const'
end

local function built_by_name(out, m, list, x, W, C)
  local short, marks = shortener(list, x), on_lines(list)
  local far = x.kind == 'dir' or x.kind == 'file'
  for _, p in ipairs(seams.first_uses(list)) do
    blank(out)
    local h = row({ at = p.decl and { path = p.decl.path, line = p.decl.line, name = p.name } }):add ' '
    name(h, p, true)
    local where = p.decl and short(p.decl.path) or ''
    h:add '   '
    if not signature(h, C, p, W - h.w - 3 - math.min(width(where), 30)) then
      h:add(kind_word(m, p), 'SeamLabel')
    end
    out[#out + 1] = after(h, where, W)
    numbered(out, m, p, W, far and in_of(p) or nil, marks(p))
  end
end

local function built_signatures(out, m, list, C, W)
  local fns, tys, vals = seams.signatures(list)
  local fs, alone = {}, {}
  for _, p in ipairs(fns) do
    local f = types_view.fn_of(C, p.id, 'b:' .. p.id)
    if f then
      f.place = p
      fs[#fs + 1] = f
    else
      alone[#alone + 1] = p
    end
  end
  local cols = types_view.columns(C, fs, 40)
  cols.gw = gives_room(cols, W)
  for _, f in ipairs(fs) do
    blank(out)
    local i = #out + 1
    types_view.fn_rows(out, C, f, cols, false)
    out[i].meta.place = true
  end
  for _, group in ipairs { { 'calls', alone }, { 'types', tys }, { 'values', vals } } do
    if #group[2] > 0 then
      blank(out)
      local first = group[2][1]
      local r = row { at = first.decl and { path = first.decl.path, line = first.decl.line, name = first.name }, place = true }
      out[#out + 1] = names(r:add(' ' .. group[1] .. '  ', 'SeamLabel'), group[2], W, '   ')
    end
  end
end

---------------------------------------------------------------- the views

local function say(out, text)
  out[#out + 1] = row():add(' ' .. text, 'SeamLabel')
end

--- Used by for row `x`, in `display`.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param display string
---@param ctx seam.ViewCtx
function M.used_by(out, x, m, display, ctx)
  local list = M.places(m, x, 'used')
  if #list == 0 then
    return say(out, x.kind == 'fn' and 'nothing calls it or names it' or x.kind == 'dir' and 'nothing outside it uses it' or 'no other file uses it')
  end
  local W = ctx.width - 1
  local C = types_view.context(m, ctx, home_of(m, x) or '')
  if display == 'by name' then
    used_by_name(out, m, list, x, ctx, W, C)
  elseif display == 'by user' then
    used_by_user(out, m, list, x, W, C)
  else
    used_by_file(out, m, list, x, ctx, W)
  end
end

--- Built from for row `x`, in `display`.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param display string
---@param ctx seam.ViewCtx
function M.built_from(out, x, m, display, ctx)
  local list = M.places(m, x, 'built')
  if #list == 0 then
    return say(
      out,
      x.kind == 'dir' and 'it draws on nothing outside it' or x.kind == 'file' and 'it draws on no other file' or 'it draws on nothing in the repo'
    )
  end
  local W = ctx.width - 1
  local C = types_view.context(m, ctx, home_of(m, x) or '')
  if display == 'by name' then
    built_by_name(out, m, list, x, W, C)
  elseif display == 'as signatures' then
    built_signatures(out, m, list, C, W)
  else
    built_by_file(out, m, list, x, W)
  end
end

return M
