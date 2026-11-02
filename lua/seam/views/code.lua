-- The Code view: a function from its doc comment to its end, a file whole,
-- a type's declaration; each name from another file underlined where it
-- lives, each value's type after its name where none is written.
local api = vim.api
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local names = require 'seam.names'
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

-- a name no repo function or type answers, written at byte `col` of line
-- `l`: a package's type, looked up where it is written, or its value
local function written_type(path, l, col)
  local root, src = names.tree(path)
  local n = root and root:named_descendant_for_range(l - 1, col, l - 1, col)
  local t = n and n:type()
  if not (t == 'type_identifier' or t == 'identifier') then
    return nil
  end
  local w = vim.treesitter.get_node_text(n, src)
  local _, sc = n:start()
  if w:match '^%u' then
    return { kind = 'type', name = w, from = { path = path, line = l, col = sc } }
  elseif t == 'identifier' then
    -- a package's function or value, `createRoot`: what the server says of it
    return { kind = 'value', name = w, from = { path = path, line = l, col = sc } }
  end
end

--- What the code copied under the cursor in `win` names, as the foot
--- tells it: a repo function `{ id }`, a repo type `{ kind = 'type', name,
--- decl }`, a type of no repo's `{ kind = 'type', name, from }`, a value no
--- type is written for or a package's `{ kind = 'value', name, from }`,
--- `from` where it is made; nil off one.
---@param win integer
---@param m table
---@return table|nil
function M.at_cursor(win, m)
  local cur = api.nvim_win_get_cursor(win)
  for _, c in ipairs(code.spans(api.nvim_win_get_buf(win), cur[1] - 1)) do
    if type(c[3]) == 'number' and cur[2] >= c[4] and cur[2] < c[4] + c[5] then
      local col = c[3] + cur[2] - c[4]
      local n = names.at(m, c[1], c[2], col)
      if not n then
        return vim.uv.fs_stat(code.root .. '/' .. c[1]) and written_type(c[1], c[2], col) or nil
      elseif n.kind == 'call' then
        return { id = n.id }
      elseif n.kind == 'type' then
        return { kind = 'type', name = n.name, decl = n.decl }
      elseif n.at and m.graph then
        -- a function the file holds as a value, `const f = () => …`
        for _, node in ipairs(outline.by_file(m.graph)[c[1]] or {}) do
          if node.name == n.name and node.line == n.at.line and node.kind ~= 'module' then
            return { id = node.id }
          end
        end
      end
      if n.at and not n.type and (n.kind == 'value' or n.kind == 'param') then
        return { kind = 'value', name = n.name, from = { path = c[1], line = n.at.line, col = n.at.col } }
      end
      return nil
    end
  end
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
---@param diffed? boolean with the range's changes inline, when the diff is on
function M.lines(out, m, path, s, e, nodes, diffed)
  local first = #out + 1
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
  local cd = require 'seam.codediff'
  -- one function: its own lines then and now, as the pane diffs it; else the file
  local whole = s == 1 and e == #code.file(path).lines
  local inline = diffed and cd.diff_of(path, not whole and #nodes == 1 and nodes[1].name or nil)
  local marks = inline and {} or cd.marks(path)
  M.rows(out, path, set, {}, function(cr, start, src, l)
    if marks[l] then
      cr.h[#cr.h + 1] = { 0, start, cd.MARK_HL[marks[l]], 160 }
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
  if inline then
    -- a function's own lines at the range's start, removed before its first line or after its last
    local C = require('seam.changes').get()
    local d = #nodes == 1 and s > 1 and C and require('seam.changes').decl(C, path, nodes[1].name)
    cd.inline(out, first, inline, path, s, e, d and d.from)
  end
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
