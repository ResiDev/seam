-- The tree drawn: the head over everything, the rows on the left, and the
-- pane beside them, its head with the tabs over the view shown.
local api = vim.api
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local theme = require 'seam.theme'
local tree = require 'seam.tree'
local views = require 'seam.views'
local M = {}

local row, trunc, shape = draw.row, draw.trunc, draw.shape

-- the tree's width, and where the sorted orders' two counts end
M.LW = 46
local USED_END, CALLS_END = 37, 44
local WORDS = { used = 'most used first', calls = 'most calling first' }

--- What a sorted order is called; nil for the tree.
---@param o seam.Outline
---@return string|nil
function M.order_word(o)
  return WORDS[o.order]
end

local function dir_name(it)
  return table.concat(it.segs or { it.path:match '[^/]+$' }, '/') .. '/'
end

--- A row's name as plain text: `fn()`, `<Component>`, a file's name, a
--- folder's with its slash.
---@param m table
---@param x seam.ORow|nil
---@return string
function M.name(m, x)
  if not x then
    return ''
  elseif x.kind == 'fn' then
    return shape(m.graph.nodes[x.id])
  elseif x.kind == 'file' then
    return x.path:match '[^/]+$'
  end
  return dir_name(x.item)
end

-- a function's name in its shape, coloured as declared; `under` marks the
-- name alone, `dim` all of it
local function fn_name(r, node, room, under, dim)
  local s = shape(node)
  local pre, post = s:match('^(.-)' .. vim.pesc(node.name) .. '(.*)$')
  local at = r.b
  if not pre or api.nvim_strwidth(s) > room then
    r:add(trunc(s, room), 'SeamName')
  else
    r:add(pre, 'SeamPunct')
    local s0 = r.b
    code.add_name(r, node.path, node.line, node.name, 'SeamName', room)
    if under then
      r.h[#r.h + 1] = { s0, r.b, under, 320 }
    end
    r:add(post, 'SeamPunct')
  end
  if dim then
    r.h[#r.h + 1] = { at, r.b, 'SeamDim', 330 }
  end
  return r
end

-- how a call's row marks where it lives
local function call_mark(m, x, node)
  if x.where == 'file' then
    return 'SeamUnder'
  elseif x.where == 'pkg' then
    return theme.hue(index.pkg_of(m, node.path)).under, index.pkg_of(m, node.path)
  end
end

--- The head over the screen: the row under the cursor, or the order.
---@param buf integer
---@param m table
---@param o seam.Outline
---@param x seam.ORow|nil
function M.head(buf, m, o, x)
  local r = row():add(' Seams', 'SeamLabel')
  if WORDS[o.order] then
    r:add('   ' .. WORDS[o.order], 'SeamBold')
  elseif x then
    r:add(' › ', 'SeamLabel'):add(M.name(m, x), 'SeamBold')
  end
  draw.put(buf, { r })
end

--- The tree's bar over its rows: blank in the tree, the counts' titles in
--- a sorted order, the one it sorts by lit.
---@param o seam.Outline
---@return string
function M.titles(o)
  if not WORDS[o.order] then
    return ' '
  end
  local function hl(which)
    return o.order == which and '%#SeamBold#' or '%#SeamLabel#'
  end
  local used, calls = 'used by', 'calls'
  return '%#SeamLabel#' .. string.rep(' ', USED_END - #used) .. hl 'used' .. used .. string.rep(' ', CALLS_END - USED_END - #calls) .. hl 'calls' .. calls
end

-- a row of the tree, saying where it is for gf
local function tree_row(m, x)
  if x.kind == 'fn' then
    local node = m.graph.nodes[x.id]
    return row { at = { path = node.path, line = math.max(1, node.line), name = node.name } }
  end
  return row { kind = x.kind, path = x.path }
end

--- The rows of the tree.
---@param buf integer
---@param m table
---@param o seam.Outline
---@param rows seam.ORow[]
function M.rows(buf, m, o, rows)
  local out = {}
  local flat = WORDS[o.order] ~= nil
  for _, x in ipairs(rows) do
    local r = tree_row(m, x)
    if flat then
      -- the package's bar down the left, on the functions listed
      r:add ' '
      if x.depth == 0 then
        tree.bar(r, index.pkg_of(m, x.path))
      else
        r:add ' '
      end
      r:add ' '
    else
      r:add '  '
    end
    r:add(string.rep('  ', x.depth))
    local room = (flat and USED_END - 6 or M.LW - 1) - r.w
    if x.kind == 'fn' then
      local node = m.graph.nodes[x.id]
      local under, pkg = call_mark(m, x, node)
      if pkg then
        tree.bar(r, pkg)
        room = room - 1
      end
      fn_name(r, node, room, under, x.seen)
      if flat and x.depth == 0 then
        local lit, dim = o.order == 'used' and 'SeamBold' or 'SeamLabel', o.order == 'calls' and 'SeamBold' or 'SeamLabel'
        r:to(USED_END - #tostring(x.used)):add(tostring(x.used), lit)
        r:to(CALLS_END - #tostring(x.calls)):add(tostring(x.calls), dim)
      end
    else
      if x.can_open and not x.open then
        r:add('▸ ', 'SeamText')
        room = room - 2
      end
      if x.kind == 'dir' then
        local hl = not x.can_open and 'SeamDim' or x.item.ispkg and theme.hue(x.item.pkg).bar or 'SeamName'
        r:add(trunc(dir_name(x.item), room), hl)
      else
        r:add(trunc(x.path:match '[^/]+$', room), 'SeamName')
      end
    end
    out[#out + 1] = r
  end
  if #out == 0 then
    out[1] = row():add('  nothing the lens lets through', 'SeamLabel')
  end
  draw.put(buf, out)
end

--- The pane's head: what the row is and where, then the tabs of the views
--- that have something for it, the one shown lit.
---@param buf integer
---@param m table
---@param o seam.Outline
---@param x seam.ORow|nil
---@param sv seam.ViewState
function M.pane_head(buf, m, o, x, sv)
  local h = row():add ' '
  if x and x.kind == 'fn' then
    local node = m.graph.nodes[x.id]
    fn_name(h, node, 60)
    h.h[#h.h + 1] = { 1, h.b, 'SeamBold', 80 }
    h:add('   ' .. node.kind .. ' in ', 'SeamLabel')
    draw.path(h, node.path, math.max(1, node.line))
    if WORDS[o.order] and x.depth == 0 then
      h:add(o.order == 'used' and ('   used by ' .. x.used) or ('   calls ' .. x.calls), 'SeamLabel')
    end
  elseif x and x.kind == 'file' then
    h:add(M.name(m, x), 'SeamBold'):add('   file in ', 'SeamLabel')
    draw.path(h, x.path:match '^(.*/)' or '')
    h:add(', ' .. draw.plural(#outline.functions(m, x.path), 'function'), 'SeamLabel')
  elseif x then
    h:add(M.name(m, x), 'SeamBold'):add('   folder, ' .. draw.plural(outline.files_under(m, outline.full(x.item)), 'file'), 'SeamLabel')
  end
  local t = row():add ' '
  local list = views.of(x)
  local shown, display = views.shown(x, sv)
  draw.tabs(
    t,
    vim.tbl_map(function(v)
      return v.name
    end, list),
    shown and shown.name
  )
  if shown and #shown.displays > 1 then
    t:add('   ' .. display, 'SeamLabel')
  end
  draw.put(buf, { h, row(), t })
end

--- The view shown for the row, in the pane, from its top.
---@param buf integer
---@param win integer|nil
---@param m table
---@param x seam.ORow|nil
---@param sv seam.ViewState
function M.pane(buf, win, m, x, sv)
  local out = {}
  local v, display = views.shown(x, sv)
  if v then
    v.draw(out, x, m, display)
  end
  draw.put(buf, out)
  code.scroll_to(win, 1, 1)
end

return M
