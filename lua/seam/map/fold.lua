-- Which of the Map's groups close, each to its one line, so a side fits
-- the room it has: the ones with the fewest names first, never one opened
-- by hand. Pure.
local M = {}

---@class seam.FoldGroup
---@field key string what it is opened by
---@field lines integer the rows it takes open, its head among them
---@field n integer its names

--- The groups closed so `groups` fit in `room` rows, a closed one a row:
--- none when they fit; else the fewest names first, the later first among
--- equals, until they fit or none is left. One in `opened` is never closed
--- and counts as its one row, so opening it closes no other.
---@param groups seam.FoldGroup[]
---@param room integer
---@param opened table<string, boolean>
---@return table<string, boolean> closed, by key
function M.closed(groups, room, opened)
  local total, can = 0, {}
  for i, g in ipairs(groups) do
    if opened[g.key] then
      total = total + 1
    else
      total = total + g.lines
      if g.lines > 1 then
        can[#can + 1] = { g = g, i = i }
      end
    end
  end
  local out = {}
  if total <= room then
    return out
  end
  table.sort(can, function(a, b)
    return a.g.n < b.g.n or (a.g.n == b.g.n and a.i > b.i)
  end)
  for _, c in ipairs(can) do
    if total <= room then
      break
    end
    out[c.g.key] = true
    total = total - c.g.lines + 1
  end
  return out
end

return M
