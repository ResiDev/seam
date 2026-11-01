-- The Map's foot: the name under the pane's cursor told in full, in a
-- window over the pane's last rows, a rule over it. A function: its
-- signature with the names of what it takes, and where it is; then the line
-- that calls it, copied with its colours, and what that line sits in. A
-- type: where it is declared, how many make and take it, and its
-- declaration as written, comments left out.
local api = vim.api
local code = require 'seam.code'
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local index = require 'seam.index'
local tv = require 'seam.typesview'
local M = {}

-- the rows a foot takes at most, its rule among them; the Map leaves as
-- many empty under it, so its last rows can scroll up out from under
M.MAX = 10
-- a type's declaration's lines before ⋯ N more lines
M.DECL = 7

local F = {}

local function known(w)
  return w:match '^%u' ~= nil
end

-- the line `lnum` of `path` from its first letter, cut with … at `room`
local function code_line(r, path, lnum, room)
  local src = code.file(path).lines[lnum] or ''
  local text = vim.trim(src)
  if api.nvim_strwidth(text) > room then
    code.add(r, path, lnum, true, math.max(1, room - 1))
    r:add('…', 'SeamLabel')
  else
    code.add(r, path, lnum, true)
  end
end

local function fn_rows(m, it, W)
  local n = m.graph.nodes[it.id]
  if not n then
    return nil
  end
  local types_view = require 'seam.views.types'
  local r = draw.row():add(' '):add(data.label(n), 'SeamMapFnBold')
  local f = types_view.fn_of(types_view.context(m, { open = {}, width = W }, n.path), it.id, 'foot:' .. it.id)
  if f then
    local ps = {}
    for i, p in ipairs(f.sig.params) do
      ps[i] = p.name .. (p.optional and '?' or '') .. (p.type and (': ' .. tv.simple(p.type)) or '')
    end
    types_view.typed(r, '(' .. table.concat(ps, ', ') .. ')', known, {}, nil)
    r:add(' → ', 'SeamLabel')
    types_view.typed(r, f.gives, known, {}, nil)
  end
  r:add('   ' .. data.short(m, n.path, n.path) .. ':' .. n.line, 'SeamLabel')
  local rows = { r }
  if it.at then
    local where = it.at.path:match '[^/]+$' .. ':' .. it.at.line
    local c = draw.row():add(' '):add(where, 'SeamLabel'):add(string.rep(' ', math.max(2, 24 - #where)))
    local right = 'in ' .. it.at.inside
    code_line(c, it.at.path, it.at.line, W - c.w - api.nvim_strwidth(right) - 3)
    c:to(W - api.nvim_strwidth(right) - 1):add('in ', 'SeamLabel'):add(it.at.inside, 'SeamMapFn')
    rows[2] = c
  end
  return rows
end

local function type_rows(m, it, W)
  local f = m.flows and m.flows[it.name]
  local e = f and f.decls[1]
  if not e then
    return nil
  end
  local makers, takers = data.flow(m, it.name)
  local rows = {
    draw
      .row()
      :add(' ')
      :add(it.name, 'SeamTypeBold')
      :add(('   type in %s:%d   made by %d, taken by %d'):format(data.short(m, e.path, e.path), e.line, #makers, #takers), 'SeamLabel'),
  }
  local lines = code.file(e.path).lines
  local keep, inside = {}, false
  for l = e.line, math.max(e.line, e.end_line or e.line) do
    local s = vim.trim(lines[l] or '')
    if inside then
      inside = not s:find('*/', 1, true)
    elseif s:sub(1, 2) == '/*' then
      inside = not s:find('*/', 3, true)
    elseif s ~= '' and s:sub(1, 2) ~= '//' then
      keep[#keep + 1] = l
    end
  end
  for i = 1, math.min(#keep, M.DECL) do
    local r = draw.row():add ' '
    code.add(r, e.path, keep[i], false, W - 2)
    rows[#rows + 1] = r
  end
  if #keep > M.DECL then
    rows[#rows + 1] = draw.row():add((' ⋯ %d more lines'):format(#keep - M.DECL), 'SeamLabel')
  end
  return rows
end

--- The foot's rows for `it`, a thing a Map's cell stands for, under a
--- rule `W` wide; nil when it has nothing to tell.
---@param m table
---@param it table|nil
---@param W integer
---@return table[]|nil
function M.rows(m, it, W)
  local rows
  if it and it.id and m.graph and m.graph.nodes[it.id] then
    rows = fn_rows(m, it, W)
  elseif it and it.kind == 'type' then
    rows = type_rows(m, it, W)
  end
  if not rows then
    return nil
  end
  table.insert(rows, 1, draw.row():add(' ' .. string.rep('─', W - 2), 'SeamMapLine'))
  return rows
end

--- The foot closed.
function M.close()
  if F.win and api.nvim_win_is_valid(F.win) then
    api.nvim_win_close(F.win, true)
  end
  F.win, F.key = nil, nil
end

--- The foot for where the pane's cursor is: shown over the pane's last
--- rows while the cursor is in the pane on the Map on something it can
--- tell, else closed.
function M.update()
  local pane = require 'seam.pane'
  local mk = require 'seam.map.keys'
  local w = pane.wins()
  local it = w and api.nvim_get_current_win() == w.pane and mk.shown() and mk.under()
  local W = w and api.nvim_win_get_width(w.pane) or 0
  local H = w and api.nvim_win_get_height(w.pane) or 0
  local m = index.model()
  local rows = it and m and M.rows(m, it, W)
  if not rows or H < #rows + 4 then
    return M.close()
  end
  local key = vim.inspect(it) .. ':' .. W .. 'x' .. H
  if key == F.key and F.win and api.nvim_win_is_valid(F.win) then
    return
  end
  if not (F.buf and api.nvim_buf_is_valid(F.buf)) then
    F.buf = draw.scratch 'foot'
  end
  draw.put(F.buf, rows)
  local cfg = { relative = 'win', win = w.pane, row = H - #rows, col = 0, width = W, height = #rows }
  if F.win and api.nvim_win_is_valid(F.win) then
    api.nvim_win_set_config(F.win, cfg)
  else
    cfg.style, cfg.focusable, cfg.zindex, cfg.noautocmd = 'minimal', false, 40, true
    F.win = api.nvim_open_win(F.buf, false, cfg)
    vim.wo[F.win].winhighlight = vim.wo[w.pane].winhighlight
    vim.wo[F.win].wrap = false
  end
  F.key = key
end

--- Is the foot shown? For the checks.
---@return integer|nil the foot's buffer
function M.shown()
  return F.win and api.nvim_win_is_valid(F.win) and F.buf or nil
end

return M
