-- The pane's views, a tab each: which rows each has something for, the
-- displays it can be shown in, and how it draws. A later view is one more
-- entry in the list. `st.view` holds the one chosen and each view's display.
local code_view = require 'seam.views.code'
local seams_view = require 'seam.views.seams'
local types_view = require 'seam.views.types'
local M = {}

---@class seam.View
---@field name string its tab
---@field displays string[] the ways it can be shown, the first by default
---@field has fun(row: seam.ORow): boolean
---@field draw fun(out: table[], row: seam.ORow, m: table, display: string, ctx: seam.ViewCtx)
---@field count fun(m: table, row: seam.ORow): string|nil what the pane's head says of the row in this view

---@class seam.ViewCtx
---@field open table<string, boolean> the types opened in place for the row, by key (seam.typesview)
---@field width integer the pane's

---@class seam.ViewState
---@field at string the view chosen, by name
---@field display table<string, string> each view's display chosen

---@return seam.ViewState
function M.new()
  return { at = 'Code', display = {} }
end

---@type seam.View[]
M.list = {
  {
    name = 'Code',
    displays = { 'code' },
    has = function(row)
      return row.kind ~= 'dir'
    end,
    draw = function(out, row, m)
      code_view.draw(out, row, m)
    end,
  },
  {
    name = 'Types',
    displays = { 'types' },
    has = function()
      return true
    end,
    draw = function(out, row, m, _, ctx)
      types_view.draw(out, row, m, ctx)
    end,
  },
  {
    name = 'Built from',
    displays = seams_view.BUILT,
    has = function()
      return true
    end,
    draw = seams_view.built_from,
    count = seams_view.built_count,
  },
  {
    name = 'Used by',
    displays = seams_view.USED,
    has = function()
      return true
    end,
    draw = seams_view.used_by,
    count = seams_view.used_count,
  },
}

M.under = code_view.under

--- The views that have something for `row`, in the tabs' order.
---@param row seam.ORow|nil
---@return seam.View[]
function M.of(row)
  local out = {}
  for _, v in ipairs(M.list) do
    if row and v.has(row) then
      out[#out + 1] = v
    end
  end
  return out
end

--- The view shown for `row` and its display: the one chosen when it has
--- something for the row, else the first that has.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@return seam.View|nil, string|nil
function M.shown(row, sv)
  local list = M.of(row)
  local v = list[1]
  for _, x in ipairs(list) do
    if x.name == sv.at then
      v = x
    end
  end
  if not v then
    return nil
  end
  local d = sv.display[v.name]
  return v, vim.tbl_contains(v.displays, d) and d or v.displays[1]
end

--- The next view, or the one before when `d` is negative, among those
--- that have something for `row`. False when there is no other.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param d integer
---@return boolean
function M.step(row, sv, d)
  local list = M.of(row)
  local v = M.shown(row, sv)
  if #list < 2 or not v then
    return false
  end
  local i = 1
  for j, x in ipairs(list) do
    if x == v then
      i = j
    end
  end
  sv.at = list[(i - 1 + d) % #list + 1].name
  return true
end

--- The view's next display, or the one before. False when it has one.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param d integer
---@return boolean
function M.step_display(row, sv, d)
  local v, now = M.shown(row, sv)
  if not v or #v.displays < 2 then
    return false
  end
  local i = vim.fn.index(v.displays, now) + 1
  sv.display[v.name] = v.displays[(i - 1 + d) % #v.displays + 1]
  return true
end

return M
