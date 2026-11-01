-- The tree's screen: the head over everything, the tree on the left, the
-- pane on the right with its head and tabs over the view shown; the keys in
-- each, the status line's hints, and `?`. The windows and helpers it shares
-- are seam.screen's.
local api = vim.api
local draw = require 'seam.draw'
local hints = require 'seam.hints'
local index = require 'seam.index'
local odraw = require 'seam.draw.outline'
local outline = require 'seam.outline'
local picker = require 'seam.picker'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local views = require 'seam.views'
local M = {}

-- seam.screen requires this module, so it is asked for when needed
local function S()
  return require 'seam.screen'
end

local function say(msg)
  api.nvim_echo({ { msg, 'SeamLabel' } }, false, {})
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

-- is the cursor in the pane, its head or its view?
local function in_pane()
  local w = api.nvim_get_current_win()
  return valid() and (w == st.owin.pane or w == st.owin.phead)
end

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

-- what the view is drawn with: the types opened in place for the row, kept
-- by its key as long as seam is open, and the pane's width
local function pane_ctx(x)
  st.opens = st.opens or {}
  local k = x and x.key or ''
  st.opens[k] = st.opens[k] or {}
  st.pctx = {
    open = st.opens[k],
    width = api.nvim_win_get_width(st.owin.pane),
    head = x and x.kind == 'type' and x.name or nil,
  }
  return st.pctx
end

-- the pane for the row: its head and tabs, and the view shown; `keep` where
-- the pane was scrolled
local function show_pane(x, keep)
  local m = index.model()
  odraw.pane_head(st.obuf.phead, m, st.outline, x, st.view)
  odraw.pane(st.obuf.pane, st.owin.pane, m, x, st.view, pane_ctx(x), keep)
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
    odraw.head(st.obuf.head, index.model(), st.outline, x)
    show_pane(subject())
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
  st.orows = outline.rows(m, o)
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

-- the next view or display, or the one before
local function step(d, display)
  return function()
    local x = subject()
    local ok
    if display then
      ok = views.step_display(x, st.view, d)
    else
      ok = views.step(x, st.view, d)
    end
    if ok then
      show_pane(x)
      S().paint()
      vim.cmd 'redrawstatus'
    end
  end
end

-- scroll the pane from the tree, as the key scrolls a window
local function scroll(k)
  return function()
    if not valid() then
      return
    end
    local keys = (vim.v.count > 0 and vim.v.count or '') .. vim.keycode(k)
    api.nvim_win_call(st.owin.pane, function()
      vim.cmd('normal! ' .. keys)
    end)
    S().paint()
  end
end

--- Show the repo type `name` in the pane, its Types view, the tree's
--- cursor where it was; the next move of it shows its row again.
---@param name string
---@return boolean found
function M.show_type(name)
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
  st.view.at = 'Types'
  moved()
  return true
end

--- `/`: a float over the tree of every function, file and type it holds,
--- the most used first; typing narrows it, fuzzily, and `<CR>` shows the
--- one picked where it lives, a type in the pane. `query` is typed already.
---@param query? string
function M.search(query)
  if not valid() then
    return
  end
  local m = index.model()
  local g = m.graph
  local items, nodes = {}, {}
  local top, up = require('seam.calls').visible(m, 'top'), require('seam.calls').visible(m, 'up')
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
    over = st.owin.tree,
    col = 1,
    width = picker.W,
    rows = api.nvim_win_get_height(st.owin.tree) + 1,
    items = items,
    query = type(query) == 'string' and query or nil,
    node = function(id)
      return nodes[id]
    end,
    column = 'used by',
    pick = function(p)
      if p and st.screen == 'tree' then
        local ty = p.id:match '^type:(.*)$'
        if ty then
          M.show_type(ty)
        else
          M.reveal(p.id:match '^file:(.*)$' or p.id)
        end
      end
    end,
    closed = function()
      if valid() then
        api.nvim_set_current_win(st.owin.tree)
      end
    end,
  }
end

-- the bridges to today's screens, until the views replace them
local function page()
  local x = M.at()
  local m = index.model()
  local c = x and x.id and m.byid[x.id]
  if c and (c.nusers or 0) > 0 then
    return S().open_page(c)
  end
  say((x and odraw.name(m, x) or 'this row') .. ' has no page: only exported functions used from another file do')
end

local function contract_of(x)
  local c = x and x.id and index.model().byid[x.id]
  return c and (c.nusers or 0) > 0 and c or nil
