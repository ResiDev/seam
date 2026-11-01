-- `/` on every screen: one float, a prompt `> query` with how many of how
-- many on its right, and a list under it of every candidate the lens lets
-- through, the most used first, narrowed as you type with Neovim's own
-- fuzzy match.
local api = vim.api
local code = require 'seam.code'
local draw = require 'seam.draw'
local M = {}

api.nvim_set_hl(0, 'SeamPickMatch', { default = true, bold = true, underline = true })

---------------------------------------------------------------- what it lists

---@class seam.Pick
---@field id string
---@field name string what typing matches
---@field used_by integer
---@field pos integer[]|nil the name's matched characters, 0-based, when a query matched it

local function by_use(nodes)
  return function(a, b)
    if a.used_by ~= b.used_by then
      return a.used_by > b.used_by
    end
    local na, nb = nodes[a.id], nodes[b.id]
    if na.name ~= nb.name then
      return na.name < nb.name
    end
    if na.path ~= nb.path then
      return na.path < nb.path
    end
    return na.line < nb.line
  end
end

--- Sort picks the most used first, then by name, then where; `nodes` by id
--- give the name, path and line.
---@param picks seam.Pick[]
---@param nodes table<string, table>
---@return seam.Pick[]
function M.sort(picks, nodes)
  table.sort(picks, by_use(nodes))
  return picks
end

--- The picks whose name `query` fuzzily matches, the best match first and
--- the order they came in between equal ones, each with the characters it
--- matched. An empty query keeps them all, as they came.
---@param picks seam.Pick[]
---@param query string
---@return seam.Pick[]
function M.fuzzy(picks, query)
  query = vim.trim(query)
  if query == '' then
    return picks
  end
  local names = {}
  for i, p in ipairs(picks) do
    names[i] = { i = i, text = p.name }
  end
  local got = vim.fn.matchfuzzypos(names, query, { key = 'text' })
  local out = {}
  for j, x in ipairs(got[1]) do
    out[j] = { i = x.i, score = got[3][j], pos = got[2][j] }
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.i < b.i
  end)
  for j, x in ipairs(out) do
    out[j] = vim.tbl_extend('force', picks[x.i], { pos = x.pos })
  end
  return out
end

---------------------------------------------------------------- the float

-- a list's width, where a row's path starts, and the room for its name
M.W = 82
local PATH_AT, NAME_ROOM = 30, 26
-- the rows above and below the list: the prompt, the column title; a gap, the keys
local ABOVE, BELOW = 2, 2

---@class seam.PickerSpec
---@field title string over the float, and the status line's left
---@field noun string what it counts: `5 of 382 functions`
---@field keys string the status line's right, and the list's last row
---@field over integer the window the float sits over, its top left
---@field focus? integer the window the cursor goes back to, `over` if not given
---@field col? integer from the left of `over`
---@field width integer inside the border
---@field rows? integer how many rows a list may take, its border too
---@field query? string typed already
---@field items seam.Pick[] the list under the prompt: these, narrowed fuzzily
---@field node fun(id: string): table a pick's name, kind, path and line
---@field column? string the title over the count at a row's end
---@field row? fun(p: seam.Pick, width: integer): table a pick's row drawn another way than a name's
---@field zindex? integer over another float
---@field pick fun(p: seam.Pick|nil, query: string) <CR>
---@field closed? fun() it closed, picked or not

local P -- the open picker

local function base(path)
  return path:match '[^/]+$' or path
end

-- a node's name in the shape of its kind, coloured as its declaration is
local function name(r, node, hl, room)
  if node.kind == 'module' then
    return r:add(draw.trunc(base(node.path), room), hl)
  end
  local s = draw.shape(node)
  local pre, post = s:match('^(.-)' .. vim.pesc(node.name) .. '(.*)$')
  if not pre or api.nvim_strwidth(s) > room then
    return r:add(draw.trunc(s, room), hl)
  end
  r:add(pre, hl)
  code.add_name(r, node.path, node.line, node.name, hl, room)
  return r:add(post, hl)
end

-- a path's folder, cut from the left to `w`
local function folder(path, w)
  local dir = path:match '^(.*/)' or ''
  if api.nvim_strwidth(dir) <= w then
    return dir
  end
  return '…' .. vim.fn.strcharpart(dir, vim.fn.strchars(dir) - w + 1)
end

local function count_text(n)
  return ('%d of %d %s'):format(n, P.total, P.spec.noun)
end

local function room()
  return math.max(1, (P.spec.rows or 10) - 2 - ABOVE - BELOW)
end

-- a pick's row: its name as the trees draw it, the letters
-- matched underlined, then where it is, then its count
local function pick_row(p, W)
  local node = P.spec.node(p.id)
  local r = draw.row()
  r:add '  '
  local at = r.b + (node.kind == 'component' and 1 or 0)
  name(r, node, 'SeamName', NAME_ROOM)
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
  return r
