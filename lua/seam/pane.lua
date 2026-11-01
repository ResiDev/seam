-- The pane on the right of every screen: its head with the tabs over the
-- view shown, for what the screen says it is about; the keys in it, and
-- those that reach it from the left: the other tab, a view aside, the next
-- display, the diff, scrolling it, n and N from place to place, + and -.
local api = vim.api
local draw = require 'seam.draw'
local index = require 'seam.index'
local odraw = require 'seam.draw.outline'
local opening = require 'seam.opening'
local st = require 'seam.state'
local views = require 'seam.views'
local M = {}

local function screen()
  return st.screen == 'code' and require 'seam.screen_code' or require 'seam.screen_tree'
end

--- The windows of the screen shown: its head, its pane's head and its pane.
---@return table|nil
function M.wins()
  local w = st.screen == 'code' and st.cwin or st.owin
  if w and w.pane and api.nvim_win_is_valid(w.pane) and api.nvim_win_is_valid(w.phead) then
    return w
  end
end

--- Is the cursor in the pane, its head or its view?
---@return boolean
function M.inside()
  local w, cur = M.wins(), api.nvim_get_current_win()
  return w ~= nil and (cur == w.pane or cur == w.phead)
end

--- What the pane shows: what the screen shown is about.
---@return seam.ORow|nil
function M.subject()
  return screen().subject()
end

-- what the view is drawn with: the types opened in place for the row, kept
-- by its key as long as seam is open, and the pane's width
local function ctx(x, w)
  st.opens = st.opens or {}
  local k = x and x.key or ''
  st.opens[k] = st.opens[k] or {}
  st.pctx = {
    open = st.opens[k],
    width = api.nvim_win_get_width(w.pane),
    head = x and x.kind == 'type' and x.name or nil,
  }
  return st.pctx
end

--- The pane for `x`: its head and tabs, and the view shown; `keep` where
--- the pane was scrolled.
---@param x seam.ORow|nil
---@param keep? boolean
function M.show(x, keep)
  M.cancel()
  local w = M.wins()
  if not w then
    return
  end
  local m = index.model()
  odraw.pane_head(st.obuf.phead, m, st.outline, x, st.view)
  odraw.pane(st.obuf.pane, w.pane, m, x, st.view, ctx(x, w), keep)
end

-- The pane following the cursor, drawn once it rests: moving over rows draws
-- nothing until the cursor stops, so a row slow to draw (a big file's diff,
-- a file seen for the first time) never holds the cursor up. 0 draws at once,
-- for the checks.
M.DELAY = 50
local timer, pending

--- The pane for `x` once the cursor has rested `M.DELAY` ms, the screen
--- painted after.
---@param x seam.ORow|nil
function M.follow(x)
  pending = { x = x }
  if M.DELAY <= 0 then
    return M.flush()
  end
  timer = timer or vim.uv.new_timer()
  timer:stop()
  timer:start(M.DELAY, 0, vim.schedule_wrap(M.flush))
end

--- A pane waiting on the cursor drawn now, before a key acts on it.
function M.flush()
  local p = pending
  if not p then
    return
  end
  pending = nil
  if timer then
    timer:stop()
  end
  M.show(p.x)
  require('seam.screen').paint()
  vim.cmd 'redrawstatus'
end

--- Nothing waiting: the pane is being drawn now.
function M.cancel()
  pending = nil
  if timer then
    timer:stop()
  end
end

--- The pane drawn again for what it shows, where it was scrolled.
function M.redraw()
  M.show(M.subject(), true)
  require('seam.screen').paint()
  vim.cmd 'redrawstatus'
end

local function shown_again(x)
  M.show(x)
  require('seam.screen').paint()
  vim.cmd 'redrawstatus'
end

