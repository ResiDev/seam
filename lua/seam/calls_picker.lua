-- `/` in the call tree: a float over it to anchor on any function. A prompt
-- line, every function the lens lets through below it, the most used first,
-- narrowed as you type with Neovim's own fuzzy match.
local api = vim.api
local calls = require 'seam.calls'
local calls_draw = require 'seam.draw.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local M = {}

api.nvim_set_hl(0, 'SeamPickMatch', { default = true, bold = true, underline = true })

-- the float's width, the tree's inside its border, where a row's path
-- starts, and the room for its name
local W, PATH_AT, NAME_ROOM = calls_draw.LW - 4, 30, 26
-- the rows above and below the list: the prompt, the used by title; a gap, the keys
local ABOVE, BELOW = 2, 2
M.KEYS = '<CR> anchor   <C-n>/<C-p> next   <Esc> back'

---@class seam.PickerHost
---@field graph fun(): seam.Graph
---@field model fun(): table
---@field over integer the window the float sits over, its top left
---@field rows integer how many rows it may take, its border too
---@field pick fun(id: string) anchor on it
---@field closed fun() it closed, picked or not

local P -- the open picker

local function base(path)
  return path:match '[^/]+$' or path
end

-- a path's folder, cut from the left to `w`
local function folder(path, w)
  local dir = path:match '^(.*/)' or ''
  if api.nvim_strwidth(dir) <= w then
    return dir
  end
  return '…' .. vim.fn.strcharpart(dir, vim.fn.strchars(dir) - w + 1)
end

local function room()
  return math.max(1, P.host.rows - 2 - ABOVE - BELOW)
end

