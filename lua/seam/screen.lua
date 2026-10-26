-- The tab page seam lives in: the explorer's windows, a page's and the call
-- tree's, the keys in each, the status line, and moving between them, the
-- cursor redrawing what it lands on.
local api = vim.api
local calls = require 'seam.calls'
local calls_draw = require 'seam.draw.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local explorer = require 'seam.draw.explorer'
local index = require 'seam.index'
local lens = require 'seam.lens'
local lens_panel = require 'seam.lens_panel'
local page = require 'seam.draw.page'
local st = require 'seam.state'
local theme = require 'seam.theme'
local M = {}

local aug = api.nvim_create_augroup('seam', { clear = true })
local ns_at = api.nvim_create_namespace 'seam.at'
local ORDERS = explorer.ORDERS
local TABS = { built = 'built from', used = 'used by' }
local shape = draw.shape

---------------------------------------------------------------- windows

local function winopts(win, cursorline)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'
  wo.wrap = false
  wo.list = false
  wo.spell = false
  wo.cursorline = cursorline or false
  wo.winfixwidth = true
  wo.statuscolumn = ''
  wo.colorcolumn = ''
  wo.sidescrolloff = 0
  wo.fillchars = 'eob: ,vert:│,horiz: ,horizup:│,horizdown:│,vertleft:│,vertright:│,verthoriz:│'
  wo.winhighlight = 'WinSeparator:SeamSep'
  wo.statusline = "%!v:lua.require'seam.screen'.status()"
end

-- one window left, the top-left one
local function reset_tab()
  api.nvim_set_current_tabpage(st.tab)
  local wins = api.nvim_tabpage_list_wins(st.tab)
  local keep = wins[1]
  for _, w in ipairs(wins) do
    local pos = api.nvim_win_get_position(w)
    if pos[1] == 0 and pos[2] == 0 then
      keep = w
    end
  end
  api.nvim_set_current_win(keep)
  vim.cmd 'silent! only!'
  return keep
end

-- a pane of code wraps, each wrapped part starting past the line number,
-- under the code it continues
local function wrap(win)
  if not win then
    return
  end
  local wo = vim.wo[win]
  wo.wrap = true
  wo.linebreak = true
  wo.breakindent = true
  wo.breakindentopt = 'list:-1,shift:2'
  vim.bo[api.nvim_win_get_buf(win)].formatlistpat = [[^\s*\d\+\s\+]]
end

local function split(buf, win, dir, enter)
  return api.nvim_open_win(buf, enter or false, { split = dir, win = win })
end

local function paint()
  if not st.tab or not api.nvim_tabpage_is_valid(st.tab) then
    return
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(st.tab)) do
    code.paint_win(w)
  end
end

