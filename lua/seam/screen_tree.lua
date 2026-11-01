-- The tree's screen: the head over everything, the tree on the left, the
-- pane on the right with its head and tabs over the view shown; the keys in
-- each, the status line's hints, and `?`. The windows and helpers it shares
-- are seam.screen's.
local api = vim.api
local changes = require 'seam.changes'
local graph = require 'seam.graph'
local hints = require 'seam.hints'
local index = require 'seam.index'
local odraw = require 'seam.draw.outline'
local outline = require 'seam.outline'
local pane = require 'seam.pane'
local picker = require 'seam.picker'
local signs = require 'seam.signs'
local st = require 'seam.state'
local views = require 'seam.views'
local M = {}

-- seam.screen requires this module, so it is asked for when needed
local function S()
  return require 'seam.screen'
end

--- Are the tree's four windows there?
---@return boolean
function M.valid()
  local w = st.owin
  return w ~= nil and api.nvim_win_is_valid(w.head) and api.nvim_win_is_valid(w.tree) and api.nvim_win_is_valid(w.phead) and api.nvim_win_is_valid(w.pane)
end
local valid = M.valid

--- The row under the tree's cursor, and its index.
---@return seam.ORow|nil, integer|nil
function M.at()
  if not (valid() and st.orows) then
    return nil
  end
  local i = api.nvim_win_get_cursor(st.owin.tree)[1]
  return st.orows[i], i
end

--- What the pane shows: a type picked with `/` until the tree's cursor
--- moves, else the row under the tree's cursor.
---@return seam.ORow|nil
function M.subject()
  if st.ptype then
    return st.ptype.row
  end
  return (M.at())
end
local subject = M.subject

local function layout()
  if st.screen == 'tree' and valid() then
    return
  end
  local s = S()
  st.screen, st.owin = 'tree', nil
  local head = s.reset_tab()
  api.nvim_win_set_buf(head, st.obuf.head)
  local tree = s.split(st.obuf.tree, head, 'below', true)
  local phead = s.split(st.obuf.phead, tree, 'right')
  local pane = s.split(st.obuf.pane, phead, 'below')
  for _, w in ipairs { head, phead, pane } do
    s.winopts(w)
  end
  s.winopts(tree, true)
  s.wrap(pane)
  vim.wo[phead].winfixwidth = false
  vim.wo[pane].winfixwidth = false
  vim.wo[head].winfixheight = true
  vim.wo[phead].winfixheight = true
  -- a rule under the head, across
  for _, w in ipairs { head, tree, phead, pane } do
    vim.wo[w].fillchars = vim.wo[w].fillchars:gsub('horizdown:│', 'horizdown:─')
  end
  vim.wo[head].fillchars = vim.wo[head].fillchars:gsub('horiz: ', 'horiz:─')
  vim.wo[tree].winhighlight = vim.wo[tree].winhighlight .. ',WinBar:SeamLabel,WinBarNC:SeamLabel'
  api.nvim_win_set_width(tree, odraw.LW)
  api.nvim_win_set_height(head, 1)
  api.nvim_win_set_height(phead, 3)
  st.owin = { head = head, tree = tree, phead = phead, pane = pane }
  st.oshown = nil
  api.nvim_set_current_win(tree)
end

-- the cursor moved in the tree: the head and the pane follow the row
local function moved()
  if st.screen ~= 'tree' or st.drawing or not (valid() and st.orows) then
    return
  end
  local x = M.at()
  st.outline.cursor = x and x.key or st.outline.cursor
  st.outline.top = api.nvim_win_call(st.owin.tree, function()
    return vim.fn.line 'w0'
  end)
  if st.ptype and api.nvim_win_get_cursor(st.owin.tree)[1] ~= st.ptype.at then
    st.ptype = nil
  end
  local key = st.ptype and st.ptype.row.key or x and x.key or ''
  if st.oshown ~= key then
    st.oshown = key
    odraw.head(st.obuf.head, index.model(), st.outline, subject())
    pane.show(subject())
    S().paint()
  end
  vim.cmd 'redrawstatus'
end

-- the cursor on the row with `key`, else the first
local function cursor_to(key)
  local i = outline.find(st.orows, key) or 1
  st.drawing = true
  api.nvim_win_set_cursor(st.owin.tree, { i, 0 })
  st.drawing = false
  moved()
end

