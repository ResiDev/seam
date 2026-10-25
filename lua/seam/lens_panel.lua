-- The lens panel: pinned folders and hiding patterns, each with a mark per
-- column. c b u mark a column, Space all three. Snacks only to pick folders.
local L = require 'seam.lens'
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace 'seam.lens'

---@class seam.LensHost
---@field lens fun(): seam.Lens
---@field model fun(): table
---@field changed fun()   -- the lens changed; filter and redraw behind the panel
---@field closed fun()    -- the panel closed

api.nvim_set_hl(0, 'SeamLensOn', { default = true, link = 'DiagnosticOk' })
api.nvim_set_hl(0, 'SeamLensOff', { default = true, link = 'Comment' })
api.nvim_set_hl(0, 'SeamLensAction', { default = true, link = 'Function' })
api.nvim_set_hl(0, 'SeamLensPattern', { default = true, link = 'Special' })
api.nvim_set_hl(0, 'SeamLensHead', { default = true, link = 'Title' })

local W = 86
local COUNT_END, MARK = 50, { contracts = 57, built = 68, used = 79 }
local MAX_MATCHES = 10

local function plural(n, word)
  return n .. ' ' .. word .. (n == 1 and '' or 's')
end

-- a row: chunks placed at columns, then turned into a line and its marks
local function line()
  local l = { text = '', marks = {} }
  function l.at(col, text, hl)
    if col and api.nvim_strwidth(l.text) < col then
      l.text = l.text .. string.rep(' ', col - api.nvim_strwidth(l.text))
    end
    local s = #l.text
    l.text = l.text .. text
    if hl then
      l.marks[#l.marks + 1] = { s, #l.text, hl }
    end
    return l
  end
  function l.add(text, hl)
    return l.at(nil, text, hl)
  end
  return l
end

local function marks(l, cols, dim)
  for _, c in ipairs(L.COLS) do
    local on = cols[c]
    l.at(MARK[c], on and '●' or '○', on and 'SeamLensOn' or 'SeamLensOff')
  end
  if dim then
    l.marks[#l.marks + 1] = { 0, #l.text, 'SeamLensOff' }
  end
end

local function contracts_in(m, dir)
  local n = 0
  for _, e in ipairs(m.exports) do
    if #(e.all_uses or e.uses) > 0 and e.path:sub(1, #dir) == dir then
      n = n + 1
    end
  end
  return n
end

local HELP = {
  { '*.test.*', 'file names like run.test.ts' },
  { 'tests/', 'a folder of that name, anywhere' },
  { 'e2e/fixtures/', 'that folder, from the repo root' },
  { 'packages/*/scripts/**', 'a path: * is one folder, ** any' },
  { '/\\.(test|spec)\\./', 'a regex on the path, between slashes' },
  { 'fixtures', 'any path with that text in it' },
}

local P -- the open panel

local function rows()
  local lens, m = P.host.lens(), P.host.model()
  local out = {}
  local function push(l, meta)
    l.meta = meta
    out[#out + 1] = l
  end
  push(line())
  push(line().at(MARK.contracts - 4, 'contracts', 'SeamLensOff').at(MARK.built - 5, 'built from', 'SeamLensOff').at(MARK.used - 3, 'used by', 'SeamLensOff'))
  push(line().at(1, 'Show only inside', 'SeamLensHead').at(COUNT_END - 9, 'contracts', 'SeamLensOff'))
  for i, p in ipairs(lens.pins) do
    local n = tostring(contracts_in(m, p.dir))
    local l = line().at(3, p.dir, 'Directory').at(COUNT_END - #n, n, 'SeamLensOff')
    marks(l, p.cols)
    push(l, { kind = 'pin', pin = p, i = i })
  end
  push(line().at(3, '+ pick folders', 'SeamLensAction'), { kind = 'pick' })
  push(line())
  push(line().at(1, 'Hide', 'SeamLensHead').at(COUNT_END - 5, 'files', 'SeamLensOff'))
  for i, h in ipairs(lens.hides) do
    local files, err = L.matches(m, h.pattern)
    local n = err and '?' or tostring(#files)
    local l = line().at(3, h.pattern, L.any(h.cols) and 'SeamLensPattern' or 'SeamLensOff').at(COUNT_END - #n, n, 'SeamLensOff')
    marks(l, h.cols)
    push(l, { kind = 'hide', hide = h, i = i })
  end
  for _, sg in ipairs(L.suggestions(lens, m)) do
    local n = tostring(sg.n)
    local l = line().at(3, sg.pattern).at(COUNT_END - #n, n)
    marks(l, L.none(), true)
    push(l, { kind = 'suggest', pattern = sg.pattern })
  end
  push(line().at(3, '+ add a pattern', 'SeamLensAction'), { kind = 'add' })
  push(line())
  -- what the row under the cursor, or the pattern being typed, matches
  local cur = P.typing and { kind = 'typing' } or (out[P.cursor or 0] or {}).meta or {}
  local pattern = P.typing or (cur.hide and cur.hide.pattern) or cur.pattern
  if pattern then
    local files, err = L.matches(m, pattern)
    local head = line().at(1, pattern ~= '' and pattern or ' ', 'SeamLensPattern')
    if err then
      head.add('   ' .. err, 'DiagnosticError')
    else
      head.add('   ' .. L.describe(pattern) .. ' · ' .. plural(#files, 'file'), 'SeamLensOff')
    end
    push(head)
    for i, f in ipairs(files) do
      if i > MAX_MATCHES then
        push(line().at(3, '… ' .. plural(#files - MAX_MATCHES, 'more file'), 'SeamLensOff'))
        break
      end
      local dir, name = f:match '^(.*/)([^/]+)$'
      push(line().at(3, dir or '', 'SeamLensOff').add(name or f))
    end
    if P.typing then
      push(line())
      for _, h in ipairs(HELP) do
        push(line().at(3, h[1], 'SeamLensPattern').at(28, h[2], 'SeamLensOff'))
      end
    end
  elseif cur.kind == 'pin' then
    local dir = cur.pin.dir
    push(line().at(1, dir, 'Directory').add('   ' .. plural(contracts_in(m, dir), 'contract') .. ' inside', 'SeamLensOff'))
  elseif cur.kind == 'add' then
    for _, h in ipairs(HELP) do
      push(line().at(3, h[1], 'SeamLensPattern').at(28, h[2], 'SeamLensOff'))
    end
  elseif cur.kind == 'pick' then
    push(line().at(1, 'Pick one folder or several (⇥), in a picker.', 'SeamLensOff'))
  end
  push(line())
  local keys = P.typing and { '⏎ add   esc cancel' }
    or { 'c b u  mark a column   ␣  all three   C B U  clear a column   X  clear all', 'a add   e edit   d delete   p pick folders   q close' }
  for _, k in ipairs(keys) do
    push(line().at(1, k, 'SeamLensOff'))
  end
  return out
end

local function draw()
  if not (P and api.nvim_buf_is_valid(P.buf)) then
    return
  end
  local out = rows()
  P.rows = out
  local lines = {}
  for i, l in ipairs(out) do
    lines[i] = l.text
  end
  vim.bo[P.buf].modifiable = true
  api.nvim_buf_set_lines(P.buf, 0, -1, false, lines)
  vim.bo[P.buf].modifiable = false
  api.nvim_buf_clear_namespace(P.buf, ns, 0, -1)
  for i, l in ipairs(out) do
    for _, mk in ipairs(l.marks) do
      api.nvim_buf_set_extmark(P.buf, ns, i - 1, mk[1], { end_col = mk[2], hl_group = mk[3] })
    end
  end
  if api.nvim_win_is_valid(P.win) then
    api.nvim_win_set_config(P.win, { relative = 'editor', row = P.row0, col = P.col0, width = W, height = math.min(#out, vim.o.lines - 4) })
  end
end

local function selectable()
  local out = {}
  for i, l in ipairs(P.rows) do
    if l.meta and l.meta.kind then
      out[#out + 1] = i
    end
  end
  return out
end

local function place(i)
  P.cursor = i
  api.nvim_win_set_cursor(P.win, { i, 2 })
  draw()
end

local function current()
  return P.rows[P.cursor or 0] and P.rows[P.cursor].meta or {}
end

local function step(n)
  local sel = selectable()
  local at = 1
  for k, i in ipairs(sel) do
    if i == P.cursor then
      at = k
    end
  end
  place(sel[math.max(1, math.min(#sel, at + n))])
end

--- put the cursor on the row a predicate picks, after a redraw
local function seek(pred)
  draw()
  for i, l in ipairs(P.rows) do
    if l.meta and pred(l.meta) then
      return place(i)
    end
  end
  place(selectable()[1])
end

local function changed(pred)
  P.host.changed()
  if pred then
    seek(pred)
  else
    draw()
  end
end

local function toggle(col)
  local cur, lens = current(), P.host.lens()
  local cols
  if cur.kind == 'pin' then
    cols = cur.pin.cols
  elseif cur.kind == 'hide' then
    cols = cur.hide.cols
  elseif cur.kind == 'suggest' then
    local h = { pattern = cur.pattern, cols = L.none() }
    table.insert(lens.hides, h)
    cols = h.cols
  else
    return
  end
  if col then
    cols[col] = not cols[col]
  else
    local to = not L.any(cols)
    for _, c in ipairs(L.COLS) do
      cols[c] = to
    end
  end
  local key = cur.pin and cur.pin.dir or cur.pattern or cur.hide.pattern
  changed(function(meta)
    return (meta.pin and meta.pin.dir == key) or (meta.hide and meta.hide.pattern == key)
  end)
end

--- every mark in one column off, or in all three; the rules stay, to mark again
local function clear(col)
  local lens = P.host.lens()
  for _, rule in ipairs(vim.list_extend(vim.list_extend({}, lens.pins), lens.hides)) do
    for _, c in ipairs(L.COLS) do
      if not col or c == col then
        rule.cols[c] = false
      end
    end
  end
  local at = P.cursor
  P.host.changed()
  draw()
  place(at)
end

local function delete()
  local cur, lens = current(), P.host.lens()
  if cur.kind == 'pin' then
    table.remove(lens.pins, cur.i)
  elseif cur.kind == 'hide' then
    table.remove(lens.hides, cur.i)
  else
    return
  end
  local at = P.cursor
  P.host.changed()
  draw()
  local sel = selectable()
  local best = sel[#sel]
  for _, i in ipairs(sel) do
    if i >= at then
      best = i
      break
    end
  end
  place(best)
end

--- type a pattern in place; the bottom of the panel shows what it matches
local function input(editing)
  local r = P.cursor
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- a path completer would take the slashes of a regex, and its ⏎
  vim.b[buf].completion = false
  api.nvim_buf_set_lines(buf, 0, -1, false, { editing and editing.pattern or '' })
  P.typing = editing and editing.pattern or ''
  draw()
  local win =
    api.nvim_open_win(buf, true, { relative = 'win', win = P.win, row = r - 1, col = 2, width = COUNT_END - 12, height = 1, style = 'minimal', zindex = 60 })
  vim.wo[win].winhighlight = 'Normal:Visual'
  local function finish(commit)
    local text = vim.trim(api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '')
    vim.cmd 'stopinsert'
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    P.typing = nil
    if api.nvim_win_is_valid(P.win) then
      api.nvim_set_current_win(P.win)
    end
    if commit and text ~= '' and L.compile(text) then
      local lens = P.host.lens()
      if editing then
        editing.pattern = text
      else
        table.insert(lens.hides, { pattern = text, cols = { contracts = true, built = true, used = true } })
      end
      return changed(function(meta)
        return meta.hide and meta.hide.pattern == text
      end)
    end
    draw()
    place(r)
  end
  local o = { buffer = buf, nowait = true }
  vim.keymap.set({ 'i', 'n' }, '<CR>', function()
    finish(true)
  end, o)
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
    finish(false)
  end, o)
  api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    buffer = buf,
    callback = function()
      P.typing = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ''
      draw()
    end,
  })
  vim.cmd 'startinsert!'
end

--- Snacks, for picking folders only; ⇥ picks several
local function pick()
  local Snacks = rawget(_G, 'Snacks')
  if not (Snacks and Snacks.picker) then
    vim.ui.input({ prompt = 'Pin to folder: ' }, function(d)
      if d and d ~= '' then
        table.insert(P.host.lens().pins, { dir = d:gsub('/?$', '/'), cols = { contracts = true, built = false, used = false } })
        changed()
      end
    end)
    return
  end
  local m, host = P.host.model(), P.host
  local count = {}
  for _, e in ipairs(m.exports) do
    if #(e.all_uses or e.uses) > 0 then
      local dir = e.path
      while true do
        dir = dir:match '^(.*)/[^/]+$'
        if not dir then
          break
        end
        count[dir .. '/'] = (count[dir .. '/'] or 0) + 1
      end
    end
  end
  local items = {}
  for d, n in pairs(count) do
    items[#items + 1] = { text = d, dir = d, n = n }
  end
  table.sort(items, function(a, b)
    return a.dir < b.dir
  end)
  M.close(true)
  local picked = false
  Snacks.picker.pick {
    title = 'Pin to folders',
    items = items,
    layout = { preset = 'select' },
    format = function(item)
      local parent, name = item.dir:match '^(.*/)([^/]+/)$'
      return { { parent or '', 'SeamLensOff' }, { name or item.dir, 'Directory' }, { '  ' .. plural(item.n, 'contract'), 'SeamLensOff' } }
    end,
    confirm = function(p)
      local dirs = {}
      for _, it in ipairs(p:selected { fallback = true }) do
        dirs[#dirs + 1] = it.dir
      end
      picked = true
      p:close()
      local lens = host.lens()
      for _, d in ipairs(dirs) do
        local have = false
        for _, pin in ipairs(lens.pins) do
          have = have or pin.dir == d
        end
        if not have then
          table.insert(lens.pins, { dir = d, cols = { contracts = true, built = false, used = false } })
        end
      end
      host.changed()
      vim.schedule(function()
        M.open(host, dirs[1])
      end)
    end,
    on_close = function()
      vim.schedule(function()
        if not picked and not P then
          M.open(host)
        end
      end)
    end,
  }
end

function M.close(quiet)
  if not P then
    return
  end
  local p = P
  P = nil
  if api.nvim_win_is_valid(p.win) then
    api.nvim_win_close(p.win, true)
  end
  if not quiet then
    p.host.closed()
  end
end

---@param host seam.LensHost
---@param at? string a folder or pattern to put the cursor on
function M.open(host, at)
  if P then
    return
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'seamlens'
  P = { host = host, buf = buf }
  P.row0 = math.max(1, math.floor(vim.o.lines * 0.12))
  P.col0 = math.max(0, math.floor((vim.o.columns - W) / 2))
  P.win = api.nvim_open_win(
    buf,
    true,
    { relative = 'editor', row = P.row0, col = P.col0, width = W, height = 10, border = 'rounded', title = ' lens ', title_pos = 'left', zindex = 50 }
  )
  local wo = vim.wo[P.win]
  wo.cursorline, wo.wrap, wo.number, wo.relativenumber, wo.signcolumn = true, false, false, false, 'no'
  wo.winhighlight = 'NormalFloat:Normal,FloatBorder:SeamLensAction'
  local o = { buffer = buf, nowait = true, silent = true }
  local map = function(lhs, fn)
    vim.keymap.set('n', lhs, fn, o)
  end
  map('j', function()
    step(vim.v.count1)
  end)
  map('k', function()
    step(-vim.v.count1)
  end)
  map('<Down>', function()
    step(1)
  end)
  map('<Up>', function()
    step(-1)
  end)
  map('gg', function()
    place(selectable()[1])
  end)
  map('G', function()
    local sel = selectable()
    place(sel[#sel])
  end)
  map('c', function()
    toggle 'contracts'
  end)
  map('b', function()
    toggle 'built'
  end)
  map('u', function()
    toggle 'used'
  end)
  local function all_or_act()
    local k = current().kind
    if k == 'add' then
      input()
    elseif k == 'pick' then
      pick()
    else
      toggle()
    end
  end
  map('<Space>', all_or_act)
  map('<CR>', all_or_act)
  map('a', function()
    seek(function(meta)
      return meta.kind == 'add'
    end)
    input()
  end)
  map('e', function()
    local cur = current()
    if cur.kind == 'hide' then
      input(cur.hide)
    end
  end)
  map('C', function()
    clear 'contracts'
  end)
  map('B', function()
    clear 'built'
  end)
  map('U', function()
    clear 'used'
  end)
  map('X', clear)
  map('d', delete)
  map('p', pick)
  for _, k in ipairs { 'q', '<Esc>', 'f' } do
    map(k, M.close)
  end
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if P and P.buf == buf and not P.typing and api.nvim_win_is_valid(P.win) and api.nvim_get_current_win() ~= P.win then
          M.close()
        end
      end)
    end,
  })
  if at then
    seek(function(meta)
      return (meta.pin and meta.pin.dir == at) or (meta.hide and meta.hide.pattern == at) or meta.pattern == at
    end)
  else
    draw()
    place(selectable()[1])
  end
end

function M.is_open()
  return P ~= nil
end

return M
