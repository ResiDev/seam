-- The tree drawn: the head over everything, the rows on the left, and the
-- pane beside them, its head with the tabs over the view shown.
local api = vim.api
local changes = require 'seam.changes'
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local outline = require 'seam.outline'
local signs = require 'seam.signs'
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
  elseif x.kind == 'type' then
    return x.name
  elseif x.kind == 'name' then
    return (x.n.object and (x.n.object .. '.') or '') .. x.n.name
  elseif x.kind == 'gone' then
    return x.file and x.name or (x.name .. (x.decl.kind == 'fn' and '()' or ''))
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

--- The range of changes on a head, when it is not from HEAD to the working tree.
---@param r table a row
---@return table r
function M.range(r)
  local g = changes.range()
  if not changes.is_default(g) then
    r:add('   changes ', 'SeamLabel'):add(g.from, 'SeamRange'):add(' → ', 'SeamLabel'):add('now', 'SeamRange')
  end
  return r
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
    if x.kind == 'type' then
      r:add(' › ', 'SeamLabel'):add(x.path:match '[^/]+$', 'SeamBold')
    end
    r:add(' › ', 'SeamLabel'):add(M.name(m, x), 'SeamBold')
  end
  draw.put(buf, { M.range(r) })
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
  elseif x.kind == 'type' then
    return row { at = { path = x.path, line = x.line, name = x.name } }
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
  local sorted = WORDS[o.order] ~= nil
  local lit, dim = o.order == 'used' and 'SeamBold' or 'SeamLabel', o.order == 'calls' and 'SeamBold' or 'SeamLabel'
  for _, x in ipairs(rows) do
    local r = tree_row(m, x)
    -- the range's sign in the left column
    r:add(x.sign or ' ', x.sign and signs.HL[x.sign])
    r:add ' '
    r:add(string.rep('  ', x.depth))
    local room = (sorted and USED_END - 6 or M.LW - 1) - r.w
    if x.kind == 'fn' then
      local node = m.graph.nodes[x.id]
      local under, pkg = call_mark(m, x, node)
      if pkg then
        tree.bar(r, pkg)
        room = room - 1
      end
      fn_name(r, node, room, under, x.seen)
    elseif x.kind == 'gone' then
      r:add(trunc(M.name(m, x), room), 'SeamGone')
    elseif x.kind == 'type' then
      code.add_name(r, x.path, x.line, x.name, 'SeamType', room)
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
    if sorted and x.used then
      r:to(USED_END - #tostring(x.used)):add(tostring(x.used), lit)
      r:to(CALLS_END - #tostring(x.calls)):add(tostring(x.calls), dim)
    end
    out[#out + 1] = r
  end
  if #out == 0 then
    out[1] = row():add(
      o.only_changed and '  nothing changed from ' .. changes.range().from .. ' to the working tree' or '  nothing the lens lets through',
      'SeamLabel'
    )
  end
  draw.put(buf, out)
end

--- A name in the code as the pane's head says it: the name, a field's or
--- method's with what it is read from, then what it is and where.
---@param h table a row
---@param n seam.Name
function M.name_head(h, n)
  local s0 = h.b
  if n.object then
    h:add(n.object, 'SeamName'):add('.', 'SeamPunct')
    h:add(n.name, n.kind == 'method' and '@function.method.call' or '@property')
  else
    h:add(n.name, 'SeamName')
  end
  h.h[#h.h + 1] = { s0, h.b, 'SeamBold', 80 }
  local function used()
    if (n.count or 0) > 0 then
      h:add('   used ' .. draw.plural(n.count, 'time'), 'SeamLabel')
    end
  end
  if n.kind == 'value' then
    h:add(n.made_by and ('   made by ' .. n.made_by.name .. ', line ' .. n.at.line) or ('   made at line ' .. n.at.line), 'SeamLabel')
    used()
  elseif n.kind == 'param' then
    h:add('   parameter' .. (n.fn and (' of ' .. n.fn) or '') .. ', line ' .. n.at.line, 'SeamLabel')
    used()
  elseif n.member and n.member.decl then
    -- the path inside its package, the head being narrow
    local p = n.member.decl.path
    local pkg = index.pkg_of(index.model(), p)
    p = (pkg ~= '.' and p:sub(#pkg + 2) or p):gsub('^src/', '')
    h:add('   ' .. (n.kind == 'method' and 'member' or 'field') .. ' of ' .. n.member.decl.name .. ', ', 'SeamLabel')
    h:add(p .. ':' .. n.member.line, 'SeamPath')
  end
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
  local shown, display = views.shown(x, sv)
  -- what the view counts of the row, in place of what the row says of itself
  local count = shown and shown.count and shown.count(m, x)
  if x and x.kind == 'fn' then
    local node = m.graph.nodes[x.id]
    fn_name(h, node, 60)
    h.h[#h.h + 1] = { 1, h.b, 'SeamBold', 80 }
    h:add('   ' .. node.kind .. ' in ', 'SeamLabel')
    draw.path(h, node.path, math.max(1, node.line))
    if x.note then
      h:add('   ' .. x.note, 'SeamLabel')
    end
    if count then
      h:add('   ' .. count, 'SeamLabel')
    elseif WORDS[o.order] and x.used then
      h:add(o.order == 'used' and ('   used by ' .. x.used) or ('   calls ' .. x.calls), 'SeamLabel')
    end
  elseif x and x.kind == 'file' then
    h:add(M.name(m, x), 'SeamBold'):add('   file in ', 'SeamLabel')
    draw.path(h, x.path:match '^(.*/)' or '')
    h:add(count and ('   ' .. count) or (', ' .. draw.plural(#outline.functions(m, x.path), 'function')), 'SeamLabel')
  elseif x and x.kind == 'type' then
    local s0 = h.b
    code.add_name(h, x.path, x.line, x.name, 'SeamTypeBold', 60)
    h.h[#h.h + 1] = { s0, h.b, 'SeamBold', 80 }
    h.meta.tv = { key = 'head', id = 1, names = { { s = s0, e = h.b, name = x.name } }, chain = {} }
    h:add('   ' .. x.decl_kind .. ' in ', 'SeamLabel')
    draw.path(h, x.path, x.line)
    local f = m.flows and m.flows[x.name]
    if count then
      h:add('   ' .. count, 'SeamLabel')
    elseif f then
      h:add(('   %s give one · %d take one'):format(draw.plural(#f.gives, 'function'), #require('seam.types').takers(f)), 'SeamLabel')
    end
  elseif x and x.kind == 'name' then
    M.name_head(h, x.n)
  elseif x and x.kind == 'gone' then
    h:add(M.name(m, x), 'SeamBold'):add('   ' .. (x.file and 'file' or x.decl.kind == 'fn' and 'function' or 'class') .. ' in ', 'SeamLabel')
    draw.path(h, x.file and (x.path:match '^(.*/)' or '') or x.path)
    if count then
      h:add('   ' .. count, 'SeamLabel')
    end
  elseif x and count then
    h:add(M.name(m, x), 'SeamBold'):add('   folder in ', 'SeamLabel')
    draw.path(h, outline.full(x.item) .. '/')
    h:add('   ' .. count, 'SeamLabel')
  elseif x then
    h:add(M.name(m, x), 'SeamBold'):add('   folder, ' .. draw.plural(outline.files_under(m, outline.full(x.item)), 'file'), 'SeamLabel')
  end
  -- the tabs, the one shown lit; a view aside after them, lit, the tabs dim
  local t = row():add ' '
  local tabs = views.tabs(x)
  draw.tabs(t, vim.tbl_map(views.label, tabs), shown and views.is_tab(shown) and views.label(shown))
  if shown and not views.is_tab(shown) then
    t:add(#tabs > 0 and '      ' or ''):add(' ' .. views.label(shown) .. ' ', 'SeamTab')
  end
  local ds = shown and views.displays(shown, x) or {}
  if shown and shown.list then
    t:add '   '
    for i, d in ipairs(ds) do
      if i > 1 then
        t:add(' · ', 'SeamDim')
      end
      t:add(d, d == display and 'SeamBold' or 'SeamLabel')
    end
  elseif #ds > 1 then
    t:add('   ' .. display, 'SeamLabel')
  end
  draw.put(buf, { h, row(), t })
end

--- The view shown for the row, in the pane, from its top unless `keep`
--- keeps where it was scrolled and the cursor.
---@param buf integer
---@param win integer|nil
---@param m table
---@param x seam.ORow|nil
---@param sv seam.ViewState
---@param ctx seam.ViewCtx
---@param keep? boolean
function M.pane(buf, win, m, x, sv, ctx, keep)
  local out = {}
  local v, display = views.shown(x, sv)
  if v then
    v.draw(out, x, m, display, ctx)
  end
  local view = keep and win and api.nvim_win_is_valid(win) and api.nvim_win_call(win, vim.fn.winsaveview)
  draw.put(buf, out)
  if win and api.nvim_win_is_valid(win) then
    vim.wo[win].wrap = not (v and v.nowrap)
  end
  if view then
    api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
    end)
  else
    code.scroll_to(win, 1, 1)
    if win and api.nvim_win_is_valid(win) then
      api.nvim_win_call(win, function()
        vim.fn.winrestview { leftcol = 0, col = 0 }
      end)
    end
  end
end

return M