--- The rows again, the cursor on the row it was on; `keep` the scroll too.
---@param keep? boolean
function M.redraw(keep)
  if not valid() then
    return
  end
  local m, o = index.model(), st.outline
  st.orows = signs.decorate(m, outline.rows(m, o), o.only_changed)
  local w = st.owin.tree
  st.drawing = true
  vim.wo[w].winbar = odraw.titles(o)
  odraw.rows(st.obuf.tree, m, o, st.orows)
  local i = outline.find(st.orows, o.cursor) or 1
  -- from the top while the row is in the first screen, else a third down
  local h = api.nvim_win_get_height(w)
  local top = keep and o.top or (i <= math.floor(h * 2 / 3) and 1 or i - math.floor(h / 3))
  api.nvim_win_call(w, function()
    vim.fn.winrestview { topline = top, lnum = i, col = 0 }
  end)
  st.drawing = false
  st.oshown = nil
  moved()
  S().paint()
end

--- The tree's screen, as it was, or on `target` (a node id or a path)
--- shown where it lives.
---@param target? string
function M.show(target)
  st.outline = st.outline or outline.new()
  st.view = st.view or views.new()
  layout()
  local found = target and outline.reveal(index.model(), st.outline, target)
  M.redraw(not found)
end

--- Show `target`, a node id or a path, where it lives in the tree.
---@param target string
---@return boolean found
function M.reveal(target)
  if not outline.reveal(index.model(), st.outline, target) then
    return false
  end
  M.redraw(false)
  return true
end

local function press(k)
  return function()
    local _, i = M.at()
    local a = outline.key(index.model(), st.outline, st.orows or {}, i or 1, k)
    if a == 'redraw' then
      M.redraw(k ~= 's')
    elseif a == 'move' then
      cursor_to(st.outline.cursor)
    end
  end
end

--- Show the repo type `name` in the pane, its Types view (or `view`), the
--- tree's cursor where it was; the next move of it shows its row again.
---@param name string
---@param view? string
---@return boolean found
function M.show_type(name, view)
  local m = index.model()
  local f = valid() and m.flows and m.flows[name]
  local e = f and f.decls[1]
  if not e then
    return false
  end
  st.ptype = {
    row = { kind = 'type', key = 'type:' .. name, name = name, path = e.path, line = e.line, end_line = e.end_line, decl_kind = e.kind },
    at = api.nvim_win_get_cursor(st.owin.tree)[1],
  }
  if view and require('seam.views').has(st.ptype.row, view) then
    st.view.aside = view
  else
    st.view.at, st.view.aside = view or 'Types', nil
  end
  moved()
  return true
end

--- `gc`: only the rows that changed in the range, and the folders and
--- files above them; again, every row.
function M.only_changed()
  st.outline.only_changed = not st.outline.only_changed or nil
  M.redraw(false)
end

--- `]c` `[c`: the cursor on the next row that changed, or the one before.
---@param d integer
function M.next_change(d)
  local _, i = M.at()
  local j = i
  for _ = 1, vim.v.count1 do
    j = j and signs.next(st.orows or {}, j, d)
  end
  if j then
    st.outline.cursor = st.orows[j].key
    cursor_to(st.outline.cursor)
  end
end

