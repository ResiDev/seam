-- A canvas for the Map's drawings: lines join by their ends into box
-- characters, text over them; each cell may say what it stands for, so the
-- rows it becomes carry the names under the cursor. As wide as what is put
-- on it: nothing is cut at the pane's edge, a long row goes on right.
-- Ported from the mocks' generator (design/mocks/src/map/ideas.py). Pure.
local draw = require 'seam.draw'
local M = {}

-- which ends a cell's line has: 1 up, 2 right, 4 down, 8 left
local GLYPH = {
  [5] = '│',
  [10] = '─',
  [6] = '┌',
  [12] = '┐',
  [3] = '└',
  [9] = '┘',
  [7] = '├',
  [13] = '┤',
  [14] = '┬',
  [11] = '┴',
  [15] = '┼',
  [1] = '╵',
  [4] = '╷',
  [2] = '╶',
  [8] = '╴',
}

local C = {}
C.__index = C

--- A canvas as wide and as tall as what is put on it.
---@return table
function M.new()
  return setmetatable({ H = 0, bits = {}, txt = {}, hl = {}, hit = {}, last = {} }, C)
end

function C:grow(y)
  while y >= self.H do
    local r = self.H
    self.bits[r], self.txt[r], self.hl[r], self.hit[r], self.last[r] = {}, {}, {}, {}, -1
    self.H = self.H + 1
  end
end

--- Text at `x`, `y`, a cell a character; `hit` what it stands for.
function C:put(x, y, text, hl, hit)
  if y < 0 then
    return x
  end
  self:grow(y)
  local k = 0
  for ch in text:gmatch '[%z\1-\127\194-\244][\128-\191]*' do
    local cx = x + k
    if cx >= 0 then
      self.txt[y][cx], self.hl[y][cx], self.hit[y][cx] = ch, hl, hit
      self.last[y] = math.max(self.last[y], cx)
    end
    k = k + 1
  end
  return x + k
end

--- Pieces `{ text, hl, hit }` one after another from `x`; where they end.
function C:seg(segs, x, y)
  for _, s in ipairs(segs) do
    x = self:put(x, y, s[1], s[2], s[3])
  end
  return x
end

function C:bit(x, y, b, hl)
  if y < 0 or x < 0 then
    return
  end
  self:grow(y)
  if b > 0 then
    self.last[y] = math.max(self.last[y], x)
  end
  self.bits[y][x] = bit.bor(self.bits[y][x] or 0, b)
  self.hl[y][x] = self.hl[y][x] or hl
end

--- A line across row `y` from `x0` to `x1`.
function C:h(x0, x1, y, hl)
  if x0 > x1 then
    x0, x1 = x1, x0
  end
  for x = x0, x1 do
    self:bit(x, y, bit.bor(x > x0 and 8 or 0, x < x1 and 2 or 0), hl or 'SeamMapLine')
  end
end

--- A line down column `x` from `y0` to `y1`.
function C:v(x, y0, y1, hl)
  if y0 > y1 then
    y0, y1 = y1, y0
  end
  for y = y0, y1 do
    self:bit(x, y, bit.bor(y > y0 and 1 or 0, y < y1 and 4 or 0), hl or 'SeamMapLine')
  end
end

function C:box(x, y, w, h, hl)
  hl = hl or 'SeamMapBox'
  self:h(x, x + w - 1, y, hl)
  self:h(x, x + w - 1, y + h - 1, hl)
  self:v(x, y, y + h - 1, hl)
  self:v(x + w - 1, y, y + h - 1, hl)
end

--- The character at a cell, text over a line, a space where nothing is.
function C:at(x, y)
  local t = self.txt[y] and self.txt[y][x]
  if t then
    return t
  end
  local b = self.bits[y] and self.bits[y][x]
  return b and b > 0 and GLYPH[b] or ' '
end

--- The canvas as rows, `indent` spaces first: each run of a highlight
--- one mark, `meta.hits` the byte span of each thing a cell stood for.
---@param indent? integer
---@return table[]
function C:rows(indent)
  local out = {}
  for y = 0, self.H - 1 do
    local r = draw.row { hits = {} }
    r:add(string.rep(' ', indent or 1))
    local last = self.last[y]
    local run, rhl, rhit = {}, nil, nil
    local function flush()
      if #run > 0 then
        local s = table.concat(run)
        local b0 = r.b
        r:add(s, rhl)
        if rhit then
          local hs = r.meta.hits
          local prev = hs[#hs]
          if prev and prev.item == rhit and prev.e == b0 then
            prev.e = r.b
          else
            hs[#hs + 1] = { s = b0, e = r.b, item = rhit }
          end
        end
      end
      run = {}
    end
    for x = 0, last do
      local ch = self:at(x, y)
      local hl = (self.txt[y][x] or (self.bits[y][x] or 0) > 0) and self.hl[y][x] or nil
      local hit = self.hit[y][x]
      if hl ~= rhl or hit ~= rhit then
        flush()
        rhl, rhit = hl, hit
      end
      run[#run + 1] = ch
    end
    flush()
    out[#out + 1] = r
  end
  -- no blank rows at the bottom
  while #out > 0 and out[#out].w <= (indent or 1) do
    out[#out] = nil
  end
  return out
end

return M
