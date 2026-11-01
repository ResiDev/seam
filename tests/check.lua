-- Drive every screen state through its real keys and report what broke.
--   SEAM_REPO=<path> [SEAM_MAX=n] [SEAM_LENS=1] nvim --headless -c 'luafile tests/check.lua'
-- Exits 0 when nothing failed. Uses your config, so other plugins' keys and
-- treesitter queries are the ones you have.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
-- this checkout first, before a seam.nvim your config would load
vim.opt.runtimepath:prepend(root)
vim.o.columns, vim.o.lines = 180, 50
local api = vim.api
local seam = require 'seam'
assert(debug.getinfo(seam.open, 'S').source:find(root, 1, true), 'seam is not loaded from ' .. root)
local screen = require 'seam.screen'
local calls = require 'seam.calls'
local picker = require 'seam.picker'
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

-- gf took you to `path` at `line` in a tab that is not seam's; then back to
-- seam's tab, the cursor in `win`
local function went(what, path, line, win)
  local name, at = api.nvim_buf_get_name(0), api.nvim_win_get_cursor(0)[1]
  if api.nvim_get_current_tabpage() == st.tab then
    fail(what .. ': gf stayed in seam')
  elseif name:sub(-#path - 1) ~= '/' .. path or at ~= line then
    fail(('%s: gf went to %s:%d, not %s:%d'):format(what, name, at, path, line))
  end
  api.nvim_set_current_tabpage(st.tab)
  if valid(win) then
    api.nvim_set_current_win(win)
  end
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
  io.stdout:write 'could not open the tree\n'
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

-- the tree: its four windows on its own buffers, its rows with the cursor on
-- the row the outline says, none wider than the tree; each call marked where
-- it lives; the pane naming the row, its tabs, and the row's code, each call
-- in it marked the same way
local tree_screen = require 'seam.screen_tree'
local outline = require 'seam.outline'
local odraw = require 'seam.draw.outline'
local theme = require 'seam.theme'
local code = require 'seam.code'
local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end
-- the groups of the marks on each line of `buf`, 1-based
local function marks(buf)
  local by = {}
  for _, mk in ipairs(api.nvim_buf_get_extmarks(buf, require('seam.draw').ns, 0, -1, { details = true })) do
    local l = mk[2] + 1
    by[l] = by[l] or {}
    by[l][mk[4].hl_group or ''] = true
  end
  return by
end
local function under_of(m, from, to)
  if from == to then
    return nil
  end
  local pkg = require('seam.index').pkg_of(m, to)
  return pkg ~= require('seam.index').pkg_of(m, from) and theme.hue(pkg).under or 'SeamUnder'
end
local function check_tree()
  if st.screen ~= 'tree' then
    return fail('not on the tree: ' .. tostring(st.screen))
  end
  local w = st.owin
  for _, k in ipairs { 'head', 'tree', 'phead', 'pane' } do
    if not valid(w[k]) or api.nvim_win_get_buf(w[k]) ~= st.obuf[k] then
      return fail('the ' .. k .. ' window is not there with its buffer')
    end
  end
  -- a float a plugin of yours put up (a notification) is not seam's
  local wins = vim.tbl_filter(function(win)
    return api.nvim_win_get_config(win).relative == ''
  end, api.nvim_tabpage_list_wins(st.tab))
  if #wins ~= 4 then
    fail(('%d windows on the tree, not 4'):format(#wins))
  end
  local rows, m = st.orows, st.models[st.cur]
  if api.nvim_buf_line_count(st.obuf.tree) ~= math.max(1, #rows) then
    fail 'the tree is not its rows'
  end
  local x = tree_screen.at()
  if #rows > 0 and not x then
    return fail 'the cursor is off the rows'
  end
  if x and x.key ~= st.outline.cursor then
    fail('the cursor is on ' .. x.key:gsub('\n', ' > ') .. ', the outline on ' .. tostring(st.outline.cursor):gsub('\n', ' > '))
  end
  local tl, tm = lines(st.obuf.tree), marks(st.obuf.tree)
  for i, r in ipairs(rows) do
    if vim.fn.strdisplaywidth(tl[i]) > odraw.LW then
      fail(('row %d is wider than the tree: %s'):format(i, tl[i]))
      break
    end
    if r.where and r.where ~= 'here' then
      local want = r.where == 'file' and 'SeamUnder' or theme.hue(require('seam.index').pkg_of(m, m.graph.nodes[r.id].path)).under
      if not (tm[i] and tm[i][want]) or (r.where == 'pkg' and not tl[i]:find('▎', 1, true)) then
        fail(('%s, from %s, is not marked %s'):format(r.key:gsub('\n', ' > '), r.where, want))
        break
      end
    elseif r.where == 'here' and tm[i] and tm[i].SeamUnder then
      fail(r.key:gsub('\n', ' > ') .. ' is in its own file, and underlined')
      break
    end
  end
  -- the pane: the row's name and where, the tabs, the view
  local head = lines(st.obuf.phead)
  local name = odraw.name(m, x)
  if x and not (head[1] or ''):find(name, 1, true) then
    fail('the pane head does not name ' .. name .. ': ' .. (head[1] or ''))
  end
  local tabs, want = vim.trim(head[3] or ''), x and (x.kind ~= 'dir' and 'Code     Types' or 'Types') or ''
  if tabs ~= want then
    fail(('the tabs are %q, not %q'):format(tabs, want))
  end
  local body = lines(st.obuf.pane)
  local shown = require('seam.views').shown(x, st.view)
  if shown and shown.name == 'Types' then
    -- a title, a function's line, or why there are no types
    local first = body[1] or ''
    if x and not (first:match '^ %S' or first:find(' → ', 1, true)) then
      fail('the Types view does not start with a title or a line: ' .. first)
    end
  elseif x and x.kind == 'fn' then
    local node = m.graph.nodes[x.id]
    local s, e = code.doc_start(node.path, node.line), math.max(node.end_line or node.line, node.line)
    if tonumber((body[1] or ''):match '^%s*(%d+)') ~= s or #body ~= e - s + 1 then
      fail(('the code of %s is not lines %d to %d: %s, %d lines'):format(node.name, s, e, body[1] or '', #body))
    end
    local bm = marks(st.obuf.pane)
    for _, c in ipairs(m.graph.down[node.id] or {}) do
      local hl = c.line >= s and c.line <= e and under_of(m, node.path, m.graph.nodes[c.to].path)
      if hl and not (bm[c.line - s + 1] and bm[c.line - s + 1][hl]) then
        fail(('%s calls %s at %d, not marked %s in its code'):format(node.name, m.graph.nodes[c.to].name, c.line, hl))
        break
      end
    end
  elseif x and x.kind == 'file' then
    if #body ~= math.max(1, #code.file(x.path).lines) then
      fail(('the code of %s is %d lines, not the file'):format(x.path, #body))
    end
  elseif x and x.kind == 'dir' then
    fail 'a folder shows its code'
  end
  return x
end
local function cursor_on(i)
  key(i .. 'G')
end
local function row_of(key_)
  return outline.find(st.orows, key_)
end

do
  local m = st.models[st.cur]
  local g = m.graph
  where = 'tree open'
  local x = check_tree()
  if not x or #st.orows == 0 then
    fail 'the tree has no rows'
  end
  -- l and h on a closed folder: open, closed again as it was; h again its parent
  where = 'tree l h folder'
  local di
  for i, r in ipairs(st.orows) do
    di = di or (r.kind == 'dir' and r.can_open and not r.open and r.depth > 0 and i) or nil
  end
  if di then
    local n, dkey = #st.orows, st.orows[di].key
    cursor_on(di)
    key 'l'
    check_tree()
    if not (st.orows[row_of(dkey)].open and #st.orows > n) then
      fail 'l did not open the folder'
    end
    key 'h'
    check_tree()
    if st.orows[row_of(dkey)].open or #st.orows ~= n or st.outline.cursor ~= dkey then
      fail 'h did not close the folder back as it was'
    end
    key 'h'
    local p = tree_screen.at()
    if not (p and p.depth < st.orows[row_of(dkey)].depth and p.kind == 'dir') then
      fail 'h on a closed folder did not go to its parent'
    end
  end
  -- a function calling into another file, another package if one does
  local f, best = nil, -1
  local down = require('seam.calls').visible(m, 'down')
  for id, n in pairs(g and g.nodes or {}) do
    if n.kind ~= 'module' and not n.test and not require('seam.index').is_test(n.path) then
      local score = 0
      for _, k in ipairs(require('seam.calls').kids(g, id, 'down', down)) do
        local where_ = under_of(m, n.path, g.nodes[k.id].path)
        score = math.max(score, where_ == 'SeamUnder' and 1 or where_ and 2 or 0)
      end
      if score > best or (score == best and id < f.id) then
        f, best = n, score
      end
    end
  end
  if f then
    -- found where it lives; its file's functions in the file's order; l its calls in the order first written
    where = 'tree l h ' .. f.id
    if not tree_screen.reveal(f.id) then
      fail('reveal found no row for ' .. f.id)
    end
    local fx = check_tree()
    if not (fx and fx.id == f.id) then
      fail('the cursor is not on ' .. f.id)
    end
    local fkey = 'f:' .. f.path
    local fi = row_of(fkey)
    local got = {}
    for i = fi + 1, #st.orows do
      if st.orows[i].depth <= st.orows[fi].depth then
        break
      end
      if st.orows[i].depth == st.orows[fi].depth + 1 then
        got[#got + 1] = st.orows[i].id
      end
    end
    local want = vim.tbl_map(function(n)
      return n.id
    end, outline.functions(m, f.path))
    if not vim.deep_equal(got, want) then
      fail "the file's rows are not its functions in its order"
    end
    key 'l'
    check_tree()
    local kids = require('seam.calls').kids(g, f.id, 'down', down)
    local fk = fkey .. '\n' .. f.id
    local i0 = row_of(fk)
    for j, k in ipairs(kids) do
      local r = st.orows[i0 + j]
      if not r or r.key ~= fk .. '\n' .. k.id then
        fail(('call %d of %s is not %s'):format(j, f.name, k.id))
        break
      end
    end
    if #kids > 0 then
      key 'j'
      key 'h'
      if st.outline.cursor ~= fk then
        fail 'h on a call did not go up to its function'
      end
      key 'h'
      check_tree()
      if st.orows[row_of(fk)].open then
        fail 'h did not close the function'
      end
      key 'l'
    end
    -- s: most used first, most calling first, then the tree on the same row
    where = 'tree s'
    for _, order in ipairs { 'used', 'calls' } do
      key 's'
      check_tree()
      if st.outline.order ~= order then
        fail('s did not go to ' .. order)
      end
      local last
      for _, r in ipairs(st.orows) do
        if r.depth == 0 then
          if last and r[order] > last then
            fail(order .. ' is not sorted most first')
            break
          end
          last = r[order]
        end
      end
      if not vim.wo[st.owin.tree].winbar:find('used by', 1, true) then
        fail 'a sorted order has no titles'
      end
      if st.outline.cursor ~= fk then
        fail('s did not keep the cursor on ' .. f.name)
      end
    end
    key 's'
    check_tree()
    if st.outline.order ~= 'tree' or st.outline.cursor ~= fk then
      fail 's a third time did not come back to the tree on the same row'
    end
    -- two views, one display each: <Tab> Types and back, <C-Tab> nothing
    where = 'tree <Tab>'
    local before = lines(st.obuf.pane)
    key '<Tab>'
    check_tree()
    if st.view.at ~= 'Types' or vim.deep_equal(lines(st.obuf.pane), before) then
      fail '<Tab> did not show the Types view'
    end
    key '<S-Tab>'
    check_tree()
    for _, k in ipairs { '<C-Tab>', '<C-S-Tab>' } do
      key(k)
      if st.view.at ~= 'Code' or not vim.deep_equal(lines(st.obuf.pane), before) then
        fail(k .. ' changed the pane with one display')
      end
    end
    -- gf on the row: its declaration; in the code beside it: that line
    where = 'tree gf'
    key 'gf'
    went('gf on ' .. f.name, f.path, math.max(1, f.line), st.owin.tree)
    local body = lines(st.obuf.pane)
    local bl = math.min(3, #body)
    local ln = tonumber((body[bl] or ''):match '^%s*(%d+)')
    key '<C-w>l'
    key '<C-w>j'
    if api.nvim_get_current_win() ~= st.owin.pane then
      fail 'the pane did not take the cursor'
    else
      api.nvim_win_set_cursor(st.owin.pane, { bl, 6 })
      key 'gf'
      went('gf in the code', f.path, ln, st.owin.pane)
      key '<Esc>'
      if api.nvim_get_current_win() ~= st.owin.tree then
        fail '<Esc> in the pane did not go back to the tree'
      end
    end
    -- the file's row: its first line
    cursor_on(fi)
    key 'gf'
    went('gf on ' .. f.path, f.path, 1, st.owin.tree)
  end
  -- the pane scrolls from the tree, the cursor staying there
  where = 'tree scroll'
  local long
  for path in pairs(outline.files(m)) do
    if #code.file(path).lines > 200 and (not long or path < long) then
      long = path
    end
  end
  if long then
    tree_screen.reveal(long)
    check_tree()
    local function top()
      return api.nvim_win_call(st.owin.pane, function()
        return vim.fn.line 'w0'
      end)
    end
    local t0 = top()
    for _, step_ in ipairs { { '<C-e>', 1 }, { '<C-d>', 2 }, { '<C-u>', -2 }, { '<C-y>', -1 } } do
      local was = top()
      key(step_[1])
      local now = top()
      if (step_[2] > 0 and now <= was) or (step_[2] < 0 and now >= was) or api.nvim_get_current_win() ~= st.owin.tree then
        fail(('%s from the tree moved the pane from %d to %d'):format(step_[1], was, now))
      end
    end
    if top() ~= t0 then
      fail 'scrolling down and back up did not come back'
    end
  end
  -- /: every function and file, typed, <CR> shows it where it lives; <Esc> changes nothing
  where = 'tree /'
  if f then
    key('/' .. f.name .. '<C-n><C-p>')
    local ps = picker.state()
    if not (ps and ps.sel) then
      fail '/ opened no list'
    end
    key '<CR>'
    local x2 = check_tree()
    local sel = ps and ps.sel
    local want = sel and (sel:match '^file:(.*)$' and ('f:' .. sel:match '^file:(.*)$') or ('f:' .. g.nodes[sel].path .. '\n' .. sel))
    if picker.is_open() or api.nvim_get_mode().mode ~= 'n' then
      fail '<CR> did not close the picker in normal mode'
    elseif not (x2 and x2.key == want) then
      fail(('/%s<CR> is on %s, not %s'):format(f.name, x2 and x2.key or 'nothing', tostring(want)))
    end
    local was = st.outline.cursor
    key '/zzzqqq<Esc>'
    if picker.is_open() or api.nvim_get_mode().mode ~= 'n' or st.outline.cursor ~= was then
      fail '<Esc> changed the tree or left the picker'
    end
  end
  -- ?: every key, closed by ? or <Esc>
  where = 'tree ?'
  local hints = require 'seam.hints'
  key '?'
  if not hints.is_open() then
    fail '? opened no keys'
  end
  key '?'
  key '?'
  key '<Esc>'
  if hints.is_open() or api.nvim_get_current_win() ~= st.owin.tree then
    fail '? or <Esc> did not close the keys back to the tree'
  end
  -- the lens over the tree: a folder hidden from contracts leaves it, the cursor kept
  where = 'tree lens'
  if f then
    local L, saved = require 'seam.lens', st.lens
    tree_screen.reveal(f.id)
    local other, odir
    for _, r in ipairs(st.orows) do
      local d = r.kind == 'file' and r.path:match '^(.*)/[^/]+$'
      if not other and d and f.path:sub(1, #d + 1) ~= d .. '/' then
        other, odir = r.path, d
      end
    end
    if other then
      st.lens = L.new()
      table.insert(st.lens.rules, { path = odir .. '/', cols = { contracts = 'hide' } })
      seam.lens_changed()
      check_tree()
      if row_of('f:' .. other) then
        fail('the lens hides ' .. other .. ' and its row stayed')
      end
      if st.outline.cursor ~= 'f:' .. f.path .. '\n' .. f.id or (tree_screen.at() or {}).id ~= f.id then
        fail 'the lens moved the cursor'
      end
      st.lens = saved
      seam.lens_changed()
      check_tree()
    end
  end
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
-- inside the window, the head saying where it is and which way
local function check_calls(fresh)
  if st.screen ~= 'calls' or not st.calls then
    return fail 'not on the Calls screen'
  end
  local w, r = st.cwin, st.calls_rows
  for _, k in ipairs { 'head', 'list', 'code' } do
    if not valid(w[k]) or api.nvim_win_get_buf(w[k]) ~= st.cbuf[k] then
      return fail('the ' .. k .. ' window is not there with its buffer')
    end
  end
  if #api.nvim_tabpage_list_wins(st.tab) ~= 3 then
    fail(('%d windows on the Calls screen, not 3'):format(#api.nvim_tabpage_list_wins(st.tab)))
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
  -- the head: the way here ending on the anchor and where it is, then the
  -- two ways from it with their counts, the one shown lit; from the top,
  -- the way here alone. What the lens keeps out of the tree, after the tabs,
  -- or from the top on the first line; nothing when it keeps nothing out
  local head = api.nvim_buf_get_lines(st.cbuf.head, 0, -1, false)
  local m = st.models[st.cur]
  local a = st.calls.anchor and m.graph.nodes[st.calls.anchor]
  if #head ~= (a and 3 or 1) or api.nvim_win_get_height(w.head) ~= #head then
    fail('the head is not the way here and the tabs: ' .. table.concat(head, ' | '))
  end
  local HIDDEN = '    ?%+(%d+) hidden  L lens$'
  local hidden = calls.hidden(m.graph, st.calls, m)
  local first = (head[1] or ''):gsub(HIDDEN, '')
  if not first:match '^ Seams › ' then
    fail('the head does not start at Seams: ' .. first)
  end
  local ends = not a and ' › where the code starts' or ('   ' .. a.path .. (a.line > 0 and ':' .. a.line or ''))
  if first:sub(-#ends) ~= ends then
    fail('the way here does not end ' .. ends .. ': ' .. first)
  end
  local said = head[a and 3 or 1] or ''
  if tonumber(said:match(HIDDEN) or 0) ~= hidden then
    fail(('the head does not say %d hidden: %s'):format(hidden, said))
  end
  if a then
    local down = #calls.kids(m.graph, a.id, 'down', calls.visible(m, 'down'))
    local up = calls.used_by(m.graph, a.id, calls.visible(m, 'up'))
    if not said:match(('^  Calls %d   Called by %d '):format(down, up)) then
      fail(('the tabs are not Calls %d and Called by %d: %s'):format(down, up, said))
    end
    local lit = st.calls.dir == 'up' and 'Called by' or 'Calls'
    local on
    for _, mk in ipairs(api.nvim_buf_get_extmarks(st.cbuf.head, require('seam.draw').ns, { 2, 0 }, { 2, -1 }, { details = true })) do
      if mk[4].hl_group == 'SeamTab' then
        on = said:sub(mk[3] + 1, mk[4].end_col):match '^ (%D+) '
      end
    end
    if on ~= lit then
      fail(('the tab lit is %s, not %s'):format(tostring(on), lit))
    end
  end
  local word = st.calls.dir == 'up' and 'above' or 'below'
  local titles = vim.wo[w.list].winbar:gsub('%%#%w+#', '')
  if require('seam.draw.calls').typed(m) then
    if not titles:match '^%s+takes → gives$' then
      fail('the titles are not takes → gives: ' .. titles)
    end
  elseif not titles:match('^%s+' .. word .. '%s+used by%s+file%s+line$') then
    fail('the titles are not ' .. word .. ', used by, file, line: ' .. titles)
  end
  -- a shared function the budget left folded says so where local would go
  for j, y in ipairs(r.rows) do
    local line = api.nvim_buf_get_lines(st.cbuf.list, j - 1, j, false)[1] or ''
    local says = y.shared and y.fold == 'folded' and y.id and not y.id:match ':0:$' or false
    if says ~= (line:find(' shared', 1, true) ~= nil) then
      fail(('row %d says shared when it is not, or not when it is: %s'):format(j, line))
      break
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
    if p.code == 'called' or not text:find('nothing calls it', 1, true) then
      fail(what .. ': nothing calls it, and the code does not say so')
    end
  elseif st.calls.code and p.code ~= st.calls.code and vim.tbl_contains(calls.codes(p), st.calls.code) then
    fail(what .. ': the code is not the view chosen, ' .. st.calls.code)
  end
  if p.code == 'types' then
    local named = m.sigs[p.node.id] and require('seam.types').named(m.sigs[p.node.id], m.flows) or {}
    for _, n in ipairs(named) do
      if not text:find('%f[%w]' .. vim.pesc(n) .. '   ' .. m.flows[n].decls[1].kind .. ' in ') then
        fail(what .. ': no declaration of ' .. n)
      end
    end
    if #named == 0 and not (text:find('no type of the repo', 1, true) or text:find('said nothing of it', 1, true)) then
      fail(what .. ': no types, and the code does not say so')
    end
  elseif p.code == 'called' then
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
  for _ = 1, 3 do
    local before = calls.pane(st.models[st.cur].graph, st.calls, st.calls_rows, api.nvim_win_get_cursor(st.cwin.list)[1], st.models[st.cur])
    if not before then
      return
    end
    local code_ = calls.next_code(before)
    key '<Tab>'
    if st.calls.code ~= code_ then
      fail('<Tab> did not go to ' .. code_ .. ' from ' .. before.code)
    end
    check_calls(false)
    if code_ ~= 'types' then
      step 'n'
      step 'n'
      step 'N'
      step(']]', true)
      step('[[', true)
    end
    key 'j'
    if st.calls.code ~= code_ then
      fail('j did not keep ' .. code_)
    end
    check_calls(false)
    if code_ ~= 'types' then
      step 'N'
    end
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

-- L opens the lens over the tree; closing it leaves the tree as it was
local function lens_and_back()
  local v = st.calls
  local was = { v.anchor, v.dir, vim.deepcopy(v.open), v.cursor }
  key 'L'
  if not require('seam.lens_panel').is_open() then
    return fail 'L did not open the lens'
  end
  key 'q'
  if require('seam.lens_panel').is_open() or api.nvim_get_current_win() ~= st.cwin.list then
    fail 'q did not close the lens back to the tree'
  end
  check_calls(false)
  if not vim.deep_equal({ v.anchor, v.dir, v.open, v.cursor }, was) then
    fail 'the lens closed on another tree'
  end
end

-- the head gives the cursor back to the tree; the code keeps it
-- until <Esc>
local function windows()
  key '<C-w>k'
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
    -- the tree on a contract's function, the cursor on its row
    local function on_screen(c)
      screen.show(c)
      api.nvim_set_current_win(st.owin.tree)
      local x = tree_screen.at()
      return x and x.id == c.id
    end
    local function on(c)
      local x = st.screen == 'tree' and tree_screen.at()
      return x and x.id == c.id
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
        for _, k in ipairs { 'j', 'l', 'l', 'h', 'h', 'O', 'H', ']', '[', 'j', 'j', 'k', 'l' } do
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
        for _, k in ipairs { 'k', 'l', 'k', 'O', ']', 'H', '[', 'C', 'j', 'l', 'j' } do
          where = 'calls ' .. c.id .. ' ' .. k
          key(k)
          check_calls(false)
        end
        where = 'calls ' .. c.id .. ' L'
        lens_and_back()
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
        if not on(c) then
          fail(('<BS> came back to %s, not the tree on %s'):format(st.screen == 'tree' and tostring(st.outline.cursor) or st.screen, c.name))
        end
        -- - from deeper: straight to the tree, on the anchor
        where = 'calls ' .. c.id .. ' -'
        on_screen(c)
        key 'c'
        local x = st.calls_rows.rows[1]
        local xn = x and x.id and st.models[st.cur].graph.nodes[x.id]
        if xn and not xn.test and xn.kind ~= 'module' then
          key '<CR>'
          key '-'
          if not on(xn) then
            fail('- did not go to the tree on ' .. x.id)
          end
        else
          key '-'
          if not on(c) then
            fail('- did not go to the tree on ' .. c.name)
          end
        end
      end
    end
    -- / anchors on any function: typed, <C-n> to the second, <CR>; the
    -- direction kept, K back; <Esc> changes nothing and leaves no insert mode
    if #list > 0 then
      where = 'calls /'
      local m = st.models[st.cur]
      seam.open_calls(list[1].id)
      key '~'
      local q = m.graph.nodes[list[1].id].name:sub(1, 3)
      local want = picker.fuzzy(calls.callables(m.graph, m), q)
      local was = st.calls.anchor
      key('/' .. q .. '<C-n><CR>')
      local to = want[math.min(2, #want)]
      if picker.is_open() then
        fail '<CR> did not close the picker'
      elseif not to or st.calls.anchor ~= to.id or st.calls.dir ~= 'up' then
        fail(('/%s<C-n><CR> anchored on %s %s, not %s up'):format(q, tostring(st.calls.anchor), st.calls.dir, to and to.id or 'nothing'))
      end
      check_calls(true)
      key '/zzz<Esc>'
      if picker.is_open() or api.nvim_get_mode().mode ~= 'n' or api.nvim_get_current_win() ~= st.cwin.list then
        fail '<Esc> did not close the picker back to the tree in normal mode'
      elseif to and st.calls.anchor ~= to.id then
        fail '<Esc> changed the anchor'
      end
      key 'K'
      if st.calls.anchor ~= was or st.calls.dir ~= 'up' then
        fail('K after / came back to ' .. tostring(st.calls.anchor) .. ', not ' .. was)
      end
      check_calls(true)
      key '<BS>'
    end
    where = 'calls from the top'
    seam.open_calls(nil)
    check_calls(true)
    for _, k in ipairs { 'j', 'j', 'l', 'O', 'H' } do
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
    if st.screen ~= 'tree' then
      fail '<BS> from the top did not come back to the tree'
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
        -- / on the design's repo: createRun by name, K back to startRun
        key '/createRun<CR>'
        if st.calls.anchor ~= 'packages/core/src/run/run.ts:75:createRun' then
          fail('/createRun<CR> anchored on ' .. tostring(st.calls.anchor))
        end
        key 'K'
        if st.calls.anchor ~= start then
          fail('K after /createRun came back to ' .. tostring(st.calls.anchor))
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
        -- gf on the row: createRun's declaration in your own tab
        where = 'calls raf-run-redesign gf'
        key 'gf'
        went('gf on createRun', 'packages/core/src/run/run.ts', 75, st.cwin.list)
        -- gf in the code beside it: the line under the cursor, the call
        p = calls.pane(st.models[st.cur].graph, st.calls, st.calls_rows, ci, st.models[st.cur])
        u = p and p.places[p.n]
        local from = u and st.models[st.cur].graph.nodes[u.from]
        local row
        for j, l in ipairs(api.nvim_buf_get_lines(st.cbuf.code, 0, -1, false)) do
          row = row or (tonumber(l:match '^%s*(%d+)  ') == (u and u.line) and j) or nil
        end
        if not (from and row) then
          fail 'the code beside createRun does not show its call'
        else
          key '<C-w>l'
          api.nvim_win_set_cursor(st.cwin.code, { row, 0 })
          key 'gf'
          went('gf in the code', from.path, u.line, st.cwin.list)
        end
        key '<BS>'
      end
      -- a lens hiding react in used by: createRun's callers leave useOwnedRun
      -- out, no row says so, and the anchor counts what the tree lost;
      -- built from hides nothing, so its calls count nothing
      where = 'calls raf-run-redesign lens'
      local L, saved = require 'seam.lens', st.lens
      st.lens = L.new()
      table.insert(st.lens.rules, { path = 'packages/react/', cols = { used = 'hide' } })
      seam.lens_changed()
      local create = 'packages/core/src/run/run.ts:75:createRun'
      seam.open_calls(create)
      key '~'
      check_calls(true)
      for _, x in ipairs(st.calls_rows.rows) do
        if x.id and st.models[st.cur].graph.nodes[x.id].path:match '^packages/react/' then
          fail(x.key:gsub('\n', ' > ') .. ' is among the callers shown')
          break
        end
      end
      if calls.hidden(st.models[st.cur].graph, st.calls, st.models[st.cur]) < 1 then
        fail "createRun's called by does not count useOwnedRun hidden"
      end
      key '~'
      check_calls(true)
      if (api.nvim_buf_get_lines(st.cbuf.head, 2, 3, false)[1] or ''):find 'hidden' then
        fail "createRun's calls say the lens hides something"
      end
      key '<BS>'
      st.lens = saved
      seam.lens_changed()
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
  for _, tab in ipairs { false, 'used' } do
    where = ('%s (%s) open'):format(c.id, tab or 'first')
    local ok, err = pcall(seam.open_page, c, tab or nil)
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
        local path = st.page.rows[api.nvim_win_get_cursor(st.page.win.list)[1]].meta.path
        key '<CR>'
        if api.nvim_get_current_tabpage() == st.tab or not api.nvim_buf_get_name(0):find(path, 1, true) then
          fail '<CR> on a user file did not show it in your own tab'
        end
        api.nvim_set_current_tabpage(st.tab)
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
        if st.screen ~= 'tree' or st.page or #st.stack > 0 then
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
      if st.screen ~= 'tree' then
        fail 'K in the tree left it'
      end
    end
  end
end

-- / on a page: a contract by name, <CR> on its page on the same tab, K back
do
  local cs = st.models[st.cur].contracts
  local from, to
  for _, c in ipairs(cs) do
    if c.nusers > 0 and not from then
      from = c
    elseif from and c.nusers > 0 and c.name ~= from.name then
      to = to or c
    end
  end
  if from and to then
    for _, tab in ipairs { 'built', 'used' } do
      where = 'page / ' .. tab
      st.stack, st.page = {}, nil
      seam.open_page(from)
      if st.page.tab ~= tab then
        key '<Tab>'
      end
      local want = picker.fuzzy(picker.contracts(st.models[st.cur]), to.name)[1]
      key('/' .. to.name .. '<C-n><C-p>')
      local ps = picker.state()
      if not ps or ps.sel ~= want.id then
        fail(('/%s: the first listed is %s, not %s'):format(to.name, ps and tostring(ps.sel) or 'no picker', want.id))
      end
      key '<CR>'
      local landed = st.page and st.page.c
      if picker.is_open() or api.nvim_get_mode().mode ~= 'n' then
        fail '<CR> did not close the picker in normal mode'
      elseif not landed or landed.id ~= want.id or st.page.tab ~= tab or #st.stack ~= 1 then
        fail(('<CR> landed on %s %s, depth %d, not %s %s'):format(landed and landed.id or 'nothing', st.page and st.page.tab or '', #st.stack, want.id, tab))
      end
      check_page()
      key '/zzz<Esc>'
      if picker.is_open() or api.nvim_get_mode().mode ~= 'n' or st.page.c ~= landed then
        fail '<Esc> changed the page or left the picker'
      end
      key 'K'
      if not st.page or st.page.c ~= from or st.page.tab ~= tab then
        fail('K after / did not come back to ' .. from.name)
      end
    end
    key '-'
  end
end

-- the types: t on a folder in the tree lists every type the most travelled first,
-- its declaration beside it; l its flow, made by then taken by; <CR> on a
-- function the call tree on it and K back to the flow; t on a function its
-- other types; / another type; t from the call tree and from a type's
-- contract; T in the call tree its columns; K back each time
do
  local m = st.models[st.cur]
  local cdraw = require 'seam.draw.calls'
  local function lines(buf)
    return api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  -- the Types screen, on the flow of `name` (nil: the list), its rows drawn
  local function check_types(name)
    if st.screen ~= 'types' or not st.types then
      return fail 'not on the Types screen'
    end
    if st.types.flow ~= name then
      return fail(('the flow of %s, not %s'):format(tostring(st.types.flow), tostring(name)))
    end
    local w = st.twin
    for _, k in ipairs { 'head', 'list', 'code' } do
      if not valid(w[k]) or api.nvim_win_get_buf(w[k]) ~= st.tbuf[k] then
        return fail('the ' .. k .. ' window is not there with its buffer')
      end
    end
    if #api.nvim_tabpage_list_wins(st.tab) ~= 3 then
      fail(('%d windows on the Types screen, not 3'):format(#api.nvim_tabpage_list_wins(st.tab)))
    end
    local rs = st.types_rows
    if #lines(st.tbuf.list) ~= math.max(1, #rs.rows) then
      fail 'the list is not its rows'
    end
    local head = lines(st.tbuf.head)
    local x = rs.rows[api.nvim_win_get_cursor(w.list)[1]]
    local pane = table.concat(lines(st.tbuf.code), '\n')
    if not name then
      if #rs.rows ~= #m.flowlist or not head[1]:find(#m.flowlist .. ' types of the repo', 1, true) then
        fail('the list is not every type that flows: ' .. head[1])
      end
      if x and not pane:find(' ' .. x.flow.name .. '   ' .. x.flow.decls[1].kind .. ' in ', 1, true) then
        fail('the declaration beside is not ' .. x.flow.name .. "'s")
      end
      return x
    end
    local f = m.flows[name]
    if not head[1]:match('^ Types › ' .. vim.pesc(name)) then
      fail('the head is not the type: ' .. head[1])
    end
    local takers = require('seam.types').takers(f)
    if not head[2]:find(('made by %d  ·  taken by %d'):format(#f.gives, #takers), 1, true) then
      fail('the head does not count its flow: ' .. head[2])
    end
    if #rs.sections ~= 2 or #rs.rows ~= #f.gives + #takers + 3 then
      fail(('%d rows for %d made by and %d taken by'):format(#rs.rows, #f.gives, #takers))
    end
    if x and x.kind == 'fn' then
      local node = m.graph.nodes[x.id]
      if not pane:find(node.name, 1, true) then
        fail('the code beside is not ' .. node.name)
      end
      if m.sigs[x.id] and m.sigs[x.id].params and not pane:find(' gives ', 1, true) then
        fail('the code beside does not say what ' .. node.name .. ' gives')
      end
    end
    return x
  end
  if not m.flows then
    io.stdout:write 'no types.json: the types are not checked\n'
  else
    where = 'types'
    screen.show()
    key 'gg'
    key 't'
    check_types(nil)
    key 'j'
    key 'j'
    local x = check_types(nil)
    where = 'types gf'
    if x then
      local e = x.flow.decls[1]
      key 'gf'
      went('gf on ' .. x.flow.name, e.path, e.line, st.twin.list)
    end
    -- the flow of the third, and the walk from it
    where = 'types l'
    key 'l'
    local name = x and x.flow.name
    local fx = check_types(name)
    if not (fx and fx.kind == 'fn') then
      fail 'a flow does not open on its first function'
    end
    key 'j'
    check_types(name)
    where = 'types <Tab>'
    key '<Tab>'
    local tx = check_types(name)
    if not (tx and tx.kind == 'section' and tx.section == 'takes') then
      fail '<Tab> did not go to taken by'
    end
    key '<Tab>'
    tx = check_types(name)
    if not (tx and tx.kind == 'section' and tx.section == 'gives') then
      fail '<Tab> did not come round to made by'
    end
    key 'j'
    fx = check_types(name)
    where = 'types <CR>'
    if fx and fx.kind == 'fn' then
      local node = m.graph.nodes[fx.id]
      key 'gf'
      went('gf on ' .. node.name, node.path, math.max(1, node.line), st.twin.list)
      key '<CR>'
      if st.screen ~= 'calls' or not st.calls or st.calls.anchor ~= fx.id then
        fail('<CR> did not anchor the call tree on ' .. fx.id)
      else
        check_calls(true)
        key 'K'
        local back = check_types(name)
        if not (back and back.key == fx.key) then
          fail 'K from the call tree did not come back to the flow on its row'
        end
      end
      -- t: its other types, one straight to its flow, several in the float
      where = 'types t'
      local others = vim.tbl_filter(function(n)
        return n ~= name
      end, m.sigs[fx.id] and require('seam.types').named(m.sigs[fx.id], m.flows) or {})
      key 't'
      if #others == 1 then
        check_types(others[1])
        key 'K'
      elseif #others > 1 then
        local ps = picker.state()
        if not (ps and #ps.ids == #others) then
          fail(('t on %s: not a float of its %d other types'):format(fx.id, #others))
        end
        key '<Esc>'
      end
      check_types(name)
    end
    where = 'types /'
    key('/' .. m.flowlist[1].name .. '<CR>')
    check_types(m.flowlist[1].name)
    key 'K'
    check_types(name)
    key 'K'
    check_types(nil)
    key '<BS>'
    if st.screen ~= 'tree' then
      fail('K from the types did not come back to the tree: ' .. tostring(st.screen))
    end
    -- the call tree: t on a function naming one repo type, its flow; T the counts
    where = 'types calls'
    local one
    for id, sig in pairs(m.sigs) do
      if #require('seam.types').named(sig, m.flows) == 1 and m.graph.nodes[id].kind ~= 'module' and (not one or id < one) then
        one = id
      end
    end
    local up = one and m.graph.up[one] and m.graph.up[one][1]
    if up then
      seam.open_calls(up.from)
      local row
      for i, y in ipairs(st.calls_rows.rows) do
        row = row or (y.id == one and i or nil)
      end
      if row then
        api.nvim_win_set_cursor(st.cwin.list, { row, 0 })
        key 'j'
        key 'k'
        local titles = vim.wo[st.cwin.list].winbar:gsub('%%#%w+#', '')
        if not titles:match '^%s+takes → gives$' then
          fail('the titles are not takes → gives: ' .. titles)
        end
        key 't'
        check_types(require('seam.types').named(m.sigs[one], m.flows)[1])
        key 'K'
        if st.screen ~= 'calls' or st.calls.anchor ~= up.from then
          fail 'K from the flow did not come back to the call tree'
        end
        key 'T'
        check_calls(false)
        if cdraw.typed(m) then
          fail 'T did not swap to the counts'
        end
        key 'T'
        check_calls(false)
        if not cdraw.typed(m) then
          fail 'T again did not swap back to the types'
        end
      end
      key '-'
    end
    if st.screen ~= 'tree' then
      fail '- did not go to the tree'
    end
    -- t on a function's row in the tree: its flow, K back to the row
    where = 'types t tree'
    if one and not m.graph.nodes[one].test then
      screen.show(one)
      if (tree_screen.at() or {}).id == one then
        key 't'
        check_types(require('seam.types').named(m.sigs[one], m.flows)[1])
        key 'K'
        if (tree_screen.at() or {}).id ~= one then
          fail('K from the flow did not come back to the tree on ' .. one)
        end
      end
    end
  end
end

-- from your own code: a file of the repo in a tab of its own, the cursor on
-- a contract's name, here() puts the tree's cursor on it, the page on its
-- page; on a local function, calls anchors on it and called by goes up; gf
-- comes back to the file
do
  local m = st.models[st.cur]
  local function name_col(path, line, name)
    local l = vim.fn.readfile(st.root .. '/' .. path, '', line)[line] or ''
    local at = l:find('%f[%w_$]' .. vim.pesc(name) .. '%f[^%w_$]')
    return at and at - 1
  end
  -- on the name in its file, in a tab that is not seam's
  local function on(path, line, col)
    vim.cmd 'tabnew'
    vim.cmd.edit(vim.fn.fnameescape(st.root .. '/' .. path))
    api.nvim_win_set_cursor(0, { line, col })
    return api.nvim_get_current_tabpage()
  end
  local c
  for _, x in ipairs(m.contracts) do
    if x.kind == 'function' and m.graph and m.graph.nodes[x.id] and name_col(x.path, x.line, x.name) then
      c = x
      break
    end
  end
  if c then
    where = 'here overview ' .. c.id
    local from = on(c.path, c.line, name_col(c.path, c.line, c.name))
    local tab = st.tab
    seam.here()
    local x = tree_screen.at()
    if st.tab ~= tab then
      fail 'here opened another tab, not the one seam had'
    elseif api.nvim_get_current_tabpage() ~= st.tab or st.screen ~= 'tree' then
      fail 'here did not show the tree'
    elseif not x or x.id ~= c.id then
      fail(('the cursor is on %s, not %s'):format(x and x.key or 'nothing', c.id))
    end
    if st.from_tab ~= from then
      fail 'gf would not go back to the file here came from'
    end
    key 'gf'
    went('gf after here', c.path, c.line, st.owin.tree)
    where = 'here page ' .. c.id
    api.nvim_set_current_tabpage(from)
    seam.here 'page'
    if not (st.page and st.page.c == c and api.nvim_get_current_tabpage() == st.tab) then
      fail 'here page did not open its page'
    end
    check_page()
    key 'K'
    if st.screen ~= 'tree' or (tree_screen.at() or {}).id ~= c.id then
      fail 'K from the page here opened did not come back to it in the tree'
    end
    api.nvim_set_current_tabpage(from)
    vim.cmd 'tabclose'
    api.nvim_set_current_tabpage(st.tab)
  end
  -- a local function: calls of it, then called by
  local f
  for _, n in pairs(m.graph and m.graph.nodes or {}) do
    if n.kind == 'function' and not n.exported and not n.test and name_col(n.path, n.line, n.name) then
      if not f or n.id < f.id then
        f = n
      end
    end
  end
  if f then
    for _, how in ipairs { 'calls', 'called_by' } do
      where = 'here ' .. how .. ' ' .. f.id
      local from = on(f.path, f.line, name_col(f.path, f.line, f.name))
      seam.here(how)
      if api.nvim_get_current_tabpage() ~= st.tab or st.screen ~= 'calls' or not st.calls then
        fail(how .. ' did not open the call tree')
      elseif st.calls.anchor ~= f.id or st.calls.dir ~= (how == 'calls' and 'down' or 'up') then
        fail(('anchored on %s %s'):format(tostring(st.calls.anchor), st.calls.dir))
      else
        check_calls(true)
      end
      api.nvim_set_current_tabpage(from)
      vim.cmd 'tabclose'
      api.nvim_set_current_tabpage(st.tab)
    end
    key '<BS>'
  end
  -- a type's name: its flow
  local ty = m.flowlist and m.flowlist[1] and m.flowlist[1].decls[1]
  if ty and name_col(ty.path, ty.line, ty.name) then
    where = 'here types ' .. ty.id
    local from = on(ty.path, ty.line, name_col(ty.path, ty.line, ty.name))
    seam.here 'types'
    if api.nvim_get_current_tabpage() ~= st.tab or st.screen ~= 'types' or not st.types or st.types.flow ~= ty.name then
      fail('here types did not open the flow of ' .. ty.name)
    end
    api.nvim_set_current_tabpage(from)
    vim.cmd 'tabclose'
    api.nvim_set_current_tabpage(st.tab)
    key '-'
  end
  -- a word naming nothing: the tree, its search holding the word
  where = 'here nothing'
  local from = on(c and c.path or f.path, 1, 0)
  api.nvim_buf_set_lines(0, 0, 0, false, { 'zzqqxx' })
  api.nvim_win_set_cursor(0, { 1, 0 })
  seam.here()
  local ps = picker.state()
  if not (ps and ps.query == 'zzqqxx' and st.screen == 'tree') then
    fail('the search does not hold the word: ' .. vim.inspect(ps, { newline = ' ', indent = '' }) .. ' ' .. tostring(st.screen))
  end
  key '<Esc>'
  if picker.is_open() then
    fail '<Esc> left the search open'
  end
  if api.nvim_tabpage_is_valid(from) then
    api.nvim_set_current_tabpage(from)
    vim.cmd 'bwipeout!'
    if api.nvim_get_current_tabpage() == from and #api.nvim_list_tabpages() > 1 then
      vim.cmd 'tabclose'
    end
  else
    fail 'the tab here was asked from is gone'
  end
  api.nvim_set_current_tabpage(st.tab)
end

io.stdout:write(('%s: %d contracts, %d keys, %d failures\n'):format(repo, #contracts, steps, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
