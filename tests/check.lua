-- Drive every screen state through its real keys and report what broke.
--   SEAM_REPO=<path> [SEAM_MAX=n] [SEAM_LENS=1] nvim --headless -c 'luafile tests/check.lua'
-- Exits 0 when nothing failed. Uses your config, so other plugins' keys and
-- treesitter queries are the ones you have.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
if not vim.tbl_contains(vim.opt.runtimepath:get(), root) then
  vim.opt.runtimepath:append(root)
end
vim.o.columns, vim.o.lines = 180, 50
local api = vim.api
local seam = require 'seam'
local screen = require 'seam.screen'
local calls = require 'seam.calls'
local function lens_any(c)
  return c.contracts or c.built or c.used
end
local st = seam.st
local repo = assert(os.getenv 'SEAM_REPO', 'set SEAM_REPO')
local max = tonumber(os.getenv 'SEAM_MAX' or '0')

local failures, steps = {}, 0
local where = ''
local function fail(msg)
  local line = where .. '  ' .. msg:gsub('\n.*', '')
  failures[#failures + 1] = line
  if #failures <= 60 then
    io.stdout:write('FAIL ' .. line .. '\n')
    io.stdout:flush()
  end
end

local function key(k)
  steps = steps + 1
  vim.v.errmsg = ''
  local ok, err = pcall(function()
    api.nvim_feedkeys(vim.keycode(k), 'mx', false)
    api.nvim_exec_autocmds('CursorMoved', { buffer = api.nvim_get_current_buf() })
  end)
  if not ok then
    fail(k .. ': ' .. tostring(err))
  elseif vim.v.errmsg ~= '' then
    fail(k .. ': ' .. vim.v.errmsg)
  end
end

local function valid(w)
  return w and api.nvim_win_is_valid(w)
end

-- the windows on screen are the ones the pane choice says
local function check_page()
  local p = st.page
  if st.screen ~= 'page' or not p then
    return fail 'not on a page'
  end
  local mid, right = valid(p.win.mid), valid(p.win.right)
  if screen.reading(p) then
    if not (mid and right) or #api.nvim_tabpage_list_wins(st.tab) ~= 3 then
      fail 'Built from as code: not the head, the code and the declaration'
    end
    local r = p.index and p.refs[p.index]
    if r then
      local cur = api.nvim_win_get_cursor(p.win.mid)
      local named = table.concat(api.nvim_buf_get_lines(p.buf.right, 0, 3, false), '\n')
      if not named:find(r.dep.name, 1, true) then
        fail(('the declaration shown is not %s, the name at the cursor'):format(r.dep.name))
      end
      if
        cur[1] == r.row
        and #vim.tbl_filter(function(x)
          return x.row == r.row and x.s <= cur[2] and cur[2] < x.e
        end, p.refs) > 0
        and not (r.s <= cur[2] and cur[2] < r.e)
      then
        fail 'the cursor is on one name, the declaration on another'
      end
    elseif #p.refs > 0 then
      fail 'names in the code, but none shown'
    end
    -- each piece of code is painted one way: two highlights of one priority
    -- on one range are drawn in no promised order
    local seen = {}
    for _, m in ipairs(api.nvim_buf_get_extmarks(p.buf.mid, require('seam.code').ns, 0, -1, { details = true })) do
      local k = m[2] .. ':' .. m[3] .. ':' .. m[4].end_col .. ':' .. m[4].priority
      if seen[k] then
        fail(('%s and %s both paint row %d at %d'):format(seen[k], m[4].hl_group, m[2] + 1, m[3]))
        break
      end
      seen[k] = m[4].hl_group
    end
    return
  end
  local want = st.panes[p.tab]
  local ok = (want == 'both' and mid and right) or (want == 'contract' and mid and not p.win.right) or (want == 'seam' and right and not p.win.mid)
  if not ok then
    fail(('panes %s on %s, but contract window %s, seam window %s'):format(want, p.tab, tostring(mid), tostring(right)))
  end
  if not valid(p.win.list) then
    fail 'no list window'
  end
  local n = #api.nvim_tabpage_list_wins(st.tab)
  local expect = 2 + (want == 'both' and 2 or 1)
  if n ~= expect then
    fail(('%d windows, expected %d'):format(n, expect))
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(st.tab)) do
    if api.nvim_win_get_height(w) < 1 then
      fail 'a window with no height'
    end
  end
