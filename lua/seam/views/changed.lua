-- The diff, on D for the session: the Code view of a function's or a
-- type's lines alone, a file whole, a folder's changed files one after
-- another, as the range changed them: removed lines where they were,
-- unnumbered on red; added lines on green; the words that changed on a line
-- lit stronger. Changes only, every run of unchanged lines folded three
-- lines from a change; or whole. For the Types view, a type's own lines and
-- a function's line as it was. Used by now and at the range's start.
local changes = require 'seam.changes'
local code = require 'seam.code'
local diff = require 'seam.diff'
local draw = require 'seam.draw'
local graph = require 'seam.graph'
local index = require 'seam.index'
local outline = require 'seam.outline'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local written = require 'seam.written'
local M = {}

local row, plural = draw.row, draw.plural
local api_width = vim.api.nvim_strwidth

M.DISPLAYS = { 'changes only', 'whole file' }
-- a folder's files shown before the rest is left to its rows
local FILES_MAX = 30

-- the file and the declaration a row stands for: nil for a file's own name
local function subject(m, x)
  if x.kind == 'fn' then
    local n = m.graph.nodes[x.id]
    return n.path, n.name
  elseif x.kind == 'type' then
    return x.path, x.name
  elseif x.kind == 'gone' then
    return x.path, not x.file and x.name or nil
  end
  return x.path, nil
end

