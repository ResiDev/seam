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
-- the pane drawn on each move, not once the cursor rests, so each key's pane is there to check
require('seam.pane').DELAY = 0
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
  -- beside the tree every view the row has is a tab, in their order; on the
  -- code screen two tabs, a view aside named after them when shown
  local V = require 'seam.views'
  local shown, display = V.shown(x, st.view)
  local tabs_of = vim.tbl_map(function(v)
    return v.name
  end, V.tabs(x))
  local want_tabs = x and x.kind == 'gone' and 'Code' or x and ((x.kind ~= 'dir' and 'Code     ' or '') .. 'Types') or ''
  if x and x.kind == 'dir' and table.concat(tabs_of, ' ') == 'Code Types' then
    want_tabs = 'Code     Types'
  end
  if st.screen ~= 'code' then
    local all = vim.tbl_map(function(v)
      return v.name
    end, V.of(x))
    local order, last = { Code = 1, Types = 2, Map = 3 }, 0
    for _, n in ipairs(all) do
      if not order[n] or order[n] < last then
        fail('beside the tree the tabs are out of order: ' .. table.concat(all, ', '))
        break
      end
      last = order[n]
    end
    if x and x.kind ~= 'gone' and #all < 2 then
      fail('beside the tree the row has only the tabs ' .. table.concat(all, ', '))
    end
    want_tabs = table.concat(all, '     ')
  end
  if table.concat(tabs_of, '     ') ~= want_tabs then
    fail(('the row has the tabs %q, not %q'):format(table.concat(tabs_of, '     '), want_tabs))
  end
  local want = want_tabs
  if shown and not V.is_tab(shown) then
    want = want .. '        ' .. shown.name
  end
  local ds = shown and V.displays(shown, x) or {}
  if shown and shown.list then
    want = want .. '    ' .. table.concat(ds, ' · ')
  elseif #ds > 1 then
    want = want .. '    ' .. display
  end
  local tabs = vim.trim(head[3] or '')
  if tabs ~= want then
    fail(('the tabs are %q, not %q'):format(tabs, want))
  end
  local body = lines(st.obuf.pane)
  if not shown or shown.name ~= 'Types' and shown.name ~= 'Code' then
    return
  elseif shown.name == 'Types' then
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
  local down = require('seam.graph').visible(m, 'down')
  for id, n in pairs(g and g.nodes or {}) do
    if n.kind ~= 'module' and not n.test and not require('seam.index').is_test(n.path) then
      local score = 0
      for _, k in ipairs(require('seam.graph').kids(g, id, 'down', down)) do
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
    local kids = require('seam.graph').kids(g, f.id, 'down', down)
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
    -- s: the tree, each level most used first, then most calling first,
    -- every row with both counts; then the tree on the same row
    where = 'tree s'
    local tree_n = #st.orows
    for _, order in ipairs { 'used', 'calls' } do
      key 's'
      check_tree()
      if st.outline.order ~= order then
        fail('s did not go to ' .. order)
      end
      if #st.orows ~= tree_n then
        fail(('%s has %d rows, the tree %d'):format(order, #st.orows, tree_n))
      end
      -- the last count at each depth, under the same parent
      local last = {}
      for _, r in ipairs(st.orows) do
        if r.kind ~= 'gone' then
          if not (r.used and r.calls) then
            fail(order .. ': ' .. r.key:gsub('\n', ' ') .. ' has no counts')
            break
          end
          for d in pairs(last) do
            if d > r.depth then
              last[d] = nil
            end
          end
          if last[r.depth] and r[order] > last[r.depth] then
            fail(order .. ' is not sorted most first at ' .. r.key:gsub('\n', ' '))
            break
          end
          last[r.depth] = r[order]
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
    -- two views, one display each: <Tab> Types and round, <S-Tab> nothing
    where = 'tree <Tab>'
    local before = lines(st.obuf.pane)
    key '<Tab>'
    check_tree()
    if st.view.at ~= 'Types' or vim.deep_equal(lines(st.obuf.pane), before) then
      fail '<Tab> did not show the Types view'
    end
    local V = require 'seam.views'
    for _ = 2, #V.tabs(tree_screen.subject()) do
      key '<Tab>'
    end
    check_tree()
    key '<S-Tab>'
    if st.view.at ~= 'Code' or not vim.deep_equal(lines(st.obuf.pane), before) then
      fail '<S-Tab> changed the pane with one display'
    end
    -- beside the tree every view is a tab: <Tab> through them all comes round
    -- to Code
    where = 'tree <Tab> round'
    local n = #V.tabs(tree_screen.subject())
    for _ = 1, n do
      key '<Tab>'
    end
    if st.view.at ~= 'Code' or not vim.deep_equal(lines(st.obuf.pane), before) then
      fail(('%d <Tab> did not come round to Code: %s'):format(n, st.view.at))
    end
    -- gm: straight to the Map, lit, and the same key back to Code; a tab
    -- here, so the status line leaves them to ?
    for _, a in ipairs { { 'gm', 'Map' } } do
      where = 'tree ' .. a[1]
      local has = V.has(tree_screen.subject(), a[2]) ~= nil
      if vim.tbl_contains(require('seam.pane').view_hints(tree_screen.subject()), a[1]) then
        fail(a[1] .. ' is hinted beside the tree, where it is a tab')
      end
      if has then
        key(a[1])
        check_tree()
        if (V.shown(tree_screen.subject(), st.view) or {}).name ~= a[2] or not (lines(st.obuf.phead)[3] or ''):find(a[2], 1, true) then
          fail(a[1] .. ' did not show ' .. a[2] .. ': ' .. (lines(st.obuf.phead)[3] or ''))
        end
        key(a[1])
        check_tree()
        if st.view.aside or not vim.deep_equal(lines(st.obuf.pane), before) then
          fail(a[1] .. ' again on ' .. a[2] .. ' did not come back to Code')
        end
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
    for _, step_ in ipairs { { '<C-e>', 1 }, { '<C-d>', 2 }, { '<C-u>', -2 }, { '<C-y>', -1 }, { '<M-j>', 2 }, { '<M-k>', -2 } } do
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

-- the code screen: J on a function's row puts its code on the left, each
-- line its number and the source as written, each value's type after its
-- name as the code's types say, the head the trail; the name under the
-- cursor answers in the pane, a value's later uses lit; n N go from import
-- to import; J on a call goes on to it, K back to the very name, 3K three
-- back, K from the first the tree on its row; gs its types and back;
-- gf the line under the cursor in your own code
local screen_code = require 'seam.screen_code'
local codetypes = require 'seam.codetypes'
local names = require 'seam.names'
local ns_uses = api.nvim_get_namespaces()['seam.uses']

-- the place on top of the trail
local function top()
  return st.code and st.code.trail[#st.code.trail]
end

local function check_code()
  if st.screen ~= 'code' or not screen_code.valid() then
    return fail('not on the code screen: ' .. tostring(st.screen))
  end
  local m, e, w = st.models[st.cur], top(), st.cwin
  for k, b in pairs { head = st.obuf.head, chead = st.cbuf.chead, code = st.cbuf.code, phead = st.obuf.phead, pane = st.obuf.pane } do
    if api.nvim_win_get_buf(w[k]) ~= b then
      fail(k .. ' does not show its buffer')
    end
  end
  local want = ' Seams'
  for _, x in ipairs(st.code.trail) do
    want = want .. ' › ' .. (x.id and require('seam.draw').shape(m.graph.nodes[x.id]) or x.path:match '[^/]+$')
  end
  if lines(st.obuf.head)[1] ~= want then
    fail(('the head says %q, not %q'):format(lines(st.obuf.head)[1], want))
  end
  local cw = api.nvim_win_get_width(w.code)
  if cw < screen_code.MIN or cw > screen_code.W then
    fail('the code is ' .. cw .. ' wide')
  end
  if st.code.display ~= 'code' then
    return
  end
  local src = code.file(e.path).lines
  local first, last
  for i, l in ipairs(lines(st.cbuf.code)) do
    local n, rest = l:match '^%s*(%d+)  (.*)$'
    n = tonumber(n)
    if not n or (rest ~= (src[n] or '') and l:match '^%s*%d+%s*$' == nil) then
      fail(('code row %d is not a numbered line of %s: %s'):format(i, e.path, l))
      break
    end
    first, last = first or n, n
  end
  -- the types after the names: those the code's types say, where they say
  local got, hints = {}, {}
  for _, mk in ipairs(api.nvim_buf_get_extmarks(st.cbuf.code, require('seam.draw').ns, 0, -1, { details = true })) do
    if mk[4].virt_text then
      got[#got + 1] = (first + mk[2]) .. ':' .. mk[4].virt_text[1][1]
    end
  end
  for _, h in ipairs(codetypes.hints(m, e.path, first or 1, last or 0)) do
    hints[#hints + 1] = h.line .. ':' .. h.text
  end
  table.sort(got)
  table.sort(hints)
  if not vim.deep_equal(got, hints) then
    fail(('the types after the names are %d, the code has %d'):format(#got, #hints))
  end
end

-- the cursor on the name at line `l` (the source's), byte `c` of it
local function cursor_at(l, c)
  local row = l - st.code.s + 1
  local start = require('seam.draw').meta(st.cbuf.code, row).start or 0
  api.nvim_win_set_cursor(st.cwin.code, { row, start + c })
  api.nvim_exec_autocmds('CursorMoved', { buffer = st.cbuf.code })
end

-- what the pane shows for the name under the cursor, against seam.names
local function check_answer()
  local e, n = top(), st.code.n
  local x = screen_code.subject()
  local ph = lines(st.obuf.phead)[1] or ''
  if not n then
    if x.kind ~= e.kind or (x.id or x.path) ~= (e.id or e.path) then
      fail 'off a name the pane does not show the function'
    end
    return
  end
  if n.kind == 'call' and not (x.kind == 'fn' and x.id == n.id) then
    fail('on the call ' .. n.name .. ' the pane does not show its function')
  elseif n.kind == 'type' and not (x.kind == 'type' and x.name == n.decl.name) then
    fail('on the type ' .. n.name .. ' the pane does not show it')
  elseif n.kind == 'file' and not (x.kind == 'file' and x.path == n.path) then
    fail('on ' .. n.name .. ' the pane does not show its file')
  elseif (n.kind == 'value' or n.kind == 'param' or n.kind == 'field' or n.kind == 'method') and not ph:find(n.name, 1, true) then
    fail(('on the %s %s the pane says %q'):format(n.kind, n.name, ph))
  end
  -- its later uses lit, each name and its line
  local lit = 0
  for _, mk in ipairs(api.nvim_buf_get_extmarks(st.cbuf.code, ns_uses, 0, -1, { details = true })) do
    lit = lit + (mk[4].hl_group == 'SeamUseName' and 1 or 0)
  end
  -- those on the screen: the uses run on past the function
  local last = st.code.s + api.nvim_buf_line_count(st.cbuf.code) - 1
  local want = 0
  for _, u in ipairs(n.uses or {}) do
    want = want + (u.line >= st.code.s and u.line <= last and 1 or 0)
  end
  want = (n.uses and #n.uses > 0) and want + 1 or 0
  if lit ~= want then
    fail(('%s: %d names lit, not its %d uses on the screen and itself'):format(n.name, lit, want))
  end
end

-- the tree on a contract's function, the cursor on its row
local function on_tree(c)
  screen.show(c)
  api.nvim_set_current_win(st.owin.tree)
  local x = tree_screen.at()
  return x and x.id == c.id
end

do
  local m = st.models[st.cur]
  local g = m.graph
  local list = {}
  for _, c in ipairs(m.contracts) do
    if g and g.nodes[c.id] and #(g.down[c.id] or {}) > 0 then
      list[#list + 1] = c
    end
  end
  local n = math.min(#list, max > 0 and max or #list)
  local kinds = {}
  for ci = 1, n do
    local c = list[math.floor((ci - 1) * #list / n) + 1]
    where = 'code ' .. c.id
    if on_tree(c) then
      local row = st.outline.cursor
      key 'J'
      check_code()
      if not (top() and top().id == c.id) then
        fail 'J did not put the function on the code screen'
      end
      -- every name on its first lines, each kind answering
      local root, s = names.tree(c.path), st.code.s
      local src = code.file(c.path).lines
      for l = s, math.min(s + 40, c.end_line or s) do
        for at in (src[l] or ''):gmatch '()[%a_$][%w_$]*' do
          local a = names.at(m, c.path, l, at - 1)
          if a and a.col == at - 1 then
            kinds[a.kind] = true
            where = ('code %s %d:%d %s'):format(c.id, l, at - 1, a.name)
            cursor_at(l, at - 1)
            check_answer()
          end
        end
      end
      where = 'code ' .. c.id .. ' n N'
      local stops = {}
      for i, l in ipairs(lines(st.cbuf.code)) do
        for _, sc in ipairs(require('seam.draw').meta(st.cbuf.code, i).stops or {}) do
          stops[#stops + 1] = { i, sc }
        end
        local _ = l
      end
      if #stops > 0 then
        api.nvim_win_set_cursor(st.cwin.code, { 1, 0 })
        key 'n'
        if not vim.deep_equal(api.nvim_win_get_cursor(st.cwin.code), stops[1]) then
          fail 'n did not go to the first import'
        end
        key 'N'
        if not vim.deep_equal(api.nvim_win_get_cursor(st.cwin.code), stops[#stops]) then
          fail 'N from the first did not go round to the last'
        end
      end
      -- J on calls, the trail growing; K back to the very name; 3K the tree
      where = 'code ' .. c.id .. ' J K'
      local depth = 1
      for _ = 1, 3 do
        local call
        for i = 1, api.nvim_buf_line_count(st.cbuf.code) do
          local meta = require('seam.draw').meta(st.cbuf.code, i)
          for _, sc in ipairs(meta.stops or {}) do
            local a = not call and meta.lnum and names.at(m, top().path, meta.lnum, sc - meta.start)
            if a and a.kind == 'call' and not a.declares then
              call = { i, sc, a.id }
            end
          end
        end
        if not call then
          break
        end
        api.nvim_win_set_cursor(st.cwin.code, { call[1], call[2] })
        api.nvim_exec_autocmds('CursorMoved', { buffer = st.cbuf.code })
        key 'J'
        depth = depth + 1
        check_code()
        if #st.code.trail ~= depth or top().id ~= call[3] then
          fail('J on a call did not go to ' .. call[3])
        end
        key 'K'
        if not vim.deep_equal(api.nvim_win_get_cursor(st.cwin.code), { call[1], call[2] }) then
          fail 'K did not come back to the very name'
        end
        key 'J'
      end
      if depth > 1 then
        key(depth .. 'K')
      else
        key 'K'
      end
      if st.screen ~= 'tree' or st.outline.cursor ~= row then
        fail(('%dK did not come back to the tree on its row: %s'):format(depth, tostring(st.screen)))
      end
      -- the types display and back
      where = 'code ' .. c.id .. ' gs'
      key 'J'
      key 'gs'
      local tl = lines(st.cbuf.code)
      if st.code.display ~= 'types' or not (tl[1] or ''):find(c.name, 1, true) or not (tl[1] or ''):match(c.line .. '%s*$') then
        fail('the types display does not start with the function: ' .. (tl[1] or ''))
      end
      for i, l in ipairs(tl) do
        if l ~= '' and not l:match '%d+%s*$' and not require('seam.draw').meta(st.cbuf.code, i).tv then
          fail('types row ' .. i .. ' has no line: ' .. l)
          break
        end
      end
      key 'gs'
      check_code()
      if st.code.display ~= 'code' then
        fail 'gs on the types did not come back to the code'
      end
      -- L opens the lens over the code; q closes it, back in the code
      key 'L'
      if not require('seam.lens_panel').is_open() then
        fail 'L on the code screen did not open the lens'
      end
      key 'q'
      if require('seam.lens_panel').is_open() or st.screen ~= 'code' or api.nvim_get_current_win() ~= st.cwin.code then
        fail 'q on the lens did not come back to the code'
      end
      -- <Tab> in the code flips the pane's tabs, or from a view aside back
      local V = require 'seam.views'
      local was, can = (V.shown(screen_code.subject(), st.view) or {}).name, V.can_step(screen_code.subject(), st.view)
      key '<Tab>'
      if can and (V.shown(screen_code.subject(), st.view) or {}).name == was then
        fail '<Tab> in the code did not step the pane'
      end
      -- gf on a line of the code
      where = 'code ' .. c.id .. ' gf'
      api.nvim_win_set_cursor(st.cwin.code, { 1, 0 })
      local meta = require('seam.draw').meta(st.cbuf.code, 1)
      key 'gf'
      went('gf in the code', c.path, meta.lnum, st.cwin.code)
      key 'K'
    end
  end
  for _, k in ipairs { 'call', 'value', 'param' } do
    if n > 0 and not kinds[k] then
      fail('no name answered as a ' .. k)
    end
  end
  -- the repository the design was drawn on: createRun's queue, its field, its method
  local cr = 'packages/core/src/run/run.ts:33:createRun'
  if g and g.nodes[cr] then
    where = 'code raf createRun'
    require('seam.screen_code').open { kind = 'fn', id = cr }
    local function on(on_line, word, want)
      local l
      for i = 33, 120 do
        if (code.file('packages/core/src/run/run.ts').lines[i] or ''):find(on_line, 1, true) then
          l = i
          break
        end
      end
      local s = code.file('packages/core/src/run/run.ts').lines[l]
      cursor_at(l, s:find(word, s:find(on_line, 1, true), true) - 1)
      local ph = lines(st.obuf.phead)[1] or ''
      if not ph:find(want, 1, true) then
        fail(('on %s the pane says %q, not %q'):format(word, ph, want))
      end
      check_answer()
    end
    on('const queue', 'queue', 'queue   made by createQueue, line 37')
    on('const adapter', 'storage', 'options.storage   field of RunOptions')
    on('queue.fail', 'fail', 'queue.fail   member of Queue')
    on('export function createRun', 'options', 'options   parameter of createRun, line 33')
    key 'K'
  end
end

-- The Map in the pane, on every contract's row or a spread of them: gm,
-- every display through <S-Tab> and round, the head naming
-- it, no row wider than the pane; in the pane the foot telling the name
-- under the cursor, the line that calls it as that line reads; <Esc> back
local views = require 'seam.views'
local foot = require 'seam.map.foot'
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

-- the Map shown in the pane, named with its display in the head, no row
-- cut, the pane unwrapped; the names on it that stand for a call, row and span
local function check_map()
  local x = tree_screen.subject()
  local v, display = views.shown(x, st.view)
  if not v or v.name ~= 'Map' then
    fail(('the pane shows %s, not the Map'):format(v and v.name or 'nothing'))
    return {}
  end
  local tabs = api.nvim_buf_get_lines(st.obuf.phead, 2, 3, false)[1] or ''
  if not tabs:find('Map', 1, true) or not tabs:find(display, 1, true) then
    fail(('the tabs %q do not name the Map %s'):format(tabs, display))
  end
  if vim.wo[st.owin.pane].wrap then
    fail 'the pane wraps the Map'
  end
  local hits = {}
  for i, l in ipairs(lines(st.obuf.pane)) do
    if l:match '…$' then
      fail(('row %d is cut: %s'):format(i, l))
      break
    end
    for _, h in ipairs(require('seam.draw').meta(st.obuf.pane, i).hits or {}) do
      if h.item.at then
        hits[#hits + 1] = { row = i, col = h.s, at = h.item.at }
      end
    end
  end
  return hits
end

for ci, c in ipairs(contracts) do
  if ci % 20 == 0 then
    io.stdout:write(('%d / %d contracts, %d keys, %d failures\n'):format(ci, #contracts, steps, #failures))
    io.stdout:flush()
  end
  where = c.id .. ' show'
  screen.show(c)
  api.nvim_set_current_win(st.owin.tree)
  if views.has(tree_screen.subject(), 'Map') or (views.shown(tree_screen.subject(), st.view) or {}).name == 'Map' then
    if (views.shown(tree_screen.subject(), st.view) or {}).name ~= 'Map' then
      key 'gm'
    end
    local v = views.shown(tree_screen.subject(), st.view)
    local ds = views.displays(v, tree_screen.subject())
    for di = 1, #ds do
      where = ('%s Map %s'):format(c.id, select(2, views.shown(tree_screen.subject(), st.view)))
      local hits = check_map()
      local h = hits[(ci + di) % math.max(#hits, 1) + 1]
      if h then
        api.nvim_set_current_win(st.owin.pane)
        api.nvim_win_set_cursor(st.owin.pane, { h.row, h.col })
        foot.update()
        local fb = foot.shown()
        if not fb then
          fail(('no foot on the name at row %d'):format(h.row))
        else
          local fl = table.concat(lines(fb), '\n')
          local src = vim.trim(code.file(h.at.path).lines[h.at.line] or '')
          if not fl:find(src:sub(1, 12), 1, true) then
            fail(('the foot does not show %s:%d, %q: %s'):format(h.at.path, h.at.line, src:sub(1, 30), fl))
          end
        end
        key '<Esc>'
        if api.nvim_get_current_win() ~= st.owin.tree then
          fail '<Esc> in the pane did not give the cursor back to the tree'
        elseif foot.shown() then
          fail 'the foot stayed with the cursor back in the tree'
        end
      end
      key '<S-Tab>'
      if di == #ds and select(2, views.shown(tree_screen.subject(), st.view)) ~= ds[1] then
        fail '<S-Tab> on the last display did not come round to the first'
      end
    end
  end
end

-- the Types view: <Tab> on a function's row, its line and its types written
-- out under it; + on a type named in one opens it under its line, hinted
-- where it acts, - closes the one the cursor is in, the cursor back on the
-- line naming it; + on the function's line opens it as written; a folder,
-- what is used outside it; / a type, its Types view in the pane until the
-- tree's cursor moves; T in the call tree its columns
do
  local m = st.models[st.cur]
  local tv = require 'seam.typesview'
  local draw = require 'seam.draw'
  -- the rows of the pane with their Types view meta
  local function tv_rows()
    local out = {}
    for i = 1, api.nvim_buf_line_count(st.obuf.pane) do
      out[i] = draw.meta(st.obuf.pane, i).tv or {}
    end
    return out
  end
  local function hinted(k)
    return screen.status():find('%%#SeamStatusKey#' .. vim.pesc(k) .. '%%#SeamStatusKeyWord#') ~= nil
  end
  -- a repo type whose declaration names another
  local function names_another(f)
    local e = f.decls[1]
    local ls = vim.fn.readfile(st.root .. '/' .. e.path)
    local inside = false
    for l = e.line + 1, math.min(e.end_line or e.line, #ls) do
      local src
      src, inside = tv.code_part(ls[l], inside)
      for _, n in
        ipairs(tv.names(src, function(x)
          return x ~= f.name and m.flows[x] ~= nil
        end))
      do
        return n.name
      end
    end
  end
  if not m.sigs then
    io.stdout:write 'no types.json: the Types view is not checked\n'
  else
    -- a function of the tree taking a type that names another, the first by id
    local fx, ty, inner
    for id, sig in pairs(m.sigs) do
      local node = m.graph.nodes[id]
      if node.kind ~= 'module' and node.kind ~= 'class' and not node.test and not require('seam.index').is_test(node.path) and (not fx or id < fx) then
        for _, p in ipairs(sig.params or {}) do
          local n = m.flows[p.type]
          local other = n and names_another(n)
          if other then
            fx, ty, inner = id, p.type, other
          end
        end
      end
    end
    if not fx then
      io.stdout:write 'no function takes a type naming another: + is not checked\n'
    else
      where = 'types view ' .. fx
      screen.show(fx)
      if (tree_screen.at() or {}).id ~= fx then
        fail('the tree is not on ' .. fx)
      end
      for _ = 1, 4 do
        if (views.shown(tree_screen.subject(), st.view) or {}).name == 'Types' then
          break
        end
        key '<Tab>'
      end
      check_tree()
      local node = m.graph.nodes[fx]
      local body = lines(st.obuf.pane)
      if st.view.at ~= 'Types' or not (body[1] or ''):find(' → ' .. node.name, 1, true) then
        fail('the Types view of ' .. node.name .. ' does not start with its line: ' .. (body[1] or ''))
      end
      local key_ = 'f:' .. fx
      local tkey = tv.child(key_, 'l', ty)
      local head
      for i, l in ipairs(body) do
        head = head or (l:match('^ takes ' .. vim.pesc(ty) .. '   ') or l:match('^ takes and gives ' .. vim.pesc(ty) .. '   ')) and i
      end
      if not head then
        fail(ty .. ', what ' .. node.name .. ' takes, is not written out under its line')
      end
      key '<C-w>l'
      key '<C-w>j'
      if api.nvim_get_current_win() ~= st.owin.pane then
        fail 'the pane did not take the cursor'
      end
      -- + on the type named inside it: under that line, a bar and its file and line
      where = 'types view +'
      local at
      for i, t in ipairs(tv_rows()) do
        for _, n in ipairs(t.names or {}) do
          if not at and t.key == tkey and n.name == inner then
            at = { i, n.s, t }
          end
        end
      end
      if not at then
        fail(inner .. ' is not a name to open in ' .. ty)
      else
        api.nvim_win_set_cursor(st.owin.pane, { at[1], at[2] })
        if not hinted '+' then
          fail '+ is not hinted on a closed type'
        end
        key '+'
        local ikey = tv.child(tkey, at[3].id, inner)
        local opened = lines(st.obuf.pane)[at[1] + 1] or ''
        if not st.pctx.open[ikey] or not opened:find('│ ' .. inner .. '   ', 1, true) then
          fail(('+ did not open %s under its line: %s'):format(inner, opened))
        end
        if hinted '+' or not hinted '-' then
          fail 'on an opened type, + is hinted or - is not'
        end
        -- - inside the type it sits in: that one closes, the cursor on the line naming it
        where = 'types view -'
        key '-'
        local t = draw.meta(st.obuf.pane, api.nvim_win_get_cursor(st.owin.pane)[1]).tv or {}
        if st.pctx.open[tkey] ~= false or st.pctx.open[ikey] ~= nil then
          fail('- did not close ' .. ty .. ' and what it held')
        elseif t.id ~= 'l' then
          fail('- did not put the cursor on the line naming ' .. ty)
        end
        key '+'
        if not tv.is_open(st.pctx.open, st.pctx.defaults, tkey) then
          fail('+ on the line did not open ' .. ty .. ' again')
        end
      end
      -- + on the function's line, off a name: it as written
      where = 'types view + line'
      api.nvim_win_set_cursor(st.owin.pane, { 1, 0 })
      key '+'
      if not st.pctx.open[key_ .. '|w'] or not (lines(st.obuf.pane)[1] or ''):match '^ [({]' then
        fail(node.name .. "'s line did not open as written")
      end
      key '-'
      if st.pctx.open[key_ .. '|w'] ~= false then
        fail(node.name .. "'s line did not close")
      end
      -- kept for the row as the cursor goes elsewhere and back
      key '<Esc>'
      key 'k'
      key 'j'
      check_tree()
      if st.opens['f:' .. node.path .. '\n' .. fx] == nil then
        fail 'what was opened for the row was not kept'
      end
      -- its folder: what is used outside it
      where = 'types view folder'
      local dir
      for _ = 1, 10 do
        local x = tree_screen.at()
        if x and x.kind == 'dir' then
          dir = x
          break
        end
        key 'h'
      end
      if dir then
        check_tree()
        local first = lines(st.obuf.pane)[1] or ''
        if not (first:find('used outside', 1, true) or first:find('nothing in it', 1, true)) then
          fail('a folder does not say what is used outside it: ' .. first)
        end
      end
      -- / a type: its Types view in the pane, the tree where it was
      where = 'types /'
      local before = st.outline.cursor
      key('/' .. ty .. '<CR>')
      local ph = lines(st.obuf.phead)[1] or ''
      if not (st.ptype and st.ptype.row.name == ty) or not ph:find(ty .. '   ', 1, true) or st.outline.cursor ~= before then
        fail('/ ' .. ty .. ' did not show its Types view in the pane: ' .. ph)
      end
      local tb = lines(st.obuf.pane)
      if
        m.flows[ty].n > 0
        and not table.concat(tb, '\n'):find(' a' .. 'n? ' .. ty)
        and not table.concat(tb, '\n'):find('a ' .. ty, 1, true)
        and not table.concat(tb, '\n'):find('an ' .. ty, 1, true)
      then
        fail(ty .. "'s Types view does not say who gives or takes it")
      end
      key 'j'
      if st.ptype then
        fail 'the tree moved and the pane still shows the type'
      end
      for _ = 1, 3 do
        if st.view.at == 'Code' then
          break
        end
        key '<Tab>'
      end
    end
  end
end

-- the Map on a function, its file, its folder and a type (tests/check_map.lua)
dofile(root .. '/tests/check_map.lua') {
  key = key,
  fail = fail,
  where = function(w)
    where = w
  end,
  st = st,
}

-- what changed, git asked of a throwaway directory in /tmp (tests/check_changed.lua)
dofile(root .. '/tests/check_changed.lua') {
  key = key,
  fail = fail,
  where = function(w)
    where = w
  end,
  st = st,
  repo = st.root,
}

-- from your own code: a file of the repo in a tab of its own, the cursor on
-- a contract's name, here() puts the tree's cursor on it, the page on it
-- with its Map; on a local function, calls puts it on the code screen
-- and called by shows its row with its Map; gf
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
    if api.nvim_get_current_tabpage() ~= st.tab or st.screen ~= 'tree' or (tree_screen.at() or {}).id ~= c.id then
      fail 'here page did not show its row in the tree'
    end
    check_map()
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
      if api.nvim_get_current_tabpage() ~= st.tab then
        fail(how .. ' did not come to seam')
      elseif how == 'calls' then
        if st.screen ~= 'code' or not (top() and top().id == f.id) then
          fail 'calls did not put the function on the code screen'
        else
          check_code()
          key 'K'
          if st.screen ~= 'tree' or (tree_screen.at() or {}).id ~= f.id then
            fail 'K from calls did not come back to its row in the tree'
          end
        end
      elseif st.screen ~= 'tree' or (tree_screen.at() or {}).id ~= f.id then
        fail 'called by did not show its row in the tree'
      else
        check_map()
      end
      api.nvim_set_current_tabpage(from)
      vim.cmd 'tabclose'
      api.nvim_set_current_tabpage(st.tab)
    end
  end
  -- a type's name: its Types view in the tree's pane
  local ty = m.flowlist and m.flowlist[1] and m.flowlist[1].decls[1]
  if ty and name_col(ty.path, ty.line, ty.name) then
    where = 'here types ' .. ty.id
    local from = on(ty.path, ty.line, name_col(ty.path, ty.line, ty.name))
    seam.here 'types'
    if api.nvim_get_current_tabpage() ~= st.tab or st.screen ~= 'tree' or not st.ptype or st.ptype.row.name ~= ty.name then
      fail('here types did not show the Types view of ' .. ty.name)
    end
    api.nvim_set_current_tabpage(from)
    vim.cmd 'tabclose'
    api.nvim_set_current_tabpage(st.tab)
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