--- `<Tab>` `<S-Tab>`: the pane's other tab, or from a view aside back to
--- the tab; with `display`, `<C-Tab>` `<C-S-Tab>`: its next display, or the
--- one before.
---@param d integer
---@param display? boolean
---@return fun()
function M.step(d, display)
  return function()
    local x = M.subject()
    local ok
    if display then
      ok = views.step_display(x, st.view, d)
    else
      ok = views.step(x, st.view)
    end
    if ok then
      shown_again(x)
    end
  end
end

-- the views aside and their keys
M.ASIDE = { gu = 'Used by', gb = 'Built from', gm = 'Map' }
M.ASIDE_KEYS = { 'gu', 'gb', 'gm' }

--- `gu` `gb` `gm`: the view aside on the key in the pane, or back.
---@param k string
---@return fun()
function M.aside(k)
  return function()
    local x = M.subject()
    if views.aside(x, st.view, M.ASIDE[k]) then
      shown_again(x)
    end
  end
end

--- `D`: the diff on or off, for the session, both sides drawn again.
function M.toggle_diff()
  require('seam.views.changed').toggle()
  local why = st.diff and M.diff_empty()
  if why then
    vim.notify('seam: diff on, ' .. why, vim.log.levels.INFO)
  end
  if st.screen == 'code' then
    require('seam.screen_code').redraw()
  else
    shown_again(M.subject())
  end
end

--- Whether the pane holds more than it shows, for `<M-j>` `<M-k>`'s hint.
---@return boolean
function M.can_scroll()
  local w = M.wins()
  if not w or not api.nvim_win_is_valid(w.pane) then
    return false
  end
  return api.nvim_win_text_height(w.pane, {}).all > api.nvim_win_get_height(w.pane)
end

--- Does `D` act: has the range changes, or is the diff on to turn off?
---@return boolean
function M.can_diff()
  return st.diff == true or require('seam.changes').any()
end

