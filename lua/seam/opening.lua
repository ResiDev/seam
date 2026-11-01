-- `+` and `-` in the pane: which type, or which function's line, the cursor
-- is on in the Types view, and opening or closing it in the set of what is
-- open for the pane's row (st.pctx.open, seam.typesview's keys).
local api = vim.api
local draw = require 'seam.draw'
local st = require 'seam.state'
local tv = require 'seam.typesview'
local M = {}

-- the Types view's row under the cursor in the pane or its head, and the
-- type named under the cursor
local function pane_tv()
  local w = api.nvim_get_current_win()
  if not (st.pctx and st.owin and (w == st.owin.pane or w == st.owin.phead)) then
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

--- What `+` and `-` would open and close where the cursor is, nil where
--- they do nothing.
---@return string|nil open, string|nil close
function M.keys()
  local t, n, head = pane_tv()
  if not t then
    return nil, nil
  end
  return to_open(t, n), to_close(t, head)
end

--- `+`: open it, the pane drawn again by `redraw`; from the head, the cursor
--- to the pane's top, where it opened.
---@param redraw fun()
function M.plus(redraw)
  local _, _, head = pane_tv()
  local k = M.keys()
  if not k then
    return
  end
  st.pctx.open[k] = true
  redraw()
  if head then
    api.nvim_set_current_win(st.owin.pane)
    api.nvim_win_set_cursor(st.owin.pane, { 1, 0 })
  end
end

--- `-`: the block closed, the pane drawn again by `redraw`, the cursor on
--- the line that named it.
---@param redraw fun()
function M.minus(redraw)
  local _, k = M.keys()
  if not k then
    return
  end
  tv.close(st.pctx.open, k)
  redraw()
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

return M