-- the changed files under a folder, the lens's leave
local function files_under(m, C, dir)
  local pre, top, out = dir .. '/', graph.visible(m, 'top'), {}
  for _, p in ipairs(C.list) do
    if p:sub(1, #pre) == pre and top(p) then
      out[#out + 1] = p
    end
  end
  return out
end

--- The repo types a function's written signature names that changed, by name.
---@param m table
---@param C seam.Changes
---@param node table
---@return string[]
function M.types_changed(m, C, node)
  C.fntypes = C.fntypes or {}
  local got = C.fntypes[node.id]
  if got then
    return got
  end
  got = {}
  local s = written.fn(node.path, node.line)
  local text = {}
  for _, p in ipairs(s and s.params or {}) do
    text[#text + 1] = p.type or ''
  end
  text[#text + 1] = s and s.ret or ''
  local seen = {}
  for _, n in
    ipairs(tv.names(table.concat(text, ' '), function(w)
      return w:match '^%u' ~= nil
    end))
  do
    if not seen[n.name] then
      seen[n.name] = true
      local t = written.type_in(node.path, n.name) or (m.flows and m.flows[n.name] and m.flows[n.name].decls[1])
      if t and changes.decl(C, t.path, n.name) then
        got[#got + 1] = n.name
      end
    end
  end
  C.fntypes[node.id] = got
  return got
end

--- Is the diff on (D), and has git said what changed?
---@return boolean
function M.on()
  return st.diff == true and changes.get() ~= nil
end

--- `D`: the diff on or off, for the session.
function M.toggle()
  st.diff = not st.diff or nil
end

--- Does the row show anything in the range: changed, new, gone, or (but
--- for `own`, its own lines only) a function a type it names changed in?
---@param m table
---@param x seam.ORow
---@param own? boolean
---@return boolean
function M.has(m, x, own)
  local C = changes.get()
  if not (C and #C.list > 0) or x.kind == 'name' then
    return false
  elseif x.kind == 'dir' then
    return #files_under(m, C, outline.full(x.item)) > 0
  end
  local path, name = subject(m, x)
  if not name then
    return C.files[path] ~= nil
  end
  return changes.decl(C, path, name) ~= nil or (not own and x.kind == 'fn' and #M.types_changed(m, C, m.graph.nodes[x.id]) > 0)
end

local WORD = { new = 'new', gone = 'gone', signature = 'signature changed', body = 'body changed', changed = 'changed' }

--- What the pane's head says of the row with the diff on.
---@param m table
---@param x seam.ORow
---@return string|nil
function M.count(m, x)
  local C = changes.get()
  if not C then
    return nil
  elseif x.kind == 'dir' then
    return plural(#files_under(m, C, outline.full(x.item)), 'file') .. ' changed'
  end
  local path, name = subject(m, x)
  if not name then
    local s = C.files[path]
    return s == 'new' and 'new file' or s == 'gone' and 'file gone' or nil
  end
  local d = changes.decl(C, path, name)
  local parts = { d and WORD[d.state] }
  if x.kind == 'fn' then
    local ts = M.types_changed(m, C, m.graph.nodes[x.id])
    if #ts > 0 then
      parts[#parts + 1] = table.concat(ts, ', ') .. ', ' .. (#ts == 1 and 'a type it names,' or 'types it names,') .. ' changed'
    end
  end
  return #parts > 0 and table.concat(parts, '; ') or nil
end

---------------------------------------------------------------- the lines

-- the bytes of `spans` on row `r`, its line starting at byte `start`, lit with `hl`
local function lit(r, start, spans, hl)
  for _, s in ipairs(spans or {}) do
    r.h[#r.h + 1] = { start + s[1], start + s[2], hl, 200 }
  end
end

--- A removed line as a row: unnumbered, `indent` columns in, on red, the
--- words that changed on it lit stronger; `at` where gf goes, `change`
--- when a change starts on it.
---@param text string
---@param spans integer[][]|nil
---@param indent integer
---@param at table
---@param change boolean|nil
---@return table
function M.del_row(text, spans, indent, at, change)
  local r = row { at = at, change = change }
  r:add(string.rep(' ', indent))
  local start = r.b
  r:add(text, 'SeamDiffDeleteFg')
  r.bg = 'SeamDiffDelete'
  lit(r, start, spans, 'SeamDiffDeleteText')
  return r
end

--- An added line's row on green, the words that changed on it lit
--- stronger, its code starting at byte `start`.
---@param r table
---@param start integer
---@param spans integer[][]|nil
function M.add_lit(r, start, spans)
  r.bg = 'SeamDiffAdd'
  lit(r, start, spans, 'SeamDiffAddText')
end

--- Rows of laid-out lines: an added or unchanged line numbered, as code;
--- a removed one unnumbered on red; a fold. Lines a0 + i of the version at
--- `from` (`ka`) and b0 + i of the one at `to` (`kb`), `path` the file gf goes to.
---@param out table[]
---@param items seam.DiffItem[]
---@param ka string|nil
---@param kb string|nil
---@param path string
---@param a0 integer
---@param b0 integer
function M.lines(out, items, ka, kb, path, a0, b0)
  local A = changes.lines(ka)
  local last = 1
  for _, it in ipairs(items) do
    last = math.max(last, b0 + (it.b or 0))
  end
  local gw = math.max(4, #tostring(last))
  for _, it in ipairs(items) do
    if it.kind == 'fold' then
      out[#out + 1] = row():add(string.rep(' ', gw - 1) .. '  ⋯ ' .. plural(it.n, 'line') .. ' unchanged', 'SeamLabel')
    elseif it.kind == 'del' then
      out[#out + 1] = M.del_row(A[a0 + it.a] or '', it.spans, gw + 3, { path = path, line = math.max(1, b0 + it.b - 1) }, it.start)
    else
      local l = b0 + it.b
      local r = row { kind = 'code', lnum = l, change = it.start, at = { path = path, line = l } }
      r:add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
      local start = r.b
      code.add(r, kb, l)
      if it.kind == 'add' then
        M.add_lit(r, start, it.spans)
      end
      out[#out + 1] = r
    end
  end
end

local function slice(lines, d)
  return d and vim.list_slice(lines, d.s, d.e) or {}
end

--- The items of a declaration's lines at each end, `name` of `path`, and
--- where each starts; nil when it did not change.
---@param C seam.Changes
---@param path string
---@param name string
---@param fold boolean
---@return seam.DiffItem[]|nil, string|nil, string|nil, integer, integer
function M.decl_items(C, path, name, fold)
  local d = changes.decl(C, path, name)
  if not d then
    return nil, nil, nil, 0, 0
  end
  local ka, kb = changes.key(C, path, 'from'), changes.key(C, path, 'to')
  local items = diff.items(slice(changes.lines(ka), d.from), slice(changes.lines(kb), d.to), { fold = fold })
  return items, ka, kb, d.from and d.from.s - 1 or 0, d.to and d.to.s - 1 or (d.from and d.from.s - 1 or 0)
end

-- a file's lines as the range changed them
local function file_rows(out, C, path, fold)
  local ka, kb = changes.key(C, path, 'from'), changes.key(C, path, 'to')
  M.lines(out, diff.items(changes.lines(ka), changes.lines(kb), { fold = fold }), ka, kb, path, 0, 0)
end

---------------------------------------------------------------- a type opened

--- A type opened in place with the diff on (seam.views.types' block),
--- its own lines marked: an added one `+`, the removed ones put back where
--- they were, `-`; `changed` set on the block when the type changed.
---@param d table the declaration: its path, name, line
---@param lines table[] the block's lines, by source line
---@return table[] lines, boolean changed
function M.block_diff(d, lines)
  local C = changes.get()
  local dc = C and not C.range.to and changes.decl(C, d.path, d.name)
  if not dc then
    return lines, false
  end
  local A = changes.lines(changes.key(C, d.path, 'from'))
  local added, before = {}, {}
  local b0 = dc.to and dc.to.s - 1 or 0
  local a0 = dc.from and dc.from.s - 1 or 0
  for _, it in ipairs(diff.items(slice(A, dc.from), slice(changes.lines(d.path), dc.to))) do
    if it.kind == 'add' then
      added[b0 + it.b] = true
    elseif it.kind == 'del' then
      local at = b0 + it.b
      before[at] = before[at] or {}
      table.insert(before[at], { id = 'd' .. (a0 + it.a), names = {}, kind = 'del', text = A[a0 + it.a] or '' })
    end
  end
  local out, last = {}, nil
  for _, l in ipairs(lines) do
    if type(l.id) == 'number' then
      vim.list_extend(out, before[l.id] or {})
      before[l.id] = nil
      l.mark = added[l.id] and '+' or nil
      last = l.id
    end
    out[#out + 1] = l
  end
  -- removed past its last line
  for at = (last or 0) + 1, (last or 0) + 2 do
    vim.list_extend(out, before[at] or {})
  end
  return out, true
end

---------------------------------------------------------------- Used by

--- How the function on row `x` changed when its signature or body did.
---@param m table
---@param x seam.ORow
---@return seam.DeclChange|nil
function M.changed_fn(m, x)
  local C = changes.get()
  local n = C and x.kind == 'fn' and m.graph.nodes[x.id]
  local d = n and changes.decl(C, n.path, n.name)
  return d and (d.state == 'signature' or d.state == 'body') and d or nil
end

-- the places that named the function at `from`: the files the range left
-- alone as they name it now, the others read at `from`
local function then_places(m, C, x)
  C.then_places = C.then_places or {}
  local got = C.then_places[x.id]
  if got then
    return got
  end
  local node = m.graph.nodes[x.id]
  got = {}
  for _, p in ipairs(require('seam.views.seams').places(m, x, 'used')) do
    if not C.files[p.path] then
      got[#got + 1] = { path = p.path, line = p.line, col = p.col, key = p.path }
    end
  end
  for _, path in ipairs(C.list) do
    if C.files[path] ~= 'new' then
      for _, u in ipairs(changes.named_at_from(C, path, node.name, node.path)) do
        got[#got + 1] = { path = path, line = u.line, col = u.col, key = changes.key(C, path, 'from') }
      end
    end
  end
  C.then_places[x.id] = got
  return got
end

--- What the pane's head says in Used by of a function that changed: how,
--- and how many places use it now and used it at `from`.
---@param m table
---@param x seam.ORow
---@return string|nil
function M.used_count(m, x)
  local d = M.changed_fn(m, x)
  if not d then
    return nil
  end
  local C = assert(changes.get())
  local now = #require('seam.views.seams').places(m, x, 'used')
  return ('%s   used by %s now, %d at %s'):format(WORD[d.state], plural(now, 'place'), #then_places(m, C, x), C.range.from)
end

-- a function's line as written in a version: (name: Type, …) → name → gives
local function was_line(r, key, d, name, gives)
  local s = key and written.fn(key, d.line)
  local ps = {}
  for _, p in ipairs(s and s.params or {}) do
    ps[#ps + 1] = p.name .. (p.optional and '?' or '') .. (p.type and (': ' .. tv.simple(p.type)) or '')
  end
  local types_view = require 'seam.views.types'
  local known = function(w)
    return w:match '^%u' ~= nil
  end
  types_view.typed(r, '(' .. table.concat(ps, ', ') .. ')', known, {}, nil)
  r:add(' → ', 'SeamLabel'):add(name, 'SeamName'):add(' → ', 'SeamLabel')
  types_view.typed(r, s and s.ret and tv.simple(s.ret) or gives or '?', known, {}, nil)
end

--- How the function `node` changed, for its line in Types with the diff
--- on: its declaration's change when it is new or its signature changed and
--- the range ends at the working tree, which the lines drawn are.
---@param node table
---@return seam.DeclChange|nil
function M.fn_state(node)
  local C = changes.get()
  local d = C and not C.range.to and changes.decl(C, node.path, node.name)
  return d and (d.state == 'new' or d.state == 'signature') and d or nil
end

--- Did the range change the type `name` declared in `path`, the range
--- ending at the working tree?
---@param path string
---@param name string
---@return boolean
function M.type_changed(path, name)
  local C = changes.get()
  return C ~= nil and not C.range.to and changes.decl(C, path, name) ~= nil
end

--- What a function took and gave at the range's start, as written then.
---@param node table
---@param d seam.DeclChange
---@return seam.TSig|nil
function M.was_sig(node, d)
  local key = changes.key(assert(changes.get()), node.path, 'from')
  local s = key and d.from and written.fn(key, d.from.line)
  return s and tv.sig(s, nil) or nil
end

--- A function's line as it was at the range's start, `-` on red: with
--- `cols` in the Types view's shape and columns, what it takes, its name,
--- what it gives; else as written, its parameters named. `gives` what it
--- gives where that version does not write it.
---@param node table
---@param d seam.DeclChange
---@param gives string|nil
---@param cols? { pw: integer, nw: integer }
---@return table
function M.was_row(node, d, gives, cols)
  local C = assert(changes.get())
  local key = changes.key(C, node.path, 'from')
  local r = row { at = { path = node.path, line = math.max(1, node.line) }, change = true }
  r:add('-', 'SeamSignDelete'):add ' '
  local sig = cols and M.was_sig(node, d)
  if sig then
    local types_view = require 'seam.views.types'
    local known = function(w)
      return w:match '^%u' ~= nil
    end
    types_view.typed(r, tv.cut(tv.takes(sig), cols.pw), known, {}, nil)
    r:to(2 + cols.pw):add(' → ', 'SeamLabel'):add(node.name, 'SeamName')
    r:to(2 + cols.pw + 3 + cols.nw):add(' → ', 'SeamLabel')
    types_view.typed(r, sig.ret and tv.gives(sig) or gives or '?', known, {}, nil)
  else
    was_line(r, key, d.from, node.name, gives)
  end
  r.bg = 'SeamDiffDelete'
  return r
end

--- Used by on a function whose signature or body changed: its line as it
--- was and is when its signature changed, who uses it now (`now`, Used by
--- as it is), then who used it at `from`, by file, each line as it was.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param display string
---@param ctx seam.ViewCtx
---@param now fun(out: table[], x: seam.ORow, m: table, display: string, ctx: seam.ViewCtx)
function M.used_by(out, x, m, display, ctx, now)
  local C = assert(changes.get())
  local d = assert(M.changed_fn(m, x))
  local node = m.graph.nodes[x.id]
  if d.state == 'signature' then
    -- what it gives as the server said, where neither version writes it
    local sig = m.sigs and m.sigs[x.id] and tv.sig(nil, m.sigs[x.id])
    local gives = sig and tv.gives(sig)
    for _, side in ipairs { { 'was  ', 'from', d.from }, { 'now  ', 'to', d.to } } do
      local r = row():add(' '):add(side[1], 'SeamLabel')
      was_line(r, changes.key(C, node.path, side[2]), side[3], node.name, gives)
      out[#out + 1] = r
    end
    out[#out + 1] = row()
  end
  out[#out + 1] = row():add(' now', 'SeamBold')
  now(out, x, m, display, ctx)
  out[#out + 1] = row()
  out[#out + 1] = row():add(' at ' .. C.range.from, 'SeamBold')
  local list = then_places(m, C, x)
  if #list == 0 then
    out[#out + 1] = row():add(' nothing named it', 'SeamLabel')
    return
  end
  local by, order = {}, {}
  for _, p in ipairs(list) do
    if not by[p.path] then
      by[p.path] = {}
      order[#order + 1] = p.path
    end
    table.insert(by[p.path], p)
  end
  table.sort(order, function(a, b)
    local ta, tb = index.is_test(a), index.is_test(b)
    if ta ~= tb then
      return tb
    end
    return #by[a] > #by[b] or (#by[a] == #by[b] and a < b)
  end)
  local hl = require('seam.views.code').under
  local short = require('seam.seams').shortener(vim.list_extend({ node.path }, order))
  local W = ctx.width - 1
  for _, path in ipairs(order) do
    out[#out + 1] = row()
    local s = C.files[path]
    local h = row({ at = { path = path, line = by[path][1].line } }):add(' '):add(short(path), 'SeamBold')
    h:add(s == 'gone' and '   file gone' or s and ('   ' .. changes.count(C, path) .. ' changed in the file') or '', 'SeamLabel')
    out[#out + 1] = h
    for _, p in ipairs(by[path]) do
      local r = row { at = s and false or { path = path, line = p.line }, place = true }
      r:add('   '):add(string.format('%4d', p.line), 'SeamGutter'):add '  '
      local src = changes.lines(p.key)[p.line] or ''
      local lead = #src:match '^%s*'
      local start = r.b - lead
      local room = W - r.w
      if api_width(src:sub(lead + 1)) > room then
        code.add(r, p.key, p.line, true, math.max(1, room - 1))
        r:add('…', 'SeamLabel')
      else
        code.add(r, p.key, p.line, true)
      end
      code.underline(r, start, src, node.name, p.col, hl(m, path, node.path) or 'SeamUse')
      out[#out + 1] = r
    end
  end
end

---------------------------------------------------------------- the view

--- Code with the diff for row `x`, in `display`.
---@param out table[]
---@param x seam.ORow
---@param m table
---@param display string
---@param ctx seam.ViewCtx
function M.draw(out, x, m, display, ctx)
  local C = changes.get()
  if not C then
    out[#out + 1] = row():add(' git has not said yet', 'SeamLabel')
    return
  end
  local fold = display ~= 'whole file'
  if x.kind == 'dir' then
    local list = files_under(m, C, outline.full(x.item))
    for i, p in ipairs(list) do
      if i > FILES_MAX then
        out[#out + 1] = row():add(' ⋯ ' .. plural(#list - FILES_MAX, 'more file') .. ', each on its row', 'SeamLabel')
        break
      end
      if #out > 0 then
        out[#out + 1] = row()
      end
      local s = C.files[p]
      out[#out + 1] =
        row({ at = { path = p, line = 1 } }):add(' ' .. p, 'SeamBold'):add(s == 'new' and '   new file' or s == 'gone' and '   file gone' or '', 'SeamLabel')
      file_rows(out, C, p, true)
    end
    return
  end
  local path, name = subject(m, x)
  if not name then
    return file_rows(out, C, path, fold)
  end
  local items, ka, kb, a0, b0 = M.decl_items(C, path, name, fold)
  if not items then
    out[#out + 1] = row():add(' its own lines are the same at both ends', 'SeamLabel')
    return
  end
  M.lines(out, items, ka, kb, path, a0, b0)
end

return M
