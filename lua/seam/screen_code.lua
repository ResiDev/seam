-- The code screen: a function's or a file's code on the left, seam's copied
-- lines with their numbers, each value's type after its name, the names
-- from another file underlined, or its types; the pane on the right for the
-- name under the cursor told in full; the
-- trail of J's in the head, K back along it.
local api = vim.api
local code = require 'seam.code'
local code_view = require 'seam.views.code'
local draw = require 'seam.draw'
local hints = require 'seam.hints'
local index = require 'seam.index'
local names = require 'seam.names'
local opening = require 'seam.opening'
local pane = require 'seam.pane'
local st = require 'seam.state'
local M = {}

local row = draw.row
local ns = api.nvim_create_namespace 'seam.uses'
-- the code's widest and narrowest, and the least the pane keeps
-- the code's width at most, at least, and its share of the screen: the pane has 40% or more
M.W, M.MIN, M.SHARE = 112, 60, 0.6
M.DISPLAYS = { 'code', 'types' }

local function S()
  return require 'seam.screen'
end

---@class seam.CodeAt one place on the trail
---@field kind 'fn'|'file'
---@field id string|nil a function's node
---@field path string
---@field cursor integer[]|nil where the cursor was in the code when it was left: line, col, top

--- Are the code screen's five windows there?
---@return boolean
function M.valid()
  local w = st.cwin
  if not w then
    return false
  end
  for _, k in ipairs { 'head', 'chead', 'code', 'phead', 'pane' } do
    if not (w[k] and api.nvim_win_is_valid(w[k])) then
      return false
    end
  end
  return true
end
local valid = M.valid

