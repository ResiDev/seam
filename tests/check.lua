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
  local want = st.panes[p.tab]
  local mid, right = valid(p.win.mid), valid(p.win.right)
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
  local L = require 'seam.lens'
  st.lens = {
    pins = { { dir = 'packages/', cols = { contracts = true, built = false, used = true } } },
    hides = {
      { pattern = '*.test.*', cols = L.everywhere() },
      { pattern = 'tests/', cols = { contracts = false, built = false, used = true } },
      { pattern = '/(fixtures|examples)/', cols = { contracts = false, built = true, used = false } },
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

-- the lens panel, through its keys; then put the lens back
do
  local panel = require 'seam.lens_panel'
  local saved = vim.deepcopy(st.lens)
  local function expect(ok, what)
    if not ok then
      fail(what)
    end
  end
  local function last()
    return st.lens.hides[#st.lens.hides]
  end
  where = 'lens panel'
  key 'f'
  expect(panel.is_open(), 'f did not open the panel')
  local n = #st.lens.hides
  key 'G'
  key 'k'
  key 'c'
  expect(#st.lens.hides == n + 1 and last().cols.contracts and not last().cols.used, 'c on a suggestion did not make a pattern for contracts')
  key 'u'
  expect(last().cols.used, 'u did not mark used by')
  key '<Space>'
  expect(not lens_any(last().cols), 'space did not clear all three')
  key '<Space>'
  expect(last().cols.contracts and last().cols.built and last().cols.used, 'space did not mark all three')
  local function type_in(keys, text)
    key(keys)
    local buf = api.nvim_get_current_buf()
    expect(vim.bo[buf].buftype == 'nofile' and api.nvim_win_get_config(0).relative == 'win', keys .. ' opened no input')
    api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    key '<CR>'
  end
  type_in('a', [[/\.(test|spec)\./]])
  expect(last().pattern == [[/\.(test|spec)\./]], 'a did not add the regex: ' .. tostring(last().pattern))
  expect(#require('seam.lens').matches(st.models[st.cur], last().pattern) > 0, 'the regex matches no file')
  type_in('e', 'tests/')
  expect(last().pattern == 'tests/', 'e did not edit it: ' .. tostring(last().pattern))
  local before = #st.lens.hides
  key 'd'
  expect(#st.lens.hides == before - 1, 'd did not delete')
  local L = require 'seam.lens'
  st.lens.pins = { { dir = 'packages/', cols = L.everywhere() } }
  st.lens.hides =
    { { pattern = '*.test.*', cols = L.everywhere() }, { pattern = [[/\.(test|spec)\./]], cols = { contracts = false, built = true, used = true } } }
  seam.lens_changed()
  local back = L.load(st.root)
  expect(vim.deep_equal(back, st.lens), 'the lens did not come back from ' .. L.file(st.root) .. ': ' .. vim.inspect(back))
  key 'U'
  expect(not st.lens.pins[1].cols.used and not st.lens.hides[2].cols.used and st.lens.hides[2].cols.built, 'U did not clear used by alone')
  key 'C'
  expect(not st.lens.hides[1].cols.contracts and st.lens.hides[1].cols.built, 'C did not clear contracts alone')
  key 'B'
  expect(not lens_any(st.lens.pins[1].cols), 'B did not clear built from')
  st.lens.hides[1].cols = L.everywhere()
  key 'X'
  expect(not lens_any(st.lens.hides[1].cols) and #st.lens.hides == 2, 'X did not clear every mark, keeping the rules')
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

local SEQ = { 'j', 'j', 'k', ']]', '[[', 'c', 'j', ']]', 'k', 'c', 's', 'j', ']]', 's', 'c', 's', 's', 'G', 'j', 'gg' }
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
        for _, k in ipairs(SEQ) do
          where = ('%s %s panes=%s'):format(c.id, st.page.tab, st.panes[st.page.tab])
          key(k)
          check_page()
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
          key '<CR>'
          if #st.stack > depth then
            check_page()
            key '<BS>'
          end
        end
        where = c.id .. ' tab'
        key '<Tab>'
        check_page()
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
      key '<BS>'
      if st.screen == 'page' then
        fail '<BS> stayed on the page'
      end
    end
  end
end

io.stdout:write(('%s: %d contracts, %d keys, %d failures\n'):format(repo, #contracts, steps, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
