-- The Map's both ways display: what the row is built from on the left, who
-- uses it on the right, the order of the tabs, joined to it by lines; a
-- function's calls and callers, a folder's or a file's files across its
-- edge with the names that cross, a type's makers and takers. Pure: the items come as pieces, the rows go
-- out with what each name stands for in `meta.hits`.
local canvas = require 'seam.map.canvas'
local M = {}

-- the most a side lists before `⋯ N more`, opened with l
M.CAP = 40

local function width(segs)
  local n = 0
  for _, s in ipairs(segs) do
    n = n + vim.api.nvim_strwidth(s[1])
  end
  return n
end

--- A side cut to CAP unless `all`, a `⋯ N more` item last standing for `side`.
---@param items table[]
---@param side 'left'|'right'
---@param all boolean|nil
---@return table[]
function M.cut(items, side, all)
  if all or #items <= M.CAP then
    return items
  end
  local out = vim.list_slice(items, 1, M.CAP)
  out[#out + 1] = { { '⋯ ' .. (#items - M.CAP) .. ' more', 'SeamLabel', { more = side } } }
  return out
end

--- The rows: `left` right-aligned to a column, each joined to the centre,
--- `right` after it, the two sides centred on the centre's row.
---@param left table[][] each item its pieces `{ text, hl, hit }`
---@param right table[][]
---@param centre table[] pieces
---@param w integer the room across
---@return table[]
function M.draw(left, right, centre, w)
  local lw = 0
  for _, s in ipairs(left) do
    lw = math.max(lw, width(s))
  end
  local n = math.max(#left, #right, 1)
  local mid = math.floor(n / 2)
  local cv = canvas.new(w)
  local l0, r0 = mid - math.floor(#left / 2), mid - math.floor(#right / 2)
  for j, s in ipairs(left) do
    cv:seg(s, lw - width(s), l0 + j - 1)
    cv:h(lw + 1, lw + 3, l0 + j - 1)
  end
  if #left > 0 then
    cv:v(lw + 3, l0, l0 + #left - 1)
    cv:h(lw + 3, lw + 6, mid)
  end
  local cx = #left > 0 and lw + 7 or 0
  cv:seg(centre, cx, mid)
  local bx = cx + 1 + width(centre)
  if #right > 0 then
    cv:h(bx, bx + 3, mid)
    cv:v(bx + 3, r0, r0 + #right - 1)
  end
  for j, s in ipairs(right) do
    cv:h(bx + 3, bx + 5, r0 + j - 1)
    cv:seg(s, bx + 6, r0 + j - 1)
  end
  return cv:rows(1)
end

return M