end

local function draw_rows()
  local W, spec = P.spec.width, P.spec
  local rows = {}
  local count = count_text(P.n)
  rows[1] = draw.row():to(W - 1 - api.nvim_strwidth(count)):add(count, 'SeamLabel')
  local list, n = P.list, room()
  P.top = math.max(1, math.min(P.top, P.sel, #list - n + 1))
  if P.sel >= P.top + n then
    P.top = P.sel - n + 1
  end
  local col = spec.column or ''
  rows[2] = draw.row():to(W - 1 - api.nvim_strwidth(col)):add(col, 'SeamLabel')
  for j = P.top, math.min(#list, P.top + n - 1) do
    local r = spec.row and spec.row(list[j], W) or pick_row(list[j], W)
    if j == P.sel then
      r.line_hl = 'CursorLine'
    end
    rows[#rows + 1] = r
  end
  if #list == 0 then
    rows[#rows + 1] = draw.row():add('  nothing by that name', 'SeamLabel')
  end
  rows[#rows + 1] = draw.row()
  rows[#rows + 1] = draw.row():add('  ' .. spec.keys, 'SeamLabel')
  draw.put(P.buf, rows)
  if api.nvim_win_is_valid(P.win) then
    api.nvim_win_set_config(P.win, { height = #rows })
    code.paint_win(P.win)
  end
end

-- the query typed changed: narrow; TextChangedI waits for the keys typed
-- ahead, so a key that moves or picks asks first
local function filter()
  local q = api.nvim_buf_get_lines(P.input, 0, 1, false)[1] or ''
  if q == P.query then
    return
  end
  P.query = q
  P.list = M.fuzzy(P.all, q)
  P.n, P.sel, P.top = #P.list, 1, 1
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

-- close it, then pick or cancel
local function close(how)
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
  local back = p.spec.focus or p.spec.over
  if api.nvim_win_is_valid(back) then
    api.nvim_set_current_win(back)
  end
  if how == 'pick' then
    p.spec.pick(p.list[p.sel], p.query)
  end
  if p.spec.closed then
    p.spec.closed()
  end
  vim.cmd 'redrawstatus'
end

--- Close it, nothing picked.
function M.close()
  close()
end

function M.is_open()
  return P ~= nil
end

--- The status line while it is open: its title, its keys.
---@return string|nil left, string|nil right
function M.status()
  if P then
    return P.spec.title, P.spec.keys
  end
end

--- What it shows, for the specs: the query, the ids listed, the one selected.
---@return { query: string, n: integer, ids: string[]|nil, sel: string|nil }|nil
function M.state()
  if not P then
    return nil
  end
  return {
    query = P.query,
    n = P.n,
    ids = vim.tbl_map(function(p)
      return p.id
    end, P.list),
    sel = P.list[P.sel] and P.list[P.sel].id,
  }
end

---@param spec seam.PickerSpec
function M.open(spec)
  if P then
    return
  end
  local q = spec.query or ''
  P = { spec = spec, query = q, sel = 1, top = 1, all = spec.items, total = #spec.items }
  P.list = M.fuzzy(P.all, q)
  P.n = #P.list
  local W = spec.width
  P.buf = draw.scratch 'picker'
  vim.bo[P.buf].bufhidden = 'wipe'
  local z = spec.zindex or 50
  local cfg = { relative = 'win', win = spec.over, row = 0, col = spec.col or 0, width = W, height = 1, zindex = z }
  P.win = api.nvim_open_win(
    P.buf,
    false,
    vim.tbl_extend('force', cfg, { border = 'rounded', title = { { ' ' .. spec.title .. ' ', 'SeamLabel' } }, title_pos = 'left' })
  )
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
  api.nvim_buf_set_lines(b, 0, -1, false, { q })
  local widest = api.nvim_strwidth(count_text(P.total))
  P.iwin =
    api.nvim_open_win(b, true, { relative = 'win', win = P.win, row = 0, col = 0, width = W - widest - 3, height = 1, style = 'minimal', zindex = z + 10 })
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
  for lhs, d in pairs { ['<C-n>'] = 1, ['<Down>'] = 1, ['<C-p>'] = -1, ['<Up>'] = -1 } do
    map(lhs, function()
      move(d)
    end)
  end
  map('<CR>', function()
    filter()
    close 'pick'
  end)
  map('<Esc>', M.close)
  map('<C-c>', M.close)
  vim.keymap.set('n', 'q', M.close, o)
  api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, { buffer = b, callback = filter })
  -- the focus gone elsewhere, a click on the screen say, it closes
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
  vim.cmd 'startinsert!'
  vim.cmd 'redrawstatus'
end

return M
