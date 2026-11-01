-- The pane's views: beside the tree every view is a tab; on the code screen
-- two, Code and Types, what is read most there, and Used by, Built from and
-- the Map aside, each on its own key (on both screens). Which rows each
-- has something for, the displays it can be shown in, and how it draws.
-- `st.view` holds the tab chosen, the view aside shown, and each view's
-- display. The diff (D) is no view: Code and Types draw what changed.
local changed_view = require 'seam.views.changed'
local code_view = require 'seam.views.code'
local index = require 'seam.index'
local st = require 'seam.state'
local map_view = require 'seam.views.map'
local names_view = require 'seam.views.names'
local seams_view = require 'seam.views.seams'
local types_view = require 'seam.views.types'
local M = {}

---@class seam.View
---@field name string its tab, or its name in the head when aside
---@field tab boolean|nil a tab on every screen; else a tab beside the tree only, aside on its key on the code screen
---@field key string|nil the key that shows it aside
---@field displays string[] the ways it can be shown, the first by default
---@field displays_of fun(row: seam.ORow): string[]|nil the ways it can be shown for this row, when they depend on it
---@field has fun(row: seam.ORow): boolean
---@field draw fun(out: table[], row: seam.ORow, m: table, display: string, ctx: seam.ViewCtx)
---@field count fun(m: table, row: seam.ORow): string|nil what the pane's head says of the row in this view

---@class seam.ViewCtx
---@field open table<string, boolean> the types opened in place for the row, by key (seam.typesview)
---@field width integer the pane's

---@class seam.ViewState
---@field at string the tab chosen, Code or Types
---@field aside string|nil the view aside shown, by name, until its key again or <Tab>
---@field display table<string, string> each view's display chosen

---@return seam.ViewState
function M.new()
  return { at = 'Code', display = {} }
end

-- the row's own lines changed in the range, with the diff on, or a row gone
local function diffed(row)
  return row.kind == 'gone' or (changed_view.on() and changed_view.has(index.model(), row, true))
end

-- a name in the code is seen through its type: its Code, Built from and
-- Used by are the type's; one with no repo type has only Types
local function as_type(row)
  return row.kind == 'name' and row.as_type or row
end
local function typed(row)
  return row.kind ~= 'name' or row.as_type ~= nil
end
local function through(f)
  return function(out, row, ...)
    return f(out, as_type(row), ...)
  end
end

---@type seam.View[]
M.list = {
  {
    name = 'Code',
    tab = true,
    gone = true,
    displays = { 'code' },
    -- with the diff on a row that changed: changes only, or whole
    displays_of = function(row)
      return diffed(as_type(row)) and changed_view.DISPLAYS or nil
    end,
    has = function(row)
      if row.kind == 'dir' then
        return changed_view.on() and changed_view.has(index.model(), row, true)
      end
      return typed(row)
    end,
    draw = function(out, row, m, display, ctx)
      local x = as_type(row)
      if diffed(x) then
        return changed_view.draw(out, x, m, display, ctx)
      end
      code_view.draw(out, x, m)
    end,
    count = function(m, row)
      return changed_view.on() and changed_view.count(m, as_type(row)) or nil
    end,
  },
  {
    name = 'Types',
    tab = true,
    displays = { 'types' },
    has = function()
      return true
    end,
    draw = function(out, row, m, _, ctx)
      ctx.diff = changed_view.on()
      if row.kind == 'name' then
        names_view.draw(out, row, m, ctx)
      else
        types_view.draw(out, row, m, ctx)
      end
    end,
    count = function(m, row)
      return changed_view.on() and changed_view.count(m, as_type(row)) or nil
    end,
  },
  {
    name = 'Built from',
    key = 'gb',
    displays = seams_view.BUILT,
    has = typed,
    draw = through(seams_view.built_from),
    count = function(m, row)
      return seams_view.built_count(m, as_type(row))
    end,
  },
  {
    name = 'Used by',
    key = 'gu',
    displays = seams_view.USED,
    has = typed,
    -- a function that changed: who uses it now, then who used it at the range's start
    draw = function(out, row, m, display, ctx)
      local x = as_type(row)
      if changed_view.changed_fn(m, x) then
        return changed_view.used_by(out, x, m, display, ctx, seams_view.used_by)
      end
      seams_view.used_by(out, x, m, display, ctx)
    end,
    count = function(m, row)
      return changed_view.used_count(m, as_type(row)) or seams_view.used_count(m, as_type(row))
    end,
  },
  {
    name = 'Map',
    key = 'gm',
    displays = map_view.DISPLAYS,
    -- the head lists them all, the one shown bold
    list = true,
    has = function(row)
      return map_view.has(index.model(), row)
    end,
    draw = map_view.draw,
    count = map_view.count,
  },
}

