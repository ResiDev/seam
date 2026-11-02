-- The Types view: a line a function, what it takes, its name, what it
-- gives, the names in one column, a blank line between. A function's own
-- types written out under its line; a file's functions, its exports first,
-- then the types it declares; a folder's functions and types used outside
-- it; a type's givers and takers, then its declaration. A type opens in
-- place under the line naming it (seam.typesview keeps which).
local api = vim.api
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local types = require 'seam.types'
local written = require 'seam.written'
local M = {}

local row = draw.row
-- the lines of one type shown before the rest is left to gf
local DECL_MAX = 60
-- the widest the takes column grows before a signature is cut
local TAKES_MAX = 52

local WORD = {
  ['@type.builtin'] = { 'string', 'number', 'boolean', 'unknown', 'void', 'never', 'any', 'bigint', 'symbol', 'object' },
  ['@constant.builtin'] = { 'undefined', 'null' },
  ['@boolean'] = { 'true', 'false' },
}
local WORD_HL = {}
for hl, ws in pairs(WORD) do
  for _, w in ipairs(ws) do
    WORD_HL[w] = hl
  end
end

local function width(s)
  return api.nvim_strwidth(s)
end

---------------------------------------------------------------- what is a type

-- the type `name` means in `path`: one the file declares, else the repo's
-- of that name, the one in `path` first
local function resolve(m, name, path)
  local t = written.type_in(path, name)
  if t then
    return t
  end
  local f = m.flows and m.flows[name]
  if not f then
    return nil
  end
  for _, e in ipairs(f.decls) do
    if e.path == path then
      return e
    end
  end
  return f.decls[1]
end

local function is_type(m, path)
  return function(name)
    return written.type_in(path, name) ~= nil or (m.flows and m.flows[name]) ~= nil
  end
end