local function top()
  return st.code and st.code.trail[#st.code.trail]
end

local function label(m, e)
  if e.kind == 'fn' then
    return draw.shape(m.graph.nodes[e.id])
  elseif e.kind == 'type' then
    return e.name
  end
  return e.path:match '[^/]+$'
end

local function type_row(d)
  return { kind = 'type', key = 'type:' .. d.name, name = d.name, path = d.path, line = d.line, end_line = d.end_line, decl_kind = d.kind }
end

-- what the pane shows off a name: the function, type or file itself
local function entry_row(e)
  if e.kind == 'fn' then
    return { kind = 'fn', id = e.id, path = e.path, key = 'f:' .. e.path .. '\n' .. e.id }
  elseif e.kind == 'type' then
    return type_row(e.decl)
  end
  return { kind = 'file', path = e.path, key = 'f:' .. e.path }
end

-- what the pane shows for a name in the code
local function name_row(m, e, n)
  if n.kind == 'call' then
    local node = m.graph.nodes[n.id]
    return {
      kind = 'fn',
      id = n.id,
      path = node.path,
      key = 'f:' .. node.path .. '\n' .. n.id,
      note = not n.declares and ((node.kind == 'value' and 'used' or 'called') .. ' at line ' .. n.line) or nil,
    }
  elseif n.kind == 'type' then
    return type_row(n.decl)
  elseif n.kind == 'file' then
    return { kind = 'file', path = n.path, key = 'f:' .. n.path }
  end
  local at = n.at or n
  return {
    kind = 'name',
    key = ('name:%s:%d:%d:%s'):format(e.path, at.line, at.col, n.name),
    n = n,
    from = e.path,
    path = e.path,
    as_type = n.decl and type_row(n.decl) or nil,
  }
end

--- What the pane shows: the name under the cursor in the code, else the
--- function or file shown.
---@return seam.ORow|nil
function M.subject()
  local e = top()
  return e and (st.code.subject or entry_row(e)) or nil
end

---------------------------------------------------------------- drawing

-- the code's rows for the display shown
local function rows_of(m, e, display, width)
  local path, s, l, nodes = code_view.span(entry_row(e), m)
  st.code.s = s
  local out = {}
  if display == 'types' then
    require('seam.views.codetypes').draw(out, m, e, width)
  else
    code_view.lines(out, m, path, s, l, nodes, true)
  end
  return out
end

-- the code's width: what its lines take with their types, between the narrowest and the widest, the pane keeping 40% of the screen
local function width_of(rows)
  local w = 0
  for _, r in ipairs(rows) do
    local x = r.w
    for _, v in ipairs(r.virt or {}) do
      x = x + api.nvim_strwidth(v[2])
    end
    w = math.max(w, x)
  end
  return math.min(math.max(M.MIN, w + 2), M.W, math.floor(vim.o.columns * M.SHARE))
end

local function heads(m, e)
  local h = row():add(' Seams', 'SeamLabel')
  for i, x in ipairs(st.code.trail) do
    h:add(' › ', 'SeamLabel'):add(label(m, x), i == #st.code.trail and 'SeamBold' or 'SeamText')
  end
  draw.put(st.obuf.head, { h })
  local c = row():add ' '
  if e.kind == 'fn' then
    local node = m.graph.nodes[e.id]
    local s0 = c.b
    code.add_name(c, node.path, node.line, node.name, 'SeamName', 60)
    c:add(node.kind == 'value' and '' or '()', 'SeamPunct')
    c.h[#c.h + 1] = { s0, c.b, 'SeamBold', 80 }
    c:add('   ' .. node.kind .. ' in ', 'SeamLabel')
    draw.path(c, node.path, math.max(1, node.line))
  elseif e.kind == 'type' then
    local s0 = c.b
    code.add_name(c, e.path, e.decl.line, e.name, 'SeamType', 60)
    c.h[#c.h + 1] = { s0, c.b, 'SeamBold', 80 }
    c:add('   ' .. e.decl.kind .. ' in ', 'SeamLabel')
    draw.path(c, e.path, e.decl.line)
  else
    c:add(label(m, e), 'SeamBold'):add('   file in ', 'SeamLabel')
    draw.path(c, e.path:match '^(.*/)' or '')
  end
  if st.code.display ~= 'code' then
    c:add('   ' .. st.code.display, 'SeamText')
  end
  draw.put(st.cbuf.chead, { c })
end

---------------------------------------------------------------- the cursor

-- the name under the code's cursor
local function answer()
  local e = top()
  local cur = api.nvim_win_get_cursor(st.cwin.code)
  local meta = draw.meta(st.cbuf.code, cur[1])
  local m = index.model()
  if st.code.display == 'types' then
    return meta.name and names.at(m, e.path, meta.name.line, meta.name.col) or nil
  end
  if meta.kind ~= 'code' or not meta.start then
    return nil
  end
  -- the name under the cursor, else the nearest on its line
  return names.near(m, e.path, meta.lnum, math.max(cur[2] - meta.start, -1))
end

--- The code's row of source line `l`, removed lines drawn between them
--- with the diff on; nil when it is not drawn.
---@param l integer
---@return integer|nil
function M.row_of(l)
  local i = l - st.code.s + 1
  if draw.meta(st.cbuf.code, i).lnum == l then
    return i
  end
  for k = 1, api.nvim_buf_line_count(st.cbuf.code) do
    if draw.meta(st.cbuf.code, k).lnum == l then
      return k
    end
  end
end

-- the later uses of the value under the cursor lit, their lines and the names on them
local function light(n)
  local buf = st.cbuf.code
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not (n and n.uses and #n.uses > 0) or st.code.display ~= 'code' then
    return
  end
  local function mark(l, c, e)
    local i = M.row_of(l)
    if not i then
      return nil
    end
    local meta = draw.meta(buf, i)
    pcall(api.nvim_buf_set_extmark, buf, ns, i - 1, meta.start + c, { end_col = meta.start + e, hl_group = 'SeamUseName', priority = 330 })
    return i - 1
  end
  mark(n.line, n.col, n.e)
  for _, u in ipairs(n.uses) do
    local i = mark(u.line, u.col, u.e)
    if i then
      api.nvim_buf_set_extmark(buf, ns, i, 0, { line_hl_group = 'SeamUseLine', priority = 85 })
    end
  end
end

local function moved()
  if st.screen ~= 'code' or st.drawing or not valid() or api.nvim_get_current_win() ~= st.cwin.code then
    return
  end
  local e = top()
  local n = answer()
  local x = n and name_row(index.model(), e, n) or entry_row(e)
  st.code.n = n
  light(n)
  local key = x.key .. (x.note or '')
  if st.code.shown ~= key then
    st.code.shown = key
    st.code.subject = x
    pane.follow(x)
  end
  vim.cmd 'redrawstatus'
end

---------------------------------------------------------------- the screen

local function layout()
  if st.screen == 'code' and valid() then
    return
  end
  local s = S()
  st.screen, st.cwin = 'code', nil
  local head = s.reset_tab()
  api.nvim_win_set_buf(head, st.obuf.head)
  local cw = s.split(st.cbuf.code, head, 'below', true)
  local pw = s.split(st.obuf.pane, cw, 'right')
  local chead = s.split(st.cbuf.chead, cw, 'above')
  local phead = s.split(st.obuf.phead, pw, 'above')
  for _, w in ipairs { head, chead, phead, pw } do
    s.winopts(w)
  end
  s.winopts(cw, true)
  s.wrap(pw)
  -- a line too long for the code is cut with … at its edge
  vim.wo[cw].list = true
  vim.wo[cw].listchars = 'extends:…,precedes:…,tab:  '
  vim.wo[pw].winfixwidth = false
  vim.wo[phead].winfixwidth = false
  for _, w in ipairs { head, chead, phead } do
    vim.wo[w].winfixheight = true
  end
  for _, w in ipairs { head, chead, cw, phead, pw } do
    vim.wo[w].fillchars = vim.wo[w].fillchars:gsub('horizdown:│', 'horizdown:─')
  end
  vim.wo[head].fillchars = vim.wo[head].fillchars:gsub('horiz: ', 'horiz:─')
  api.nvim_win_set_height(head, 1)
  api.nvim_win_set_height(chead, 1)
  api.nvim_win_set_height(phead, 3)
  st.cwin = { head = head, chead = chead, code = cw, phead = phead, pane = pw }
  api.nvim_set_current_win(cw)
end

-- the code for the place on top of the trail, the cursor where it was
-- left, else on the function's name
local function show()
  local m = index.model()
  local e = top()
  layout()
  local width = width_of(rows_of(m, e, 'code', M.W))
  local rows = st.code.display == 'code' and rows_of(m, e, 'code', width) or rows_of(m, e, st.code.display, width)
  heads(m, e)
  st.drawing = true
  draw.put(st.cbuf.code, rows)
  api.nvim_win_set_width(st.cwin.code, width)
  local w = st.cwin.code
  local c = e.cursor
  if not c then
    local node = e.kind == 'fn' and m.graph.nodes[e.id] or e.kind == 'type' and e.decl
    local l = node and M.row_of(math.max(1, node.line)) or 1
    local meta = draw.meta(st.cbuf.code, l)
    local src = node and code.file(e.path).lines[node.line] or ''
    local at = node and src:find('%f[%w_$]' .. vim.pesc(node.name) .. '%f[^%w_$]')
    c = { l, meta.start and (meta.start + (at and at - 1 or #src:match '^%s*')) or 0, 1 }
  end
  local n = api.nvim_buf_line_count(st.cbuf.code)
  api.nvim_win_call(w, function()
    vim.fn.winrestview { topline = math.max(1, math.min(c[3] or 1, n)), lnum = math.min(c[1], n), col = c[2] }
  end)
  st.drawing = false
  st.code.shown, st.code.subject = nil, nil
  api.nvim_set_current_win(w)
  moved()
  S().paint()
end

-- where the cursor is in the code: line, col, top
local function here()
  local w = st.cwin.code
  local cur = api.nvim_win_get_cursor(w)
  return { cur[1], cur[2], api.nvim_win_call(w, function()
    return vim.fn.line 'w0'
  end) }
end

--- The code screen on `e` (a function `{ kind = 'fn', id }` or a file
--- `{ kind = 'file', path }`), from the tree: a trail of one, `K` back to
--- the tree's row.
---@param e seam.CodeAt
function M.open(e)
  local m = index.model()
  if e.kind == 'fn' then
    e.path = m.graph.nodes[e.id].path
  end
  if not (st.cbuf and api.nvim_buf_is_valid(st.cbuf.code)) then
    M.init()
  end
  st.code = { trail = { e }, display = st.code and st.code.display or 'code' }
  show()
end

--- A type's place on the code screen, from its declaration.
---@param d { name: string, path: string, line: integer, end_line?: integer, kind: string }
---@return seam.CodeAt
function M.type_at(d)
  return { kind = 'type', path = d.path, name = d.name, decl = d }
end

--- `J` on a name: its function, type or file on the code screen, on the trail.
---@param e seam.CodeAt
function M.go(e)
  local m = index.model()
  if e.kind == 'fn' then
    e.path = m.graph.nodes[e.id].path
  end
  top().cursor = here()
  table.insert(st.code.trail, e)
  show()
end

--- `K`: back `count` places along the trail, to the very name left from;
--- past the first, the tree on its row.
---@param count integer
function M.back(count)
  if not st.code then
    return
  end
  for _ = 1, count do
    table.remove(st.code.trail)
    if #st.code.trail == 0 then
      st.code = { trail = {}, display = st.code.display }
      return require('seam.screen_tree').show()
    end
  end
  show()
end

--- The screen drawn again, the cursor kept.
function M.redraw()
  if st.screen ~= 'code' or not top() then
    return
  end
  if valid() then
    top().cursor = here()
  end
  show()
end

--- `gs` in the code: the code, or its types.
---@param d integer
function M.step_display(d)
  local i = vim.fn.index(M.DISPLAYS, st.code.display) + 1
  st.code.display = M.DISPLAYS[(i - 1 + d) % #M.DISPLAYS + 1]
  top().cursor = nil
  show()
end

-- the code's stops for n and N: each name from another file, in order
local function stops()
  local out = {}
  if st.code.display ~= 'code' then
    return out
  end
  for i = 1, api.nvim_buf_line_count(st.cbuf.code) do
    for _, c in ipairs(draw.meta(st.cbuf.code, i).stops or {}) do
      out[#out + 1] = { i, c }
    end
  end
  return out
end

--- `n` `N`: the next import in the code, or the one before, round the ends.
---@param d integer
function M.next_import(d)
  local list = stops()
  if #list == 0 then
    return
  end
  local cur = api.nvim_win_get_cursor(st.cwin.code)
  local function after(s)
    return s[1] > cur[1] or (s[1] == cur[1] and s[2] > cur[2])
  end
  local i
  if d > 0 then
    i = #list + 1
    for k, s in ipairs(list) do
      if after(s) then
        i = k
        break
      end
    end
    i = i + vim.v.count1 - 1
  else
    i = 0
    for k = #list, 1, -1 do
      if not after(list[k]) and not (list[k][1] == cur[1] and list[k][2] == cur[2]) then
        i = k
        break
      end
    end
    i = i - vim.v.count1 + 1
  end
  local s = list[(i - 1) % #list + 1]
  api.nvim_win_set_cursor(st.cwin.code, s)
end

-- what J would go to from the name under the cursor
local function j_target()
  local n = st.code and st.code.n
  if n and n.kind == 'call' then
    return { kind = 'fn', id = n.id }
  elseif n and n.kind == 'type' and n.decl then
    return M.type_at(n.decl)
  elseif n and n.kind == 'file' then
    return { kind = 'file', path = n.path }
  end
end

--- `<Esc>` in the pane: back to the code.
function M.leave_pane()
  M.to_code()
end

--- The cursor to the code.
function M.to_code()
  if valid() then
    api.nvim_set_current_win(st.cwin.code)
    vim.cmd 'redrawstatus'
  end
end

--- Every key of the screen, grouped as KEYS.md is, for `?`.
---@return seam.KeyGroup[]
function M.all_keys()
  if pane.inside() then
    return pane.all_keys 'code'
  end
  return {
    {
      'The code',
      {
        { 'n N', 'the next and previous import: a name from another file' },
        { ']c [c', 'the next and previous change' },
        { 'J', 'the code screen on the function or file the name under the cursor is' },
        { 'K', 'back to the very name you left from; 3K three back; from the first, the tree' },
        { '+ -', 'in its types, open and close the type under the cursor' },
        { 'gs', 'the code, or its types' },
        { 'D', 'the diff on or off, here and in the pane, for the session' },
      },
    },
    {
      'The pane',
      {
        { '<Tab>', 'Code or Types of the name under the cursor; from a view aside, back' },
        { 'gm', 'the Map, and back' },
        { '<S-Tab>', 'the next display of its view' },
        { '<M-j> <M-k>', 'scroll it half a screen, the cursor staying in the code' },
      },
    },
    {
      'Seam',
      {
        { '/', 'search the names: a function or file on the code screen, a type in the pane' },
        { 'L', 'the lens: what seam shows, and the range of changes' },
        { 'gf gd', 'that place in your own code' },
        { 'q', 'close seam' },
      },
    },
  }
end

--- The status line on the code screen: what is shown, its display and the
--- name under the cursor with its type, then the keys that act there.
---@return string
function M.status()
  local m, e = index.model(), top()
  if not e then
    return ''
  end
  local left = pane.said(label(m, e) .. '  ' .. st.code.display)
  local n = st.code.n
  if n then
    left = left .. '   ' .. (n.object and (n.object .. '.') or '') .. n.name .. (n.kind == 'call' and '()' or '') .. (n.type and (': ' .. n.type) or '')
  end
  local rules = st.lens and #st.lens.rules or 0
  if pane.inside() and require('seam.views.held').shown(st.cwin.pane) then
    return hints.status(left, { { { '<C-w>h', 'the code' } } }, rules)
  elseif pane.inside() then
    return hints.status(left, { pane.hints 'code' }, rules)
  end
  local rg = {}
  if #stops() > 0 then
    rg[#rg + 1] = { 'n N', 'import' }
  end
  local o, c = opening.keys()
  if o then
    rg[#rg + 1] = '+'
  end
  if c then
    rg[#rg + 1] = '-'
  end
  if #require('seam.codediff').line_stops(st.cwin.code, e.path) > 0 then
    rg[#rg + 1] = ']c [c'
  end
  if pane.can_diff() then
    rg[#rg + 1] = 'D'
  end
  if j_target() then
    rg[#rg + 1] = 'J'
  end
  rg[#rg + 1] = 'K'
  rg[#rg + 1] = 'gs'
  local pg = pane.view_hints(M.subject())
  if pane.can_scroll() then
    pg[#pg + 1] = '<M-j> <M-k>'
  end
  return hints.status(left, { rg, pg, { '/', 'L', 'q' } }, rules)
end

local function o(buf)
  return { buffer = buf, nowait = true, silent = true }
end

local function code_keys(buf)
  vim.keymap.set('n', 'J', function()
    local t = j_target()
    if t then
      M.go(t)
    end
  end, o(buf))
  vim.keymap.set('n', 'K', function()
    M.back(vim.v.count1)
  end, o(buf))
  vim.keymap.set('n', 'n', function()
    M.next_import(1)
  end, o(buf))
  vim.keymap.set('n', 'N', function()
    M.next_import(-1)
  end, o(buf))
  for _, k in ipairs { { ']c', 1 }, { '[c', -1 } } do
    vim.keymap.set('n', k[1], function()
      require('seam.codediff').next_line(st.cwin.code, top().path, k[2])
    end, o(buf))
  end
  -- gs the left side, the code or its types; <Tab> and <S-Tab> the pane's
  vim.keymap.set('n', 'gs', function()
    M.step_display(1)
  end, o(buf))
  vim.keymap.set('n', '<Tab>', pane.step(1), o(buf))
  vim.keymap.set('n', '<S-Tab>', pane.step(1, true), o(buf))
  pane.view_keys(buf)
  vim.keymap.set('n', '<M-j>', pane.scroll '<C-d>', o(buf))
  vim.keymap.set('n', '<M-k>', pane.scroll '<C-u>', o(buf))
  vim.keymap.set('n', '+', function()
    opening.plus(M.redraw)
  end, o(buf))
  vim.keymap.set('n', '-', function()
    opening.minus(M.redraw)
  end, o(buf))
  vim.keymap.set('n', '/', function()
    require('seam.screen_tree').search(nil, {
      over = st.cwin.code,
      pick = function(id)
        local ty = id:match '^type:(.*)$'
        local f = id:match '^file:(.*)$'
        if ty then
          local d = names.type_decl(index.model(), ty, top().path)
          if d then
            st.code.subject, st.code.shown = type_row(d), nil
            pane.show(st.code.subject)
            S().paint()
          end
        else
          M.go(f and { kind = 'file', path = f } or { kind = 'fn', id = id })
        end
      end,
    })
  end, o(buf))
  vim.keymap.set('n', 'L', function()
    S().open_lens()
  end, o(buf))
  vim.keymap.set('n', '?', function()
    hints.open(M.all_keys())
  end, o(buf))
  vim.keymap.set('n', 'q', function()
    S().close()
  end, o(buf))
  S().goto_keys(buf)
end

--- The code screen's buffers, made once, with their keys.
function M.init()
  local s = S()
  st.cbuf = { chead = draw.scratch 'code-head', code = draw.scratch 'code' }
  code_keys(st.cbuf.code)
  vim.keymap.set('n', 'q', function()
    s.close()
  end, o(st.cbuf.chead))
  s.goto_keys(st.cbuf.chead)
  api.nvim_create_autocmd('CursorMoved', { group = s.aug, buffer = st.cbuf.code, callback = moved })
  api.nvim_create_autocmd('WinEnter', { group = s.aug, buffer = st.cbuf.code, command = 'redrawstatus' })
  -- nothing to do in the code's head: the cursor goes back to the code
  api.nvim_create_autocmd('WinEnter', { group = s.aug, buffer = st.cbuf.chead, callback = M.to_code })
  api.nvim_create_autocmd('VimResized', {
    group = s.aug,
    callback = function()
      if st.screen == 'code' and api.nvim_get_current_tabpage() == st.tab then
        M.redraw()
      end
    end,
  })
end

return M
