-- The tab page seam lives in: its windows' options, the status line of the
-- screen shown (the tree, seam.screen_tree; the code, seam.screen_code), gf
-- to your own code, the lens, types landing, opening and closing.
local api = vim.api
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
  if picker.is_open() then
    local left, right = picker.status()
    return '%#SeamMode# NORMAL %#SeamStatus# ' .. left:gsub('%%', '%%%%') .. '%=' .. right:gsub('%%', '%%%%') .. ' '
  elseif lens_panel.focused() then
    return require('seam.hints').status('lens', { { { 'j k', 'row' }, { 'f', 'from' }, { 't', 'to' }, { 'x', 'reset' }, { 'q', 'close' } } }, 0)
  elseif st.screen == 'code' then
    return require('seam.screen_code').status()
  end
  return tree_screen.status()
end

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
  if st.screen == 'code' and st.code and st.code.trail[1] then
    local e = st.code.trail[#st.code.trail]
    local node = e.id and index.model().graph.nodes[e.id]
    return node and { path = node.path, line = math.max(1, node.line), name = node.name } or { path = e.path, line = 1 }
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
  return buf == (st.obuf and st.obuf.head) or buf == (st.obuf and st.obuf.phead) or buf == (st.cbuf and st.cbuf.chead)
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

--- Start over on the tree, on `c` when given: a contract (its function,
--- else its file), a node id or a path; nothing under it for K.
---@param c? table|string
function M.show(c)
  st.code = nil
  tree_screen.show(type(c) == 'table' and target_of(c) or c)
end

---------------------------------------------------------------- types

--- The types landed while seam was open: the screen shown drawn again with them.
function M.types_landed()
  if not (st.tab and api.nvim_tabpage_is_valid(st.tab)) then
    return
  end
  if st.screen == 'tree' then
    tree_screen.redraw(true)
  elseif st.screen == 'code' then
    require('seam.screen_code').redraw()
  end
  vim.cmd 'redrawstatus'
end

---------------------------------------------------------------- changes

--- Ask git what changed in the range, the screen shown drawn again once it
--- has said: the signs, the diff.
function M.ask_changes()
  local root = st.root
  require('seam.changes').ask(root, function()
    if st.root == root then
      M.types_landed()
    end
  end)
end

---------------------------------------------------------------- lens

--- The lens changed: save it, filter every source, redraw what is shown.
function M.lens_changed()
  lens.save(st.lens, st.root)
  for _, m in pairs(st.models) do
    lens.apply(st.lens, m)
  end
  if st.screen == 'tree' then
    tree_screen.redraw(true)
  elseif st.screen == 'code' then
    require('seam.screen_code').redraw()
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
    range = require('seam.changes').range,
    set_range = function(r)
      st.range = r
      M.ask_changes()
      M.types_landed()
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
      M.ask_changes()
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
    st.range, st.changes = nil, nil
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
  M.ask_changes()
  vim.defer_fn(function()
    index.load()
    index.types(root)
    vim.cmd 'redrawstatus'
  end, 30)
end

return M
