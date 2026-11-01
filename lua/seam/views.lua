-- The pane's views, a tab each: which rows each has something for, the
-- displays it can be shown in, and how it draws. A later view is one more
-- entry in the list. `st.view` holds the one chosen and each view's display.
local calls_draw = require 'seam.draw.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local theme = require 'seam.theme'
local M = {}

---@class seam.View
---@field name string its tab
---@field displays string[] the ways it can be shown, the first by default
---@field has fun(row: seam.ORow): boolean
---@field draw fun(out: table[], row: seam.ORow, m: table, display: string)

---@class seam.ViewState
---@field at string the view chosen, by name
---@field display table<string, string> each view's display chosen

---@return seam.ViewState
function M.new()
  return { at = 'Code', display = {} }
end

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

-- the code of a function from its doc comment to its end, or a whole file,
-- with line numbers; each call in it marked where its function lives
local function code_view(out, row, m)
  local g = m.graph
  local path, s, e, nodes
  if row.kind == 'fn' then
    local node = g.nodes[row.id]
    path, nodes = node.path, { node }
    s, e = code.doc_start(path, node.line), math.max(node.end_line or node.line, node.line)
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

---@type seam.View[]
M.list = {
  {
    name = 'Code',
    displays = { 'code' },
    has = function(row)
      return row.kind ~= 'dir'
    end,
    draw = function(out, row, m)
      code_view(out, row, m)
    end,
  },
}

--- The views that have something for `row`, in the tabs' order.
---@param row seam.ORow|nil
---@return seam.View[]
function M.of(row)
  local out = {}
  for _, v in ipairs(M.list) do
    if row and v.has(row) then
      out[#out + 1] = v
    end
  end
  return out
end

--- The view shown for `row` and its display: the one chosen when it has
--- something for the row, else the first that has.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@return seam.View|nil, string|nil
function M.shown(row, sv)
  local list = M.of(row)
  local v = list[1]
  for _, x in ipairs(list) do
    if x.name == sv.at then
      v = x
    end
  end
  if not v then
    return nil
  end
  local d = sv.display[v.name]
  return v, vim.tbl_contains(v.displays, d) and d or v.displays[1]
end

--- The next view, or the one before when `d` is negative, among those
--- that have something for `row`. False when there is no other.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param d integer
---@return boolean
function M.step(row, sv, d)
  local list = M.of(row)
  local v = M.shown(row, sv)
  if #list < 2 or not v then
    return false
  end
  local i = 1
  for j, x in ipairs(list) do
    if x == v then
      i = j
    end
  end
  sv.at = list[(i - 1 + d) % #list + 1].name
  return true
end

--- The view's next display, or the one before. False when it has one.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param d integer
---@return boolean
function M.step_display(row, sv, d)
  local v, now = M.shown(row, sv)
  if not v or #v.displays < 2 then
    return false
  end
  local i = vim.fn.index(v.displays, now) + 1
  sv.display[v.name] = v.displays[(i - 1 + d) % #v.displays + 1]
  return true
end

return M
