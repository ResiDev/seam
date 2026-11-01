-- The tab page seam lives in: the tree's windows (seam.screen_tree), a
-- page's, the call tree's and the types', the keys in each, the status
-- line, and moving between them, the cursor redrawing what it lands on.
local api = vim.api
local calls = require 'seam.calls'
local calls_draw = require 'seam.draw.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local lens = require 'seam.lens'
local lens_panel = require 'seam.lens_panel'
local page = require 'seam.draw.page'
local picker = require 'seam.picker'
local st = require 'seam.state'
local tree_screen = require 'seam.screen_tree'
local theme = require 'seam.theme'
local types = require 'seam.types'
local types_draw = require 'seam.draw.types'
local M = {}

local aug = api.nvim_create_augroup('seam', { clear = true })
M.aug = aug
local ns_at = api.nvim_create_namespace 'seam.at'
local TABS = { built = 'built from', used = 'used by' }
local shape = draw.shape
local goto_keys

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

-- what seam.screen_tree shares
M.winopts, M.reset_tab, M.wrap, M.split, M.paint = winopts, reset_tab, wrap, split, paint

---------------------------------------------------------------- status

--- The status line: where you are on the left, the keys on the right.
---@return string
function M.status()
  local left, right = '', ''
  local srcs = #st.names > 1 and ('S ' .. st.names[(vim.fn.index(st.names, st.cur) + 1) % #st.names + 1]) or ''
  if st.screen == 'tree' and not picker.is_open() then
    return tree_screen.status()
  end
  if picker.is_open() then
    left, right = picker.status()
  elseif st.screen == 'page' and st.page then
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
    if M.flow_of(p.c) then
      hints[#hints + 1] = 't its flow'
    end
    if #st.stack > 0 then
      hints[#hints + 1] = 'K ' .. draw.trail(st.stack[#st.stack])
    end
    hints[#hints + 1] = (#st.stack > 0 and '- ' or 'K ') .. 'overview'
    right = table.concat(hints, '   ')
  elseif st.screen == 'calls' and st.calls then
    left, right = M.calls_status()
  elseif st.screen == 'types' and st.types then
    left, right = M.types_status()
  end
  if srcs ~= '' and st.screen ~= 'calls' and st.screen ~= 'types' and not picker.is_open() then
    right = right .. '   ' .. srcs
  end
  -- a lens on is said in the same place on every screen, the far right, in its red
  local n = st.lens and #st.lens.rules or 0
  local mark = n > 0 and ('L lens ' .. n) or ''
  -- the keys that fit, the last ones dropped first
  local room = vim.o.columns - 12 - api.nvim_strwidth(left) - (n > 0 and #mark + 3 or 0)
  local keys = vim.tbl_filter(function(k)
    return n == 0 or k ~= 'L lens'
  end, vim.split(right, '   ', { plain = true }))
  while #keys > 1 and api.nvim_strwidth(table.concat(keys, '   ')) > room do
    keys[#keys] = nil
  end
  right = table.concat(keys, '   '):gsub('%%', '%%%%')
  if n > 0 then
    right = right .. '   %#SeamStatusLens#' .. mark .. '%#SeamStatus#'
  end
  return '%#SeamMode# NORMAL %#SeamStatus# ' .. left:gsub('%%', '%%%%') .. '%=' .. right .. ' '
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

local show_page, show_calls, show_types

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
  vim.keymap.set('n', '/', M.page_pick, o)
  vim.keymap.set('n', 't', function()
    M.contract_flow(st.page.c)
  end, o)
  vim.keymap.set('n', 'q', M.close, o)
  vim.keymap.set('n', 'S', M.switch, o)
  goto_keys(buf)
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
  goto_keys(p.buf.head)
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
    M.jump { path = r.meta.path, line = u and u.line or 1, col = u and u.col and u.col - 1 }
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
    label = a and ('calls of ' .. (a.kind == 'module' and vim.fn.fnamemodify(a.path, ':t') or shape(a))) or 'where the code starts',
  }
end

--- Open contract `c`'s page, over the page or Calls screen shown if there is
--- one, on `tab` when given.
---@param c table
---@param tab? 'built'|'used'
function M.open_page(c, tab)
  if st.page then
    st.stack[#st.stack + 1] = st.page
  elseif st.screen == 'calls' and st.calls then
    st.stack[#st.stack + 1] = calls_entry()
    st.calls, st.calls_rows = nil, nil
  end
  tab = tab or #c.deps == 0 and c.nusers > 0 and 'used' or 'built'
  st.page = { kind = 'page', c = c, tab = tab, sel = {} }
  show_page()
end

--- `/` on a page: a float over its left to switch to any contract the lens
--- lets through, on the tab shown, K back. On the tree, over it, to open
--- one's page. `query` is typed already.
---@param query? string
function M.page_pick(query)
  local p = st.page
  local over = p and (p.win.list or p.win.mid) or (not p and st.screen == 'tree' and tree_screen.valid() and st.owin.tree)
  if not (over and api.nvim_win_is_valid(over)) then
    return
  end
  local m = index.model()
  picker.open {
    title = 'open',
    noun = 'contracts',
    keys = '<CR> open   <C-n>/<C-p> next   <Esc> back',
    over = over,
    focus = api.nvim_get_current_win(),
    col = 1,
    width = picker.W,
    rows = api.nvim_win_get_height(over) + 1,
    items = picker.contracts(m),
    query = type(query) == 'string' and query or nil,
    node = function(id)
      return m.byid[id]
    end,
    column = 'used by',
    pick = function(x)
      local c = x and index.model().byid[x.id]
      if c and st.page == p and (not p or c ~= p.c) then
        M.open_page(c, p and p.tab)
      end
    end,
  }
end

--- Back: the previous page or Calls screen, or the tree.
function M.back()
  local e = table.remove(st.stack)
  st.page, st.types = nil, nil
  if e and e.kind == 'calls' then
    st.calls, st.calls_top = e.calls, e.top
    show_calls()
  elseif e and e.kind == 'types' then
    st.types = e
    show_types()
  elseif e then
    st.page = e
    show_page()
  else
    tree_screen.show()
  end
end

-- where a contract is in the tree: its function, else its file
local function target_of(c)
  local g = index.model().graph
  return c and (g and g.nodes[c.id] and c.id or c.path) or nil
end

--- Straight to the tree from any depth, on the contract you were reading.
function M.overview()
  local c = st.page and st.page.c
  st.stack, st.page, st.types, st.calls, st.calls_rows = {}, nil, nil, nil, nil
  tree_screen.show(target_of(c))
end

-- the tab page to show code in: the one seam was opened from, else the
-- first that is not seam's
local function code_tab()
  if st.from_tab and st.from_tab ~= st.tab and api.nvim_tabpage_is_valid(st.from_tab) then
    return st.from_tab
  end
  for _, t in ipairs(api.nvim_list_tabpages()) do
    if t ~= st.tab then
      return t
    end
  end
end

-- a window in the current tab page that holds a file: the current one,
-- unless it is a float, a sidebar or a list
local function file_win()
  local function holds(w)
    return api.nvim_win_get_config(w).relative == '' and vim.bo[api.nvim_win_get_buf(w)].buftype == ''
  end
  local cur = api.nvim_get_current_win()
  if holds(cur) then
    return cur
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if holds(w) then
      return w
    end
  end
  return cur
end

--- That place in your own code: the tab page seam was opened from (else the
--- first that is not seam's, else a new one), the file in its window, the
--- cursor on the line, centred, the jump in the jumplist. Seam's tab stays.
---@param t seam.Place|nil
function M.jump(t)
  if not (t and t.path) then
    api.nvim_echo({ { 'nothing here to go to', 'SeamLabel' } }, false, {})
    return
  end
  local file = vim.fs.normalize(st.root .. '/' .. t.path)
  local tab = code_tab()
  if tab then
    api.nvim_set_current_tabpage(tab)
  else
    vim.cmd 'tabnew'
  end
  api.nvim_set_current_win(file_win())
  vim.cmd "normal! m'"
  if vim.fs.normalize(api.nvim_buf_get_name(0)) ~= file then
    if not pcall(vim.cmd.edit, vim.fn.fnameescape(file)) then
      vim.cmd.split(vim.fn.fnameescape(file))
    end
  end
  local line = math.max(1, math.min(t.line or 1, api.nvim_buf_line_count(0)))
  local src = api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ''
  local col = t.col
  if not col and t.name and t.name ~= '' then
    local at = src:find('%f[%w_$]' .. vim.pesc(t.name) .. '%f[^%w_$]')
    col = at and at - 1
  end
  col = math.max(0, math.min(col or #src:match '^%s*', math.max(0, #src - 1)))
  api.nvim_win_set_cursor(0, { line, col })
  vim.cmd 'normal! zvzz'
end

-- what the screen shown is about: the contract, the page's, the anchor
local function subject()
  if st.screen == 'types' and st.types then
    local f = st.types.flow and index.model().flows[st.types.flow]
    local x = not f and st.types_rows and st.twin and api.nvim_win_is_valid(st.twin.list) and st.types_rows.rows[api.nvim_win_get_cursor(st.twin.list)[1]]
    f = f or (x and x.flow)
    local e = f and f.decls[1]
    return e and { path = e.path, line = e.line, name = e.name }
  end
  if st.screen == 'calls' and st.calls then
    local node = st.calls.anchor and index.model().graph.nodes[st.calls.anchor]
    return node and { path = node.path, line = math.max(1, node.line), name = node.kind ~= 'module' and node.name or nil }
  end
  if st.screen == 'tree' then
    local x = tree_screen.at()
    local node = x and x.id and index.model().graph.nodes[x.id]
    if node then
      return { path = node.path, line = math.max(1, node.line), name = node.name }
    end
    return x and x.kind == 'file' and { path = x.path, line = 1 } or nil
  end
  local c = st.screen == 'page' and st.page and st.page.c
  return c and { path = c.path, line = c.line, name = c.name }
end

-- the heads: what is not a row of its own goes to what the screen is about
local function about_subject(buf)
  return buf == (st.obuf and st.obuf.head)
    or buf == (st.obuf and st.obuf.phead)
    or buf == (st.page and st.page.buf and st.page.buf.head)
    or buf == (st.cbuf and st.cbuf.head)
    or buf == (st.tbuf and st.tbuf.head)
end

--- gf: that place in your own code, from the line under the cursor. A row
--- naming a function, contract or file, its declaration or the file; a line
--- of code, that line; a head, what the screen is about.
function M.gf()
  local buf = api.nvim_get_current_buf()
  local cur = api.nvim_win_get_cursor(0)
  local t = draw.at(buf, cur[1], cur[2])
  if not t and about_subject(buf) then
    t = subject()
  end
  M.jump(t)
end

-- gf and gd, the same jump, in a buffer of seam's
goto_keys = function(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'gf', M.gf, o)
  vim.keymap.set('n', 'gd', M.gf, o)
end
M.goto_keys = goto_keys

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
      tree_screen.show()
      return
    end
    for _, sp in ipairs(st.stack) do
      if sp.kind == 'page' then
        sp.c = find(sp.c) or sp.c
      end
    end
    st.page.c = nc
    st.page.sel = {}
    show_page()
  elseif st.screen == 'tree' then
    tree_screen.redraw(true)
  end
end

---------------------------------------------------------------- calls

local function calls_valid()
  local w = st.cwin
  return w and api.nvim_win_is_valid(w.head) and api.nvim_win_is_valid(w.list) and api.nvim_win_is_valid(w.code)
end

-- the rows the budget fills: the list's
local function calls_height()
  if not calls_valid() then
    return 40
  end
  return api.nvim_win_get_height(st.cwin.list)
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
  table.insert(crumb, 1, v.anchor and calls_label(g.nodes[v.anchor]) or 'where the code starts')
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
  if p and #calls.codes(p) > 1 then
    local words = { types = 'types', called = 'called at', itself = 'itself' }
    swap = { '<Tab> ' .. words[calls.next_code(p)] }
  end
  if p and p.code == 'called' then
    swap[#swap + 1] = 'n/N place'
  elseif p and p.code == 'itself' and #p.lines > 0 then
    swap[#swap + 1] = 'n/N call'
  end
  if calls_valid() and api.nvim_get_current_win() == st.cwin.code then
    return left, table.concat(vim.list_extend(swap, { '<Esc> the tree', 'K back', '- tree', 'q close' }), '   ')
  end
  local hints = vim.list_extend(swap, { 'j/k row' })
  if index.model().sigs then
    vim.list_extend(hints, { 't its types', calls_draw.typed(index.model()) and 'T counts' or 'T types' })
  end
  vim.list_extend(hints, { 'h fold', 'l open', 'J page', 'K back' })
  if v.anchor then
    hints[#hints + 1] = v.dir == 'up' and '~ calls' or '~ called by'
  end
  vim.list_extend(hints, { 'L lens', '<CR> anchor here', '/ anchor on', '[ ] sibling', 'O open all', 'H as it opened', '- tree', 'C from the top' })
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
  for _, w in ipairs { head, pane } do
    winopts(w)
  end
  winopts(list, true)
  wrap(pane)
  vim.wo[pane].winfixwidth = false
  vim.wo[head].winfixheight = true
  api.nvim_win_set_width(list, calls_draw.LW)
  -- the column titles in the tree's own bar, right over its rows
  vim.wo[list].winhighlight = vim.wo[list].winhighlight .. ',WinBar:SeamLabel,WinBarNC:SeamLabel'
  st.cwin = { head = head, list = list, code = pane }
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
  api.nvim_win_set_height(st.cwin.head, calls_draw.head(st.cbuf.head, g, v, vim.o.columns))
  vim.wo[st.cwin.list].winbar = calls_draw.titles(v)
  local r = calls.rows(g, v, calls_height(), m)
  st.calls_rows = r
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
  -- the screen the tree was opened from, a type's flow say
  if #st.stack > 0 then
    return M.back()
  end
  tree_screen.show()
end

-- a contract a page shows: an export used from another file
local function contract_of(id)
  local c = id and index.model().byid[id]
  return c and (c.nusers or 0) > 0 and c or nil
end

-- straight to the tree, on the anchor
local function calls_overview()
  local a = st.calls and st.calls.anchor
  st.stack, st.calls, st.calls_rows = {}, nil, nil
  tree_screen.show(a)
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
      elseif a == 'tree' then
        return calls_leave()
      end
    end
  end
end

-- `/`: a float over the tree to anchor on any function, the direction kept;
-- given a direction, a fresh tree that way instead, K going to the tree
local function calls_pick(query, dir)
  if not calls_valid() then
    return
  end
  local w = st.cwin
  local m = index.model()
  picker.open {
    title = 'anchor on',
    noun = 'functions',
    keys = '<CR> anchor   <C-n>/<C-p> next   <Esc> back',
    over = w.list,
    col = 1,
    width = picker.W,
    rows = api.nvim_win_get_height(w.list) + 1,
    items = calls.callables(m.graph, m),
    query = type(query) == 'string' and query or nil,
    node = function(id)
      return index.model().graph.nodes[id]
    end,
    column = 'used by',
    pick = function(x)
      if x and st.screen == 'calls' and st.calls then
        if dir then
          st.calls = calls.new(x.id, dir)
        else
          calls.anchor(st.calls, x.id)
        end
        show_calls()
      end
    end,
    closed = function()
      if calls_valid() then
        api.nvim_set_current_win(w.list)
      end
    end,
  }
end

local function calls_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  local press = calls_press
  for _, k in ipairs { 'l', 'h', 'O', 'H', '<CR>', '~', '<BS>', 'K', 'C', '<Tab>', ']', '[' } do
    vim.keymap.set('n', k, press(k), o)
  end
  vim.keymap.set('n', 'L', M.open_lens, o)
  vim.keymap.set('n', '/', function()
    calls_pick()
  end, o)
  vim.keymap.set('n', 'j', press('j', true), o)
  vim.keymap.set('n', 'k', press('k', true), o)
  vim.keymap.set('n', 'n', press(']]', true), o)
  vim.keymap.set('n', 'N', press('[[', true), o)
  vim.keymap.set('n', '<Down>', press 'j', o)
  vim.keymap.set('n', '<Up>', press 'k', o)
  vim.keymap.set('n', 'J', calls_page, o)
  vim.keymap.set('n', '-', calls_overview, o)
  vim.keymap.set('n', 'T', function()
    local m = M.typed_model()
    if m then
      st.columns = calls_draw.typed(m) and 'counts' or 'types'
      show_calls()
    end
  end, o)
  vim.keymap.set('n', 't', function()
    local x = st.calls_rows and st.calls_rows.rows[calls_at()]
    M.its_types(x and x.id, nil, st.cwin.list)
  end, o)
  goto_keys(buf)
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
    if calls.key(m.graph, st.calls, st.calls_rows, calls_at(), '<BS>', calls_height(), m) == 'tree' then
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
  goto_keys(buf)
end

--- The Calls screen on a function, component or class by id, or from the top;
--- down from it, or up when `dir` says.
---@param id string|nil
---@param dir? seam.Dir
function M.open_calls(id, dir)
  local m = index.model()
  if not (m and m.graph) then
    vim.notify('seam: this index has no calls; :Seam! indexes again', vim.log.levels.WARN)
    return
  end
  if id and not m.graph.nodes[id] then
    vim.notify('seam: ' .. (index.id_path(id) and id:match '[^:]*$' or id) .. ' is not a function, component or class', vim.log.levels.INFO)
    return
  end
  if not (st.cbuf and api.nvim_buf_is_valid(st.cbuf.list)) then
    st.cbuf = { head = draw.scratch 'calls-head', list = draw.scratch 'calls', code = draw.scratch 'calls-code' }
    calls_keys(st.cbuf.list)
    calls_code_keys(st.cbuf.code)
    for _, b in ipairs { st.cbuf.head } do
      vim.keymap.set('n', 'q', M.close, { buffer = b, nowait = true, silent = true })
      goto_keys(b)
      -- nothing to do in the head: the cursor goes back to the tree
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
  st.calls = calls.new(id, dir or 'down')
  show_calls()
end

--- `/` on the Calls screen, `query` typed already; with `dir`, the pick
--- starts a fresh tree that way.
---@param query? string
---@param dir? seam.Dir
function M.calls_pick(query, dir)
  calls_pick(query, dir)
end

--- Start over on the tree, on `c` when given: a contract (its function,
--- else its file), a node id or a path; nothing under it for K.
---@param c? table|string
function M.show(c)
  st.stack, st.page, st.calls, st.calls_rows, st.types = {}, nil, nil, nil, nil
  tree_screen.show(type(c) == 'table' and target_of(c) or c)
end

---------------------------------------------------------------- types

local function types_valid()
  local w = st.twin
  return w and api.nvim_win_is_valid(w.head) and api.nvim_win_is_valid(w.list) and api.nvim_win_is_valid(w.code)
end

local function say(msg)
  api.nvim_echo({ { msg, 'SeamLabel' } }, false, {})
end

--- The model shown, when it has its types; else one line saying why not.
---@return table|nil
function M.typed_model()
  local m = index.model()
  if not (m and m.flows) and st.root then
    index.types(st.root)
    m = index.model()
  end
  if m and m.flows then
    return m
  end
  if index.asking_types(st.root) then
    say 'no types yet: the TypeScript server is being asked, and the screen redraws when they land'
  elseif index.types_refused(st.root) then
    say 'no types: the TypeScript server did not answer for this repo; :Seam! asks again'
  else
    say 'no types: this repo has no call graph to type; :Seam! indexes it again'
  end
end

--- The flow of contract `c`, when it is a type some function takes or makes.
---@param c table|nil
---@return seam.Flow|nil
function M.flow_of(c)
  local m = index.model()
  local f = c and m and m.flows and m.flows[c.name]
  return f and f.n > 0 and vim.tbl_contains(f.decls, c) and f or nil
end

-- the row under the list's cursor, and its index
local function types_at()
  if not (types_valid() and st.types_rows) then
    return nil
  end
  local i = api.nvim_win_get_cursor(st.twin.list)[1]
  return st.types_rows.rows[i], i
end

--- The status line on the Types screen: the type, and the row under the
--- cursor among the rest; then the keys.
---@return string left, string right
function M.types_status()
  local v, rs = st.types, st.types_rows
  local x, i = types_at()
  if not v.flow then
    local left = 'types'
    if x then
      left = left .. ('  %s  %d of %d'):format(x.key, i, #rs.rows)
    end
    return left, table.concat({ 'j/k row', 'l its flow', '/ a type', 'K back', '- tree', 'q close' }, '   ')
  end
  local left = v.flow
  if x and x.section then
    left = left .. '  ' .. (x.section == 'gives' and 'made by' or 'taken by')
    local at
    for _, s in ipairs(rs.sections) do
      at = s <= i and s or at
    end
    if x.kind == 'fn' and at then
      left = left .. ('  %d of %d'):format(i - at, rs.rows[at].n)
    end
  end
  return left, table.concat({ 'j/k row', 't its types', '<CR> its calls', '<Tab> next section', '/ a type', 'K back', '- tree' }, '   ')
end

local function types_layout()
  if st.screen == 'types' and types_valid() then
    return
  end
  st.screen, st.twin = 'types', nil
  local head = reset_tab()
  api.nvim_win_set_buf(head, st.tbuf.head)
  local list = split(st.tbuf.list, head, 'below', true)
  local pane = split(st.tbuf.code, list, 'right')
  for _, w in ipairs { head, pane } do
    winopts(w)
  end
  winopts(list, true)
  wrap(pane)
  vim.wo[pane].winfixwidth = false
  vim.wo[head].winfixheight = true
  api.nvim_win_set_width(list, types_draw.LW)
  vim.wo[list].winhighlight = vim.wo[list].winhighlight .. ',WinBar:SeamLabel,WinBarNC:SeamLabel'
  st.twin = { head = head, list = list, code = pane }
  api.nvim_set_current_win(list)
end

-- what is beside the list, when the cursor moved to another row
local function types_moved()
  if st.screen ~= 'types' or st.drawing or not (types_valid() and st.types_rows) then
    return
  end
  local x = types_at()
  st.types.cursor = x and x.key or st.types.cursor
  draw.cursor_line(st.twin.list)
  if st.types_shown ~= (x and x.key or '') then
    st.types_shown = x and x.key or ''
    types_draw.pane(st.tbuf.code, st.twin.code, index.model(), st.types, x)
    paint()
  end
  vim.cmd 'redrawstatus'
end

show_types = function()
  local m = index.model()
  local v = st.types
  types_layout()
  api.nvim_win_set_height(st.twin.head, types_draw.head(st.tbuf.head, m, v))
  vim.wo[st.twin.list].winbar = types_draw.titles(v)
  local rs = types_draw.rows(m, v)
  st.types_rows = rs
  -- back on the row it was on; a flow opens on its first function
  local target
  for i, x in ipairs(rs.rows) do
    if x.key == v.cursor then
      target = i
    end
    if not target and not v.cursor and x.kind == (v.flow and 'fn' or 'type') then
      target = i
    end
  end
  target = target or rs.stops[1] or 1
  st.drawing = true
  types_draw.list(st.tbuf.list, m, v, rs)
  api.nvim_win_call(st.twin.list, function()
    vim.fn.winrestview { topline = v.top or 1, lnum = target, col = 0 }
  end)
  v.top = nil
  st.drawing = false
  st.types_shown = nil
  types_moved()
  paint()
end

-- the Types screen as it is, for K to come back to
local function types_entry()
  local v = st.types
  local w = st.twin and st.twin.list
  v.top = w and api.nvim_win_is_valid(w) and api.nvim_win_call(w, function()
    return vim.fn.line 'w0'
  end) or nil
  v.label = v.flow and ('flow of ' .. v.flow) or 'types'
  return v
end

local types_keys

--- The Types screen: the flow of type `name`, or every type the most
--- travelled first; over the screen shown, which K comes back to.
---@param name string|nil
function M.open_types(name)
  if not M.typed_model() then
    return
  end
  if st.screen == 'types' and st.types then
    st.stack[#st.stack + 1] = types_entry()
  elseif st.screen == 'calls' and st.calls then
    st.stack[#st.stack + 1] = calls_entry()
    st.calls, st.calls_rows = nil, nil
  elseif st.screen == 'page' and st.page then
    st.stack[#st.stack + 1] = st.page
    st.page = nil
  end
  if not (st.tbuf and api.nvim_buf_is_valid(st.tbuf.list)) then
    st.tbuf = { head = draw.scratch 'types-head', list = draw.scratch 'types', code = draw.scratch 'types-code' }
    types_keys(st.tbuf)
  end
  st.types = { kind = 'types', flow = name }
  show_types()
end

--- `t` on contract `c`: its flow, when it is a type a function takes or makes.
---@param c table|nil
function M.contract_flow(c)
  if not (c and M.typed_model()) then
    return
  end
  if not M.flow_of(c) then
    return say(shape(c) .. ' is not a type that flows through a function')
  end
  M.open_types(c.name)
end

--- `/` on the Types screen, or `t` naming several: a float over `over` of
--- the types in `names` (all of them when nil), the most travelled first;
--- `<CR>` follows one. `query` is typed already.
---@param over integer
---@param names? string[]
---@param query? string
function M.types_pick(over, names, query)
  local m = M.typed_model()
  if not (m and over and api.nvim_win_is_valid(over)) then
    return
  end
  local items = {}
  for _, f in ipairs(m.flowlist) do
    if not names or vim.tbl_contains(names, f.name) then
      items[#items + 1] = { id = f.name, name = f.name, used_by = f.n }
    end
  end
  picker.open {
    title = 'types',
    noun = 'types',
    keys = '<CR> its flow   <C-n>/<C-p> next   <Esc> back',
    over = over,
    focus = over,
    col = 1,
    width = picker.W,
    rows = api.nvim_win_get_height(over) + 1,
    items = items,
    query = type(query) == 'string' and query or nil,
    node = function(id)
      return m.flows[id].decls[1]
    end,
    column = 'functions',
    pick = function(x)
      if x then
        M.open_types(x.id)
      end
    end,
  }
end

--- `t` on a function: the repo types it takes and gives, but `except`; one,
--- its flow, several the `/` float over `over` holding them.
---@param id string|nil
---@param except string|nil
---@param over integer
function M.its_types(id, except, over)
  local m = M.typed_model()
  if not (m and id) then
    return
  end
  local node = m.graph.nodes[id]
  local sig = m.sigs[id]
  local names = vim.tbl_filter(function(n)
    return n ~= except
  end, sig and types.named(sig, m.flows) or {})
  if #names == 0 then
    local what = node.kind == 'module' and 'the top of the file' or shape(node)
    return say(what .. (except and ' takes and gives no other type of the repo' or ' takes and gives no type of the repo'))
  elseif #names == 1 then
    return M.open_types(names[1])
  end
  M.types_pick(over, names)
end

types_keys = function(b)
  local function o(buf)
    return { buffer = buf, nowait = true, silent = true }
  end
  local function move(n)
    return function()
      if st.types_rows then
        step(st.twin.list, st.types_rows.stops, n * vim.v.count1)
      end
    end
  end
  local function follow()
    local x = types_at()
    if x and x.kind == 'type' then
      M.open_types(x.flow.name)
    elseif x and x.kind == 'fn' then
      st.stack[#st.stack + 1] = types_entry()
      st.types = nil
      M.open_calls(x.id)
    end
  end
  local lo = o(b.list)
  vim.keymap.set('n', 'j', move(1), lo)
  vim.keymap.set('n', 'k', move(-1), lo)
  vim.keymap.set('n', '<Down>', move(1), lo)
  vim.keymap.set('n', '<Up>', move(-1), lo)
  vim.keymap.set('n', '<CR>', follow, lo)
  vim.keymap.set('n', 'l', function()
    local x = types_at()
    if x and x.kind == 'type' then
      follow()
    end
  end, lo)
  vim.keymap.set('n', 't', function()
    local x = types_at()
    if x and x.kind == 'fn' then
      M.its_types(x.id, st.types.flow, st.twin.list)
    end
  end, lo)
  vim.keymap.set('n', '<Tab>', function()
    local rs = st.types_rows
    if not (rs and #rs.sections > 0) then
      return
    end
    local cur = api.nvim_win_get_cursor(st.twin.list)[1]
    local to = rs.sections[1]
    for _, s in ipairs(rs.sections) do
      if s > cur then
        to = s
        break
      end
    end
    api.nvim_win_set_cursor(st.twin.list, { to, 0 })
  end, lo)
  vim.keymap.set('n', '/', function()
    M.types_pick(st.twin.list)
  end, lo)
  api.nvim_create_autocmd('CursorMoved', { group = aug, buffer = b.list, callback = types_moved })
  for _, buf in ipairs { b.list, b.code, b.head } do
    vim.keymap.set('n', 'K', M.back, o(buf))
    vim.keymap.set('n', '<BS>', M.back, o(buf))
    vim.keymap.set('n', '-', M.overview, o(buf))
    vim.keymap.set('n', 'q', M.close, o(buf))
    goto_keys(buf)
  end
  -- the code beside keeps the cursor to scroll and search; <Esc> gives it back
  vim.keymap.set('n', '<Esc>', function()
    if types_valid() then
      api.nvim_set_current_win(st.twin.list)
    end
  end, o(b.code))
  api.nvim_create_autocmd('WinEnter', {
    group = aug,
    buffer = b.head,
    callback = function()
      if st.screen == 'types' and types_valid() then
        api.nvim_set_current_win(st.twin.list)
      end
    end,
  })
  api.nvim_create_autocmd('WinEnter', {
    group = aug,
    buffer = b.code,
    callback = function()
      vim.cmd 'redrawstatus'
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = aug,
    callback = function()
      if st.screen == 'types' and st.types and api.nvim_get_current_tabpage() == st.tab then
        show_types()
      end
    end,
  })
end

--- The types landed while seam was open: the screen shown drawn again with them.
function M.types_landed()
  if not (st.tab and api.nvim_tabpage_is_valid(st.tab)) then
    return
  end
  if st.screen == 'calls' and st.calls and calls_valid() then
    show_calls()
  elseif st.screen == 'types' and st.types and types_valid() then
    show_types()
  elseif st.screen == 'tree' then
    tree_screen.redraw(true)
  end
  vim.cmd 'redrawstatus'
end

---------------------------------------------------------------- lens

--- The lens changed: save it, filter every source, redraw what is shown. A
--- page redraws when the panel closes: drawing it closes every window.
function M.lens_changed()
  lens.save(st.lens, st.root)
  for _, m in pairs(st.models) do
    lens.apply(st.lens, m)
  end
  -- what the budget opened in a call tree was for the lens before: shown,
  -- under a page, or an anchor back
  local trees = { st.calls }
  for _, e in ipairs(st.stack or {}) do
    trees[#trees + 1] = e.kind == 'calls' and e.calls or nil
  end
  for _, v in ipairs(trees) do
    for _, s in ipairs { v, unpack(v.back) } do
      s.auto = nil
    end
  end
  if st.screen == 'calls' and st.calls then
    show_calls()
  elseif st.screen == 'page' and st.page then
    if lens_panel.is_open() then
      st.page_stale = true
    else
      show_page()
    end
  elseif st.screen == 'tree' then
    tree_screen.redraw(true)
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

--- Open the tree on the repo at `root`, in a tab page of its own; when
--- seam is open on it already, its tab, as it was.
---@param root string
function M.open(root)
  local from = api.nvim_get_current_tabpage()
  if st.tab and api.nvim_tabpage_is_valid(st.tab) then
    if st.root == root and st.screen then
      if from ~= st.tab then
        st.from_tab = from
      end
      api.nvim_set_current_tabpage(st.tab)
      return
    end
    M.close()
    if api.nvim_tabpage_is_valid(from) then
      api.nvim_set_current_tabpage(from)
    end
  end
  st.root = root
  local dir = index.dir(root)
  st.lens = lens.load(root)
  if st.loaded_root ~= root then
    st.models, st.names, st.hues, st.cur, st.outline, st.view = {}, {}, nil, nil, nil, nil
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
  st.stack, st.page = {}, nil
  -- the tab page gf goes back to, to show the code
  if from ~= st.tab then
    st.from_tab = from
  end
  vim.cmd 'tabnew'
  st.tab = api.nvim_get_current_tabpage()
  local blank = api.nvim_get_current_buf()
  vim.bo[blank].bufhidden = 'wipe'
  tree_screen.init()
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
  tree_screen.show()
  vim.defer_fn(function()
    index.load()
    index.types(root)
    vim.cmd 'redrawstatus'
  end, 30)
end

return M