-- a type's declaration as the lines of a block, from its doc comment when
-- `doc`, to its end; the types each line names
local function block(C, d, doc)
  local key = d.path .. ':' .. d.line .. (doc and ':doc' or '')
  if C.blocks[key] then
    return C.blocks[key]
  end
  local P = code.file(d.path)
  local s, e = doc and code.doc_start(d.path, d.line) or d.line, math.max(d.end_line or d.line, d.line)
  local lines, inside = {}, false
  local known = is_type(C.m, d.path)
  for l = s, math.min(e, s + DECL_MAX - 1) do
    local src
    src, inside = tv.code_part(P.lines[l] or '', inside)
    local at = tv.names(src, known)
    local names = {}
    for _, n in ipairs(at) do
      names[#names + 1] = n.name
    end
    lines[#lines + 1] = { id = l, names = names, at = at, path = d.path, kind = 'src' }
  end
  if e > s + DECL_MAX - 1 then
    lines[#lines + 1] = { id = 'more', names = {}, kind = 'more', n = e - s - DECL_MAX + 1 }
  end
  local b = { decl = d, lines = lines }
  -- with the diff on, its own lines as the range changed them
  if C.diff then
    b.lines, b.changed = C.diff(d, lines)
  end
  C.blocks[key] = b
  return b
end

---------------------------------------------------------------- drawing

-- `text` on `r` coloured as code: every type named, the builtins, strings;
-- `lit` lit; each type `known` says is one to open placed in `names` where
-- it sits in the row
local function typed(r, text, known, names, lit)
  local base = r.b
  r:add(text, 'SeamText')
  local i = 1
  while true do
    local a, q = text:match('()(["\'`])', i)
    local b = a and text:find(q, a + 1, true)
    if not b then
      break
    end
    r.h[#r.h + 1] = { base + a - 1, base + b, '@string', 155 }
    i = b + 1
  end
  for a, w in text:gmatch '()([%a_$][%w_$]*)' do
    if WORD_HL[w] then
      r.h[#r.h + 1] = { base + a - 1, base + a - 1 + #w, WORD_HL[w], 155 }
    end
  end
  for a in text:gmatch '()…' do
    r.h[#r.h + 1] = { base + a - 1, base + a - 1 + #'…', 'SeamLabel', 156 }
  end
  for _, n in
    ipairs(tv.names(text, function(w)
      return not WORD_HL[w] and w:match '^[%u_$]' ~= nil
    end))
  do
    local s, e = base + n.s - 1, base + n.e - 1
    r.h[#r.h + 1] = { s, e, 'SeamType', 160 }
    if n.name == lit then
      r.h[#r.h + 1] = { s, e, 'SeamLit', 170 }
    end
    if known(n.name) then
      names[#names + 1] = { s = s, e = e, name = n.name }
    else
      -- a package's, for the foot to look up
      r.meta.others = r.meta.others or {}
      table.insert(r.meta.others, { s = s, e = e, name = n.name })
    end
  end
  return r
end

-- does an open block hold another open one?
local function holds(open, key)
  local under = key .. '|'
  for k, v in pairs(open) do
    if v and k:sub(1, #under) == under then
      return true
    end
  end
  return false
end

-- the names placed on a row of block `key`, line `id`, the one opened last lit
local function light(C, r, key, id, names)
  for _, n in ipairs(names) do
    local k = tv.child(key, id, n.name)
    if tv.is_open(C.open, C.defaults, k) and not holds(C.open, k) and not C.top_keys[k] then
      r.h[#r.h + 1] = { n.s, n.e, 'SeamLit', 170 }
    end
  end
end

local function bar(r, col)
  return r:add(string.rep(' ', col)):add('│', 'SeamSep')
end

-- the rows of laid-out items: a block's head, its lines, under the line
-- naming it; a top block (a function's own types) unbarred, after a blank,
-- `label` saying what the function does with it
local function render(out, C, items)
  local cols, bars = {}, {}
  -- with the diff on, was the row before marked: where a change starts, for ]c
  local was_signed = false
  for _, x in ipairs(items) do
    local d = x.depth
    if x.head then
      local top = C.top_keys[x.key]
      local dc = x.head.decl
      local r = row { at = { path = dc.path, line = dc.line, name = dc.name } }
      if top then
        out[#out + 1] = row()
        r:add(' ' .. top .. ' ', 'SeamLabel')
        bars[d] = nil
      else
        bars[d] = cols[d - 1] or 1
        bar(r, bars[d]):add ' '
      end
      r:add(dc.name, 'SeamTypeBold'):add('   ' .. dc.kind .. ' in ', 'SeamLabel')
      draw.path(r, dc.path, dc.line)
      if x.head.changed then
        r:add('   '):add('~', 'SeamSignChange'):add(' changed', 'SeamLabel')
      end
      r.meta.tv = { key = x.key, chain = x.chain, names = {}, path = dc.path }
      out[#out + 1] = r
    else
      local l = x.line
      local r = l.kind == 'src' and row { kind = 'code', lnum = l.id } or row()
      if bars[d] then
        bar(r, bars[d])
      end
      local names = {}
      if C.diff and (l.kind == 'src' or l.kind == 'del') then
        -- the sign after the bar: + an added line, - a removed one
        local sign = l.kind == 'del' and '-' or l.mark
        r:add(sign or ' ', sign == '-' and 'SeamSignDelete' or sign and 'SeamSignAdd' or nil)
        r.bg = sign == '-' and 'SeamDiffDelete' or sign and 'SeamDiffAdd' or nil
        r.meta.change = (sign and not was_signed) or nil
        was_signed = sign ~= nil
      else
        was_signed = false
      end
      if l.kind == 'del' then
        r:add('      '):add(l.text, 'SeamDiffDeleteFg')
      elseif l.kind == 'src' then
        r:add(string.format('%4d  ', l.id), 'SeamGutter')
        local start = r.b
        local src = code.file(l.path).lines[l.id] or ''
        cols[d] = r.w + #src:match '^%s*'
        code.add(r, l.path, l.id)
        local lit = C.lit_lines
        if lit and lit.path == l.path and l.id >= lit.from and l.id <= lit.to then
          r.line_hl = 'SeamLit'
        end
        for _, n in ipairs(l.at) do
          names[#names + 1] = { s = start + n.s - 1, e = start + n.e - 1, name = n.name }
        end
      elseif l.kind == 'more' then
        r:add(('      ⋯ %d more lines, gf reads them'):format(l.n), 'SeamLabel')
      elseif l.kind == 'part' then
        r:add '   '
        cols[d] = r.w
        typed(r, l.text, C.known, names, C.lit)
      elseif l.kind == 'type' then
        r:add ' '
        cols[d] = r.w
        typed(r, l.name, C.known, names, C.lit)
        r:to(l.col):add(l.note, 'SeamLabel')
      end
      light(C, r, x.key, l.id, names)
      r.meta.tv = { key = x.key, id = l.id, names = names, chain = x.chain, path = l.path or C.path }
      out[#out + 1] = r
    end
  end
end

-- the layout of `lines` in block `key`, inside the blocks of `chain`,
-- `seen` the types not to open again
local function lay(C, lines, key, chain, seen)
  return tv.layout(lines, key, {
    open = C.open,
    defaults = C.defaults,
    resolve = function(name, l, k)
      local d = resolve(C.m, name, l.path or C.path)
      return d and block(C, d, C.top_keys[k] ~= nil) or nil
    end,
  }, #chain, chain, seen)
end

---------------------------------------------------------------- functions

-- a function as its line writes it, or nil when it has no signature
local function fn_of(C, id, key)
  local m = C.m
  local node = m.graph.nodes[id]
  if not node or node.kind == 'module' or node.kind == 'class' then
    return nil
  end
  m.tvsigs = m.tvsigs or {}
  local sig = m.tvsigs[id]
  if sig == nil then
    sig = tv.sig(written.fn(node.path, node.line), m.sigs and m.sigs[id]) or false
    m.tvsigs[id] = sig
  end
  if not sig then
    return nil
  end
  return { id = id, node = node, sig = sig, takes = tv.takes(sig), gives = tv.gives(sig), key = key }
end

-- the columns for a list of functions: the names one width, the takes
-- as wide as the widest, up to what leaves room for the rest
local function columns(C, fs, max)
  local nw, pw, gw = 1, 1, 1
  for _, f in ipairs(fs) do
    nw = math.max(nw, width(f.node.name))
    pw = math.max(pw, width(f.takes))
    -- with the diff on, room for what it took too
    local d = C.diff and require('seam.views.changed').fn_state(f.node)
    local was = d and d.state == 'signature' and require('seam.views.changed').was_sig(f.node, d)
    if was then
      pw = math.max(pw, width(tv.takes(was)))
    end
    gw = math.max(gw, width(f.gives))
  end
  local room = C.width - nw - math.min(gw, 40) - 8
  return { nw = nw, pw = math.max(12, math.min(pw, max or TAKES_MAX, room)) }
end

-- a function's line, opened as written when it is, and the types opened
-- under it; `top` its own types, open by default and written out unbarred
local function fn_rows(out, C, f, cols, kept, top)
  local node, key = f.node, f.key
  local wkey = key .. '|w'
  local is_written = tv.is_open(C.open, nil, wkey)
  local open, parts, close = tv.opened(f.sig)
  -- with the diff on, a sign column: its line as it was over it when its signature changed, + new or changed
  local d = C.diff and require('seam.views.changed').fn_state(node)
  if d and d.state == 'signature' then
    out[#out + 1] = require('seam.views.changed').was_row(node, d, f.gives, cols)
  end
  local r = row { at = { path = node.path, line = math.max(1, node.line), name = node.name } }
  local names = {}
  local o = C.diff and 1 or 0
  if C.diff then
    r:add(d and '+' or ' ', d and 'SeamSignAdd' or nil)
    r.bg = d and 'SeamDiffAdd' or nil
    r.meta.change = (d and d.state == 'new') or nil
  end
  r:add ' '
  typed(r, is_written and open or tv.cut(f.takes, cols.pw), C.known, names, C.lit)
  r:to(o + 1 + cols.pw):add(' → ', 'SeamLabel')
  if kept then
    r:add(node.name, 'SeamText')
  else
    code.add_name(r, node.path, node.line, node.name, 'SeamName', cols.nw)
  end
  r:to(o + 1 + cols.pw + 3 + cols.nw):add(' → ', 'SeamLabel')
  typed(r, cols.gw and tv.cut(f.gives, cols.gw) or f.gives, C.known, names, C.lit)
  local line = { id = 'l', names = {}, path = node.path }
  local seen = {}
  for _, n in ipairs(names) do
    if not seen[n.name] then
      seen[n.name] = true
      line.names[#line.names + 1] = n.name
    end
  end
  if top then
    local takes = {}
    for _, n in ipairs(tv.names(f.takes, C.known)) do
      takes[n.name] = true
    end
    local gives = {}
    for _, n in ipairs(tv.names(f.gives, C.known)) do
      gives[n.name] = true
    end
    for _, n in ipairs(line.names) do
      local k = tv.child(key, 'l', n)
      C.defaults[k] = true
      C.top_keys[k] = (takes[n] and gives[n]) and 'takes and gives' or takes[n] and 'takes' or 'gives'
    end
  end
  light(C, r, key, 'l', names)
  r.meta.tv = { key = key, id = 'l', names = names, chain = {}, fn = wkey, path = node.path, fn_id = f.id }
  out[#out + 1] = r
  if is_written then
    local lines = {}
    for i, p in ipairs(parts) do
      lines[i] = { id = 'p' .. i, names = {}, text = p, kind = 'part', path = node.path }
      for _, n in ipairs(tv.names(p, C.known)) do
        lines[i].names[#lines[i].names + 1] = n.name
      end
    end
    render(out, C, lay(C, lines, wkey, { wkey }, {}))
    local cr = row():add(' ' .. close, 'SeamText')
    cr.meta.tv = { key = wkey, chain = { wkey }, names = {}, path = node.path, fn_id = f.id }
    out[#out + 1] = cr
  end
  local items = lay(C, { line }, key, {}, {})
  table.remove(items, 1)
  render(out, C, items)
end

-- functions a line each, a blank line between
local function fn_list(out, C, fs, cols, kept)
  for i, f in ipairs(fs) do
    if i > 1 then
      out[#out + 1] = row()
    end
    fn_rows(out, C, f, cols, kept)
  end
end

local function title(out, text)
  if #out > 0 and out[#out].w > 0 then
    out[#out + 1] = row()
  end
  out[#out + 1] = row():add(' ' .. text, 'SeamBold')
end

-- rows naming types, a note after each, every type openable under its row
local function type_rows(out, C, list, key)
  local tw = 1
  for _, t in ipairs(list) do
    tw = math.max(tw, width(t.name))
  end
  local lines = {}
  for i, t in ipairs(list) do
    lines[i] = { id = 't' .. i, names = { t.name }, name = t.name, note = t.note, col = tw + 4, kind = 'type', path = t.path }
    -- with the diff on, a type the range changed written out with its own lines
    if C.diff and require('seam.views.changed').type_changed(t.path, t.name) then
      C.defaults[tv.child(key, 't' .. i, t.name)] = true
    end
  end
  render(out, C, lay(C, lines, key, {}, {}))
end

---------------------------------------------------------------- the views

local function fn_view(out, C, id)
  local f = fn_of(C, id, 'f:' .. id)
  if not f then
    out[#out + 1] = row():add(' the TypeScript server said nothing of it', 'SeamLabel')
    return
  end
  local cols = columns(C, { f }, C.width)
  fn_rows(out, C, f, cols, false, true)
end

local function file_view(out, C, path)
  local ex, kept = {}, {}
  for _, n in ipairs(outline.functions(C.m, path)) do
    local f = fn_of(C, n.id, 'f:' .. n.id)
    if f then
      table.insert(n.exported and ex or kept, f)
    end
  end
  local cols = columns(C, vim.list_extend(vim.list_slice(ex), kept))
  if #ex > 0 then
    title(out, 'exported')
    fn_list(out, C, ex, cols)
  end
  if #kept > 0 then
    title(out, 'kept in ' .. path:match '[^/]+$')
    fn_list(out, C, kept, cols, true)
  end
  local ts = {}
  for _, t in ipairs(written.types(path)) do
    ts[#ts + 1] = { name = t.name, note = t.kind .. (t.exported and '' or ', kept to itself'), path = path }
  end
  if #ts > 0 then
    title(out, 'declared in ' .. path:match '[^/]+$')
    type_rows(out, C, ts, 'decls')
  end
  if #out == 0 then
    out[#out + 1] = row():add(' no function or type here', 'SeamLabel')
  end
end

local CALLABLE = { ['function'] = true, component = true, class = true }

local function dir_view(out, C, dir, label)
  local inside = function(p)
    return p:sub(1, #dir + 1) == dir .. '/'
  end
  local fs, ts = {}, {}
  for _, e in ipairs(C.m.exports) do
    if inside(e.path) and not index.is_test(e.path) then
      local files = {}
      for _, u in ipairs(e.uses or {}) do
        if not inside(u.path) and not index.is_test(u.path) then
          files[u.path] = true
        end
      end
      local n = vim.tbl_count(files)
      if n > 0 and CALLABLE[e.kind] and e.kind ~= 'class' then
        local f = fn_of(C, e.id, 'f:' .. e.id)
        if f then
          fs[#fs + 1] = f
        end
      elseif n > 0 and types.KIND[e.kind] then
        ts[#ts + 1] = { name = e.name, n = n, path = e.path, note = draw.plural(n, 'file') }
      end
    end
  end
  table.sort(fs, function(a, b)
    return a.node.path < b.node.path or (a.node.path == b.node.path and a.node.line < b.node.line)
  end)
  table.sort(ts, function(a, b)
    return a.n > b.n or (a.n == b.n and a.name < b.name)
  end)
  if #fs > 0 then
    title(out, 'functions used outside ' .. label)
    fn_list(out, C, fs, columns(C, fs))
  end
  if #ts > 0 then
    title(out, 'types used outside ' .. label)
    type_rows(out, C, ts, 'outside')
  end
  if #out == 0 then
    out[#out + 1] = row():add(' nothing in it is used outside it', 'SeamLabel')
  end
end

local function a(name)
  return (name:match '^[AEIOU]' and 'an ' or 'a ') .. name
end

local function type_view(out, C, x)
  local f = C.m.flows[x.name]
  local gives, takes = {}, {}
  for _, id in ipairs(f and f.gives or {}) do
    gives[#gives + 1] = fn_of(C, id, 'g:' .. id)
  end
  for _, id in ipairs(f and types.takers(f) or {}) do
    takes[#takes + 1] = fn_of(C, id, 't:' .. id)
  end
  C.lit = x.name
  local cols = columns(C, vim.list_extend(vim.list_slice(gives), takes))
  if #gives > 0 then
    title(out, 'gives ' .. a(x.name))
    fn_list(out, C, gives, cols)
  end
  if #takes > 0 then
    title(out, 'takes ' .. a(x.name))
    fn_list(out, C, takes, cols)
  end
  if #out > 0 then
    out[#out + 1] = row()
  end
  render(out, C, lay(C, block(C, x, true).lines, 'decl', {}, { [x.name] = true }))
end

--- What function lines are drawn with, here and in the views that show
--- them (Used by and Built from as signature lines): the types opened in
--- place for the pane's row, the pane's width, the types `path` names.
---@param m table
---@param ctx seam.ViewCtx
---@param path string
---@return table
function M.context(m, ctx, path)
  local C = {
    m = m,
    open = ctx.open,
    defaults = {},
    top_keys = {},
    blocks = {},
    width = ctx.width,
    path = path,
    known = is_type(m, path),
    -- with the diff on, in the Types view: each type opened with its own lines
    diff = ctx.diff and require('seam.views.changed').block_diff or nil,
  }
  ctx.defaults = C.defaults
  return C
end

--- A function as its line writes it, under the key `key`, nil without a signature.
M.fn_of = fn_of
--- The columns for a list of functions.
M.columns = columns
--- A function's line, and the types opened under it.
M.fn_rows = fn_rows
--- Text coloured as a signature is.
M.typed = typed
--- The layout of lines in a block, the types open under them (seam.typesview).
M.lay = lay
--- The rows of laid-out items.
M.render = render

--- What is under the cursor in `win`, drawn as the Types view draws, as
--- the foot tells it: a type named there, resolved in the file its line is
--- from (`path` when the line does not say), a type's head, a type of no
--- repo's named in that file, a value's type the server said
--- (seam.views.names), a name in a declaration's copied code, else the
--- function whose line it is.
---@param win integer
---@param m table
---@param path string|nil
---@return table|nil
function M.at_cursor(win, m, path)
  local buf = api.nvim_win_get_buf(win)
  local cur = api.nvim_win_get_cursor(win)
  local meta = draw.meta(buf, cur[1])
  local t = meta.tv
  if not t then
    return nil
  end
  path = t.path or path
  local n = tv.at(t.names, cur[2])
  if not n and meta.at then
    -- the name a row is about: a type's head, a type declared in the code
    local s = (api.nvim_buf_get_lines(buf, cur[1] - 1, cur[1], false)[1] or ''):find(meta.at.name, 1, true)
    n = s and cur[2] >= s - 1 and cur[2] < s - 1 + #meta.at.name and { name = meta.at.name } or nil
  end
  local d = n and path and resolve(m, n.name, path)
  if d then
    return { kind = 'type', name = n.name, decl = d }
  elseif meta.value then
    return meta.value
  end
  local o = path and tv.at(meta.others or {}, cur[2])
  if o then
    return { kind = 'type', name = o.name, from = { path = path } }
  end
  return require('seam.views.code').at_cursor(win, m) or (t.fn_id and { id = t.fn_id }) or nil
end

--- Why there are no types to show, said in one dim line.
---@return string
function M.why()
  index.types(st.root)
  if index.asking_types(st.root) then
    return 'no types yet: the TypeScript server is being asked, and the pane redraws when they land'
  elseif index.types_refused(st.root) then
    return 'no types: the TypeScript server did not answer for this repo; :Seam! asks again'
  end
  return 'no types: this repo has no call graph to type; :Seam! indexes it again'
end

--- The view for `x`.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param ctx seam.ViewCtx
function M.draw(out, x, m, ctx)
  if not (m.graph and m.sigs) then
    out[#out + 1] = row():add(' ' .. M.why(), 'SeamLabel')
    return
  end
  local path = x.kind == 'dir' and outline.full(x.item) or x.path
  local C = M.context(m, ctx, path)
  -- the type the pane's head names, opened over the view
  if ctx.head then
    local items = lay(C, { { id = 1, names = { ctx.head }, path = path } }, 'head', {}, {})
    table.remove(items, 1)
    if #items > 0 then
      render(out, C, items)
      out[#out + 1] = row()
    end
  end
  if x.kind == 'fn' then
    fn_view(out, C, x.id)
  elseif x.kind == 'file' then
    file_view(out, C, x.path)
  elseif x.kind == 'type' then
    type_view(out, C, x)
  else
    dir_view(out, C, path, (x.item.segs and table.concat(x.item.segs, '/') or path:match '[^/]+$') .. '/')
  end
end

return M
