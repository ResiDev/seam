-- The Map's size display: a bar a thing, as long as how much it reaches
-- (or is used), the number after it, and a second column beside: how
-- many use it, or where it lives. Pure: rows with what each label stands
-- for in `meta.map`.
local draw = require 'seam.draw'
local M = {}

local row = draw.row

-- the most rows before `⋯ N more`
M.CAP = 60
local INDENT = 3

---@class seam.MapBar
---@field label string
---@field hl string
---@field n integer how long its bar is
---@field text string|nil the number written after the bar, `n` when nil
---@field second string|nil the second column
---@field second_hl string|nil
---@field map table|nil what the row stands for

---@class seam.MapSizeOpts
---@field title string|nil a line over everything
---@field head string|nil the bars' title, over them
---@field second string|nil the second column's title
---@field items seam.MapBar[] the longest first
---@field all boolean|nil every row, not CAP
---@field width integer

--- The rows of the size display.
---@param o seam.MapSizeOpts
---@return table[]
function M.draw(o)
  local out = {}
  local lw = 14
  for _, it in ipairs(o.items) do
    lw = math.max(lw, vim.api.nvim_strwidth(it.label) + 4)
  end
  lw = math.min(lw, 40)
  local mx = 1
  for _, it in ipairs(o.items) do
    mx = math.max(mx, it.n)
  end
  local bw = math.max(10, math.min(56, o.width - INDENT - lw - 24))
  local second = INDENT + lw + bw + 10
  if o.title then
    out[#out + 1] = row():add(string.rep(' ', INDENT)):add(o.title, 'SeamLabel')
    out[#out + 1] = row()
  end
  if o.head or o.second then
    local r = row():to(INDENT + lw)
    r:add(o.head or '', 'SeamLabel')
    if o.second then
      r:to(second):add(o.second, 'SeamLabel')
    end
    out[#out + 1] = r
    out[#out + 1] = row()
  end
  local items = o.items
  if not o.all and #items > M.CAP then
    items = vim.list_slice(items, 1, M.CAP)
  end
  for _, it in ipairs(items) do
    local r = row { map = it.map }
    r:add(string.rep(' ', INDENT))
    r:add(draw.trunc(it.label, lw - 2), it.hl):to(INDENT + lw)
    local w = math.floor(bw * it.n / mx + 0.5)
    if w > 0 then
      r:add(string.rep(' ', w), 'SeamMapBar')
    else
      r:add('▏', 'SeamMapLine')
    end
    r:add(' ' .. (it.text or tostring(it.n)), 'SeamLabel')
    if it.second then
      r:to(second):add(it.second, it.second_hl or 'SeamText')
    end
    out[#out + 1] = r
  end
  if #items < #o.items then
    local r = row { map = { more = 'size' } }
    r:add(string.rep(' ', INDENT)):add('⋯ ' .. (#o.items - #items) .. ' more', 'SeamLabel')
    out[#out + 1] = r
  end
  return out
end

return M
