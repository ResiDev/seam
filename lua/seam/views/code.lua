-- The Code view: a function from its doc comment to its end, a file whole,
-- a type's declaration; each call in it underlined where its function lives.
local calls_draw = require 'seam.draw.calls'
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

---@param out table[]
---@param row seam.ORow
---@param m table
function M.draw(out, row, m)
  local g = m.graph
  local path, s, e, nodes
  if row.kind == 'fn' then
    local node = g.nodes[row.id]
    path, nodes = node.path, { node }
    s, e = code.doc_start(path, node.line), math.max(node.end_line or node.line, node.line)
  elseif row.kind == 'type' then
    path, nodes = row.path, {}
    s, e = code.doc_start(path, row.line), math.max(row.end_line or row.line, row.line)
  else
    path = row.path
    s, e = 1, #code.file(path).lines
    nodes = g and outline.by_file(g)[path] or {}
  end
  if e < s then
    out[#out + 1] = draw.row():add(' nothing to read here', 'SeamLabel')
    return
  end
  local refs = {}
  for _, n in ipairs(nodes) do
    for _, c in ipairs(g.down[n.id] or {}) do
      local to = g.nodes[c.to]
      local hl = c.line >= s and c.line <= e and M.under(m, path, to.path)
      if hl then
        refs[c.line] = refs[c.line] or {}
        table.insert(refs[c.line], { to.name, c.col, hl })
      end
    end
  end
  local set = {}
  for l = s, e do
    set[l] = true
  end
  calls_draw.code_rows(out, path, set, {}, function(cr, start, src, l)
    for _, r in ipairs(refs[l] or {}) do
      code.underline(cr, start, src, r[1], r[2], r[3])
    end
  end)
end

return M
