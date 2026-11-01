-- `+` and `-`: which type, or which function's line, the cursor is on in
-- the pane's Types view or the code's types display, and opening or closing
-- it in the set of what is open there (seam.typesview's keys: st.pctx.open
-- for the pane's row, st.cctx.open for the code); in Used by and Built
-- from, a group's places past four, shown and hidden again.
local api = vim.api
local draw = require 'seam.draw'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local M = {}

-- where the cursor is, when it is somewhere + and - act: its window and
-- buffer, what is open there, and whether it is the pane's head
local function here()
  local w = api.nvim_get_current_win()
  local p = require('seam.pane').wins()
  if st.pctx and p and (w == p.pane or w == p.phead) then
    return { win = w, buf = api.nvim_win_get_buf(w), ctx = st.pctx, head = w == p.phead, pane = p.pane }
  end
  local c = st.screen == 'code' and st.cwin
  if st.cctx and c and w == c.code then
    return { win = w, buf = api.nvim_win_get_buf(w), ctx = st.cctx, pane = w }
  end
end

-- the Types view's row under the cursor, and the type named under it
local function at_tv(h)
  local cur = api.nvim_win_get_cursor(h.win)
  local t = draw.meta(h.buf, cur[1]).tv
  return t, t and tv.at(t.names, cur[2])
end

-- the block `-` closes where the cursor is: the innermost open around it,
-- or the function opened on its line, or the type the head opened
local function to_close(h, t)
  local open = h.ctx.open
  if h.head then
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
local function to_open(h, t, n)
  local open = h.ctx.open
  if n then
    local k = tv.child(t.key, t.id, n.name)
    return not tv.is_open(open, h.ctx.defaults, k) and k or nil
  elseif t.fn and not tv.is_open(open, nil, t.fn) then
    return t.fn
  end
end

--- Is the key one of a group's places past four, not a type?
---@param k string|nil
---@return boolean
function M.is_more(k)
  return k ~= nil and k:match '^more:' ~= nil
end

--- What `+` and `-` would open and close where the cursor is, nil where
--- they do nothing.
---@return string|nil open, string|nil close
function M.keys()
  local h = here()
  if not h then
    return nil, nil
  end
  local meta = not h.head and draw.meta(h.buf, api.nvim_win_get_cursor(h.win)[1]) or {}
  if meta.more or meta.less then
    return meta.more, meta.less
  end
  local t, n = at_tv(h)
  if not t then
    return nil, nil
  end
  return to_open(h, t, n), to_close(h, t)
end

--- `+`: open it, drawn again by `redraw`; from the head, the cursor to the
--- pane's top, where it opened.
---@param redraw fun()
function M.plus(redraw)
  local h = here()
  local k = M.keys()
  if not k then
    return
  end
  h.ctx.open[k] = true
  redraw()
  if h.head then
    api.nvim_set_current_win(h.pane)
    api.nvim_win_set_cursor(h.pane, { 1, 0 })
  end
end

--- `-`: the block closed, drawn again by `redraw`, the cursor on the line
--- that named it.
---@param redraw fun()
function M.minus(redraw)
  local h = here()
  local _, k = M.keys()
  if not k then
    return
  end
  tv.close(h.ctx.open, k)
  redraw()
  local w = h.pane
  local buf = api.nvim_win_get_buf(w)
  if M.is_more(k) then
    for i = 1, api.nvim_buf_line_count(buf) do
      if draw.meta(buf, i).more == k then
        api.nvim_win_set_cursor(w, { i, 0 })
        return
      end
    end
    return
  end
  local parent, id = k:match '^(.*)|([^|]*)$'
  local name = id:match ':(.*)$'
  id = id:match '^(.-):' or 'l'
  for i = 1, api.nvim_buf_line_count(buf) do
    local t = draw.meta(buf, i).tv
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

return M
