-- The view you came from (a prototype): the buffer seam was last arrived at
-- from, a thread's page or your own code, shown itself in the pane with
-- its own keys and options; seam draws nothing into it. One at a time.
local api = vim.api
local st = require 'seam.state'
local M = {}

M.NAME = 'held'

local aug = api.nvim_create_augroup('seam.held', { clear = true })

---@class seam.Held
---@field buf integer
---@field view table|nil where its window was at the hold, for the first time it is shown

--- The buffer held, while it is there.
---@return integer|nil
function M.buf()
  local h = st.held
  return h and api.nvim_buf_is_valid(h.buf) and h.buf or nil
end

--- Its name in the head: what the buffer calls itself, else its file.
---@return string|nil
function M.label()
  local b = M.buf()
  if not b then
    return nil
  end
  local n = vim.b[b].seam_name
  if type(n) == 'string' and n ~= '' then
    return n
  end
  local file = api.nvim_buf_get_name(b)
  return file ~= '' and vim.fs.basename(file) or 'buffer'
end

--- Hold `buf`, where its window shows it now; nil lets go.
---@param buf integer|nil
function M.hold(buf)
  api.nvim_clear_autocmds { group = aug }
  if buf == 0 then
    buf = api.nvim_get_current_buf()
  end
  if not (buf and api.nvim_buf_is_valid(buf)) then
    st.held = nil
    return
  end
  local win = api.nvim_get_current_buf() == buf and api.nvim_get_current_win() or vim.fn.win_findbuf(buf)[1]
  st.held = { buf = buf, view = win and api.nvim_win_call(win, vim.fn.winsaveview) or nil }
  api.nvim_create_autocmd('BufWipeout', {
    group = aug,
    buffer = buf,
    once = true,
    callback = function()
      st.held = nil
      vim.schedule(M.gone)
    end,
  })
end

local later = api.nvim_create_augroup('seam.held.later', { clear = true })

--- The buffer held wiped: its tab gone. Shown in the pane, Neovim closed
--- the pane's window with it, before any autocommand: the screen is laid
--- out again, when seam's tab is next shown if it is not now.
function M.gone()
  if not (st.tab and api.nvim_tabpage_is_valid(st.tab)) then
    return
  end
  if require('seam.pane').wins() then
    return require('seam.pane').redraw()
  end
  if api.nvim_get_current_tabpage() ~= st.tab then
    api.nvim_create_autocmd('TabEnter', { group = later, once = true, callback = vim.schedule_wrap(M.gone) })
  elseif st.screen == 'code' then
    require('seam.screen_code').redraw()
  else
    require('seam.screen_tree').show()
  end
end

-- While the cursor is in the pane on the buffer held, <Tab> and <S-Tab>
-- step seam's views as on its own pane; the buffer's own maps of them (a
-- thread page folds on <Tab>) come back when the cursor leaves.
local KEYS = { ['<Tab>'] = { 1 }, ['<S-Tab>'] = { 1, true } }
local keys = api.nvim_create_augroup('seam.held.keys', { clear = true })
---@type { buf: integer, maps: table<string, table|false> }|nil
local taken

local function give_back()
  local t = taken
  taken = nil
  if not (t and api.nvim_buf_is_valid(t.buf)) then
    return
  end
  for lhs, m in pairs(t.maps) do
    pcall(vim.keymap.del, 'n', lhs, { buffer = t.buf })
    if m then
      api.nvim_buf_call(t.buf, function()
        vim.fn.mapset(m)
      end)
    end
  end
end

---@param win integer
local function take(win)
  local buf = api.nvim_win_get_buf(win)
  if taken and taken.buf == buf then
    return
  end
  give_back()
  local pane = require 'seam.pane'
  taken = { buf = buf, maps = {} }
  api.nvim_buf_call(buf, function()
    for lhs, a in pairs(KEYS) do
      local m = vim.fn.maparg(lhs, 'n', false, true)
      taken.maps[lhs] = m.buffer == 1 and m or false
      vim.keymap.set('n', lhs, pane.step(a[1], a[2]), { buffer = buf, nowait = true, desc = 'seam: the next view' })
    end
  end)
end

--- The pane's window `win` showing the buffer held, where it was the first
--- time after a hold, where it was left after that.
---@param win integer
function M.show(win)
  local h = assert(st.held)
  if api.nvim_win_get_buf(win) ~= h.buf then
    api.nvim_win_set_buf(win, h.buf)
  end
  -- seam's line under it, not the buffer's own ([Scratch] [-] for a
  -- thread's page): set for this buffer in this window only
  vim.wo[win][0].statusline = "%!v:lua.require'seam.screen'.status()"
  api.nvim_clear_autocmds { group = keys }
  api.nvim_create_autocmd('WinEnter', {
    group = keys,
    callback = function()
      if api.nvim_get_current_win() == win and api.nvim_win_get_buf(win) == M.buf() then
        take(win)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, { group = keys, callback = give_back })
  if api.nvim_get_current_win() == win then
    take(win)
  end
  if h.view then
    api.nvim_win_call(win, function()
      vim.fn.winrestview(h.view)
    end)
    h.view = nil
  end
end

--- Does the pane's window `win` show something not seam's?
---@param win integer
---@return boolean
function M.shown(win)
  return api.nvim_win_get_buf(win) ~= st.obuf.pane
end

--- The pane's window `win` given back its own buffer.
---@param win integer
function M.hide(win)
  api.nvim_clear_autocmds { group = keys }
  give_back()
  if M.shown(win) then
    api.nvim_win_set_buf(win, st.obuf.pane)
  end
end

return M
