-- The lens panel: one row a rule, and in each column what it does there,
-- `only` or `hide`. c b u turn a column, Space all three. Rules come from a
-- picker: folders, files, or a pattern typed and its matches listed live.
local L = require 'seam.lens'
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace 'seam.lens'

---@class seam.LensHost
---@field lens fun(): seam.Lens
---@field model fun(): table
---@field root fun(): string  -- the repo, for previewing its files
---@field changed fun()   -- the lens changed; filter and redraw behind the panel
---@field closed fun()    -- the panel closed

api.nvim_set_hl(0, 'SeamLensOnly', { default = true, link = 'DiagnosticOk' })
api.nvim_set_hl(0, 'SeamLensHide', { default = true, link = 'DiagnosticError' })
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

local WAY_HL = { only = 'SeamLensOnly', hide = 'SeamLensHide' }

--- each column's way, the word under its name; a column left be, a dot
local function ways(l, cols)
  for _, c in ipairs(L.COLS) do
    local way = cols[c]
    l.at(way and MARK[c] - 2 or MARK[c], way or '·', way and WAY_HL[way] or 'SeamLensOff')
  end
end

--- the next way a column turns to: left be, only, hide
local NEXT = { [''] = 'only', only = 'hide', hide = nil }

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
  push(
    line()
      .at(COUNT_END - 5, 'files', 'SeamLensOff')
      .at(MARK.contracts - 4, 'contracts', 'SeamLensOff')
      .at(MARK.built - 5, 'built from', 'SeamLensOff')
      .at(MARK.used - 3, 'used by', 'SeamLensOff')
  )
  for i, r in ipairs(lens.rules) do
    local n = tostring(#L.rule_files(m, r))
    local hl = not L.any(r.cols) and 'SeamLensOff' or r.path and 'Directory' or 'SeamLensPattern'
    local l = line().at(3, L.label(r), hl).at(COUNT_END - #n, n, 'SeamLensOff')
    ways(l, r.cols)
    push(l, { kind = 'rule', rule = r, i = i })
  end
  push(line().at(3, '+ add: pick folders and files, or type a pattern', 'SeamLensAction'), { kind = 'add' })
  push(line())
  -- what the row under the cursor, or the pattern being typed, holds
  local cur = (out[P.cursor or 0] or {}).meta or {}
  local rule = P.typing and { pattern = P.typing } or cur.rule or (cur.pattern and { pattern = cur.pattern })
  if rule then
    local files, err = L.matches(m, rule.pattern or '')
    if rule.path then
      files, err = L.rule_files(m, rule), nil
    end
    local what = rule.path and (rule.path:sub(-1) == '/' and 'that folder' or 'that file') or L.describe(rule.pattern)
    local head = line().at(1, L.label(rule) ~= '' and L.label(rule) or ' ', rule.path and 'Directory' or 'SeamLensPattern')
    head.add('   ' .. (err or (what .. ' · ' .. plural(#files, 'file'))), err and 'DiagnosticError' or 'SeamLensOff')
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
  elseif cur.kind == 'add' then
    push(line().at(1, 'A picker: folders or files, ⇥ for several, or type a pattern to see its matches.', 'SeamLensOff'))
  end
  push(line())
  local keys = P.typing and { '⏎ done   esc cancel' }
    or { 'c b u  turn a column: only, hide, neither   ␣  all three together', 'C B U  clear a column   X  clear all   a add   e edit   d delete   q close' }
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

--- turn one column, or with none all three together: neither, only, hide
local function turn(col)
  local rule = current().rule
  if not rule then
    return
  end
  local cols = rule.cols
  if col then
    cols[col] = NEXT[cols[col] or '']
  else
    local to = 'only'
    if cols.contracts == cols.built and cols.built == cols.used then
      to = NEXT[cols.contracts or '']
    end
    for _, c in ipairs(L.COLS) do
      cols[c] = to
    end
  end
  changed(function(meta)
    return meta.rule == rule
  end)
end

--- one column cleared in every rule, or all three; the rules stay, to turn again
local function clear(col)
  for _, rule in ipairs(P.host.lens().rules) do
    for _, c in ipairs(L.COLS) do
      if not col or c == col then
        rule.cols[c] = nil
      end
    end
  end
  local at = P.cursor
  P.host.changed()
  draw()
  place(at)
end

local function delete()
  local cur = current()
  if cur.kind ~= 'rule' then
    return
  end
  table.remove(P.host.lens().rules, cur.i)
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

--- edit a rule's pattern in place; the bottom of the panel shows what it matches
---@param editing seam.Rule
local function input(editing)
  local r = P.cursor
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- a path completer would take the slashes of a regex, and its ⏎
  vim.b[buf].completion = false
  api.nvim_buf_set_lines(buf, 0, -1, false, { editing.pattern })
  P.typing = editing.pattern
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
      editing.pattern = text
      return changed(function(meta)
        return meta.rule == editing
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

--- Snacks, to add rules. Empty, it lists folders; typing lists what the
--- pattern matches, live: the pattern itself first, to take all it matches,
--- then its folders and files. ⇥ picks several. A new rule does nothing
--- until a column is turned.
local function pick()
  local Snacks = rawget(_G, 'Snacks')
  local host = P.host
  ---@return seam.Rule first the first rule added, or the one it already was
  local function add(new)
    local rules, first = host.lens().rules, nil
    for _, r in ipairs(new) do
      local have
      for _, old in ipairs(rules) do
        have = have or (L.label(old) == L.label(r) and old)
      end
      if not have then
        r.cols = {}
        table.insert(rules, r)
      end
      first = first or have or r
    end
    host.changed()
    return first
  end
  if not (Snacks and Snacks.picker) then
    vim.ui.input({ prompt = 'Add a pattern: ' }, function(text)
      if text and L.compile(text) then
        local r = add { { pattern = vim.trim(text) } }
        seek(function(meta)
          return meta.rule == r
        end)
      end
    end)
    return
  end
  local m, root = host.model(), host.root()
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
  local folders = vim.tbl_keys(count)
  table.sort(folders)
  local function list(files)
    return { text = #files > 0 and table.concat(files, '\n') or 'nothing matches' }
  end
  local function folder(d)
    local inside = vim.tbl_filter(function(f)
      return f:sub(1, #d) == d
    end, L.files(m))
    return { text = d, kind = 'folder', path = d, n = count[d], preview = list(inside) }
  end
  local function items(q)
    if q == '' then
      return vim.tbl_map(folder, folders)
    end
    local files, err = L.matches(m, q)
    if err then
      return { { text = q, kind = 'error', err = err, preview = { text = err } } }
    end
    local out = { { text = q, kind = 'pattern', pattern = q, n = #files, preview = list(files) } }
    local fn = L.compile(q)
    for _, d in ipairs(folders) do
      if fn(d) then
        out[#out + 1] = folder(d)
      end
    end
    for _, f in ipairs(files) do
      out[#out + 1] = { text = f, kind = 'file', path = f, file = root .. '/' .. f, preview = 'file' }
    end
    return out
  end
  local function split(path)
    local parent, name = path:match '^(.*/)([^/]+/?)$'
    return parent or '', name or path
  end
  M.close(true)
  local picked = false
  Snacks.picker.pick {
    title = 'Add to the lens',
    live = true,
    finder = function(_, ctx)
      return items(vim.trim(ctx.filter.search))
    end,
    format = function(item)
      if item.kind == 'pattern' then
        return { { item.pattern, 'SeamLensPattern' }, { '   all ' .. plural(item.n, 'file') .. ' it matches · ' .. L.describe(item.pattern), 'SeamLensOff' } }
      elseif item.kind == 'error' then
        return { { item.text, 'SeamLensPattern' }, { '   ' .. item.err, 'DiagnosticError' } }
      end
      local parent, name = split(item.path)
      local out = { { parent, 'SeamLensOff' }, { name, item.kind == 'folder' and 'Directory' or 'Normal' } }
      if item.n then
        out[#out + 1] = { '  ' .. plural(item.n, 'contract'), 'SeamLensOff' }
      end
      return out
    end,
    preview = 'preview',
    confirm = function(p)
      local new = {}
      for _, it in ipairs(p:selected { fallback = true }) do
        if it.kind == 'pattern' then
          new[#new + 1] = { pattern = it.pattern }
        elseif it.path then
          new[#new + 1] = { path = it.path }
        end
      end
      if #new == 0 then
        return
      end
      picked = true
      p:close()
      local first = add(new)
      vim.schedule(function()
        M.open(host, first)
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
---@param at? seam.Rule the rule to put the cursor on
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
    turn 'contracts'
  end)
  map('b', function()
    turn 'built'
  end)
  map('u', function()
    turn 'used'
  end)
  local function act()
    if current().kind == 'add' then
      pick()
    else
      turn()
    end
  end
  map('<Space>', act)
  map('<CR>', act)
  map('a', pick)
  map('e', function()
    local rule = current().rule
    if rule and rule.pattern then
      input(rule)
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
  for _, k in ipairs { 'q', '<Esc>', 'L' } do
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
      return meta.rule == at
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
