-- The pane on the right of every screen: its head with the tabs over the
-- view shown, for what the screen says it is about; the keys in it, and
-- those that reach it from the left: the next view or display, scrolling
-- it, n and N from place to place, + and -.
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
  local w = M.wins()
  if not w then
    return
  end
  local m = index.model()
  odraw.pane_head(st.obuf.phead, m, st.outline, x, st.view)
  odraw.pane(st.obuf.pane, w.pane, m, x, st.view, ctx(x, w), keep)
end

--- The pane drawn again for what it shows, where it was scrolled.
function M.redraw()
  M.show(M.subject(), true)
  require('seam.screen').paint()
  vim.cmd 'redrawstatus'
end

--- `<Tab>` `<S-Tab>`, or with `display` `<C-Tab>` `<C-S-Tab>`: the pane's
--- next view or display, or the one before.
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
      ok = views.step(x, st.view, d)
    end
    if ok then
      M.show(x)
      require('seam.screen').paint()
      vim.cmd 'redrawstatus'
    end
  end
end

--- Scroll the pane from the left, as the key scrolls a window.
---@param k string
---@return fun()
function M.scroll(k)
  return function()
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

--- The pane's stops for n and N: the places Used by and Built from show.
---@return integer[]
function M.stops()
  local out = {}
  if not M.wins() then
    return out
  end
  for i = 1, api.nvim_buf_line_count(st.obuf.pane) do
    if draw.meta(st.obuf.pane, i).place then
      out[#out + 1] = i
    end
  end
  return out
end

--- `n` `N`: the cursor to the next place in the pane, or the one before,
--- round the ends; from the left, into the pane.
---@param d integer
function M.next_place(d)
  local list = M.stops()
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
  local row, pane = {}, {}
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
  local v = views.shown(x, st.view)
  if #views.of(x) > 1 then
    pane[#pane + 1] = '<Tab>'
  end
  if v and #v.displays > 1 then
    pane[#pane + 1] = '<C-Tab>'
  end
  local seam = { { '<Esc>', back } }
  if st.screen == 'code' then
    seam[#seam + 1] = 'K'
  end
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
  vim.list_extend(seam, { { 'gf gd', 'that place in your own code' }, { 'q', 'close seam' } })
  return {
    {
      'The pane',
      {
        { '+', 'open the type under the cursor, or a function as written; on ⋯ N more, the rest' },
        { '-', 'close the one the cursor is in; on a place it showed, hide the rest again' },
        { 'n N', 'the next and previous place, in Used by and Built from' },
        { '<Tab> <S-Tab>', 'next and previous view' },
        { '<C-Tab> <C-S-Tab>', 'next and previous display' },
      },
    },
    { 'Seam', seam },
  }
end

local function o(buf)
  return { buffer = buf, nowait = true, silent = true }
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
  vim.keymap.set('n', '<Esc>', function()
    screen().leave_pane()
  end, o(buf))
  vim.keymap.set('n', 'K', function()
    if st.screen == 'code' then
      require('seam.screen_code').back(vim.v.count1)
    end
  end, o(buf))
  vim.keymap.set('n', 'J', '<Nop>', o(buf))
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
