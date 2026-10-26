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

-- the explorer: every view and every side, moving in each
where = 'explorer'
for _, view in ipairs { 'v', 'V' } do
  for _, side in ipairs { 'b', 'b', 'u', 'u', 'b', 'u', 'u' } do
    where = ('explorer %s %s sides=%s'):format(view, st.view, st.sides)
    key(side)
    key 'j'
    key 'j'
    key 'k'
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