end

-- the Types view's row under the cursor in the pane or its head, and the
-- type named under the cursor
local function pane_tv()
  local w = api.nvim_get_current_win()
  if not (in_pane() and st.pctx) then
    return nil
  end
  local cur = api.nvim_win_get_cursor(w)
  local t = draw.meta(api.nvim_win_get_buf(w), cur[1]).tv
  return t, t and tv.at(t.names, cur[2]), w == st.owin.phead
end

-- the block `-` closes where the cursor is: the innermost open around it,
-- or the function opened on its line, or the type the head opened
local function to_close(t, head)
  local open = st.pctx.open
  if head then
    for k, v in pairs(open) do
      if v and k:match '^head|' and not k:match '^head|.*|' then
        return k
      end
    end
  elseif #t.chain > 0 then
    return t.chain[#t.chain]
  elseif t.fn and tv.is_open(open, nil, t.fn) then
    return t.fn
  end
end

-- what `+` opens where the cursor is: the type named under it, or the
-- function on its line as written
local function to_open(t, n)
  local open = st.pctx.open
  if n then
    local k = tv.child(t.key, t.id, n.name)
    return not tv.is_open(open, st.pctx.defaults, k) and k or nil
  elseif t.fn and not tv.is_open(open, nil, t.fn) then
    return t.fn
  end
end

-- `+` and `-`, and whether each acts where the cursor is
local function type_keys()
  local t, n, head = pane_tv()
  if not t then
    return nil, nil
  end
  return to_open(t, n), to_close(t, head)
end

local function redraw_pane()
  show_pane(subject(), true)
  S().paint()
  vim.cmd 'redrawstatus'
end

local function plus()
  local _, _, head = pane_tv()
  local k = type_keys()
  if not k then
    return
  end
  st.pctx.open[k] = true
  redraw_pane()
  if head then
    api.nvim_set_current_win(st.owin.pane)
    api.nvim_win_set_cursor(st.owin.pane, { 1, 0 })
  end
end

-- `-`: the block closed, the cursor on the line that named it
local function minus()
  local _, k = type_keys()
  if not k then
    return
  end
  tv.close(st.pctx.open, k)
  redraw_pane()
  local parent, id = k:match '^(.*)|([^|]*)$'
  local name = id:match ':(.*)$'
  id = id:match '^(.-):' or 'l'
  local w = st.owin.pane
  for i = 1, api.nvim_buf_line_count(st.obuf.pane) do
    local t = draw.meta(st.obuf.pane, i).tv
    if t and t.key == parent and tostring(t.id) == id then
      local col = 0
      for _, x in ipairs(t.names) do
        col = x.name == name and x.s or col
      end
      api.nvim_set_current_win(w)
      api.nvim_win_set_cursor(w, { i, col })
      return
    end
  end
end

-- every key of the screen, grouped as KEYS.md is, for `?`
local function all_keys()
  if in_pane() then
    return {
      {
        'The pane',
        {
          { '+', 'open the type under the cursor, or a function as written' },
          { '-', 'close the one the cursor is in' },
          { '<Tab> <S-Tab>', 'next and previous view' },
          { '<C-Tab> <C-S-Tab>', 'next and previous display' },
        },
      },
      { 'Seam', { { '<Esc>', 'back to the tree' }, { 'gf gd', 'that place in your own code' }, { 'q', 'close seam' } } },
    }
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
        { '<CR>', 'its page, until the views hold it' },
        { 'c', 'its calls, on the Calls screen' },
        { 't', 'its types, on the Types screen' },
      },
    },
    {
      'The pane',
      {
        { '<Tab> <S-Tab>', 'next and previous view' },
        { '<C-Tab> <C-S-Tab>', 'next and previous display' },
        { '<C-d> <C-u>', 'scroll it half a screen' },
        { '<C-e> <C-y>', 'scroll it a line' },
      },
    },
    { 'The tree', { { 's', 'order: by folder, most used, most calling' }, { '/', 'search the names' } } },
    { 'Seam', seam },
  }
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
    local v = views.shown(px, st.view)
    if v then
      left = left .. '  ' .. v.name:lower()
    end
  end
  local row, pane, seam = {}, {}, {}
  local v = views.shown(px, st.view)
  if #views.of(px) > 1 then
    pane[#pane + 1] = '<Tab>'
  end
  if v and #v.displays > 1 then
    pane[#pane + 1] = '<C-Tab>'
  end
  if in_pane() then
    local o, c = type_keys()
    row = { o and '+' or nil, c and '-' or nil }
    row = vim.tbl_values(row)
    table.sort(row, function(a, b)
      return a == '+' and b ~= '+'
    end)
    seam = { '<Esc>', 'q' }
  elseif x then
    if x.can_open and not x.open then
      row[#row + 1] = 'l'
    end
    if x.open or outline.parent(st.orows, i) then
      row[#row + 1] = 'h'
    end
    if contract_of(x) then
      row[#row + 1] = '<CR>'
    end
    if x.kind == 'fn' then
      row[#row + 1] = 'c'
    end
    row[#row + 1] = 't'
    seam = { 's', '/', 'L', 'q' }
  else
    seam = { 's', '/', 'L', 'q' }
  end
  return hints.status(left, { row, pane, seam }, st.lens and #st.lens.rules or 0)
end

local function o(buf)
  return { buffer = buf, nowait = true, silent = true }
end

-- the keys of the pane's head and view, and the tree's own on the tree
local function shared_keys(buf)
  for _, k in ipairs { { '<Tab>', 1 }, { '<S-Tab>', -1 } } do
    vim.keymap.set('n', k[1], step(k[2]), o(buf))
  end
  for _, k in ipairs { { '<C-Tab>', 1 }, { '<C-S-Tab>', -1 } } do
    vim.keymap.set('n', k[1], step(k[2], true), o(buf))
  end
  vim.keymap.set('n', '?', function()
    hints.open(all_keys())
  end, o(buf))
  vim.keymap.set('n', 'q', function()
    S().close()
  end, o(buf))
  S().goto_keys(buf)
end

local function tree_keys(buf)
  shared_keys(buf)
  for _, k in ipairs { 'l', 'h', 's' } do
    vim.keymap.set('n', k, press(k), o(buf))
  end
  for _, k in ipairs { '<C-d>', '<C-u>', '<C-e>', '<C-y>' } do
    vim.keymap.set('n', k, scroll(k), o(buf))
  end
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
  end, o(buf))
  vim.keymap.set('n', '<CR>', page, o(buf))
  vim.keymap.set('n', 'c', function()
    local x = M.at()
    if x and x.kind == 'fn' then
      S().open_calls(x.id)
    end
  end, o(buf))
  vim.keymap.set('n', 't', function()
    local x = M.at()
    if x and x.kind == 'fn' then
      S().its_types(x.id, nil, st.owin.tree)
    else
      S().open_types(nil)
    end
  end, o(buf))
  -- nothing above the tree, and no hover from another plugin's K; J waits for the code screen
  vim.keymap.set('n', 'K', '<Nop>', o(buf))
  vim.keymap.set('n', 'J', '<Nop>', o(buf))
end

local function pane_keys(buf)
  shared_keys(buf)
  vim.keymap.set('n', '+', plus, o(buf))
  vim.keymap.set('n', '-', minus, o(buf))
  vim.keymap.set('n', '<Esc>', function()
    if valid() then
      api.nvim_set_current_win(st.owin.tree)
      vim.cmd 'redrawstatus'
    end
  end, o(buf))
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
  pane_keys(st.obuf.phead)
  pane_keys(st.obuf.pane)
  vim.keymap.set('n', 'q', function()
    s.close()
  end, o(st.obuf.head))
  s.goto_keys(st.obuf.head)
  api.nvim_create_autocmd('CursorMoved', { group = s.aug, buffer = st.obuf.tree, callback = moved })
  -- nothing to do in the head: the cursor goes back to the tree
  api.nvim_create_autocmd('WinEnter', {
    group = s.aug,
    buffer = st.obuf.head,
    callback = function()
      if st.screen == 'tree' and valid() then
        api.nvim_set_current_win(st.owin.tree)
      end
    end,
  })
  for _, b in ipairs { st.obuf.phead, st.obuf.pane } do
    api.nvim_create_autocmd('CursorMoved', {
      group = s.aug,
      buffer = b,
      callback = function()
        vim.cmd 'redrawstatus'
      end,
    })
  end
  for _, b in ipairs { st.obuf.phead, st.obuf.pane, st.obuf.tree } do
    api.nvim_create_autocmd('WinEnter', {
      group = s.aug,
      buffer = b,
      callback = function()
        vim.cmd 'redrawstatus'
      end,
    })
  end
end

return M
