-- The view you came from: seam opened from a buffer holds it, a tab beside
-- seam's own views, the pane's window showing the buffer itself, on the
-- lab's excalidraw copy (SEAM_REPO).
--   nvim --headless --clean -l tests/held.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.cmd 'runtime plugin/seam.lua'
local api = vim.api
local repo = vim.env.SEAM_REPO or (root .. '/lab/excalidraw')
if not vim.uv.fs_stat(repo .. '/package.json') then
  io.stdout:write('held: no repo at ' .. repo .. ', skipped\n')
  os.exit(0)
end

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

local seam = require 'seam'
local st = seam.st
local pane = require 'seam.pane'
local views = require 'seam.views'
pane.DELAY = 0

local function tab_names()
  return vim.tbl_map(views.label, views.tabs(pane.subject()))
end
local function pane_buf()
  return api.nvim_win_get_buf(st.owin.pane)
end
local function to_held()
  st.view.aside, st.view.at = nil, 'held'
  pane.redraw()
end
local function opened()
  assert(
    vim.wait(20000, function()
      return st.tab ~= nil and api.nvim_tabpage_is_valid(st.tab) and st.owin ~= nil
    end, 50),
    'seam opened'
  )
end

-- your code, line 20, numbers on
vim.cmd.edit(repo .. '/packages/element/src/Scene.ts')
local code, code_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
vim.wo.number = true
api.nvim_win_set_cursor(0, { 20, 0 })

seam.show('packages/element/src/mutateElement.ts:mutateElement@Map', { root = repo })
opened()
eq(st.held and st.held.buf, code, 'show without from holds the buffer it was called from')
eq(tab_names(), { 'Code', 'Types', 'Map', 'Scene.ts' }, 'its file names the tab, after seam’s')
eq(views.shown(pane.subject(), st.view).name, 'Map', 'landed on the view the target names')
eq(pane_buf(), st.obuf.pane, 'the pane shows seam’s own buffer')

to_held()
eq(pane_buf(), code, 'shown, the pane’s window holds the buffer itself')
eq(api.nvim_win_get_cursor(st.owin.pane)[1], 20, 'where its cursor was')
eq(vim.wo[st.owin.pane].number, true, 'with its own window’s options')

local before = api.nvim_win_get_cursor(st.owin.tree)[1]
api.nvim_win_set_cursor(st.owin.tree, { before + 1, 0 })
api.nvim_exec_autocmds('CursorMoved', { buffer = st.obuf.tree })
pane.flush()
eq(pane_buf(), code, 'the tree’s cursor moved: still the buffer held')
eq(api.nvim_win_get_cursor(st.owin.pane)[1], 20, 'not moved by the row')

pane.step(1)()
eq(pane_buf(), st.obuf.pane, '<Tab> away: seam’s own buffer back')
eq(vim.wo[st.owin.pane].number, false, 'and seam’s options')
eq(vim.wo[code_win].number, true, 'your window as it was')
eq(api.nvim_buf_is_valid(code) and api.nvim_buf_get_name(code):match 'Scene.ts$', 'Scene.ts', 'the buffer left alone')

seam.hold(nil)
eq(st.held, nil, 'hold(nil) lets go')
eq(tab_names(), { 'Code', 'Types', 'Map' }, 'nothing held, no tab')

local page = api.nvim_create_buf(false, true)
api.nvim_buf_set_lines(page, 0, -1, false, { 'a thread', 'its second line' })
vim.b[page].seam_name = 'How a scene stores elements'
seam.show('packages/element/src/Scene.ts', { from = page, root = repo })
eq(st.held and st.held.buf, page, 'show with from holds it, from seam’s tab too')
eq(tab_names()[#tab_names()], 'How a scene stores elements', 'a buffer’s seam_name names the tab')

to_held()
eq(pane_buf(), page, 'the page shown')
api.nvim_buf_delete(page, { force = true })
eq(st.held, nil, 'wiped, it is let go')
vim.wait(50)
eq(require('seam.screen_tree').valid(), true, 'the pane laid out again')
eq(pane_buf(), st.obuf.pane, 'seam’s buffer in it')
eq(tab_names(), { 'Code', 'Types', 'Map' }, 'and its tab gone')

-- from your code again: here holds it, from a file at the repo's root
api.nvim_set_current_tabpage(st.from_tab)
vim.cmd.edit(repo .. '/setupTests.ts')
local setup = api.nvim_get_current_buf()
api.nvim_win_set_cursor(0, { 9, 8 })
seam.here()
opened()
eq(st.held and st.held.buf, setup, 'here holds the buffer it was called from')
to_held()
eq(api.nvim_win_get_cursor(st.owin.pane), { 9, 8 }, 'at its cursor')

api.nvim_set_current_win(st.owin.tree)
seam.start(repo)
eq(st.held and st.held.buf, setup, 'from seam’s own tab, what is held stays')

-- a buffer with its own <Tab>, as a thread's page folds on it
local page = api.nvim_create_buf(false, true)
vim.keymap.set('n', '<Tab>', function() end, { buffer = page, desc = 'fold' })
local function tab_desc(buf)
  return api.nvim_buf_call(buf, function()
    return vim.fn.maparg('<Tab>', 'n', false, true).desc
  end)
end
seam.hold(page)
to_held()
eq(pane_buf(), page, 'the page in the pane')
eq(tab_desc(page), 'fold', 'the cursor in the tree: the page keeps its <Tab>')
api.nvim_set_current_win(st.owin.pane)
eq(tab_desc(page), 'seam: the next view', 'the cursor in the pane on the page: <Tab> is seam’s')
api.nvim_set_current_win(st.owin.tree)
eq(tab_desc(page), 'fold', 'back in the tree: the page’s own <Tab> again')
api.nvim_set_current_win(st.owin.pane)
api.nvim_feedkeys(api.nvim_replace_termcodes('<Tab>', true, false, true), 'x', false)
eq(pane_buf() ~= page, true, '<Tab> in the page steps to seam’s next view')
eq(tab_desc(page), 'fold', 'and the page has its own <Tab> back')

io.stdout:write(('held: %d checks, %d failed\n'):format(checks, #failures))
os.exit(#failures == 0 and 0 or 1)