--- `/`: a float over the tree of every function, file and type it holds,
--- the most used first; typing narrows it, fuzzily, and `<CR>` shows the
--- one picked where it lives, a type in the pane. `query` is typed already;
--- `on` puts it over another window, `pick` doing what it says with the
--- id picked (`type:Name`, `file:path`, a node's).
---@param query? string
---@param on? { over: integer, pick: fun(id: string) }
function M.search(query, on)
  if not (on or valid()) then
    return
  end
  local m = index.model()
  local g = m.graph
  local items, nodes = {}, {}
  local top, up = graph.visible(m, 'top'), graph.visible(m, 'up')
  for id, n in pairs(g and g.nodes or {}) do
    if n.kind ~= 'module' and not n.test and top(n.path) then
      items[#items + 1] = { id = id, name = n.name, used_by = outline.used_by(g, id, up) }
      nodes[id] = n
    end
  end
  for path in pairs(outline.files(m)) do
    local id = 'file:' .. path
    local name = path:match '[^/]+$'
    items[#items + 1] = { id = id, name = name, used_by = 0 }
    nodes[id] = { kind = 'module', name = name, path = path, line = 1 }
  end
  for name, f in pairs(m.flows or {}) do
    local e = f.decls[1]
    if e and top(e.path) and not index.is_test(e.path) then
      local id = 'type:' .. name
      items[#items + 1] = { id = id, name = name, used_by = e.nusers or 0 }
      nodes[id] = { kind = 'type', name = name, path = e.path, line = e.line }
    end
  end
  picker.sort(items, nodes)
  picker.open {
    title = 'search',
    noun = 'names',
    keys = '<CR> show it   <C-n>/<C-p> next   <Esc> back',
    over = on and on.over or st.owin.tree,
    col = 1,
    width = picker.W,
    rows = api.nvim_win_get_height(on and on.over or st.owin.tree) + 1,
    items = items,
    query = type(query) == 'string' and query or nil,
    node = function(id)
      return nodes[id]
    end,
    column = 'used by',
    pick = function(p)
      if p and on then
        on.pick(p.id)
      elseif p and st.screen == 'tree' then
        local ty = p.id:match '^type:(.*)$'
        if ty then
          M.show_type(ty)
        else
          M.reveal(p.id:match '^file:(.*)$' or p.id)
        end
      end
    end,
    closed = function()
      local w = on and on.over or valid() and st.owin.tree
      if w and api.nvim_win_is_valid(w) then
        api.nvim_set_current_win(w)
      end
    end,
  }
end

-- every key of the screen, grouped as KEYS.md is, for `?`
function M.all_keys()
  if pane.inside() then
    return pane.all_keys 'tree'
  end
  local seam = { { 'L', 'the lens: what the tree shows' }, { 'gf gd', 'that place in your own code' } }
  if #st.names > 1 then
    seam[#seam + 1] = { 'S', 'the next source' }
  end
  vim.list_extend(seam, { { 'R', 'read the index again' }, { 'q', 'close seam' } })
  return {
    {
      'This row',
      {
        { 'j k', 'move' },
        { 'l', 'open it: a folder, a file, the calls' },
        { 'h', 'close it, or up a level' },
        { 'J', 'the code screen on it: a function or a file' },
      },
    },
    {
      'The pane',
      {
        { '<Tab> <S-Tab>', 'Code or Types; from a view aside, back' },
        { 'gu gb gm', 'Used by, Built from, the Map, and back' },
        { '<C-Tab> <C-S-Tab>', 'next and previous display' },
        { 'D', 'the diff on or off, here and on the code screen, for the session' },
        { 'n N', 'into it, on the next and previous place, in Used by and Built from' },
        { '> <', 'a level more or less, in the Map' },
        { 'T', 'inputs and outputs, in the Map' },
        { '<C-d> <C-u> <M-j> <M-k>', 'scroll it half a screen' },
        { '<C-e> <C-y>', 'scroll it a line' },
      },
    },
    {
      'The tree',
      {
        { 's', 'order: by folder, most used, most calling' },
        { '/', 'search the names' },
        { 'gc', 'only what changed, and back' },
        { ']c [c', 'the next and previous change' },
      },
    },
    { 'Seam', seam },
  }
end

--- `<Esc>` in the pane: back to the tree.
function M.leave_pane()
  if valid() then
    api.nvim_set_current_win(st.owin.tree)
    vim.cmd 'redrawstatus'
  end
end

--- The status line on the tree: the row and its view, or the order, on the
--- left; the keys that act where the cursor is on the right.
---@return string
function M.status()
  local m = index.model()
  local x, i = M.at()
  local px = subject()
  local left = odraw.order_word(st.outline)
  if not left or st.ptype then
    left = odraw.name(m, px)
    local v, d = views.shown(px, st.view)
    if v then
      left = left .. '  ' .. v.name:lower() .. (#views.displays(v, px) > 1 and ' · ' .. d or '') .. require('seam.map.keys').status(pane.inside())
    end
  end
  if st.outline.only_changed then
    left = 'only what changed   ' .. left
  end
  left = pane.said(left)
  local rules = st.lens and #st.lens.rules or 0
  if pane.inside() then
    return hints.status(left, { pane.hints 'tree' }, rules)
  end
  local row, pgroup = {}, pane.view_hints(px)
  -- the Map's levels and types, from the tree too
  local ma = require('seam.map.keys').acts()
  if ma.levels then
    pgroup[#pgroup + 1] = '> <'
  end
  if ma.T then
    pgroup[#pgroup + 1] = 'T'
  end
  if pane.can_diff() then
    pgroup[#pgroup + 1] = 'D'
  end
  if x then
    if x.can_open and not x.open then
      row[#row + 1] = 'l'
    end
    if x.open or outline.parent(st.orows, i) then
      row[#row + 1] = 'h'
    end
    if x.kind == 'fn' or x.kind == 'file' then
      row[#row + 1] = 'J'
    end
    if pane.has_places() then
      row[#row + 1] = 'n N'
    end
  end
  local seam = { 's', '/', 'L', 'q' }
  -- the change keys take the room of the ones every tree has, still in ?
  if changes.any() then
    row = vim.list_extend(
      { ']c [c', 'gc' },
      vim.tbl_filter(function(k)
        return k ~= 'h'
      end, row)
    )
    seam = { 'L', 'q' }
  end
  return hints.status(left, { row, pgroup, seam }, rules)
end

local function o(buf)
  return { buffer = buf, nowait = true, silent = true }
end

local function tree_keys(buf)
  for _, k in ipairs { { '<Tab>', 1 }, { '<S-Tab>', -1 } } do
    vim.keymap.set('n', k[1], pane.step(k[2]), o(buf))
  end
  for _, k in ipairs { { '<C-Tab>', 1 }, { '<C-S-Tab>', -1 } } do
    vim.keymap.set('n', k[1], pane.step(k[2], true), o(buf))
  end
  pane.view_keys(buf)
  vim.keymap.set('n', '?', function()
    hints.open(M.all_keys())
  end, o(buf))
  vim.keymap.set('n', 'q', function()
    S().close()
  end, o(buf))
  S().goto_keys(buf)
  vim.keymap.set('n', 'n', function()
    pane.next_place(1)
  end, o(buf))
  vim.keymap.set('n', 'N', function()
    pane.next_place(-1)
  end, o(buf))
  for _, k in ipairs { 'l', 'h', 's' } do
    vim.keymap.set('n', k, press(k), o(buf))
  end
  for _, k in ipairs { '<C-d>', '<C-u>', '<C-e>', '<C-y>' } do
    vim.keymap.set('n', k, pane.scroll(k), o(buf))
  end
  vim.keymap.set('n', '<M-j>', pane.scroll '<C-d>', o(buf))
  vim.keymap.set('n', '<M-k>', pane.scroll '<C-u>', o(buf))
  vim.keymap.set('n', '/', function()
    M.search()
  end, o(buf))
  vim.keymap.set('n', 'L', function()
    S().open_lens()
  end, o(buf))
  vim.keymap.set('n', 'S', function()
    S().switch()
  end, o(buf))
  vim.keymap.set('n', 'R', function()
    index.load()
    M.redraw(true)
    S().ask_changes()
  end, o(buf))
  vim.keymap.set('n', 'gc', M.only_changed, o(buf))
  for _, k in ipairs { '>', '<', 'T' } do
    vim.keymap.set('n', k, function()
      require('seam.map.keys').key(k)
    end, o(buf))
  end
  vim.keymap.set('n', ']c', function()
    M.next_change(1)
  end, o(buf))
  vim.keymap.set('n', '[c', function()
    M.next_change(-1)
  end, o(buf))
  vim.keymap.set('n', 'J', function()
    local x = M.at()
    if x and x.kind == 'fn' then
      require('seam.screen_code').open { kind = 'fn', id = x.id }
    elseif x and x.kind == 'file' then
      require('seam.screen_code').open { kind = 'file', path = x.path }
    end
  end, o(buf))
  -- nothing above the tree, and no hover from another plugin's K
  vim.keymap.set('n', 'K', '<Nop>', o(buf))
end

--- The tree's buffers, made once, with their keys.
function M.init()
  local s = S()
  st.obuf = {
    head = require('seam.draw').scratch 'seams',
    tree = require('seam.draw').scratch 'tree',
    phead = require('seam.draw').scratch 'pane-head',
    pane = require('seam.draw').scratch 'pane',
  }
  tree_keys(st.obuf.tree)
  pane.keys(st.obuf.phead)
  pane.keys(st.obuf.pane)
  vim.keymap.set('n', 'q', function()
    s.close()
  end, o(st.obuf.head))
  s.goto_keys(st.obuf.head)
  api.nvim_create_autocmd('CursorMoved', { group = s.aug, buffer = st.obuf.tree, callback = moved })
  -- nothing to do in the head: the cursor goes back to the tree, or the code
  api.nvim_create_autocmd('WinEnter', {
    group = s.aug,
    buffer = st.obuf.head,
    callback = function()
      if st.screen == 'tree' and valid() then
        api.nvim_set_current_win(st.owin.tree)
      elseif st.screen == 'code' then
        require('seam.screen_code').to_code()
      end
    end,
  })
  pane.autocmds(s.aug)
  api.nvim_create_autocmd('WinEnter', {
    group = s.aug,
    buffer = st.obuf.tree,
    callback = function()
      vim.cmd 'redrawstatus'
    end,
  })
end

return M