end

-- open
seam.start(repo)
vim.wait(120000, function()
  return st.screen ~= nil and st.tab ~= nil and api.nvim_tabpage_is_valid(st.tab)
end, 50)
if not st.tab then
  io.stdout:write 'could not open the explorer\n'
  vim.cmd 'cquit 1'
end
vim.wait(200)
-- the check marks the lens; the repository's own file goes back as it was
local lens_file = require('seam.lens').file(st.root)
local lens_before = vim.uv.fs_stat(lens_file) and vim.fn.readfile(lens_file, 'b')
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    if lens_before then
      vim.fn.mkdir(vim.fs.dirname(lens_file), 'p')
      vim.fn.writefile(lens_before, lens_file, 'b')
    else
      vim.fn.delete(lens_file)
      vim.fn.delete(vim.fs.dirname(lens_file), 'd')
    end
  end,
})
if os.getenv 'SEAM_LENS' then
  st.lens = {
    rules = {
      { path = 'packages/', cols = { contracts = 'only', used = 'only' } },
      { pattern = '*.test.*', cols = require('seam.lens').all 'hide' },
      { pattern = 'tests/', cols = { used = 'hide' } },
      { pattern = '/(fixtures|examples)/', cols = { built = 'hide' } },
    },
  }
  seam.lens_changed()
  io.stdout:write(('with a lens: %d contracts\n'):format(#st.models[st.cur].contracts))
end

-- the explorer's head: its declaration in two rows, five beside one tree
-- alone, none wider than the head
local function check_head(c)
  local w = st.win.rhead
  local lines = api.nvim_buf_get_lines(st.buf.rhead, 0, -1, false)
  local most = 1 + (st.sides == 'both' and 2 or 5) + 1
  if #lines > most then
    fail(('%s: the head has %d rows, at most %d'):format(c.name, #lines, most))
  end
  if api.nvim_win_get_height(w) ~= #lines then
    fail(('%s: the head is %d rows high for %d rows'):format(c.name, api.nvim_win_get_height(w), #lines))
  end
  for i = 2, #lines do
    if vim.fn.strdisplaywidth(lines[i]) > api.nvim_win_get_width(w) then
      fail(('%s: head row %d is wider than the head'):format(c.name, i))
    end
  end
end
-- built from's names: no row wider than its tree, wrapped to two rows, five
-- beside it alone
local function check_names()
  if not valid(st.win.mid) then
    return
  end
  local most, run = st.sides == 'both' and 2 or 5, 0
  for i, l in ipairs(api.nvim_buf_get_lines(st.buf.mid, 0, -1, false)) do
    if vim.fn.strdisplaywidth(l) > api.nvim_win_get_width(st.win.mid) then
      fail(('built from row %d is wider than its tree'):format(i))
    end
    local under = vim.trim(vim.fn.strcharpart(l, 0, 30):gsub('▎', '')) == '' and vim.trim(l:gsub('▎', '')) ~= ''
    run = under and run + 1 or 0
    if run == most then
      fail(("%s: a file's names take more than %d rows"):format(st.shown and st.shown.name or '?', most))
    end
  end
end

for _, side in ipairs { 'u', 'u', 'b', 'b' } do
  key(side)
  for _, c in ipairs(st.models[st.cur].contracts) do
    where = 'explorer head sides=' .. st.sides
    require('seam.draw.explorer').contract(c)
    check_head(c)
    check_names()
  end
end

-- the explorer: every view and every side, moving in each
where = 'explorer'
for _, view in ipairs { 'v', 'V' } do
  for _, side in ipairs { 'b', 'b', 'u', 'u', 'b', 'u', 'u' } do
    where = ('explorer %s %s sides=%s'):format(view, st.view, st.sides)
    key(side)
    for _, k in ipairs { 'j', 'j', 'k' } do
      key(k)
      check_names()
      if #api.nvim_buf_get_extmarks(st.buf.rhead, require('seam.code').ns, 0, -1, {}) == 0 then
        fail(k .. ' left the head uncoloured on ' .. (st.shown and st.shown.name or 'nothing'))
      end
    end
  end
  key(view)
  where = ('explorer back from %s'):format(view)
  key(view)
end
for _ = 1, #seam.st.names + 3 do
  key '<Tab>'
end

-- the lens panel, through its keys and its picker; then put the lens back
do
  local panel = require 'seam.lens_panel'
  local L = require 'seam.lens'
  local saved = vim.deepcopy(st.lens)
  local function expect(ok, what)
    if not ok then
      fail(what)
    end
  end
  local function last()
    return st.lens.rules[#st.lens.rules]
  end
  where = 'lens panel'
  key 'L'
  expect(panel.is_open(), 'L did not open the panel')
  -- the picker: type, wait for the live list, take the row asked for
  local function pick(query, want)
    key 'a'
    local Snacks = rawget(_G, 'Snacks')
    local p = Snacks and Snacks.picker.get()[1]
    expect(p, 'a opened no picker')
    if not p then
      return
    end
    p.input:set('', query)
    p:find()
    local items = {}
    vim.wait(3000, function()
      items = p:items()
      return items[1] and items[1].text == query
    end)
    for i, it in ipairs(items) do
      if want(it) then
        p.list:view(i)
        p:action 'confirm'
        vim.wait(1000, panel.is_open)
        return it
      end
    end
    fail('the picker listed nothing wanted for ' .. query)
    p:close()
    vim.wait(1000, panel.is_open)
  end
  local n2 = #st.lens.rules
  pick([[/\.(test|spec)\./]], function(it)
    return it.kind == 'pattern'
  end)
  expect(#st.lens.rules == n2 + 1 and last().pattern == [[/\.(test|spec)\./]], 'the picker did not add the regex')
  expect(#L.rule_files(st.models[st.cur], last()) > 0, 'the regex holds no file')
  expect(panel.is_open() and vim.bo.filetype == 'seamlens', 'the panel did not come back after the picker')
  key 'c'
  expect(last().cols.contracts == 'only' and not last().cols.used, 'c on the picked rule did not turn contracts to only')
  key 'c'
  expect(last().cols.contracts == 'hide', 'c again did not turn contracts to hide')
  key 'c'
  expect(last().cols.contracts == nil, 'c a third time did not leave contracts be')
  key 'u'
  expect(last().cols.used == 'only', 'u did not turn used by')
  key '<Space>'
  expect(last().cols.contracts == 'only' and last().cols.built == 'only' and last().cols.used == 'only', 'space on a mixed rule did not make all three only')
  key '<Space>'
  expect(last().cols.contracts == 'hide' and last().cols.built == 'hide' and last().cols.used == 'hide', 'space did not turn all three to hide')
  key '<Space>'
  expect(not lens_any(last().cols), 'space did not leave all three be')
  local folder = pick('src', function(it)
    return it.kind == 'folder'
  end)
  expect(folder and last().path == folder.path, 'the picker did not add a folder')
  local before = #st.lens.rules
  key 'd'
  expect(#st.lens.rules == before - 1, 'd did not delete')
  local function type_in(keys, text)
    key(keys)
    local buf = api.nvim_get_current_buf()
    expect(vim.bo[buf].buftype == 'nofile' and api.nvim_win_get_config(0).relative == 'win', keys .. ' opened no input')
    api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    key '<CR>'
  end
  key 'k'
  type_in('e', 'tests/')
  expect(last().pattern == 'tests/', 'e did not edit it: ' .. tostring(last().pattern))
  st.lens.rules = {
    { path = 'packages/', cols = L.all 'only' },
    { pattern = '**/src/**', cols = { contracts = 'only' } },
    { pattern = '*.test.*', cols = L.all 'hide' },
    { pattern = [[/\.(test|spec)\./]], cols = { built = 'hide', used = 'only' } },
  }
  seam.lens_changed()
  local back = L.load(st.root)
  expect(vim.deep_equal(back, st.lens), 'the lens did not come back from ' .. L.file(st.root) .. ': ' .. vim.inspect(back))
  local r = st.lens.rules
  key 'U'
  expect(not r[1].cols.used and not r[4].cols.used and r[4].cols.built == 'hide', 'U did not clear used by alone')
  key 'C'
  expect(not r[3].cols.contracts and r[3].cols.built == 'hide', 'C did not clear contracts alone')
  key 'B'
  expect(not lens_any(r[1].cols), 'B did not clear built from')
  r[3].cols = L.all 'hide'
  key 'X'
  expect(not lens_any(r[3].cols) and #r == 4, 'X did not clear every column, keeping the rules')
  key 'q'
  expect(not panel.is_open(), 'q did not close the panel')
  st.lens = saved
  seam.lens_changed()
end

local check_code

-- the call tree: its four windows on its own buffers, the list its rows with
-- the cursor on the row the view says, the call lit beside it, the budget
-- inside the window, the anchor on top either way and the pin saying which
local function check_calls(fresh)
  if st.screen ~= 'calls' or not st.calls then
    return fail 'not on the Calls screen'
  end
  local w, r = st.cwin, st.calls_rows
  for _, k in ipairs { 'head', 'pin', 'list', 'code' } do
    if not valid(w[k]) or api.nvim_win_get_buf(w[k]) ~= st.cbuf[k] then
      return fail('the ' .. k .. ' window is not there with its buffer')
    end
  end
  if #api.nvim_tabpage_list_wins(st.tab) ~= 4 then
    fail(('%d windows on the Calls screen, not 4'):format(#api.nvim_tabpage_list_wins(st.tab)))
  end
  if api.nvim_buf_line_count(st.cbuf.list) ~= math.max(1, #r.rows) then
    fail 'the list is not its rows'
  end
  local i = api.nvim_win_get_cursor(w.list)[1]
  local x = r.rows[i]
  if #r.rows > 0 and not x then
    return fail 'the cursor is off the rows'
  end
  if x and x.key ~= st.calls.cursor then
    fail('the cursor is on ' .. x.key:gsub('\n', ' > ') .. ', the view on ' .. tostring(st.calls.cursor):gsub('\n', ' > '))
  end
  check_code(x and i or nil)
  if fresh and r.levels > 0 and #r.rows > api.nvim_win_get_height(w.list) then
    fail(('the budget opened %d levels into %d rows, %d high'):format(r.levels, #r.rows, api.nvim_win_get_height(w.list)))
  end
  for j, y in ipairs(r.rows) do
    if y.parent and y.parent >= j then
      return fail 'a row sits above the row it hangs from'
    end
  end
  if st.calls.anchor then
    local pin = api.nvim_buf_get_lines(st.cbuf.pin, 0, -1, false)
    local want = st.calls.dir == 'up' and '↓ calls' or '↑'
    if #pin ~= 3 or pin[1]:sub(1, #want) ~= want or not pin[2]:match '^━' then
      fail('the pin is not the other way, the anchor, the titles: ' .. table.concat(pin, ' | '))
    end
    local word = st.calls.dir == 'up' and 'above' or 'below'
    if not pin[3]:match(word) then
      fail('the column is not ' .. word)
    end
  end
end

-- the code beside the tree: the view chosen, or itself when nothing calls
-- it; called at, one lit line that is a real call of a real caller, the
-- name on it underlined; itself, the call `]]` stepped to lit
check_code = function(i)
  local g, m = st.models[st.cur].graph, st.models[st.cur]
  local p = calls.pane(g, st.calls, st.calls_rows, i, m)
  if not p then
    return
  end
  local lines = api.nvim_buf_get_lines(st.cbuf.code, 0, -1, false)
  local lit, used, marks = {}, {}, api.nvim_buf_get_extmarks(st.cbuf.code, require('seam.draw').ns, 0, -1, { details = true })
  for _, mk in ipairs(marks) do
    used[mk[2]] = used[mk[2]] or mk[4].hl_group == 'SeamUse'
  end
  for _, mk in ipairs(marks) do
    if mk[4].line_hl_group == 'SeamLit' then
      lit[#lit + 1] = tonumber((lines[mk[2] + 1] or ''):match '^%s*(%d+)')
      lit.used = used[mk[2]]
    end
  end
  local text = table.concat(lines, '\n')
  local what = p.node.id .. ' (' .. p.code .. ')'
  if #p.places == 0 then
    if p.code ~= 'itself' or not text:find('nothing calls it', 1, true) then
      fail(what .. ': nothing calls it, and the code does not say so')
    end
  elseif p.code ~= st.calls.code then
    fail(what .. ': the code is not the view chosen, ' .. st.calls.code)
  end
  if p.code == 'called' then
    local u = p.places[p.n]
    local real = false
    for _, e in ipairs(g.up[p.node.id] or {}) do
      real = real or (u and e.from == u.from and e.line == u.line)
    end
    if not real or #lit ~= 1 or lit[1] ~= u.line or not lit.used then
      fail(('%s: place %d of %d lit at %s, not a call of %s'):format(what, p.n, #p.places, tostring(lit[1]), p.node.name))
    end
    if not text:find(('called at  %d of %d'):format(p.n, #p.places), 1, true) then
      fail(what .. ': the head does not say which place')
    end
  elseif p.n > 0 and (#lit ~= 1 or lit[1] ~= p.lines[p.n]) then
    fail(('%s: call %d at %d, lit %s'):format(what, p.n, p.lines[p.n], tostring(lit[1])))
  end
  return p
end

-- <Tab> swaps the code and the choice sticks across j; ]] and [[ step
-- round the places or calls, from the tree and from the code
local function swap()
  local function step(k, from_code)
    local before = calls.pane(st.models[st.cur].graph, st.calls, st.calls_rows, api.nvim_win_get_cursor(st.cwin.list)[1], st.models[st.cur])
    if from_code then
      key '<C-w>l'
    end
    key(k)
    if from_code then
      if api.nvim_get_current_win() ~= st.cwin.code then
        fail(k .. ' in the code left it')
      end
      key '<Esc>'
    elseif api.nvim_get_current_win() ~= st.cwin.list then
      fail(k .. ' in the tree took the cursor')
    end
    check_calls(false)
    local now = calls.pane(st.models[st.cur].graph, st.calls, st.calls_rows, api.nvim_win_get_cursor(st.cwin.list)[1], st.models[st.cur])
    local list = before and (before.code == 'called' and before.places or before.lines) or {}
    if before and now and #list > 1 then
      local want = (k == ']]' or k == 'n') and before.n % #list + 1 or (before.n <= 1 and #list or before.n - 1)
      if now.n ~= want then
        fail(('%s went from %d to %d of %d, not %d'):format(k, before.n, now.n, #list, want))
      end
    end
  end
  for _, code_ in ipairs { 'itself', 'called' } do
    local was = st.calls.code
    key '<Tab>'
    if st.calls.code == was or st.calls.code ~= code_ then
      fail('<Tab> did not swap to ' .. code_)
    end
    check_calls(false)
    step 'n'
    step 'n'
    step 'N'
    step(']]', true)
    step('[[', true)
    key 'j'
    if st.calls.code ~= code_ then
      fail('j did not keep ' .. code_)
    end
    check_calls(false)
    step 'N'
  end
end

local function find_row(k)
  for i, x in ipairs(st.calls_rows and st.calls_rows.rows or {}) do
    if x.key == k then
      return i, x
    end
  end
end

-- J on a row that is a contract: its page over the tree, and K back to the
-- tree as it was; on a row that is not, still the tree
local function page_and_back()
  local m = st.models[st.cur]
  local pi, none
  for i, x in ipairs(st.calls_rows.rows) do
    local c = x.id and m.byid[x.id]
    if c and c.nusers > 0 then
      pi = pi or i
    else
      none = none or i
    end
  end
  if none then
    key(none .. 'G')
    key 'J'
    if st.screen ~= 'calls' then
      fail 'J on a row with no page left the tree'
    end
  end
  if not pi then
    return
  end
  key(pi .. 'G')
  local v = st.calls
  local was = { v.anchor, v.dir, vim.deepcopy(v.open), v.cursor, #v.back }
  local top = api.nvim_win_call(st.cwin.list, function()
    return vim.fn.line 'w0'
  end)
  local want = m.byid[st.calls_rows.rows[pi].id]
  key 'J'
  local under = st.stack[#st.stack]
  if st.screen ~= 'page' or st.page.c ~= want or not (under and under.kind == 'calls') then
    return fail "J did not open the row's page over the tree"
  end
  check_page()
  key 'K'
  check_calls(false)
  local now = st.calls
  if not vim.deep_equal({ now.anchor, now.dir, now.open, now.cursor, #now.back }, was) then
    fail 'K from the page did not come back to the tree as it was'
  end
  local top2 = api.nvim_win_call(st.cwin.list, function()
    return vim.fn.line 'w0'
  end)
  if top2 ~= top then
    fail(('K came back scrolled to %d, not %d'):format(top2, top))
  end
end

-- the head and the pin give the cursor back to the tree; the code keeps it
-- until <Esc>
local function windows()
  key '<C-w>k'
  if api.nvim_get_current_win() ~= st.cwin.list then
    fail 'the pin kept the cursor'
  end
  key '<C-w>t'
  if api.nvim_get_current_win() ~= st.cwin.list then
    fail 'the head kept the cursor'
  end
  key '<C-w>l'
  if api.nvim_get_current_win() ~= st.cwin.code then
    fail 'the code did not take the cursor'
  end
  key '<Esc>'
  if api.nvim_get_current_win() ~= st.cwin.list then
    fail '<Esc> in the code did not go back to the tree'
  end
end

do
  local g = st.models[st.cur].graph
  if not g then
    fail 'the index has no call graph'
  else
    local function on_screen(c)
      require('seam.draw.explorer').list()
      st.shown = nil
      api.nvim_set_current_win(st.win.list)
      return screen.find(c.name, c.path)
    end
    local list = {}
    for _, c in ipairs(st.models[st.cur].contracts) do
      if g.nodes[c.id] and #(g.down[c.id] or {}) > 0 then
        list[#list + 1] = c
      end
    end
    local n = math.min(#list, max > 0 and max or #list)
    for ci = 1, n do
      local c = list[math.floor((ci - 1) * #list / n) + 1]
      where = 'calls ' .. c.id
      if on_screen(c) then
        key 'c'
        check_calls(true)
        for _, k in ipairs { 'j', 'l', 'l', 'h', 'h', 'L', 'H', ']', '[', 'j', 'j', 'k', 'l' } do
          where = 'calls ' .. c.id .. ' ' .. k
          key(k)
          check_calls(false)
        end
        where = 'calls ' .. c.id .. ' swap'
        swap()
        for _, k in ipairs { '<CR>', '~' } do
          where = 'calls ' .. c.id .. ' ' .. k
          key(k)
          check_calls(true)
        end
        where = 'calls ' .. c.id .. ' ~ swap'
        swap()
        for _, k in ipairs { 'k', 'l', 'k', 'L', ']', 'H', '[', 'C', 'j', 'l', 'j' } do
          where = 'calls ' .. c.id .. ' ' .. k
          key(k)
          check_calls(false)
        end
        where = 'calls ' .. c.id .. ' J'
        page_and_back()
        where = 'calls ' .. c.id .. ' windows'
        windows()
        where = 'calls ' .. c.id .. ' back'
        for j = 1, 10 do
          if st.screen ~= 'calls' then
            break
          end
          -- the first from the code beside the tree
          if j == 1 then
            key '<C-w>l'
          end
          key(j % 2 == 0 and '<BS>' or 'K')
          if st.screen == 'calls' and api.nvim_get_current_win() ~= st.cwin.list then
            fail 'K from the code did not come back to the tree'
          end
        end
        if st.screen ~= 'explorer' or st.shown ~= c then
          fail(
            ('<BS> came back to %s, not the explorer on %s'):format(st.screen == 'explorer' and (st.shown and st.shown.name or 'nothing') or st.screen, c.name)
          )
        end
        -- - from deeper: straight to the explorer, on the anchor
        where = 'calls ' .. c.id .. ' -'
        on_screen(c)
        key 'c'
        local x = st.calls_rows.rows[1]
        local xc = x and x.id and st.models[st.cur].byid[x.id]
        if xc and xc.nusers > 0 then
          key '<CR>'
          key '-'
          if st.screen ~= 'explorer' or st.shown ~= xc then
            fail('- did not go to the explorer on ' .. x.id)
          end
        else
          key '-'
          if st.screen ~= 'explorer' or st.shown ~= c then
            fail('- did not go to the explorer on ' .. c.name)
          end
        end
      end
    end
    where = 'calls from the top'
    key 'C'
    check_calls(true)
    for _, k in ipairs { 'j', 'j', 'l', 'L', 'H' } do
      key(k)
    end
    -- h folds an open folder, l opens it again
    where = 'calls from the top h'
    local di
    for i, x in ipairs(st.calls_rows.rows) do
      di = di or (x.kind == 'dir' and x.fold == 'open' and #x.kids > 0 and i) or nil
    end
    if not di then
      fail 'no open folder from the top'
    else
      local dkey, n = st.calls_rows.rows[di].key, #st.calls_rows.rows
      key(di .. 'G')
      key 'h'
      check_calls(false)
      local _, d = find_row(dkey)
      if not (d and d.fold == 'folded' and #st.calls_rows.rows < n and st.calls.cursor == dkey) then
        fail 'h on an open folder did not fold it'
      end
      key 'l'
      if #st.calls_rows.rows ~= n then
        fail 'l did not open the folder again as it was'
      end
    end
    key '<BS>'
    if st.screen ~= 'explorer' then
      fail '<BS> from the top did not come back to the explorer'
    end
    -- the repository the design was drawn on: its facts, and on screen
    local start = 'packages/core/src/run/run.ts:83:startRun'
    if g.nodes[start] then
      where = 'calls raf-run-redesign'
      local callees = {}
      for _, e in ipairs(g.down[start]) do
        callees[e.to] = true
      end
      if vim.tbl_count(callees) ~= 29 then
        fail(('startRun calls %d, not 29'):format(vim.tbl_count(callees)))
      end
      local hit = false
      for _, u in ipairs(g.up['packages/core/src/run/run.ts:75:createRun'] or {}) do
        hit = hit or (g.nodes[u.from].name == 'useOwnedRun' and u.line == 59 and g.nodes[u.from].path:match 'useRun%.ts$' ~= nil)
      end
      if not hit then
        fail 'useOwnedRun does not call createRun at useRun.ts:59'
      end
      local main = g.down['apps/demo/app/main.tsx:0:'] or {}
      if not (main[1] and g.nodes[main[1].to].name == 'App') then
        fail "main.tsx's top does not call <App>"
      end
      if on_screen(st.models[st.cur].byid[start]) then
        key 'c'
        local top = 0
        if not st.calls_rows then
          fail 'c did not open the Calls screen on startRun'
        end
        for _, x in ipairs(st.calls_rows and st.calls_rows.rows or {}) do
          top = top + (x.parent and 0 or 1)
        end
        if top ~= 29 then
          fail(('startRun shows %d rows under it, not 29'):format(top))
        end
        key '<BS>'
      end
      -- createRun under useOwnedRun: called at opens on useRun.ts:59, among
      -- the places of its 7 callers
      where = 'calls raf-run-redesign createRun'
      seam.open_calls 'packages/react/src/useRun.ts:39:useOwnedRun'
      local ci = find_row 'packages/react/src/useRun.ts:39:useOwnedRun\npackages/core/src/run/run.ts:75:createRun'
      if not ci then
        fail 'createRun is not a row under useOwnedRun'
      else
        key(ci .. 'G')
        local p = check_code(ci)
        local by = {}
        for _, u in ipairs(p and p.places or {}) do
          by[u.from] = true
        end
        local u = p and p.places[p.n]
        if not (p and p.code == 'called' and vim.tbl_count(by) == 7 and u and u.line == 59 and u.from:match 'useRun%.ts:%d+:useOwnedRun$') then
          fail(('createRun called at: %d callers, on %s, not 7 and useRun.ts:59'):format(vim.tbl_count(by), u and (u.from .. ':' .. u.line) or 'nothing'))
        end
        key 'n'
        check_code(ci)
        key '<BS>'
      end
    end
  end
end

-- every contract's page, or a spread of them
local contracts = {}
for _, c in pairs(st.models[st.cur].byid) do
  if c.nusers and c.nusers > 0 then
    contracts[#contracts + 1] = c
  end
end
table.sort(contracts, function(a, b)
  return a.id < b.id
end)
if max > 0 and #contracts > max then
  local pick, step = {}, #contracts / max
  for i = 0, max - 1 do
    pick[#pick + 1] = contracts[math.floor(i * step) + 1]
  end
  contracts = pick
end

local SEQ = { 'j', 'j', 'k', ']]', '[[', 'c', 'j', ']]', 'k', 'c', 's', 'j', ']]', 's', 'c', 's', 's', 'G', 'j', 'gg', 'v', 'j', 'v' }
-- Built from as code: the cursor moves as in any code, n and N go by names
local READ = { 'n', 'n', 'N', '3n', 'j', 'j', 'w', 'w', 'k', 'G', 'n', 'gg', 'N', '$', 'b', ']]', '[[', 'c', 's' }
for ci, c in ipairs(contracts) do
  if ci % 20 == 0 then
    io.stdout:write(('%d / %d contracts, %d keys, %d failures\n'):format(ci, #contracts, steps, #failures))
    io.stdout:flush()
  end
  for _, sides in ipairs { 'both', 'used' } do
    st.sides = sides
    where = ('%s (%s) open'):format(c.id, sides)
    local ok, err = pcall(seam.open_page, c)
    if not ok then
      fail(tostring(err))
    else
      for _ = 1, 2 do
        for _, k in ipairs(screen.reading(st.page) and READ or SEQ) do
          where = ('%s %s panes=%s %s'):format(c.id, st.page.tab, st.panes[st.page.tab], screen.reading(st.page) and 'code' or 'list')
          key(k)
          check_page()
        end
        if screen.reading(st.page) then
          -- n lands on a name, and the list then shows the same one
          local p = st.page
          if #p.refs > 0 then
            key 'n'
            local cur = api.nvim_win_get_cursor(p.win.mid)
            local r = p.refs[p.index]
            if not (r and cur[1] == r.row and cur[2] == r.s) then
              fail 'n did not land on a name'
            end
            where = c.id .. ' code to list'
            key 'v'
            check_page()
            local d = st.page.rows[api.nvim_win_get_cursor(st.page.win.list)[1]].meta.dep
            if not d or d.name ~= r.dep.name then
              fail(('v went to the list on %s, not %s'):format(d and d.name or 'nothing', r.dep.name))
            end
            for _, k in ipairs(SEQ) do
              key(k)
              check_page()
            end
            key 'v'
            check_page()
          end
        end
        -- the same keys from inside the stacked panes
        for _, w in ipairs { st.page.win.mid, st.page.win.right } do
          if valid(w) then
            api.nvim_set_current_win(w)
            where = ('%s %s from a pane'):format(c.id, st.page.tab)
            key 'c'
            check_page()
            key 'c'
            check_page()
            break
          end
        end
        if ci % 7 == 0 and st.page.tab == 'built' then
          where = c.id .. ' enter a dependency'
          local depth = #st.stack
          key(ci % 2 == 0 and 'J' or '<CR>')
          if #st.stack > depth then
            check_page()
            key(ci % 2 == 0 and 'K' or '<BS>')
            if #st.stack ~= depth then
              fail 'K or <BS> did not come back up from a dependency'
            end
          end
        end
        where = c.id .. ' tab'
        key '<Tab>'
        check_page()
      end
      if st.page.tab == 'used' then
        where = c.id .. ' J on used by'
        local depth = #st.stack
        key 'J'
        if api.nvim_get_current_tabpage() ~= st.tab or #st.stack ~= depth or st.screen ~= 'page' then
          fail 'J on used by left the page'
        end
      end
      if ci % 11 == 0 and st.page.tab == 'used' then
        where = c.id .. ' open a user file'
        key '<CR>'
        if api.nvim_get_current_tabpage() ~= st.tab then
          vim.cmd 'tabclose'
          api.nvim_set_current_tabpage(st.tab)
        else
          fail '<CR> on a user file opened nothing'
        end
        if st.page and valid(st.page.win.list) then
          api.nvim_set_current_win(st.page.win.list)
        end
      end
      if ci % 5 == 0 then
        where = c.id .. ' straight to the overview'
        if st.page.tab == 'built' then
          key '<CR>'
        end
        key '-'
        if st.screen ~= 'explorer' or st.page or #st.stack > 0 then
          fail('- left a page open from depth ' .. (#st.stack + 1))
        end
        seam.open_page(c)
      end
      where = c.id .. ' back'
      local up = ci % 2 == 0 and 'K' or '<BS>'
      key(up)
      if st.screen == 'page' then
        fail(up .. ' stayed on the page')
      end
      key 'K'
      if st.screen ~= 'explorer' then
        fail 'K in the explorer left it'
      end
    end
  end
end

io.stdout:write(('%s: %d contracts, %d keys, %d failures\n'):format(repo, #contracts, steps, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