M.under = code_view.under

--- The views that have something for `row`, in the tabs' order.
---@param row seam.ORow|nil
---@return seam.View[]
function M.of(row)
  local out = {}
  for _, v in ipairs(M.list) do
    -- a row gone has only what it was
    if row and (row.kind ~= 'gone' or v.gone) and v.has(row) then
      out[#out + 1] = v
    end
  end
  return out
end

--- The ways `v` can be shown for `row`.
---@param v seam.View
---@param row seam.ORow|nil
---@return string[]
function M.displays(v, row)
  return row and v.displays_of and v.displays_of(row) or v.displays
end

local function find(list, name)
  for _, v in ipairs(list) do
    if v.name == name then
      return v
    end
  end
end

--- Is `v` a tab on the screen shown: every view beside the tree, Code and
--- Types on the code screen.
---@param v seam.View
---@return boolean
function M.is_tab(v)
  return v.tab == true or st.screen ~= 'code'
end

--- The view shown for `row` and its display: the view aside when the row
--- has it, else the tab chosen when it is a tab here, else the first tab,
--- else the first view aside the row has.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@return seam.View|nil, string|nil
function M.shown(row, sv)
  local list = M.of(row)
  local v = sv.aside and find(list, sv.aside)
  if not v then
    local at = find(list, sv.at)
    v = at and M.is_tab(at) and at or nil
  end
  if not v then
    for _, x in ipairs(list) do
      if M.is_tab(x) then
        v = x
        break
      end
    end
  end
  v = v or list[1]
  if not v then
    return nil
  end
  local ds = M.displays(v, row)
  local d = sv.display[v.name]
  return v, vim.tbl_contains(ds, d) and d or ds[1]
end

--- The tabs `row` has on the screen shown.
---@param row seam.ORow|nil
---@return seam.View[]
function M.tabs(row)
  return vim.tbl_filter(M.is_tab, M.of(row))
end

--- Does `<Tab>` act: a view aside shown, or more than one tab?
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@return boolean
function M.can_step(row, sv)
  local v = M.shown(row, sv)
  return v ~= nil and ((not M.is_tab(v) and #M.tabs(row) > 0) or #M.tabs(row) > 1)
end

--- `<Tab>` `<S-Tab>`: from a view aside back to the tab chosen; on a tab,
--- the next one, or with `d` -1 the one before, round the ends. False when
--- nothing changed.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param d? integer
---@return boolean
function M.step(row, sv, d)
  local v = M.shown(row, sv)
  if not v then
    return false
  end
  sv.aside = nil
  if not M.is_tab(v) then
    return M.shown(row, sv) ~= v
  end
  local tabs = M.tabs(row)
  if #tabs < 2 then
    return false
  end
  local i = 1
  for k, t in ipairs(tabs) do
    if t == v then
      i = k
    end
  end
  sv.at = tabs[(i - 1 + (d or 1)) % #tabs + 1].name
  return true
end

--- The view aside called `name` on the row, if it has it.
---@param row seam.ORow|nil
---@param name string
---@return seam.View|nil
function M.has(row, name)
  local v = find(M.of(row), name)
  return v and not v.tab and v or nil
end

--- `gu` `gb` `gm`: the view aside called `name`, or when it is shown, back
--- to the tab chosen. False when the row has no such view.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param name string
---@return boolean
function M.aside(row, sv, name)
  if not M.has(row, name) then
    return false
  end
  local v = M.shown(row, sv)
  sv.aside = not (v and v.name == name) and name or nil
  return true
end

--- The view's next display, or the one before. False when it has one.
---@param row seam.ORow|nil
---@param sv seam.ViewState
---@param d integer
---@return boolean
function M.step_display(row, sv, d)
  local v, now = M.shown(row, sv)
  local ds = v and M.displays(v, row) or {}
  if #ds < 2 then
    return false
  end
  local i = vim.fn.index(ds, now) + 1
  sv.display[v.name] = ds[(i - 1 + d) % #ds + 1]
  return true
end

return M