-- the cursor in `win` to the next `n`th of the rows in `list`, or back
local function step(win, list, n)
  if not list or #list == 0 then
    return
  end
  local cur = api.nvim_win_get_cursor(win)[1]
  local idx
  if n > 0 then
    idx = #list
    for i, r in ipairs(list) do
      if r > cur then
        idx = math.min(#list, i + n - 1)
        break
      end
    end
  else
    idx = 1
    for i = #list, 1, -1 do
      if list[i] < cur then
        idx = math.max(1, i + n + 1)
        break
      end
    end
  end
  api.nvim_win_set_cursor(win, { list[idx], 0 })
end

---------------------------------------------------------------- status

--- The status line: where you are on the left, the keys on the right.
---@return string
function M.status()
  local left, right = '', ''
  local srcs = #st.names > 1 and ('S ' .. st.names[(vim.fn.index(st.names, st.cur) + 1) % #st.names + 1]) or ''
  if st.screen == 'page' and st.page then
    local p = st.page
    local pos = ''
    if p.count and p.count > 0 then
      pos = string.format('  %d of %d', p.index or 1, p.count)
    end
    left = shape(p.c) .. '  ' .. TABS[p.tab] .. pos
    local hints = {}
    local seam = p.tab == 'built' and 'dependency' or 'file'
    local panes = st.panes[p.tab]
    if M.reading(p) then
      hints[#hints + 1] = 'n/N next name'
      if p.enter then
        hints[#hints + 1] = 'J enter ' .. p.enter
      end
      hints[#hints + 1] = 'v list'
    elseif p.tab == 'built' then
      hints[#hints + 1] = 'j/k next'
      if p.enter then
        hints[#hints + 1] = 'J enter ' .. p.enter
      end
      hints[#hints + 1] = 'v code'
    else
      hints[#hints + 1] = 'j/k next file'
      hints[#hints + 1] = ']] next use'
      hints[#hints + 1] = '<CR> open'
    end
    if not M.reading(p) then
      hints[#hints + 1] = panes == 'contract' and 'c both' or 'c contract'
      hints[#hints + 1] = panes == 'seam' and 's both' or ('s ' .. seam)
    end
    hints[#hints + 1] = '<Tab> ' .. (p.tab == 'built' and 'used by' or 'built from')
    if #st.stack > 0 then
      hints[#hints + 1] = 'K ' .. draw.trail(st.stack[#st.stack])
    end
    hints[#hints + 1] = (#st.stack > 0 and '- ' or 'K ') .. 'overview'
    right = table.concat(hints, '   ')
  elseif st.screen == 'calls' and st.calls then
    left, right = M.calls_status()
  else
    left = 'seams'
    local vw = st.view == 'diagram' and 'v trees   V map' or st.view == 'map' and 'v diagram   V trees' or 'v diagram   V map'
    local sd = st.sides == 'built' and 'b both   u used by' or st.sides == 'used' and 'b built from   u both' or 'b built from   u used by'
    right = '<Tab> ' .. ORDERS[st.order % #ORDERS + 1].short .. '   ' .. vw .. '   ' .. sd .. '   L lens   / search   J open   c calls   C from the top'
  end
  if srcs ~= '' and st.screen ~= 'calls' then
    right = right .. '   ' .. srcs
  end
  -- the keys that fit, the last ones dropped first
  local room = vim.o.columns - 12 - api.nvim_strwidth(left)
  local keys = vim.split(right, '   ', { plain = true })
  while #keys > 1 and api.nvim_strwidth(table.concat(keys, '   ')) > room do
    keys[#keys] = nil
  end
  right = table.concat(keys, '   ')
  return '%#SeamMode# NORMAL %#SeamStatus# ' .. left:gsub('%%', '%%%%') .. '%=' .. right:gsub('%%', '%%%%') .. ' '
end

---------------------------------------------------------------- explorer

--- The cursor moved in the explorer's list: draw the contract it is on.
function M.on_move()
  if st.screen ~= 'explorer' or st.drawing then
    return
  end
  local r = api.nvim_win_get_cursor(st.win.list)[1]
  local c = st.rowc[r]
  if c and c ~= st.shown then
    st.shown = c
    explorer.contract(c)
    paint()
  end
end

-- draw the list, the cursor back on `keep` or the contract it was on
local function show_list(keep)
  explorer.list()
  local want = keep or st.shown
  local target = st.crows[1] or 1
  if want then
    for _, i in ipairs(st.crows) do
      local c = st.rowc[i]
      if c == want or (c.path == want.path and c.name == want.name) then
        target = i
        break
      end
    end
  end
  if st.win.list and api.nvim_win_is_valid(st.win.list) then
    st.drawing = true
    api.nvim_win_set_cursor(st.win.list, { target, 0 })
    st.drawing = false
  end
  st.shown = nil
  M.on_move()
  paint()
end

local function layout_explorer()
  st.screen = 'explorer'
  local lh = reset_tab()
  api.nvim_win_set_buf(lh, st.buf.lhead)
  local rh = split(st.buf.rhead, lh, 'right')
  local list = split(st.buf.list, lh, 'below', true)
  if st.view ~= 'trees' then
    local dg = split(st.buf.diag, rh, 'below')
    api.nvim_win_set_width(lh, explorer.LW)
    api.nvim_win_set_height(lh, 3)
    api.nvim_win_set_height(rh, 3)
    for _, w in ipairs { lh, rh, dg } do
      winopts(w)
    end
    vim.wo[dg].winfixwidth = false
    winopts(list, true)
    vim.wo[lh].winfixheight = true
    vim.wo[rh].winfixheight = true
    st.win = { lhead = lh, rhead = rh, list = list, diag = dg }
    api.nvim_set_current_win(list)
    return
  end
  local mid, right
  if st.sides == 'built' then
    mid = split(st.buf.mid, rh, 'below')
  elseif st.sides == 'used' then
    right = split(st.buf.right, rh, 'below')
  else
    mid = split(st.buf.mid, rh, 'below')
    right = split(st.buf.right, mid, 'right')
  end
  api.nvim_win_set_width(lh, explorer.LW)
  api.nvim_win_set_height(lh, 3)
  api.nvim_win_set_height(rh, 3)
  if mid and right then
    api.nvim_win_set_width(mid, explorer.MW)
  end
  for _, w in ipairs { lh, rh, mid, right } do
    winopts(w)
  end
  winopts(list, true)
  vim.wo[lh].winfixheight = true
  vim.wo[rh].winfixheight = true
  st.win = { lhead = lh, rhead = rh, list = list, mid = mid, right = right }
  api.nvim_set_current_win(list)
end

--- The explorer's right side: 'trees', 'diagram' or 'map'.
---@param v string
function M.set_view(v)
  st.view = v
  local cur = api.nvim_win_get_cursor(st.win.list)
  local top = api.nvim_win_call(st.win.list, function()
    return vim.fn.line 'w0'
  end)
  st.drawing = true
  layout_explorer()
  api.nvim_win_call(st.win.list, function()
    vim.fn.winrestview { topline = top, lnum = cur[1], col = cur[2] }
  end)
  st.drawing = false
  st.shown = nil
  M.on_move()
  paint()
  vim.cmd 'redrawstatus'
end

--- Narrow the list to the names matching what is typed, as it is typed.
function M.search()
  local au = api.nvim_create_autocmd('CmdlineChanged', {
    group = aug,
    callback = function()
      st.filter = vim.fn.getcmdline()
      pcall(show_list)
      vim.cmd 'redraw'
    end,
  })
  local ok, q = pcall(vim.fn.input, { prompt = '/', default = st.filter, cancelreturn = '\0' })
  api.nvim_del_autocmd(au)
  if not ok or q == '\0' then
    q = ''
  end
  st.filter = q
  show_list()
end

--- Put the list's cursor on a contract by name, and a path fragment.
---@param name string
---@param inpath? string
---@return integer|nil row
function M.find(name, inpath)
  for i, c in pairs(st.rowc) do
    if c.name == name and (not inpath or c.path:find(inpath, 1, true)) then
      api.nvim_win_set_cursor(st.win.list, { i, 0 })
      api.nvim_win_call(st.win.list, function()
        vim.cmd 'normal! zz'
      end)
      M.on_move()
      return i
    end
  end
end

---------------------------------------------------------------- page

local function selected(p)
  if not (p.win.list and api.nvim_win_is_valid(p.win.list)) then
    return
  end
  local cur = api.nvim_win_get_cursor(p.win.list)[1]
  local r = p.rows and p.rows[cur]
  if not r or not r.meta.select then
    return
  end
  for i, sr in ipairs(p.sel_rows) do
    if sr == cur then
      p.index = i
    end
  end
  page.seam(p, r.meta)
  p.sel[p.tab] = cur
  if r.meta.dep then
    p.focus = r.meta.dep.name .. ':' .. tostring(r.meta.dep.target)
  end
  paint()
  vim.cmd 'redrawstatus'
end

local show_page, show_calls

--- Is the page showing Built from as code, the contract read top to bottom?
---@param p table
---@return boolean
function M.reading(p)
  return p.tab == 'built' and st.built_as == 'code'
end

-- the cursor moved in the code: the name it is on, or the nearest on its
-- line, becomes the one shown; on a line naming none, the last one stays
local function code_moved(p)
  local win = p.win.mid
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local cur = api.nvim_win_get_cursor(win)
  p.at = cur
  draw.cursor_line(win)
  local best, dist
  for i, r in ipairs(p.refs) do
    if r.row == cur[1] then
      local d = cur[2] < r.s and r.s - cur[2] or cur[2] >= r.e and cur[2] - r.e + 1 or 0
      if not dist or d < dist then
        best, dist = i, d
      end
    end
  end
  if not best or best == p.index then
    return
  end
  p.index = best
  local r = p.refs[best]
  p.focus = r.dep.name .. ':' .. tostring(r.dep.target)
  api.nvim_buf_clear_namespace(p.buf.mid, ns_at, 0, -1)
  api.nvim_buf_set_extmark(p.buf.mid, ns_at, r.row - 1, r.s, { end_col = r.e, hl_group = 'SeamRefAt', priority = 320 })
  page.declaration(p, r.dep)
  paint()
  vim.cmd 'redrawstatus'
end

-- the cursor to the `n`th name after it in the code, or before; round the ends
local function next_ref(p, n)
  local refs = p.refs
  if #refs == 0 then
    return
  end
  local cur = api.nvim_win_get_cursor(p.win.mid)
  local i
  if n > 0 then
    i = #refs + 1
    for k, r in ipairs(refs) do
      if r.row > cur[1] or (r.row == cur[1] and r.s > cur[2]) then
        i = k
        break
      end
    end
    i = i + n - 1
  else
    i = 0
    for k = #refs, 1, -1 do
      local r = refs[k]
      if r.row < cur[1] or (r.row == cur[1] and r.s < cur[2]) then
        i = k
        break
      end
    end
    i = i + n + 1
  end
  i = (i - 1) % #refs + 1
  api.nvim_win_set_cursor(p.win.mid, { refs[i].row, refs[i].s })
  code_moved(p)
end

local function page_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  local function other()
    st.page.tab = st.page.tab == 'built' and 'used' or 'built'
    show_page()
  end
  vim.keymap.set('n', '<Tab>', other, o)
  vim.keymap.set('n', '<S-Tab>', other, o)
  for key, only in pairs { c = 'contract', s = 'seam' } do
    vim.keymap.set('n', key, function()
      local t = st.page.tab
      st.panes[t] = st.panes[t] == only and 'both' or only
      show_page()
    end, o)
  end
  -- Built from as code or as a list
  vim.keymap.set('n', 'v', function()
    if st.page.tab == 'built' then
      st.built_as = st.built_as == 'code' and 'list' or 'code'
      show_page()
    end
  end, o)
  vim.keymap.set('n', '<BS>', M.back, o)
  vim.keymap.set('n', 'K', M.back, o)
  -- down a level: into a dependency's page; a user file is another tab, which K could not leave
  vim.keymap.set('n', 'J', function()
    if st.page.tab == 'built' then
      M.page_enter()
    end
  end, o)
  vim.keymap.set('n', '-', M.overview, o)
  vim.keymap.set('n', 'L', M.open_lens, o)
  vim.keymap.set('n', 'q', M.close, o)
  vim.keymap.set('n', 'S', M.switch, o)
  vim.keymap.set('n', 'gd', function()
    M.goto_decl(st.page.c)
  end, o)
  vim.keymap.set('n', 'R', function()
    index.load()
    show_page()
  end, o)
end

-- Built from as code: the contract on the left, the cursor moving through it
-- as through any code, and the declaration of the name it is on beside it
local function show_code(p, head)
  local left = split(p.buf.mid, head, 'below', true)
  api.nvim_win_set_height(head, 3)
  local right = split(p.buf.right, left, 'right')
  winopts(left)
  winopts(right)
  wrap(left)
  wrap(right)
  vim.wo[left].scrolloff = 4
  p.win.mid, p.win.right = left, right
  for _, b in ipairs { p.buf.mid, p.buf.right } do
    page_keys(b)
    local o = { buffer = b, nowait = true, silent = true }
    vim.keymap.set('n', 'c', '<Nop>', o)
    vim.keymap.set('n', 's', '<Nop>', o)
  end
  local o = { buffer = p.buf.mid, nowait = true, silent = true }
  for _, k in ipairs { 'n', ']]' } do
    vim.keymap.set('n', k, function()
      next_ref(p, vim.v.count1)
    end, o)
  end
  for _, k in ipairs { 'N', '[[' } do
    vim.keymap.set('n', k, function()
      next_ref(p, -vim.v.count1)
    end, o)
  end
  vim.keymap.set('n', '<CR>', M.page_enter, o)
  local width = page.code(p)
  api.nvim_win_set_width(left, math.max(50, math.min(width + 2, math.floor(vim.o.columns * 0.6))))
  p.count, p.index = #p.refs, nil
  api.nvim_create_autocmd('CursorMoved', {
    group = aug,
    buffer = p.buf.mid,
    callback = function(ev)
      if st.page == p and p.buf.mid == ev.buf then
        code_moved(p)
      end
    end,
  })
  -- back where it was, or on the name the list was on, or the first
  local at
  for _, r in ipairs(p.refs) do
    if p.focus == r.dep.name .. ':' .. tostring(r.dep.target) then
      at = at or { r.row, r.s }
      if p.at and p.at[1] == r.row then
        at = p.at
        break
      end
    end
  end
  at = at or (p.refs[1] and { p.refs[1].row, p.refs[1].s }) or { 4, 0 }
  api.nvim_win_set_cursor(left, { math.min(at[1], api.nvim_buf_line_count(p.buf.mid)), at[2] })
  if #p.refs > 0 then
    code_moved(p)
  else
    p.enter = nil
    page.empty(p)
    draw.cursor_line(left)
  end
  paint()
  vim.cmd 'redrawstatus'
end

-- the page in `st.page`, laid out again in fresh buffers
show_page = function()
  local p = st.page
  st.screen = 'page'
  local keep = reset_tab()
  local old = p.buf or {}
  p.buf = { head = draw.scratch 'head' }
  api.nvim_win_set_buf(keep, p.buf.head)
  for _, b in pairs(old) do
    if api.nvim_buf_is_valid(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  page.head(p)
  winopts(keep)
  vim.wo[keep].winfixheight = true
  p.win = { head = keep }
  p.buf.mid, p.buf.right = draw.scratch 'contract', draw.scratch 'seam'
  p.refs = nil
  if M.reading(p) then
    return show_code(p, keep)
  end
  p.buf.list = draw.scratch 'list'
  local list = split(p.buf.list, keep, 'below', true)
  api.nvim_win_set_height(keep, 3)
  -- the contract sits where the flow puts it: below what it is built
  -- from, above what uses it
  local panes = st.panes[p.tab]
  local right, mid
  if panes == 'contract' then
    mid = split(p.buf.mid, list, 'right')
  else
    right = split(p.buf.right, list, 'right')
    if panes == 'both' then
      mid = split(p.buf.mid, right, p.tab == 'built' and 'below' or 'above')
      local s, e = page.decl_range(p.c)
      local h = api.nvim_win_get_height(right) + api.nvim_win_get_height(mid)
      api.nvim_win_set_height(mid, math.min(e - s + 1 + 4, math.floor(h * 0.45)))
    end
  end
  api.nvim_win_set_width(list, 40)
  winopts(list, true)
  for _, w in pairs { right = right, mid = mid } do
    winopts(w)
    wrap(w)
  end
  if right and mid then
    local upper = p.tab == 'built' and right or mid
    vim.wo[upper].fillchars = vim.wo[upper].fillchars:gsub('horiz: ', 'horiz:─'):gsub('vertright:│', 'vertright:├')
  end
  p.win.list, p.win.mid, p.win.right = list, mid, right
  for _, b in ipairs { p.buf.list, p.buf.mid, p.buf.right } do
    page_keys(b)
  end
  local o = { buffer = p.buf.list, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function()
    step(list, p.sel_rows, vim.v.count1)
  end, o)
  vim.keymap.set('n', 'k', function()
    step(list, p.sel_rows, -vim.v.count1)
  end, o)
  vim.keymap.set('n', '<Down>', function()
    step(list, p.sel_rows, 1)
  end, o)
  vim.keymap.set('n', '<Up>', function()
    step(list, p.sel_rows, -1)
  end, o)
  vim.keymap.set('n', ']]', function()
    M.next_use(1)
  end, o)
  vim.keymap.set('n', '[[', function()
    M.next_use(-1)
  end, o)
  vim.keymap.set('n', '<CR>', M.page_enter, o)
  api.nvim_create_autocmd('CursorMoved', {
    group = aug,
    buffer = p.buf.list,
    callback = function(ev)
      if st.page and st.page.buf.list == ev.buf then
        selected(st.page)
      end
    end,
  })
  page.list(p)
  local want = p.sel[p.tab] or p.sel_rows[1]
  for _, i in ipairs(p.tab == 'built' and p.sel_rows or {}) do
    local d = p.rows[i].meta.dep
    if p.focus == d.name .. ':' .. tostring(d.target) then
      want = i
      break
    end
  end
  if want then
    api.nvim_win_set_cursor(list, { want, 0 })
    selected(p)
  else
    page.empty(p)
  end
  paint()
  vim.cmd 'redrawstatus'
end

--- Used by: the cursor to the `n`th next use in the file shown.
---@param n integer
function M.next_use(n)
  local p = st.page
  if not p or p.tab ~= 'used' or not p.win.right or not p.lit_rows or #p.lit_rows == 0 then
    return
  end
  local w = p.win.right
  draw.cursor_line(w)
  p.use_i = ((p.use_i or 0) + n - 1) % #p.lit_rows + 1
  local r = p.lit_rows[p.use_i]
  api.nvim_win_set_cursor(w, { r, 0 })
  api.nvim_win_call(w, function()
    vim.cmd 'normal! zz'
  end)
  code.paint_win(w)
end

--- Built from: enter the dependency's page. Used by: open the file at the use.
function M.page_enter()
  local p = st.page
  if M.reading(p) then
    local r = p.index and p.refs[p.index]
    local t = r and r.dep.target and index.model().byid[r.dep.target]
    if t and t.nusers > 0 then
      M.open_page(t)
    end
    return
  end
  local cur = api.nvim_win_get_cursor(p.win.list)[1]
  local r = p.rows[cur]
  if not r then
    return
  end
  if p.tab == 'built' and r.meta.dep and r.meta.dep.target then
    local t = index.model().byid[r.meta.dep.target]
    if t and t.nusers > 0 then
      M.open_page(t)
    end
  elseif r.meta.path then
    local us = index.uses_by_file(p.c)[r.meta.path]
    local u = us and us[p.use_i or 1] or (us and us[1])
    vim.cmd('tabnew +' .. (u and u.line or 1) .. ' ' .. vim.fn.fnameescape(st.root .. '/' .. r.meta.path))
  end
end

-- What K comes back to from a page, kept in `st.stack` under it: another
-- page, or the Calls screen as it was, each tagged with its kind.
local function calls_entry()
  local v = st.calls
  local g = index.model().graph
  local a = v.anchor and g.nodes[v.anchor]
  local w = st.cwin and st.cwin.list
  return {
    kind = 'calls',
    calls = v,
    top = w and api.nvim_win_is_valid(w) and api.nvim_win_call(w, function()
      return vim.fn.line 'w0'
    end) or nil,
    label = a and ('calls of ' .. (a.kind == 'module' and vim.fn.fnamemodify(a.path, ':t') or shape(a))) or 'calls from the top',
  }
end

--- Open contract `c`'s page, over the page or Calls screen shown if there is one.
---@param c table
function M.open_page(c)
  if st.page then
    st.stack[#st.stack + 1] = st.page
  elseif st.screen == 'calls' and st.calls then
    st.stack[#st.stack + 1] = calls_entry()
    st.calls, st.calls_rows = nil, nil
  else
    st.explorer_at = st.shown
  end
  local tab = (st.sides == 'used' or #c.deps == 0) and c.nusers > 0 and 'used' or 'built'
  st.page = { kind = 'page', c = c, tab = tab, sel = {} }
  show_page()
end

--- Back: the previous page or Calls screen, or the explorer.
function M.back()
  local e = table.remove(st.stack)
  if e and e.kind == 'calls' then
    st.page = nil
    st.calls, st.calls_top = e.calls, e.top
    show_calls()
  elseif e then
    st.page = e
    show_page()
  else
    st.page = nil
    layout_explorer()
    show_list(st.explorer_at)
    paint()
  end
end

--- Straight to the explorer from any depth, on the contract you were reading.
function M.overview()
  local c = st.page and st.page.c
  st.stack, st.page = {}, nil
  layout_explorer()
  show_list(c or st.explorer_at)
  paint()
end

--- The declaration, in a normal window.
---@param c table|nil
function M.goto_decl(c)
  if c then
    vim.cmd('tabnew +' .. c.line .. ' ' .. vim.fn.fnameescape(st.root .. '/' .. c.path))
  end
end

--- The next source, on the same contract.
function M.switch()
  index.load()
  if #st.names < 2 then
    vim.notify('seam: only ' .. (st.cur or '?') .. ' is loaded', vim.log.levels.INFO)
    return
  end
  local i = vim.fn.index(st.names, st.cur)
  st.cur = st.names[(i + 1) % #st.names + 1]
  local m = index.model()
  if st.screen == 'page' and st.page then
    local function find(c)
      return m.byid[c.id] or m.bykey[c.path .. ':' .. c.name]
    end
    local nc = find(st.page.c)
    if not nc then
      vim.notify('seam: ' .. st.page.c.name .. ' is not an export in ' .. st.cur, vim.log.levels.WARN)
      st.stack, st.page = {}, nil
      layout_explorer()
      show_list()
      return
    end
    for _, sp in ipairs(st.stack) do
      if sp.kind == 'page' then
        sp.c = find(sp.c) or sp.c
      end
    end
    if st.explorer_at then
      st.explorer_at = find(st.explorer_at) or st.explorer_at
    end
    st.page.c = nc
    st.page.sel = {}
    show_page()
  else
    show_list(st.shown)
    paint()
  end
end

---------------------------------------------------------------- calls

local function calls_valid()
  local w = st.cwin
  return w and api.nvim_win_is_valid(w.head) and api.nvim_win_is_valid(w.list) and api.nvim_win_is_valid(w.pin) and api.nvim_win_is_valid(w.code)
end

local function calls_height()
  return calls_valid() and api.nvim_win_get_height(st.cwin.list) or 40
end

-- the row under the list's cursor
local function calls_at()
  if not (calls_valid() and st.calls_rows) then
    return 1
  end
  local l = api.nvim_win_get_cursor(st.cwin.list)[1]
  return math.max(1, math.min(l, #st.calls_rows.rows))
end

local function calls_label(node)
  return node.kind == 'module' and vim.fn.fnamemodify(node.path, ':t') or shape(node)
end

--- The status line on the Calls screen: the way from the top of the tree to
--- the row under the cursor, then the keys.
---@return string left, string right
function M.calls_status()
  local v, r = st.calls, st.calls_rows
  local g = index.model().graph
  local i = calls_at()
  local x = r and r.rows[i]
  local crumb = {}
  local p = x
  while p do
    table.insert(crumb, 1, p.id and calls_label(g.nodes[p.id]) or p.kind == 'tests' and 'tests' or vim.fn.fnamemodify(p.path or '', ':t'))
    p = p.parent and r.rows[p.parent]
  end
  table.insert(crumb, 1, v.anchor and calls_label(g.nodes[v.anchor]) or 'from the top')
  local left = table.concat(crumb, ' › ')
  if v.anchor then
    left = left .. '  ' .. (v.dir == 'up' and 'called by' or 'calls')
  end
  if x then
    local sibs = {}
    if x.parent then
      sibs = r.rows[x.parent].kids
    else
      for j, y in ipairs(r.rows) do
        if not y.parent then
          sibs[#sibs + 1] = j
        end
      end
    end
    table.sort(sibs)
    left = left .. ('  %d of %d'):format(vim.fn.index(sibs, i) + 1, #sibs)
  end
  local p = calls.pane(g, v, r, x and i or nil, index.model())
  local swap = {}
  if p and #p.places > 0 then
    swap = { '<Tab> ' .. (p.code == 'called' and 'itself' or 'called at'), 'n/N ' .. (p.code == 'called' and 'place' or 'call') }
  elseif p and #p.lines > 0 then
    swap = { 'n/N call' }
  end
  if calls_valid() and api.nvim_get_current_win() == st.cwin.code then
    return left, table.concat(vim.list_extend(swap, { '<Esc> the tree', 'K back', '- explorer', 'q close' }), '   ')
  end
  local hints = vim.list_extend(swap, { 'j/k row', 'h fold', 'l open', 'J page', 'K back' })
  if v.anchor then
    hints[#hints + 1] = v.dir == 'up' and '~ calls' or '~ called by'
  end
  vim.list_extend(hints, { '<CR> anchor here', '[ ] sibling', 'L open all', 'H as it opened', '- explorer', 'C from the top' })
  return left, table.concat(hints, '   ')
end

local function calls_layout()
  if st.screen == 'calls' and calls_valid() then
    return
  end
  st.screen, st.cwin = 'calls', nil
  local head = reset_tab()
  api.nvim_win_set_buf(head, st.cbuf.head)
  local list = split(st.cbuf.list, head, 'below', true)
  local pane = split(st.cbuf.code, list, 'right')
  local pin = split(st.cbuf.pin, list, 'above')
  for _, w in ipairs { head, pin, pane } do
    winopts(w)
  end
  winopts(list, true)
  wrap(pane)
  vim.wo[pane].winfixwidth = false
  vim.wo[head].winfixheight = true
  vim.wo[pin].winfixheight = true
  api.nvim_win_set_width(list, calls_draw.LW)
  st.cwin = { head = head, list = list, pin = pin, code = pane }
  st.calls_drawn = nil
  api.nvim_set_current_win(list)
end

-- the code of the row under the cursor, when it moved to another
local function calls_moved()
  if st.screen ~= 'calls' or st.drawing or not (calls_valid() and st.calls_rows) then
    return
  end
  local i = calls_at()
  local x = st.calls_rows.rows[i]
  st.calls.cursor = x and x.key or st.calls.cursor
  draw.cursor_line(st.cwin.list)
  if st.calls_shown ~= (x and x.key or '') then
    st.calls_shown = x and x.key or ''
    calls_draw.pane(st.cbuf.code, st.cwin.code, index.model().graph, st.calls, st.calls_rows, x and i)
    paint()
  end
  vim.cmd 'redrawstatus'
end

local function calls_cursor(key)
  local r = st.calls_rows
  local target
  for i, x in ipairs(r.rows) do
    if x.key == key then
      target = i
    end
  end
  if not target then
    target = 1
    for i = #r.rows, 1, -1 do
      target = not st.calls.anchor and r.rows[i].id and i or target
    end
  end
  st.drawing = true
  api.nvim_win_set_cursor(st.cwin.list, { target, 0 })
  st.drawing = false
  calls_moved()
end

show_calls = function()
  local m = index.model()
  local g, v = m.graph, st.calls
  calls_layout()
  api.nvim_win_set_height(st.cwin.head, 2)
  api.nvim_win_set_height(st.cwin.pin, v.anchor and 3 or 2)
  local h = calls_height()
  local r = calls.rows(g, v, h, m)
  st.calls_rows = r
  calls_draw.head(st.cbuf.head, g, v, r, vim.o.columns)
  calls_draw.pin(st.cbuf.pin, g, v)
  local w = st.cwin.list
  local same = st.calls_drawn == (v.anchor or '') .. v.dir
  local top = st.calls_top or same and api.nvim_win_call(w, function()
    return vim.fn.line 'w0'
  end) or nil
  st.calls_top = nil
  st.drawing = true
  calls_draw.list(st.cbuf.list, g, v, r)
  api.nvim_win_call(w, function()
    vim.fn.winrestview { topline = top or 1 }
  end)
  st.drawing = false
  st.calls_drawn = (v.anchor or '') .. v.dir
  st.calls_shown = nil
  calls_cursor(v.cursor)
  paint()
end

local function calls_leave()
  st.calls, st.calls_rows = nil, nil
  layout_explorer()
  show_list(st.explorer_at)
  paint()
end

-- a contract the explorer lists and a page shows: an export used from another file
local function contract_of(id)
  local c = id and index.model().byid[id]
  return c and (c.nusers or 0) > 0 and c or nil
end

-- straight to the explorer, on the anchor when it is a contract
local function calls_overview()
  st.explorer_at = contract_of(st.calls and st.calls.anchor) or st.explorer_at
  calls_leave()
end

-- the contract page of the row's function; one line saying why when it has none
local function calls_page()
  local x = st.calls_rows and st.calls_rows.rows[calls_at()]
  local id = x and x.id
  local c = contract_of(id)
  if c then
    return M.open_page(c)
  end
  local node = id and index.model().graph.nodes[id]
  local what = node and calls_label(node) or 'this row'
  api.nvim_echo({ { what .. ' has no page: only exported functions used from another file do', 'SeamLabel' } }, false, {})
end

-- the code beside the tree again, the row the same: another view or place
local function calls_pane()
  local i = calls_at()
  local x = st.calls_rows.rows[i]
  calls_draw.pane(st.cbuf.code, st.cwin.code, index.model().graph, st.calls, st.calls_rows, x and i)
  paint()
  vim.cmd 'redrawstatus'
end

local function calls_press(k, times)
  return function()
    for _ = 1, times and vim.v.count1 or 1 do
      local m = index.model()
      local a = calls.key(m.graph, st.calls, st.calls_rows, calls_at(), k, calls_height(), m)
      if a == 'redraw' then
        show_calls()
      elseif a == 'move' then
        calls_cursor(st.calls.cursor)
      elseif a == 'pane' then
        calls_pane()
      elseif a == 'explorer' then
        return calls_leave()
      end
    end
  end
end

local function calls_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  local press = calls_press
  for _, k in ipairs { 'l', 'h', 'L', 'H', '<CR>', '~', '<BS>', 'K', 'C', '<Tab>', ']', '[' } do
    vim.keymap.set('n', k, press(k), o)
  end
  vim.keymap.set('n', 'j', press('j', true), o)
  vim.keymap.set('n', 'k', press('k', true), o)
  vim.keymap.set('n', 'n', press(']]', true), o)
  vim.keymap.set('n', 'N', press('[[', true), o)
  vim.keymap.set('n', '<Down>', press 'j', o)
  vim.keymap.set('n', '<Up>', press 'k', o)
  vim.keymap.set('n', 'J', calls_page, o)
  vim.keymap.set('n', '-', calls_overview, o)
  vim.keymap.set('n', 'gd', function()
    local g = index.model().graph
    local x = st.calls_rows and st.calls_rows.rows[calls_at()]
    local id = x and x.id or st.calls.anchor
    local node = id and g.nodes[id]
    if node then
      M.goto_decl { path = node.path, line = math.max(1, node.line) }
    end
  end, o)
  vim.keymap.set('n', 'q', M.close, o)
end

-- the code beside the tree keeps the cursor, to scroll and search it; <Esc>
-- gives it back to the tree, and the keys that leave work from it too
local function calls_code_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  local function tree()
    if calls_valid() then
      api.nvim_set_current_win(st.cwin.list)
      vim.cmd 'redrawstatus'
    end
  end
  local function back()
    tree()
    local m = index.model()
    if calls.key(m.graph, st.calls, st.calls_rows, calls_at(), '<BS>', calls_height(), m) == 'explorer' then
      return calls_leave()
    end
    show_calls()
  end
  vim.keymap.set('n', '<Esc>', tree, o)
  vim.keymap.set('n', '<Tab>', calls_press '<Tab>', o)
  vim.keymap.set('n', ']]', calls_press(']]', true), o)
  vim.keymap.set('n', '[[', calls_press('[[', true), o)
  vim.keymap.set('n', 'K', back, o)
  vim.keymap.set('n', '<BS>', back, o)
  vim.keymap.set('n', '-', calls_overview, o)
  vim.keymap.set('n', 'q', M.close, o)
end

--- The Calls screen on a function, component or class by id, or from the top.
---@param id string|nil
function M.open_calls(id)
  local m = index.model()
  if not (m and m.graph) then
    vim.notify('seam: this index has no calls; :Seam! indexes again', vim.log.levels.WARN)
    return
  end
  if id and not m.graph.nodes[id] then
    vim.notify('seam: ' .. (index.id_path(id) and id:match '[^:]*$' or id) .. ' is not a function, component or class', vim.log.levels.INFO)
    return
  end
  if st.screen == 'explorer' then
    st.explorer_at = st.shown
  end
  if not (st.cbuf and api.nvim_buf_is_valid(st.cbuf.list)) then
    st.cbuf = { head = draw.scratch 'calls-head', pin = draw.scratch 'calls-pin', list = draw.scratch 'calls', code = draw.scratch 'calls-code' }
    calls_keys(st.cbuf.list)
    calls_code_keys(st.cbuf.code)
    for _, b in ipairs { st.cbuf.head, st.cbuf.pin } do
      vim.keymap.set('n', 'q', M.close, { buffer = b, nowait = true, silent = true })
      -- nothing to do in the head or the pin: the cursor goes back to the tree
      api.nvim_create_autocmd('WinEnter', {
        group = aug,
        buffer = b,
        callback = function()
          if st.screen == 'calls' and calls_valid() then
            api.nvim_set_current_win(st.cwin.list)
          end
        end,
      })
    end
    api.nvim_create_autocmd('WinEnter', {
      group = aug,
      buffer = st.cbuf.code,
      callback = function()
        vim.cmd 'redrawstatus'
      end,
    })
    api.nvim_create_autocmd('CursorMoved', { group = aug, buffer = st.cbuf.list, callback = calls_moved })
    api.nvim_create_autocmd('VimResized', {
      group = aug,
      callback = function()
        if st.screen == 'calls' and api.nvim_get_current_tabpage() == st.tab then
          show_calls()
        end
      end,
    })
  end
  st.calls = calls.new(id, 'down')
  show_calls()
end

---------------------------------------------------------------- lens

--- The lens changed: save it, filter every source, redraw what is shown. A
--- page redraws when the panel closes: drawing it closes every window.
function M.lens_changed()
  lens.save(st.lens, st.root)
  for _, m in pairs(st.models) do
    lens.apply(st.lens, m)
  end
  if st.screen == 'calls' and st.calls then
    st.calls.auto = nil
    show_calls()
  elseif st.screen == 'page' and st.page then
    if lens_panel.is_open() then
      st.page_stale = true
    else
      show_page()
    end
  elseif st.win and st.win.list and api.nvim_win_is_valid(st.win.list) then
    show_list(st.shown)
    st.shown = nil
    M.on_move()
    paint()
  end
end

function M.open_lens()
  lens_panel.open {
    lens = function()
      return st.lens
    end,
    model = index.model,
    root = function()
      return st.root
    end,
    changed = M.lens_changed,
    closed = function()
      if st.page_stale and st.screen == 'page' and st.page then
        st.page_stale = false
        show_page()
      end
    end,
  }
end

---------------------------------------------------------------- the tab

local function explorer_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function()
    step(st.win.list, st.crows, vim.v.count1)
  end, o)
  vim.keymap.set('n', 'k', function()
    step(st.win.list, st.crows, -vim.v.count1)
  end, o)
  vim.keymap.set('n', '<Down>', function()
    step(st.win.list, st.crows, 1)
  end, o)
  vim.keymap.set('n', '<Up>', function()
    step(st.win.list, st.crows, -1)
  end, o)
  vim.keymap.set('n', '<Tab>', function()
    st.order = st.order % #ORDERS + 1
    show_list()
    paint()
  end, o)
  vim.keymap.set('n', '<S-Tab>', function()
    st.order = (st.order - 2) % #ORDERS + 1
    show_list()
    paint()
  end, o)
  vim.keymap.set('n', '/', M.search, o)
  vim.keymap.set('n', 'v', function()
    M.set_view(st.view == 'diagram' and 'trees' or 'diagram')
  end, o)
  vim.keymap.set('n', 'V', function()
    M.set_view(st.view == 'map' and 'trees' or 'map')
  end, o)
  -- b: built from alone, u: used by alone; again for both
  vim.keymap.set('n', 'b', function()
    st.sides = st.sides == 'built' and 'both' or 'built'
    M.set_view(st.view)
  end, o)
  vim.keymap.set('n', 'u', function()
    st.sides = st.sides == 'used' and 'both' or 'used'
    M.set_view(st.view)
  end, o)
  local function open()
    if st.shown then
      M.open_page(st.shown)
    end
  end
  vim.keymap.set('n', '<CR>', open, o)
  vim.keymap.set('n', 'J', open, o)
  vim.keymap.set('n', 'c', function()
    if st.shown then
      M.open_calls(st.shown.id)
    end
  end, o)
  vim.keymap.set('n', 'C', function()
    M.open_calls(nil)
  end, o)
  -- the top level: nothing above it, and no hover from another plugin's K
  vim.keymap.set('n', 'K', '<Nop>', o)
  vim.keymap.set('n', 'gd', function()
    M.goto_decl(st.shown)
  end, o)
  vim.keymap.set('n', 'S', M.switch, o)
  vim.keymap.set('n', 'L', M.open_lens, o)
  vim.keymap.set('n', 'q', M.close, o)
  vim.keymap.set('n', 'R', function()
    index.load()
    show_list()
  end, o)
end

function M.close()
  if st.tab and api.nvim_tabpage_is_valid(st.tab) then
    if #api.nvim_list_tabpages() > 1 then
      api.nvim_set_current_tabpage(st.tab)
      vim.cmd 'tabclose'
    end
  end
  if st.laststatus then
    vim.o.laststatus = st.laststatus
    vim.o.showtabline = st.showtabline
  end
end

--- Open the explorer on the repo at `root`, in a tab page of its own.
---@param root string
function M.open(root)
  st.root = root
  local dir = index.dir(root)
  st.lens = lens.load(root)
  if st.loaded_root ~= root then
    st.models, st.names, st.hues, st.cur, st.filter, st.order = {}, {}, nil, nil, '', 1
    st.loaded_root = root
  end
  code.root = root
  code.reset()
  theme.setup()
  -- the one shown first, now; the rest once the screen is up
  local first = st.cur or 'treesitter'
  if vim.uv.fs_stat(dir .. '/' .. first .. '.json') then
    index.load(first)
  else
    index.load()
  end
  if #st.names == 0 then
    vim.notify('seam: no JSON in ' .. dir, vim.log.levels.ERROR)
    return
  end
  st.cur = st.cur and st.models[st.cur] and st.cur or (vim.tbl_contains(st.names, 'treesitter') and 'treesitter' or st.names[1])
  theme.assign(index.model(), dir .. '/hues.json')
  st.stack, st.page, st.shown = {}, nil, nil
  vim.cmd 'tabnew'
  st.tab = api.nvim_get_current_tabpage()
  local blank = api.nvim_get_current_buf()
  vim.bo[blank].bufhidden = 'wipe'
  st.buf = {
    lhead = draw.scratch 'contracts-head',
    rhead = draw.scratch 'head',
    list = draw.scratch 'contracts',
    mid = draw.scratch 'built-from',
    right = draw.scratch 'used-by',
    diag = draw.scratch 'diagram',
  }
  explorer_keys(st.buf.list)
  for _, b in ipairs { st.buf.lhead, st.buf.rhead, st.buf.mid, st.buf.right, st.buf.diag } do
    local o = { buffer = b, nowait = true, silent = true }
    vim.keymap.set('n', 'q', M.close, o)
    vim.keymap.set('n', 'S', M.switch, o)
  end
  api.nvim_create_autocmd('CursorMoved', { group = aug, buffer = st.buf.list, callback = M.on_move })
  api.nvim_create_autocmd('WinScrolled', {
    group = aug,
    callback = function()
      if api.nvim_get_current_tabpage() == st.tab then
        paint()
      end
    end,
  })
  -- one status line and no tab line while seam's tab is the one shown
  api.nvim_create_autocmd('TabEnter', {
    group = aug,
    callback = function()
      if api.nvim_get_current_tabpage() == st.tab then
        st.laststatus = vim.o.laststatus
        st.showtabline = vim.o.showtabline
        vim.o.laststatus = 3
        vim.o.showtabline = 0
      end
    end,
  })
  api.nvim_create_autocmd('TabLeave', {
    group = aug,
    callback = function()
      if api.nvim_get_current_tabpage() == st.tab and st.laststatus then
        vim.o.laststatus = st.laststatus
        vim.o.showtabline = st.showtabline
      end
    end,
  })
  st.laststatus = vim.o.laststatus
  st.showtabline = vim.o.showtabline
  vim.o.laststatus = 3
  vim.o.showtabline = 0
  layout_explorer()
  show_list()
  paint()
  vim.defer_fn(function()
    index.load()
    if st.screen == 'explorer' and st.shown then
      explorer.contract_head(st.shown)
      paint()
    end
    vim.cmd 'redrawstatus'
  end, 30)
end

return M
