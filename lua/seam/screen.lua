-- The tab page seam lives in: the tree's windows (seam.screen_tree) and the
-- call tree's, the keys in each, the status line, and moving between them,
-- the cursor redrawing what it lands on.
local api = vim.api
local calls = require 'seam.calls'
local calls_draw = require 'seam.draw.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local lens = require 'seam.lens'
local lens_panel = require 'seam.lens_panel'
local picker = require 'seam.picker'
local st = require 'seam.state'
local tree_screen = require 'seam.screen_tree'
local theme = require 'seam.theme'
local M = {}

local aug = api.nvim_create_augroup('seam', { clear = true })
M.aug = aug
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

-- what seam.screen_tree shares
M.winopts, M.reset_tab, M.wrap, M.split, M.paint = winopts, reset_tab, wrap, split, paint

---------------------------------------------------------------- status

--- The status line: where you are on the left, the keys on the right.
---@return string
function M.status()
  local left, right = '', ''
  if st.screen == 'tree' and not picker.is_open() then
    return tree_screen.status()
  end
  if picker.is_open() then
    left, right = picker.status()
  elseif st.screen == 'calls' and st.calls then
    left, right = M.calls_status()
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

local show_calls

-- where a contract is in the tree: its function, else its file
local function target_of(c)
  local g = index.model().graph
  return c and (g and g.nodes[c.id] and c.id or c.path) or nil
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

-- what the screen shown is about: the row, the anchor
local function subject()
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
end

-- the heads: what is not a row of its own goes to what the screen is about
local function about_subject(buf)
  return buf == (st.obuf and st.obuf.head) or buf == (st.obuf and st.obuf.phead) or buf == (st.cbuf and st.cbuf.head)
end

--- gf: that place in your own code, from the line under the cursor. A row
--- naming a function or file, its declaration or the file; a line
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

--- The next source, on the same row.
function M.switch()
  index.load()
  if #st.names < 2 then
    vim.notify('seam: only ' .. (st.cur or '?') .. ' is loaded', vim.log.levels.INFO)
    return
  end
  local i = vim.fn.index(st.names, st.cur)
  st.cur = st.names[(i + 1) % #st.names + 1]
  local m = index.model()
  if st.screen == 'tree' then
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
    hints[#hints + 1] = calls_draw.typed(index.model()) and 'T counts' or 'T types'
  end
  vim.list_extend(hints, { 'h fold', 'l open', 'K back' })
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
  tree_screen.show()
end

-- straight to the tree, on the anchor
local function calls_overview()
  local a = st.calls and st.calls.anchor
  st.calls, st.calls_rows = nil, nil
  tree_screen.show(a)
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
  vim.keymap.set('n', '-', calls_overview, o)
  -- J waits for the code screen
  vim.keymap.set('n', 'J', '<Nop>', o)
  vim.keymap.set('n', 'T', function()
    local m = M.typed_model()
    if m then
      st.columns = calls_draw.typed(m) and 'counts' or 'types'
      show_calls()
    end
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
  st.calls, st.calls_rows = nil, nil
  tree_screen.show(type(c) == 'table' and target_of(c) or c)
end

---------------------------------------------------------------- types

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

--- The types landed while seam was open: the screen shown drawn again with them.
function M.types_landed()
  if not (st.tab and api.nvim_tabpage_is_valid(st.tab)) then
    return
  end
  if st.screen == 'calls' and st.calls and calls_valid() then
    show_calls()
  elseif st.screen == 'tree' then
    tree_screen.redraw(true)
  end
  vim.cmd 'redrawstatus'
end

---------------------------------------------------------------- lens

--- The lens changed: save it, filter every source, redraw what is shown.
function M.lens_changed()
  lens.save(st.lens, st.root)
  for _, m in pairs(st.models) do
    lens.apply(st.lens, m)
  end
  -- what the budget opened in a call tree was for the lens before: shown,
  -- or an anchor back
  if st.calls then
    for _, s in ipairs { st.calls, unpack(st.calls.back) } do
      s.auto = nil
    end
  end
  if st.screen == 'calls' and st.calls then
    show_calls()
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
    st.models, st.names, st.hues, st.cur, st.outline, st.view, st.opens, st.ptype = {}, {}, nil, nil, nil, nil, nil, nil
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