--- The keys for the pane's views where they act on `x`: `<Tab>`, `gu` `gb`
--- `gm` each where the row has its view, `<C-Tab>` with more than one display.
---@param x seam.ORow|nil
---@return string[]
function M.view_hints(x)
  local out = {}
  if views.can_step(x, st.view) then
    out[#out + 1] = '<Tab>'
  end
  for _, k in ipairs(M.ASIDE_KEYS) do
    if views.has(x, M.ASIDE[k]) then
      out[#out + 1] = k
    end
  end
  local v = views.shown(x, st.view)
  if v and #views.displays(v, x) > 1 then
    out[#out + 1] = '<C-Tab>'
  end
  return out
end

--- With the diff on and nothing to draw, why: git said no, or the range
--- holds no change. nil while there are changes or they are being asked.
---@return string|nil
function M.diff_empty()
  local ch = require 'seam.changes'
  local C = ch.get()
  if not C or C.pending then
    return nil
  end
  if C.err then
    if C.err:lower():find('not a git repository', 1, true) then
      return 'no git repository here'
    end
    return 'git: ' .. (C.err ~= '' and C.err or 'no answer')
  end
  if #C.list == 0 then
    local r = ch.range()
    return 'nothing changed from ' .. r.from .. ' to the working tree, L picks the range'
  end
end

--- The status line's left begun: `diff on` while it is, and why it draws
--- nothing when it does not.
---@param left string
---@return string
function M.said(left)
  if not st.diff then
    return left
  end
  local why = M.diff_empty()
  return 'diff on' .. (why and (' · ' .. why) or '') .. '   ' .. left
end

--- Scroll the pane from the left, as the key scrolls a window.
---@param k string
---@return fun()
function M.scroll(k)
  return function()
    M.flush()
    local w = M.wins()
    if not w then
      return
    end
    local keys = (vim.v.count > 0 and vim.v.count or '') .. vim.keycode(k)
    api.nvim_win_call(w.pane, function()
      vim.cmd('normal! ' .. keys)
    end)
    require('seam.screen').paint()
  end
end

--- The pane's stops for n and N: the places Used by and Built from show;
--- with `what` 'change', the changes the diff shows, for ]c [c.
---@param what? 'place'|'change'
---@return integer[]
function M.stops(what)
  local out = {}
  if not M.wins() then
    return out
  end
  for i = 1, api.nvim_buf_line_count(st.obuf.pane) do
    if draw.meta(st.obuf.pane, i)[what or 'place'] then
      out[#out + 1] = i
    end
  end
  return out
end

--- `n` `N`: the cursor to the next place in the pane, or the one before,
--- round the ends; from the left, into the pane. With `what` 'change',
--- `]c` `[c` in the pane: the next change in its diff.
---@param d integer
---@param what? 'place'|'change'
function M.next_place(d, what)
  M.flush()
  local list = M.stops(what)
  if #list == 0 then
    return
  end
  local w = M.wins().pane
  local cur = api.nvim_win_get_cursor(w)[1]
  -- from the left, the place the pane's cursor is on counts as the next
  if not M.inside() and d > 0 then
    cur = cur - 1
  end
  local i
  if d > 0 then
    i = #list + 1
    for k, l in ipairs(list) do
      if l > cur then
        i = k
        break
      end
    end
    i = i + vim.v.count1 - 1
  else
    i = 0
    for k = #list, 1, -1 do
      if list[k] < cur then
        i = k
        break
      end
    end
    i = i - vim.v.count1 + 1
  end
  api.nvim_set_current_win(w)
  api.nvim_win_set_cursor(w, { list[(i - 1) % #list + 1], 0 })
  draw.cursor_line(w)
  require('seam.screen').paint()
  vim.cmd 'redrawstatus'
end

--- Has the view shown places for n and N?
---@return boolean
function M.has_places()
  local v = views.shown(M.subject(), st.view)
  return v ~= nil and (v.name == 'Used by' or v.name == 'Built from') and #M.stops() > 0
end

--- The keys that act with the cursor in the pane, its three groups.
---@param back string the window `<Esc>` goes back to, its word
---@return table row, table pane, table seam
function M.hints(back)
  local x = M.subject()
  local row = require('seam.map.keys').hints()
  local o, c = opening.keys()
  if o then
    row[#row + 1] = opening.is_more(o) and { '+', 'more' } or '+'
  end
  if c then
    row[#row + 1] = opening.is_more(c) and { '-', 'fewer' } or '-'
  end
  if M.has_places() then
    row[#row + 1] = 'n N'
  end
  if #M.stops 'change' > 0 then
    row[#row + 1] = ']c [c'
  end
  local pane = M.view_hints(x)
  if M.can_diff() then
    pane[#pane + 1] = 'D'
  end
  local seam = { { '<Esc>', back } }
  if st.screen == 'code' then
    seam[#seam + 1] = 'K'
  end
  seam[#seam + 1] = 'L'
  seam[#seam + 1] = 'q'
  return row, pane, seam
end

--- The pane's keys in `?`.
---@param back string
---@return seam.KeyGroup[]
function M.all_keys(back)
  local seam = { { '<Esc>', 'back to the ' .. back } }
  if st.screen == 'code' then
    seam[#seam + 1] = { 'K', 'back where you were, a count for more' }
  end
  vim.list_extend(seam, { { 'L', 'the lens: what seam shows, and the range of changes' }, { 'gf gd', 'that place in your own code' }, { 'q', 'close seam' } })
  return {
    {
      'The pane',
      {
        { '+', 'open the type under the cursor, or a function as written; on ⋯ N more, the rest' },
        { '-', 'close the one the cursor is in; on a place it showed, hide the rest again' },
        { 'n N', 'the next and previous place, in Used by and Built from' },
        { ']c [c', 'the next and previous change, with the diff on' },
        { '<Tab> <S-Tab>', 'Code or Types; from a view aside, back' },
        { 'gu gb gm', 'Used by, Built from, the Map, and back' },
        { '<C-Tab> <C-S-Tab>', 'next and previous display' },
        { 'D', 'the diff on or off, both sides, for the session' },
      },
    },
    {
      'The Map',
      {
        { 'l', "open the call under the cursor a level deeper in the Map's tree, or its ⋯ more; elsewhere show it" },
        { 'h', 'close it again' },
        { '> <', 'a level more or less, everywhere at once' },
        { 'T', 'inputs and outputs, and the choice stays' },
        { 'J', 'the code screen on the name under the cursor' },
      },
    },
    { 'Seam', seam },
  }
end

local function o(buf)
  return { buffer = buf, nowait = true, silent = true }
end

--- `gu` `gb` `gm` and `D` in `buf`, the same on every screen.
---@param buf integer
function M.view_keys(buf)
  for _, k in ipairs(M.ASIDE_KEYS) do
    vim.keymap.set('n', k, M.aside(k), o(buf))
  end
  vim.keymap.set('n', 'D', M.toggle_diff, o(buf))
end

--- The keys of the pane's head and view, on both screens.
---@param buf integer
function M.keys(buf)
  for _, k in ipairs { { '<Tab>', 1 }, { '<S-Tab>', -1 } } do
    vim.keymap.set('n', k[1], M.step(k[2]), o(buf))
  end
  for _, k in ipairs { { '<C-Tab>', 1 }, { '<C-S-Tab>', -1 } } do
    vim.keymap.set('n', k[1], M.step(k[2], true), o(buf))
  end
  M.view_keys(buf)
  vim.keymap.set('n', '+', function()
    opening.plus(M.redraw)
  end, o(buf))
  vim.keymap.set('n', '-', function()
    opening.minus(M.redraw)
  end, o(buf))
  vim.keymap.set('n', 'n', function()
    M.next_place(1)
  end, o(buf))
  vim.keymap.set('n', 'N', function()
    M.next_place(-1)
  end, o(buf))
  vim.keymap.set('n', ']c', function()
    M.next_place(1, 'change')
  end, o(buf))
  vim.keymap.set('n', '[c', function()
    M.next_place(-1, 'change')
  end, o(buf))
  vim.keymap.set('n', '<Esc>', function()
    screen().leave_pane()
  end, o(buf))
  vim.keymap.set('n', 'K', function()
    if st.screen == 'code' then
      require('seam.screen_code').back(vim.v.count1)
    end
  end, o(buf))
  -- the Map's keys; elsewhere l and h move as they do
  local mk = require 'seam.map.keys'
  for _, k in ipairs { 'l', 'h', '>', '<', 'T', 'J' } do
    vim.keymap.set('n', k, function()
      if not mk.key(k) and (k == 'l' or k == 'h') then
        vim.cmd('normal! ' .. vim.v.count1 .. k)
      end
    end, o(buf))
  end
  vim.keymap.set('n', 'L', function()
    require('seam.screen').open_lens()
  end, o(buf))
  vim.keymap.set('n', '?', function()
    require('seam.hints').open(screen().all_keys())
  end, o(buf))
  vim.keymap.set('n', 'q', function()
    require('seam.screen').close()
  end, o(buf))
  require('seam.screen').goto_keys(buf)
end

--- The pane's buffers' autocommands: the line under the cursor lit, the
--- status line following.
---@param aug integer
function M.autocmds(aug)
  for _, b in ipairs { st.obuf.phead, st.obuf.pane } do
    api.nvim_create_autocmd('CursorMoved', {
      group = aug,
      buffer = b,
      callback = function()
        local w = M.wins()
        if w and api.nvim_get_current_win() == w.pane then
          draw.cursor_line(w.pane)
        end
        vim.cmd 'redrawstatus'
      end,
    })
    api.nvim_create_autocmd('WinEnter', {
      group = aug,
      buffer = b,
      callback = function()
        M.flush()
        vim.cmd 'redrawstatus'
      end,
    })
  end
  api.nvim_create_autocmd('WinLeave', {
    group = aug,
    buffer = st.obuf.pane,
    callback = function()
      draw.cursor_clear(st.obuf.pane)
    end,
  })
end

return M
