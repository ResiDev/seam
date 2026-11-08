-- The code screen's types display, its left side on gs: the
-- function's line, then its values in the order made, `name  Type`, each
-- function inside under its own line, indented; a file's declarations. A
-- type opens in place under the line naming it. With the diff on, a line
-- whose signature changed under its line as it was, a type the range
-- changed `~`, and a type opened with its own lines.
local api = vim.api
local changed = require 'seam.views.changed'
local code = require 'seam.code'
local codetypes = require 'seam.codetypes'
local draw = require 'seam.draw'
local outline = require 'seam.outline'
local st = require 'seam.state'
local types_view = require 'seam.views.types'
local M = {}

local row = draw.row
local SIGN_HL = { ['+'] = 'SeamSignAdd', ['~'] = 'SeamSignChange' }

--- The types display for `e`, a function or a file on the code screen,
--- `width` wide.
---@param out table[]
---@param m table
---@param e seam.CodeAt
---@param width integer
function M.draw(out, m, e, width)
  local node = e.kind == 'fn' and m.graph.nodes[e.id]
  local list = node and codetypes.fn(m, e.path, node.line, node.name) or codetypes.file(m, e.path)
  if e.kind == 'type' then
    list = vim.tbl_filter(function(r)
      return r.kind == 'type' and r.name == e.name and r.line == e.decl.line
    end, list)
  end
  st.copens = st.copens or {}
  st.copens[e.path .. (e.id or '')] = st.copens[e.path .. (e.id or '')] or {}
  st.cctx = { open = st.copens[e.path .. (e.id or '')], width = width, diff = changed.on() }
  local C = types_view.context(m, st.cctx, e.path)
  local col = 18
  for _, r in ipairs(list) do
    if r.kind == 'value' then
      col = math.max(col, 3 + 2 * r.depth + api.nvim_strwidth(r.name) + 2)
    end
  end
  -- with the diff on, the sign column two wide, a space after the sign
  local o = C.diff and ' ' or ''
  col = col + #o
  local lines = code.file(e.path).lines
  for _, r in ipairs(list) do
    if r.kind == 'blank' then
      out[#out + 1] = row()
    else
      local x = row { at = { path = e.path, line = r.line, name = r.name } }
      local placed = {}
      -- with the diff on, a sign column: a line as it was over a line whose signature changed
      local d = C.diff and r.depth == 0 and r.kind == 'fn' and changed.fn_state { path = e.path, name = r.name, line = r.line }
      if d and d.state == 'signature' then
        out[#out + 1] = changed.was_row({ path = e.path, name = r.name, line = r.line }, d, r.ret)
      end
      local sign = d and '+' or (C.diff and r.kind == 'type' and changed.type_changed(e.path, r.name) and '~') or ' '
      x:add(sign, SIGN_HL[sign]):add(o)
      if d then
        x.bg = 'SeamDiffAdd'
        x.meta.change = d.state == 'new' or nil
      end
      if r.kind == 'fn' then
        x:add(string.rep(' ', 2 * r.depth))
        types_view.typed(x, r.params, C.known, placed)
        x:add(' → ', 'SeamLabel'):add(r.name, r.depth == 0 and 'SeamTitle' or '@function')
        if r.ret then
          x:add(' → ', 'SeamLabel')
          types_view.typed(x, r.ret, C.known, placed)
        end
        if r.depth > 0 then
          local at = (lines[r.line] or ''):find('%f[%w_$]' .. vim.pesc(r.name) .. '%f[^%w_$]')
          x.meta.name = at and { line = r.line, col = at - 1 } or nil
        end
      elseif r.kind == 'value' then
        x:add(string.rep(' ', 2 + 2 * r.depth)):add(r.name, 'SeamName'):to(col)
        types_view.typed(x, r.type or '', C.known, placed)
        x.meta.name = { line = r.line, col = r.col }
      else
        x:add(r.name, 'SeamType'):to(col):add(r.type, 'SeamLabel')
      end
      x:to(width - 7):add((' %4d'):format(r.line), 'SeamGutter')
      local key = 'ct:' .. r.line .. ':' .. r.name
      x.meta.tv = { key = key, id = 'l', names = placed, chain = {}, path = e.path }
      if r.kind == 'fn' and r.depth == 0 then
        for _, n in ipairs(outline.by_file(m.graph)[e.path] or {}) do
          if n.line == r.line and n.name == r.name then
            x.meta.tv.fn_id = n.id
          end
        end
      end
      out[#out + 1] = x
      local seen, line = {}, { id = 'l', names = {}, path = e.path }
      for _, p in ipairs(placed) do
        if not seen[p.name] then
          seen[p.name] = true
          line.names[#line.names + 1] = p.name
        end
      end
      local items = types_view.lay(C, { line }, key, {}, {})
      table.remove(items, 1)
      types_view.render(out, C, items)
    end
  end
end

return M
