-- The tab page seam lives in: the explorer's windows and a page's, the keys
-- in each, the status line, and moving between them, the cursor redrawing
-- what it lands on.
local api = vim.api
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
    if p.tab == 'built' then
      hints[#hints + 1] = 'j/k next'
      if p.enter then
        hints[#hints + 1] = '<CR> enter ' .. p.enter
      end
    else
      hints[#hints + 1] = 'j/k next file'
      hints[#hints + 1] = ']] next use'
      hints[#hints + 1] = '<CR> open'
    end
    hints[#hints + 1] = panes == 'contract' and 'c both' or 'c contract'
    hints[#hints + 1] = panes == 'seam' and 's both' or ('s ' .. seam)
    hints[#hints + 1] = '<Tab> ' .. (p.tab == 'built' and 'used by' or 'built from')
    if #st.stack > 0 then
      hints[#hints + 1] = '<BS> ' .. shape(st.stack[#st.stack].c)
    end
    hints[#hints + 1] = (#st.stack > 0 and '- ' or '<BS> ') .. 'overview'
    right = table.concat(hints, '   ')
  else
    left = 'contracts  ' .. ORDERS[st.order].short
    local vw = st.view == 'diagram' and 'v trees   V map' or st.view == 'map' and 'v diagram   V trees' or 'v diagram   V map'
    local sd = st.sides == 'built' and 'b both   u used by' or st.sides == 'used' and 'b built from   u both' or 'b built from   u used by'
    right = '<Tab> ' .. ORDERS[st.order % #ORDERS + 1].short .. '   ' .. vw .. '   ' .. sd .. '   f lens   / search   <CR> open'
  end
  if srcs ~= '' then
    right = right .. '   ' .. srcs
  end
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
  paint()
  vim.cmd 'redrawstatus'
end

local show_page

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
  vim.keymap.set('n', '<BS>', M.back, o)
  vim.keymap.set('n', '-', M.overview, o)
  vim.keymap.set('n', 'f', M.open_lens, o)
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
  p.buf.list, p.buf.mid, p.buf.right = draw.scratch 'list', draw.scratch 'contract', draw.scratch 'seam'
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
  vim.wo[w].cursorline = true
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

--- Open contract `c`'s page, over the page shown if there is one.
---@param c table
function M.open_page(c)
  if st.page then
    st.stack[#st.stack + 1] = st.page
  else
    st.explorer_at = st.shown
  end
  local tab = (st.sides == 'used' or #c.deps == 0) and c.nusers > 0 and 'used' or 'built'
  st.page = { c = c, tab = tab, sel = {} }
  show_page()
end

--- Back: the previous page, or the explorer.
function M.back()
  if #st.stack > 0 then
    st.page = table.remove(st.stack)
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
      sp.c = find(sp.c) or sp.c
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

---------------------------------------------------------------- lens

--- The lens changed: save it, filter every source, redraw what is shown. A
--- page redraws when the panel closes: drawing it closes every window.
function M.lens_changed()
  lens.save(st.lens, st.root)
  for _, m in pairs(st.models) do
    lens.apply(st.lens, m)
  end
  if st.screen == 'page' and st.page then
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
  vim.keymap.set('n', '<CR>', function()
    if st.shown then
      M.open_page(st.shown)
    end
  end, o)
  vim.keymap.set('n', 'gd', function()
    M.goto_decl(st.shown)
  end, o)
  vim.keymap.set('n', 'S', M.switch, o)
  vim.keymap.set('n', 'f', M.open_lens, o)
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
    end
    vim.cmd 'redrawstatus'
  end, 30)
end

return M
