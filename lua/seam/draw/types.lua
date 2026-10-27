-- The Types screen drawn: every repo type the most travelled first, or one
-- type's flow, the functions that make it then the ones that take it; and
-- beside it the type's declaration, or the function under the cursor.
local api = vim.api
local calls_draw = require 'seam.draw.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local page = require 'seam.draw.page'
local tree = require 'seam.tree'
local types = require 'seam.types'
local M = {}

local row, trunc, plural = draw.row, draw.trunc, draw.plural

-- the list's width, and where its columns end or start
M.LW = calls_draw.LW
local N_END, MAKE_END, TAKE_END, DECL_AT = 47, 53, 60, 62

---@class seam.TypesView
---@field kind 'types'
---@field flow string|nil the type followed; nil: the list of them all
---@field cursor string|nil the key of the row under the cursor
---@field top integer|nil the first row in view, to come back to

---@class seam.TypesRow
---@field key string
---@field kind 'type'|'section'|'fn'|'blank'
---@field flow seam.Flow|nil a type's row
---@field section 'gives'|'takes'|nil
---@field id string|nil a function's node
---@field n integer|nil a section's functions

local function base(path)
  return path:match '[^/]+$' or path
end

--- The rows of a view: a type a row, or a flow's two sections, made by then
--- taken by, a function a row; with the rows the cursor stops on and the
--- section titles.
---@param m table the model
---@param view seam.TypesView
---@return { rows: seam.TypesRow[], stops: integer[], sections: integer[] }
function M.rows(m, view)
  local rows, stops, sections = {}, {}, {}
  local function put(x, stop)
    rows[#rows + 1] = x
    if stop then
      stops[#stops + 1] = #rows
    end
  end
  if not view.flow then
    for _, f in ipairs(m.flowlist or {}) do
      put({ key = f.name, kind = 'type', flow = f }, true)
    end
    return { rows = rows, stops = stops, sections = sections }
  end
  local f = m.flows and m.flows[view.flow]
  if not f then
    return { rows = rows, stops = stops, sections = sections }
  end
  for _, s in ipairs { { 'gives', f.gives }, { 'takes', types.takers(f) } } do
    if #rows > 0 then
      put { key = 'blank', kind = 'blank' }
    end
    put({ key = s[1], kind = 'section', section = s[1], n = #s[2] }, true)
    sections[#sections + 1] = #rows
    for _, id in ipairs(s[2]) do
      put({ key = s[1] .. '\n' .. id, kind = 'fn', section = s[1], id = id }, true)
    end
  end
  return { rows = rows, stops = stops, sections = sections }
end

local function decl_at(e)
  return { path = e.path, line = e.line, name = e.name }
end

--- The head: the list says what it is; a flow, the type and where it is
--- declared, then how many functions it goes through, made by and taken by.
---@param buf integer
---@param m table
---@param view seam.TypesView
---@return integer rows
function M.head(buf, m, view)
  local f = view.flow and m.flows and m.flows[view.flow]
  if not f then
    local h = row():add(' Types', 'SeamLabel')
    h:add(('   %d types of the repo in what its functions take and give, the most travelled first'):format(#(m.flowlist or {})), 'SeamLabel')
    draw.put(buf, { h, row() })
    return 2
  end
  local e = f.decls[1]
  local h = row():add(' Types › ', 'SeamLabel'):add(f.name, 'SeamTypeBold')
  if #f.decls > 1 then
    h:add(' ×' .. #f.decls, 'SeamLabel')
  end
  h:add('   ' .. e.kind .. ' in ', 'SeamLabel')
  draw.path(h, e.path, e.line)
  local t = row():add(('   through %s:  made by '):format(plural(f.n, 'function')), 'SeamLabel')
  t:add(tostring(#f.gives), 'SeamText'):add('  ·  taken by ', 'SeamLabel'):add(tostring(#types.takers(f)), 'SeamText')
  draw.put(buf, { h, t })
  return 2
end

--- The column titles over the list, for its window's bar; a flow has none.
---@param view seam.TypesView
---@return string
function M.titles(view)
  if view.flow then
    return ''
  end
  local r = row()
  r:to(N_END - 9):add 'functions'
  r:to(MAKE_END - 4):add 'make'
  r:to(TAKE_END - 4):add 'take'
  r:to(DECL_AT):add 'declared in'
  return '%#SeamLabel#' .. r:text()
end

local function right(r, s, at, hl)
  return r:to(at - api.nvim_strwidth(s)):add(s, hl or 'SeamText')
end

--- The rows drawn.
---@param buf integer
---@param m table
---@param view seam.TypesView
---@param rs table what M.rows gave
function M.list(buf, m, view, rs)
  local g = m.graph
  local out = {}
  for _, x in ipairs(rs.rows) do
    local d
    if x.kind == 'type' then
      local f, e = x.flow, x.flow.decls[1]
      d = row { at = decl_at(e) }
      tree.bar(d, e.pkg)
      d:add ' '
      d:add(trunc(f.name, N_END - 6 - d.w), 'SeamType')
      if #f.decls > 1 then
        d:add(' ×' .. #f.decls, 'SeamLabel')
      end
      right(d, tostring(f.n), N_END)
      right(d, tostring(#f.gives), MAKE_END)
      right(d, tostring(#types.takers(f)), TAKE_END)
      d:to(DECL_AT):add(trunc(base(e.path) .. ':' .. e.line, M.LW - DECL_AT - 1), 'SeamPath')
    elseif x.kind == 'section' then
      local f = m.flows[view.flow]
      d = row { at = decl_at(f.decls[1]) }
      d:add(x.section == 'gives' and ' made by' or ' taken by', 'SeamSection'):add('  ' .. x.n, 'SeamLabel')
    elseif x.kind == 'fn' then
      local node = g.nodes[x.id]
      d = row { at = { path = node.path, line = math.max(1, node.line), name = node.kind ~= 'module' and node.name or nil } }
      tree.bar(d, index.pkg_of(m, node.path))
      d:add ' '
      calls_draw.name(d, node, node.test and 'SeamTest' or 'SeamName', calls_draw.SIG_AT + 8 - d.w)
      local f = m.flows[view.flow]
      if f.new and f.new[x.id] and x.section == 'gives' then
        d:add(' new', 'SeamLabel')
      end
      calls_draw.sig(d, m, x.id, view.flow)
    else
      d = row { at = false }
    end
    out[#out + 1] = d
  end
  if #rs.rows == 0 then
    out[#out + 1] = row({ at = false }):add(view.flow and '  no function takes or makes it' or '  no type of the repo flows through a function', 'SeamLabel')
  end
  draw.put(buf, out)
end

-- every place `name` is written on a row of code, underlined
local function underline_all(cr, start, src, name)
  local i = 1
  while true do
    local a, b = src:find('%f[%w_$]' .. vim.pesc(name) .. '%f[^%w_$]', i)
    if not a then
      return
    end
    cr.h[#cr.h + 1] = { start + a - 1, start + b, 'SeamUse', 320 }
    i = b + 1
  end
end

-- a type's declarations, each its head then its lines; and what it goes
-- through, the key to its flow when it is not the one shown
local function declaration(out, m, f, shown)
  for j, e in ipairs(f.decls) do
    if j > 1 then
      out[#out + 1] = row()
    end
    local h = row():add(' ' .. f.name, 'SeamTypeBold'):add('   ' .. e.kind .. ' in ', 'SeamLabel')
    draw.path(h, e.path, e.line)
    out[#out + 1] = h
    out[#out + 1] = row()
    local s, l = page.decl_range(e)
    local set = {}
    for k = s, l do
      set[k] = true
    end
    calls_draw.code_rows(out, e.path, set, {}, function() end)
  end
  out[#out + 1] = row()
  local r = row():add((' made by %d  ·  taken by %d'):format(#f.gives, #types.takers(f)), 'SeamLabel')
  if not shown then
    r:add('  ·  ', 'SeamLabel'):add('l', 'SeamText'):add(' its flow', 'SeamLabel')
  end
  out[#out + 1] = r
end

-- a function of the flow: its head, what it takes and gives, the type lit,
-- and its code, the type underlined wherever it is written
local function fn(out, m, id, name)
  local node = m.graph.nodes[id]
  local h = row():add ' '
  calls_draw.name(h, node, 'SeamBold', 60)
  if not node.exported and node.kind ~= 'module' then
    h:add(' local', 'SeamDim')
  end
  h:add('   ' .. (node.kind == 'module' and 'top of the file' or node.kind) .. ' in ', 'SeamLabel')
  draw.path(h, node.path, node.line > 0 and node.line or nil)
  out[#out + 1] = h
  calls_draw.takes_gives(out, m, id, name)
  out[#out + 1] = row()
  local set = {}
  for l = code.doc_start(node.path, node.line), math.max(node.end_line or node.line, node.line) do
    set[l] = true
  end
  calls_draw.code_rows(out, node.path, set, {}, function(cr, start, src)
    underline_all(cr, start, src, name)
  end)
end

--- Beside the list: the type under the cursor, its declaration; in a flow,
--- the function under the cursor, or on a title the type's declaration.
---@param buf integer
---@param win integer|nil
---@param m table
---@param view seam.TypesView
---@param x seam.TypesRow|nil
function M.pane(buf, win, m, view, x)
  local out = { row() }
  if x and x.kind == 'type' then
    declaration(out, m, x.flow, false)
  elseif x and x.kind == 'fn' then
    fn(out, m, x.id, view.flow)
  elseif view.flow and m.flows[view.flow] then
    declaration(out, m, m.flows[view.flow], true)
  end
  draw.put(buf, out)
  code.scroll_to(win, 1, 1)
end

return M
