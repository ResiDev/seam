-- The Map's foot: the name under the pane's cursor told in full, in a
-- window over the pane's last rows, at least 15% of it, at most half, a
-- rule and an empty row over it, an empty row under it, its lines going on
-- under themselves, nothing cut, code in its colours. A function: its
-- signature as written in its file, where it is, and when the file does
-- not write what it gives, what the server says it gives, an object a
-- field a line; then the line that calls it, and what that line sits in. A
-- type: where it is declared, how many make and take it, and its
-- declaration as written, comments left out.
local api = vim.api
local code = require 'seam.code'
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local index = require 'seam.index'
local tv = require 'seam.typesview'
local written = require 'seam.written'
local M = {}

-- the rows a foot takes at most; the Map leaves as many empty under it,
-- so its last rows can scroll up out from under
M.MAX = 30
-- the share of the pane a foot takes at least, and at most
M.SHARE, M.MOST = 0.15, 0.5
-- a type's declaration's lines before ⋯ N more lines
M.DECL = 7

local F = {}

local function known(w)
  return w:match '^%u' ~= nil
end

-- an object inside what a function gives, past this long, as its fields' names
local LONG = 50

-- what a function gives as lines of TypeScript: an object a field a line,
-- an object inside it as the names of its fields when long
local function gives_lines(g)
  g = tv.simple(g)
  if g:sub(1, 1) ~= '{' or #g <= LONG then
    return { g }
  end
  local out = { '{' }
  for _, part in ipairs(tv.parts(g)) do
    local name, t = part:match '^([^:]-%??)%s*:%s*(.*)$'
    if name and t:sub(1, 1) == '{' and #t > LONG then
      local ns = {}
      for _, q in ipairs(tv.parts(t)) do
        q = q:gsub('^readonly%s+', '')
        ns[#ns + 1] = q:match '^([%w_$]+%??)%s*[:(<]' or q
      end
      part = name .. ': { ' .. table.concat(ns, ', ') .. ' }'
    end
    out[#out + 1] = '  ' .. part
  end
  out[#out + 1] = '}'
  return out
end

-- the function's signature as its file writes it, from its line to its
-- body, each line coloured as there, comments left out, a run of lines
-- that are each a bare name (a destructured parameter) on one; nil when
-- the file has no body to end it
local function sig_rows(n)
  local bl, bc = written.sig_end(n.path, n.line)
  if not bl or bl < n.line or bl - n.line > 60 then
    return nil
  end
  local lines = code.file(n.path).lines
  local ind = #(lines[n.line] or ''):match '^%s*'
  local rows, inside, names = {}, false, nil
  for l = n.line, bl do
    local src = lines[l] or ''
    local s = vim.trim(src)
    local from = math.min(ind, #src:match '^%s*')
    local len = l == bl and bc - from or nil
    if inside then
      inside = not s:find('*/', 1, true)
    elseif s:sub(1, 2) == '/*' then
      inside = not s:find('*/', 3, true)
    elseif s == '' or s:sub(1, 2) == '//' or (len and vim.trim(src:sub(from + 1, from + len)) == '') then
      names = nil
    elseif l < bl and s:match '^[%w_$]+,?$' then
      if names then
        names:add ' '
        code.add(names, n.path, l, true)
      else
        names = draw.row():add ' '
        code.add(names, n.path, l, from)
        rows[#rows + 1] = names
      end
    else
      names = nil
      local r = draw.row():add ' '
      code.add(r, n.path, l, from, len)
      rows[#rows + 1] = r
    end
  end
  return #rows > 0 and rows or nil
end

local function fn_rows(m, it, W)
  local n = m.graph.nodes[it.id]
  if not n then
    return nil
  end
  local types_view = require 'seam.views.types'
  local f = types_view.fn_of(types_view.context(m, { open = {}, width = W }, n.path), it.id, 'foot:' .. it.id)
  local rows = sig_rows(n)
  if rows then
    -- what it gives, from the server, where the file does not write it
    local w = written.fn(n.path, n.line)
    if f and f.gives and not (w and w.ret) then
      local key = 'foot-gives:' .. it.id
      local gl = gives_lines(f.gives)
      local pre = 'type Gives = '
      local vl = vim.deepcopy(gl)
      vl[1] = pre .. vl[1]
      code.virtual(key, n.path, vl)
      for i = 1, #gl do
        local r = draw.row():add(i == 1 and ' → ' or '   ', 'SeamLabel')
        code.add(r, key, i, i == 1 and #pre or 0)
        rows[#rows + 1] = r
      end
    end
  else
    local r = draw.row():add(' '):add(data.label(n), 'SeamMapFnBold')
    if f then
      local ps = {}
      for i, p in ipairs(f.sig.params) do
        ps[i] = p.name .. (p.optional and '?' or '') .. (p.type and (': ' .. tv.simple(p.type)) or '')
      end
      types_view.typed(r, '(' .. table.concat(ps, ', ') .. ')', known, {}, nil)
      r:add(' → ', 'SeamLabel')
      types_view.typed(r, f.gives, known, {}, nil)
    end
    rows = { r }
  end
  rows[1]:add('   ' .. data.short(m, n.path, n.path) .. ':' .. n.line, 'SeamLabel')
  if it.at then
    local c = draw.row():add(' '):add(it.at.path:match '[^/]+$' .. ':' .. it.at.line, 'SeamLabel'):add '   '
    code.add(c, it.at.path, it.at.line, true)
    c:add('   in ', 'SeamLabel'):add(it.at.inside, 'SeamMapFn')
    rows[#rows + 1] = draw.row()
    rows[#rows + 1] = c
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
    code.add(r, e.path, keep[i], false)
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
  table.insert(rows, 2, draw.row())
  rows[#rows + 1] = draw.row()
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
  local least = math.ceil(H * M.SHARE)
  if not rows or H < least + 4 then
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
  local cfg = { relative = 'win', win = w.pane, row = H - least, col = 0, width = W, height = least }
  if F.win and api.nvim_win_is_valid(F.win) then
    api.nvim_win_set_config(F.win, cfg)
  else
    cfg.style, cfg.focusable, cfg.zindex, cfg.noautocmd = 'minimal', false, 40, true
    F.win = api.nvim_open_win(F.buf, false, cfg)
    -- the pane's own colours, not a float's
    local pw = vim.wo[w.pane].winhighlight
    local normal = pw:match '%f[%w]Normal:([%w_]+)' or 'Normal'
    vim.wo[F.win].winhighlight = 'NormalFloat:' .. normal .. (pw ~= '' and (',' .. pw) or '')
    local wo = vim.wo[F.win]
    wo.wrap, wo.linebreak, wo.breakindent, wo.breakindentopt = true, true, true, 'shift:2'
  end
  -- as tall as its lines wrapped, at least its share, at most MAX
  local h = api.nvim_win_text_height(F.win, {}).all
  h = math.max(least, math.min(h, M.MAX, math.floor(H * M.MOST)))
  api.nvim_win_set_config(F.win, { relative = 'win', win = w.pane, row = H - h, col = 0, width = W, height = h })
  code.paint_win(F.win)
  F.key = key
end

--- Is the foot shown? For the checks.
---@return integer|nil the foot's buffer
function M.shown()
  return F.win and api.nvim_win_is_valid(F.win) and F.buf or nil
end

return M