local function draw_rows()
  local g = P.host.graph()
  local list, n = P.list, room()
  P.top = math.max(1, math.min(P.top, P.sel, #list - n + 1))
  if P.sel >= P.top + n then
    P.top = P.sel - n + 1
  end
  local rows = {}
  local count = ('%d of %d functions'):format(#list, #P.all)
  rows[1] = draw.row():to(W - 1 - #count):add(count, 'SeamLabel')
  rows[2] = draw.row():to(W - 1 - 7):add('used by', 'SeamLabel')
  for j = P.top, math.min(#list, P.top + n - 1) do
    local p = list[j]
    local node = g.nodes[p.id]
    local r = draw.row()
    r:add '  '
    local at = r.b + (node.kind == 'component' and 1 or 0)
    calls_draw.name(r, node, 'SeamName', NAME_ROOM)
    for _, c in ipairs(p.pos or {}) do
      local b = at + vim.fn.byteidx(node.name, c)
      if b < r.b then
        r.h[#r.h + 1] = { b, b + 1, 'SeamPickMatch', 200 }
      end
    end
    local used = tostring(p.used_by)
    local line = ':' .. node.line
    local w = W - 1 - #used - 3 - PATH_AT - api.nvim_strwidth(base(node.path)) - #line
    r:to(math.max(PATH_AT, r.w + 2))
    r:add(folder(node.path, math.max(1, w)), 'SeamPath'):add(base(node.path), 'SeamName'):add(line, 'SeamPath')
    r:to(W - 1 - #used):add(used, 'SeamText')
    if j == P.sel then
      r.line_hl = 'CursorLine'
    end
    rows[#rows + 1] = r
  end
  if #list == 0 then
    rows[#rows + 1] = draw.row():add('  nothing by that name', 'SeamLabel')
  end
  rows[#rows + 1] = draw.row()
  rows[#rows + 1] = draw.row():add('  ' .. M.KEYS, 'SeamLabel')
  draw.put(P.buf, rows)
  if api.nvim_win_is_valid(P.win) then
    api.nvim_win_set_config(P.win, { height = #rows })
    code.paint_win(P.win)
  end
end

-- the list for the query typed; TextChangedI waits for the keys typed
-- ahead, so a key that moves or picks asks first
local function filter()
  local q = api.nvim_buf_get_lines(P.input, 0, 1, false)[1] or ''
  if q == P.query then
    return
  end
  P.query = q
  P.list = calls.fuzzy(P.host.graph(), P.all, q)
  P.sel, P.top = 1, 1
  draw_rows()
end

local function move(d)
  filter()
  if #P.list == 0 then
    return
  end
  P.sel = (P.sel - 1 + d) % #P.list + 1
  draw_rows()
end

--- Close it, nothing picked unless `id`.
---@param id? string
function M.close(id)
  if not P then
    return
  end
  local p = P
  P = nil
  vim.cmd 'stopinsert'
  for _, w in ipairs { p.iwin, p.win } do
    if api.nvim_win_is_valid(w) then
      api.nvim_win_close(w, true)
    end
  end
  if api.nvim_win_is_valid(p.host.over) then
    api.nvim_set_current_win(p.host.over)
  end
  if id then
    p.host.pick(id)
  end
  p.host.closed()
end

function M.is_open()
  return P ~= nil
end

--- What it shows, for the specs: the query, the ids listed, the one selected.
---@return { query: string, ids: string[], sel: string|nil }|nil
function M.state()
  if not P then
    return nil
  end
  return {
    query = P.query,
    ids = vim.tbl_map(function(p)
      return p.id
    end, P.list),
    sel = P.list[P.sel] and P.list[P.sel].id,
  }
end

---@param host seam.PickerHost
function M.open(host)
  if P then
    return
  end
  local g, m = host.graph(), host.model()
  local all = calls.callables(g, m)
  P = { host = host, all = all, list = all, sel = 1, top = 1, query = '' }
  P.buf = draw.scratch 'calls-picker'
  vim.bo[P.buf].bufhidden = 'wipe'
  local cfg = { relative = 'win', win = host.over, row = 0, col = 1, width = W, height = 4, zindex = 50 }
  P.win = api.nvim_open_win(P.buf, false, vim.tbl_extend('force', cfg, { border = 'rounded', title = { { ' anchor on ', 'SeamLabel' } }, title_pos = 'left' }))
  local wo = vim.wo[P.win]
  wo.cursorline, wo.wrap, wo.number, wo.relativenumber, wo.signcolumn = false, false, false, false, 'no'
  wo.winhighlight = 'NormalFloat:Normal,FloatBorder:SeamLabel,FloatTitle:SeamLabel'
  draw_rows()

  -- the prompt: a buffer of one line over the float's first, typed in insert mode
  P.input = api.nvim_create_buf(false, true)
  local b = P.input
  vim.bo[b].bufhidden = 'wipe'
  vim.bo[b].filetype = 'seampicker'
  vim.b[b].completion = false
  local count = ('%d of %d functions'):format(#all, #all)
  P.iwin = api.nvim_open_win(b, true, { relative = 'win', win = P.win, row = 0, col = 0, width = W - #count - 3, height = 1, style = 'minimal', zindex = 60 })
  local iwo = vim.wo[P.iwin]
  iwo.winhighlight = 'NormalFloat:Normal'
  iwo.statusline = "%!v:lua.require'seam.screen'.status()"
  -- `> ` before the query, never part of it
  api.nvim_buf_set_extmark(
    b,
    api.nvim_create_namespace 'seam.picker',
    0,
    0,
    { virt_text = { { '> ', 'SeamLabel' } }, virt_text_pos = 'inline', right_gravity = false }
  )

  local o = { buffer = b, nowait = true, silent = true }
  local function map(lhs, fn)
    vim.keymap.set({ 'i', 'n' }, lhs, fn, o)
  end
  map('<C-n>', function()
    move(1)
  end)
  map('<Down>', function()
    move(1)
  end)
  map('<C-p>', function()
    move(-1)
  end)
  map('<Up>', function()
    move(-1)
  end)
  map('<CR>', function()
    filter()
    local p = P.list[P.sel]
    M.close(p and p.id)
  end)
  map('<Esc>', function()
    M.close()
  end)
  map('<C-c>', function()
    M.close()
  end)
  vim.keymap.set('n', 'q', function()
    M.close()
  end, o)
  api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, { buffer = b, callback = filter })
  -- the focus gone elsewhere, a click on the tree say, it closes
  api.nvim_create_autocmd('WinLeave', {
    buffer = b,
    callback = function()
      vim.schedule(function()
        if P and P.input == b and api.nvim_get_current_win() ~= P.iwin then
          M.close()
        end
      end)
    end,
  })
  vim.cmd 'startinsert'
  vim.cmd 'redrawstatus'
end

return M
