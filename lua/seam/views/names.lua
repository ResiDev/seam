-- The Types view of a name in the code (a row of kind 'name'): a method's
-- line, then the type a field or method is in with its lines lit, then each
-- repo type its type names, written out under labels (`in`, `is`, `takes`,
-- `gives`) and open by default, as a function's own types are. A value no
-- type is written for: the type the TypeScript server says, asked once the
-- pane shows it (seam.lookup), drawn as a written one is.
local draw = require 'seam.draw'
local lookup = require 'seam.lookup'
local tv = require 'seam.typesview'
local types = require 'seam.types'
local types_view = require 'seam.views.types'
local M = {}

local row = draw.row

--- A function type's takes and gives, the parameters' names left out:
--- `(a: A, ...b: B[]) => R` is `(A, B[])` and `R`.
---@param t string
---@return string|nil takes, string|nil gives
function M.shape(t)
  local c = t:sub(1, 1) == '(' and types.closing(t, 1)
  if not c then
    return nil
  end
  local ret = t:sub(c + 1):match '^%s*=>%s*(.*)$'
  local parts = {}
  for _, p in ipairs(tv.parts(t:sub(1, c))) do
    parts[#parts + 1] = p:gsub('^%.%.%.', ''):gsub('^[%w_$]+%??%s*:%s*', '')
  end
  return '(' .. table.concat(parts, ', ') .. ')', ret and vim.trim(ret)
end

---@param out table[]
---@param x seam.ORow a name's row: `n` what seam.names said of it, `from` the code's path
---@param m table
---@param ctx seam.ViewCtx
function M.draw(out, x, m, ctx)
  local n, path = x.n, x.from
  local C = types_view.context(m, ctx, path)
  local line = { id = 'l', names = {}, path = path }
  local labels = {}
  local function add(name, label)
    if not labels[name] then
      labels[name] = label
      line.names[#line.names + 1] = name
    end
  end
  local mem = n.member
  if n.kind == 'method' and mem and mem.type then
    local takes, gives = M.shape(mem.type)
    local r = row { at = { path = mem.decl.path, line = mem.line, name = mem.name } }
    local placed = {}
    r:add ' '
    types_view.typed(r, takes or mem.type, C.known, placed)
    if takes then
      r:add(' → ', 'SeamLabel'):add(n.name, 'SeamName'):add(' → ', 'SeamLabel')
      types_view.typed(r, gives or 'unknown', C.known, placed)
    end
    out[#out + 1] = r
  end
  if (n.kind == 'method' or n.kind == 'field') and mem and mem.decl then
    add(mem.decl.name, 'in')
    C.lit_lines = { path = mem.decl.path, from = mem.doc or mem.line, to = mem.end_line or mem.line }
  end
  local t = n.kind == 'method' and mem and mem.type or n.type
  local said, asking
  if not t and n.at then
    said, asking = lookup.value(path, n.at, function()
      -- drawn again when the pane still shows the name
      local pane = require 'seam.pane'
      local x2 = pane.wins() and pane.subject()
      if x2 and x2.key == x.key then
        pane.redraw()
      end
    end)
    t = said and said.type
  end
  if said then
    out[#out + 1] = row():add(' no type is written for it; the TypeScript server says', 'SeamLabel')
    local r, placed = row():add ' ', {}
    types_view.typed(r, t, C.known, placed)
    -- under the key and line the repo types it names open under below; the
    -- foot off those tells what the server said
    r.meta.tv = { key = 'n', id = 'l', names = placed, chain = {}, path = path }
    r.meta.value = { kind = 'value', name = n.name, from = { path = path, line = n.at.line, col = n.at.col } }
    out[#out + 1] = r
    -- the type's own declaration, a package's: a repo type opens under is below
    local d = said.def
    if d and d.pkg then
      out[#out + 1] = row()
      require('seam.foot').declared(m, d, d.name or '', out)
    end
  end
  if t then
    local takes = n.kind == 'method' and M.shape(t)
    local tk = {}
    for _, nm in ipairs(takes and tv.names(takes, C.known) or {}) do
      tk[nm.name] = true
    end
    for _, nm in ipairs(tv.names(t, C.known)) do
      add(nm.name, n.kind ~= 'method' and 'is' or tk[nm.name] and 'takes' or 'returns')
    end
  end
  if #line.names == 0 then
    if said then
      return
    end
    local r = row():add ' '
    if t then
      types_view.typed(r, t, C.known, {})
    else
      r:add(asking and 'no type is written for it; asking the TypeScript server' or 'no type is written for it', 'SeamLabel')
    end
    out[#out + 1] = r
    return
  end
  for _, nm in ipairs(line.names) do
    local k = tv.child('n', 'l', nm)
    C.defaults[k] = true
    C.top_keys[k] = labels[nm]
  end
  local items = types_view.lay(C, { line }, 'n', {}, {})
  table.remove(items, 1)
  types_view.render(out, C, items)
  -- the first label's blank line is the pane's own
  if #out > 0 and out[1].w == 0 then
    table.remove(out, 1)
  end
end

return M
