-- Which of the Map's groups close, each to its one line, so a side fits
-- the room it has: the ones with the fewest names first, never one opened
-- by hand; and the head of one opened by hand, which h closes. Pure.
local M = {}

---@class seam.FoldGroup
---@field key string what it is opened by
---@field lines integer the rows it takes open, its head among them
---@field n integer its names

--- The groups closed so `groups` fit in `room` rows, a closed one a row:
--- none when they fit; else the fewest names first, the later first among
--- equals, until they fit or none is left; then each closed one that fits
--- in the rows left opens again, the last closed first, so one group too
--- tall for the pane does not close all the others. One in `opened` is
--- never closed and counts as its one row, so opening it closes no other.
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
  local shut = {}
  for _, c in ipairs(can) do
    if total <= room then
      break
    end
    out[c.g.key] = true
    shut[#shut + 1] = c.g
    total = total - c.g.lines + 1
  end
  for i = #shut, 1, -1 do
    local g = shut[i]
    if total + g.lines - 1 <= room then
      out[g.key] = nil
      total = total + g.lines - 1
    end
  end
  return out
end

--- The head of a group opened by hand: its pieces, each standing also for
--- closing it with h, by `key`.
---@param segs table[]
---@param key string
---@return table[]
function M.head(segs, key)
  local out = {}
  for i, s in ipairs(segs) do
    local hit = { opened = key }
    for k, v in pairs(s[3] or {}) do
      hit[k] = v
    end
    out[i] = { s[1], s[2], hit }
  end
  return out
end

return M
