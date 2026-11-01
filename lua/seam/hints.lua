-- The keys, said where they act: in the status line each key that acts
-- there with its one word, lit, in three groups always in this order (the
-- row, the pane, seam); and `?`, a float of every key on the screen,
-- grouped as KEYS.md is.
local api = vim.api
local draw = require 'seam.draw'
local M = {}

--- Each key's one word, the same on every screen.
M.WORD = {
  l = 'open',
  h = 'close',
  ['+'] = 'open type',
  ['-'] = 'close type',
  J = 'code',
  K = 'back',
  ['<Tab>'] = 'view',
  ['<C-Tab>'] = 'display',
  ['<S-Tab>'] = 'code or types',
  ['<M-j> <M-k>'] = 'scroll',
  s = 'order',
  ['/'] = 'search',
  L = 'lens',
  q = 'close seam',
  ['<Esc>'] = 'tree',
  ['n N'] = 'place',
  [']c [c'] = 'change',
  gc = 'only changed',
  ['> <'] = 'levels',
  T = 'types',
  gu = 'used by',
  gb = 'built from',
  gm = 'map',
  D = 'diff',
}

-- a key and its word: the key's own, or the one given with it
local function said(k)
  if type(k) == 'table' then
    return k[1], k[2]
  end
  return k, M.WORD[k]
end

local GAP, BAR = '   ', '  │  '

local function plain(groups)
  local parts = {}
  for _, g in ipairs(groups) do
    local items = {}
    for _, k in ipairs(g) do
      local key, word = said(k)
      items[#items + 1] = key .. ' ' .. word
    end
    parts[#parts + 1] = table.concat(items, GAP)
  end
  return table.concat(parts, BAR)
end

--- The status line: `left` where you are, then `groups` of keys, those
--- that fit, the last group dropped first; a lens with rules said in its
--- red far right, `L lens 3`, in place of `L lens`.
---@param left string
---@param groups (string|string[])[][] the row's keys, the pane's, seam's: a key, or a key and its word here
---@param rules integer the lens's rules
---@return string
function M.status(left, groups, rules)
  local mark = rules > 0 and ('L lens ' .. rules) or nil
  local gs = {}
  for _, g in ipairs(groups) do
    local keep = vim.tbl_filter(function(k)
      return not (mark and k == 'L')
    end, g)
    if #keep > 0 then
      gs[#gs + 1] = keep
    end
  end
  local room = vim.o.columns - 12 - api.nvim_strwidth(left) - (mark and #mark + 3 or 0)
  while #gs > 1 and api.nvim_strwidth(plain(gs)) > room do
    table.remove(gs)
  end
  while #gs == 1 and #gs[1] > 0 and api.nvim_strwidth(plain(gs)) > room do
    table.remove(gs[1])
  end
  local parts = {}
  for _, g in ipairs(gs) do
    local items = {}
    for _, k in ipairs(g) do
      local key, word = said(k)
      items[#items + 1] = '%#SeamStatusKey#' .. key .. '%#SeamStatusKeyWord# ' .. word
    end
    parts[#parts + 1] = table.concat(items, '%#SeamStatus#' .. GAP)
  end
  local right = table.concat(parts, '%#SeamStatusSep#' .. BAR)
  if mark then
    right = right .. '%#SeamStatus#   %#SeamStatusLens#' .. mark
  end
  return '%#SeamMode# NORMAL %#SeamStatus# ' .. left:gsub('%%', '%%%%') .. '%=' .. right .. '%#SeamStatus# '
end

local H -- the float open: { win, buf, back }

-- close the float, the cursor back where it was unless it went elsewhere
local function shut(back)
  if not H then
    return
  end
  local h = H
  H = nil
  if api.nvim_win_is_valid(h.win) then
    api.nvim_win_close(h.win, true)
  end
  if back and api.nvim_win_is_valid(h.back) then
    api.nvim_set_current_win(h.back)
  end
end

--- Close the float of keys.
function M.close()
  shut(true)
end

function M.is_open()
  return H ~= nil
end

---@alias seam.KeyGroup { [1]: string, [2]: { [1]: string, [2]: string }[] }

--- `?`: a float at the bottom right of every key on the screen, a group a
--- title, each key lit and what it does; `?` `<Esc>` `q` close it.
---@param groups seam.KeyGroup[]
function M.open(groups)
  if H then
    return M.close()
  end
  local kw = 0
  for _, g in ipairs(groups) do
    for _, e in ipairs(g[2]) do
      kw = math.max(kw, api.nvim_strwidth(e[1]))
    end
  end
  kw = kw + 3
  local rows = {}
  for j, g in ipairs(groups) do
    if j > 1 then
      rows[#rows + 1] = draw.row()
    end
    rows[#rows + 1] = draw.row():add(' ' .. g[1], 'SeamBold')
    for _, e in ipairs(g[2]) do
      rows[#rows + 1] = draw.row():add('   '):add(e[1], 'SeamKey'):to(3 + kw):add(e[2], 'SeamText')
    end
  end
  rows[#rows + 1] = draw.row()
  rows[#rows + 1] = draw.row():add(' every key on this screen   ? or <Esc> closes', 'SeamKeyWord')
  local w = 0
  for _, r in ipairs(rows) do
    w = math.max(w, r.w + 1)
  end
  local buf = draw.scratch 'keys'
  vim.bo[buf].bufhidden = 'wipe'
  draw.put(buf, rows)
  local back = api.nvim_get_current_win()
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.max(0, vim.o.lines - 3 - #rows - 2),
    col = math.max(0, vim.o.columns - w - 3),
    width = w,
    height = #rows,
    border = 'rounded',
    zindex = 40,
  })
  local wo = vim.wo[win]
  wo.cursorline, wo.wrap, wo.number, wo.relativenumber, wo.signcolumn = false, false, false, false, 'no'
  wo.winhighlight = 'NormalFloat:Normal,FloatBorder:SeamSep'
  wo.statusline = "%!v:lua.require'seam.screen'.status()"
  H = { win = win, buf = buf, back = back }
  local o = { buffer = buf, nowait = true, silent = true }
  for _, k in ipairs { '?', '<Esc>', 'q' } do
    vim.keymap.set('n', k, M.close, o)
  end
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if H and H.buf == buf then
          shut(false)
        end
      end)
    end,
  })
end

return M
