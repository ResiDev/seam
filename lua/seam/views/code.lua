-- The Code view: a function from its doc comment to its end, a file whole,
-- a type's declaration; each name from another file underlined where it
-- lives, each value's type after its name where none is written.
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local theme = require 'seam.theme'
local M = {}

--- How a name used in `from` and declared in `to` is marked: nothing in its
--- own file, underlined from another file, underlined in its package's hue
--- from another package.
---@param m table
---@param from string a path
---@param to string a path
---@return string|nil
function M.under(m, from, to)
  if from == to then
    return nil
  end
  local pkg = index.pkg_of(m, to)
  if pkg ~= index.pkg_of(m, from) then
    return theme.hue(pkg).under
  end
  return 'SeamUnder'
end

--- Code rows of `path` for the lines in `set`, a ⋯ between runs, `lit`
--- lines lit, `mark(r, start, src, l)` underlining on each; the first lit.
---@param out table[]
---@param path string
---@param set table<integer, true>
---@param lit table<integer, true>
---@param mark fun(r: table, start: integer, src: string, l: integer)
---@return integer|nil
function M.rows(out, path, set, lit, mark)
  local lines = vim.tbl_keys(set)
  table.sort(lines)
  local gw = math.max(3, #tostring(lines[#lines] or 1))
  local P = code.file(path)
  local first, prev
  for _, l in ipairs(lines) do
    if prev and l > prev + 1 then
      out[#out + 1] = draw.row():add(string.rep(' ', gw) .. '⋯', 'SeamLabel')
    end
    local cr = draw.row { kind = 'code', lnum = l }
    cr:add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
    local start = cr.b
    code.add(cr, path, l)
    if lit[l] then
      cr.line_hl = 'SeamLit'
      first = first or #out + 1
    end
    mark(cr, start, P.lines[l] or '', l)
    out[#out + 1] = cr
    prev = l
  end
  return first
end

--- What a row's code is: its file and its lines, a function from its doc
--- comment, a type's declaration, a file whole; and the nodes it holds.
---@param row seam.ORow
---@param m table
---@return string path, integer s, integer e, table[] nodes
function M.span(row, m)
  local g = m.graph
  if row.kind == 'fn' then
    local node = g.nodes[row.id]
    return node.path, code.doc_start(node.path, node.line), math.max(node.end_line or node.line, node.line), { node }
  elseif row.kind == 'type' then
    return row.path, code.doc_start(row.path, row.line), math.max(row.end_line or row.line, row.line), {}
  end
  return row.path, 1, #code.file(row.path).lines, g and outline.by_file(g)[row.path] or {}
end

-- the names in lines s..e that live in another file, by line: each call,
-- each use of another file's export
local function elsewhere(m, path, s, e, nodes)
  local g, out, seen = m.graph, {}, {}
  local function add(l, name, col, to)
    local hl = l >= s and l <= e and M.under(m, path, to)
    if hl and not seen[l .. ':' .. col] then
      seen[l .. ':' .. col] = true
      out[l] = out[l] or {}
      table.insert(out[l], { name, col, hl })
    end
  end
  for _, n in ipairs(nodes) do
    for _, c in ipairs(g.down[n.id] or {}) do
      add(c.line, g.nodes[c.to].name, c.col, g.nodes[c.to].path)
    end
  end
  if not m.uses_in then
    m.uses_in = {}
    for _, x in ipairs(m.exports or {}) do
      for _, u in ipairs(x.uses or {}) do
        m.uses_in[u.path] = m.uses_in[u.path] or {}
        table.insert(m.uses_in[u.path], { u.line, x.name, u.col, x.path })
      end
    end
  end
  for _, u in ipairs(m.uses_in[path] or {}) do
    add(u[1], u[2], u[3], u[4])
  end
  return out
end

--- Lines s..e of `path` as code rows, with line numbers: each name from
--- another file underlined where it lives (its place on the row kept in
--- the row's `stops`), each value's type after its name where none is
--- written, a function's return after its parameters.
---@param out table[]
---@param m table
---@param path string
---@param s integer
---@param e integer
---@param nodes table[] the functions whose calls are underlined
function M.lines(out, m, path, s, e, nodes)
  local refs = elsewhere(m, path, s, e, nodes)
  local hints = {}
  for _, h in ipairs(require('seam.codetypes').hints(m, path, s, e)) do
    hints[h.line] = hints[h.line] or {}
    table.insert(hints[h.line], h)
  end
  local set = {}
  for l = s, e do
    set[l] = true
  end
  -- the lines the range changed, their numbers in the signs' colours
  local changed = require 'seam.views.changed'
  local marks = changed.marks(path)
  M.rows(out, path, set, {}, function(cr, start, src, l)
    if marks[l] then
      cr.h[#cr.h + 1] = { 0, start, changed.MARK_HL[marks[l]], 160 }
    end
    cr.meta.stops = {}
    for _, r in ipairs(refs[l] or {}) do
      local before = #cr.h
      code.underline(cr, start, src, r[1], r[2], r[3])
      if #cr.h > before then
        table.insert(cr.meta.stops, cr.h[#cr.h][1])
      end
    end
    table.sort(cr.meta.stops)
    cr.meta.start = start
    for _, h in ipairs(hints[l] or {}) do
      cr.virt = cr.virt or {}
      cr.virt[#cr.virt + 1] = { start + h.col, h.text }
    end
  end)
end

---@param out table[]
---@param row seam.ORow
---@param m table
function M.draw(out, row, m)
  local path, s, e, nodes = M.span(row, m)
  if e < s then
    out[#out + 1] = draw.row():add(' nothing to read here', 'SeamLabel')
    return
  end
  M.lines(out, m, path, s, e, nodes)
end

return M
