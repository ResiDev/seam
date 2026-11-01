-- Two versions of some lines, compared: the hunks between them, with the
-- bytes that changed on each line of a hunk, from codediff.nvim's
-- compute_diff when it is there, else Vim's own vim.text.diff and a word
-- diff of each pair of lines; and the hunks laid out as the diff
-- reads them, removed lines where they were, the unchanged runs folded.
local M = {}

---@class seam.Hunk
---@field a integer the first line of `a` it takes, or the one it is inserted before
---@field na integer
---@field b integer the first line of `b` it gives, or the one it was removed before
---@field nb integer
---@field del table<integer, integer[][]> by line of `a`, the changed bytes { s, e } (0-based, e past)
---@field add table<integer, integer[][]> by line of `b`, the same

-- `false` to leave codediff out, for the specs
M.codediff = true

local function codediff()
  if not M.codediff then
    return nil
  end
  local ok, d = pcall(require, 'codediff.core.diff')
  return ok and d or nil
end

-- a line's words, its runs of spaces and each other character, with where they start
local function tokens(s)
  local out, i = {}, 1
  while i <= #s do
    local a, b = s:find('^[%w_$]+', i)
    if not a then
      a, b = s:find('^%s+', i)
    end
    if not a then
      a, b = i, i
      -- a whole UTF-8 character
      while b < #s and s:byte(b + 1) >= 0x80 and s:byte(b + 1) < 0xC0 do
        b = b + 1
      end
    end
    out[#out + 1] = { t = s:sub(a, b), s = a - 1, e = b }
    i = b + 1
  end
  return out
end

-- the spans of tokens i..j, the blanks at either end left out
local function span(toks, i, j, out)
  while i <= j and not toks[i].t:find '%S' do
    i = i + 1
  end
  while j >= i and not toks[j].t:find '%S' do
    j = j - 1
  end
  if j >= i then
    local last = out[#out]
    if last and last[2] == toks[i].s then
      last[2] = toks[j].e
    else
      out[#out + 1] = { toks[i].s, toks[j].e }
    end
  end
end

--- The bytes of `a` and of `b` that differ, word by word.
---@param a string
---@param b string
---@return integer[][] sa, integer[][] sb
function M.words(a, b)
  local ta, tb = tokens(a), tokens(b)
  local la, lb = {}, {}
  for i, t in ipairs(ta) do
    la[i] = t.t
  end
  for i, t in ipairs(tb) do
    lb[i] = t.t
  end
  local sa, sb = {}, {}
  if #la == 0 or #lb == 0 then
    span(ta, 1, #ta, sa)
    span(tb, 1, #tb, sb)
    return sa, sb
  end
  local idx = vim.text.diff(table.concat(la, '\n') .. '\n', table.concat(lb, '\n') .. '\n', { result_type = 'indices', algorithm = 'histogram' })
  ---@cast idx integer[][]
  for _, h in ipairs(idx) do
    local a0, na, b0, nb = h[1], h[2], h[3], h[4]
    if na > 0 then
      span(ta, a0, a0 + na - 1, sa)
    end
    if nb > 0 then
      span(tb, b0, b0 + nb - 1, sb)
    end
  end
  return sa, sb
end

-- a UTF-16 column of codediff's, 1-based, as a byte of `line`, 0-based
local function byte(line, col)
  if col <= 1 then
    return 0
  end
  local ok, b = pcall(vim.str_byteindex, line, 'utf-16', col - 1, false)
  return ok and b or math.min(col - 1, #line)
end

-- codediff's inner changes as the bytes they cover on each line of one side
local function inner(changes, side, lines, s, n)
  local out = {}
  for _, c in ipairs(changes or {}) do
    local r = c[side]
    for l = math.max(r.start_line, s), math.min(r.end_line, s + n - 1) do
      local text = lines[l] or ''
      local from = l == r.start_line and byte(text, r.start_col) or 0
      local to = l == r.end_line and byte(text, r.end_col) or #text
      if to > from then
        out[l] = out[l] or {}
        table.insert(out[l], { from, to })
      end
    end
  end
  return out
end

-- the words of each pair of lines in a hunk that takes and gives lines
local function pair_words(h, a, b)
  for i = 0, math.min(h.na, h.nb) - 1 do
    local sa, sb = M.words(a[h.a + i] or '', b[h.b + i] or '')
    h.del[h.a + i], h.add[h.b + i] = sa, sb
  end
end

--- The hunks between `a` and `b`, in order.
---@param a string[]
---@param b string[]
---@return seam.Hunk[]
function M.hunks(a, b)
  local out = {}
  -- one side empty: all of the other, which codediff does not say
  if #a == 0 or #b == 0 then
    if #a + #b > 0 then
      out[1] = { a = 1, na = #a, b = 1, nb = #b, del = {}, add = {} }
    end
    return out
  end
  local cd = codediff()
  if cd then
    local ok, r = pcall(cd.compute_diff, a, b, { max_computation_time_ms = 1000 })
    if ok and r then
      for _, c in ipairs(r.changes) do
        local h = {
          a = c.original.start_line,
          na = c.original.end_line - c.original.start_line,
          b = c.modified.start_line,
          nb = c.modified.end_line - c.modified.start_line,
          del = {},
          add = {},
        }
        -- words lit only where lines were changed, not wholly added or removed
        if h.na > 0 and h.nb > 0 then
          h.del = inner(c.inner_changes, 'original', a, h.a, h.na)
          h.add = inner(c.inner_changes, 'modified', b, h.b, h.nb)
        end
        out[#out + 1] = h
      end
      return out
    end
  end
  local ta = #a > 0 and table.concat(a, '\n') .. '\n' or ''
  local tb = #b > 0 and table.concat(b, '\n') .. '\n' or ''
  local idx = vim.text.diff(ta, tb, { result_type = 'indices', algorithm = 'histogram' })
  ---@cast idx integer[][]
  for _, x in ipairs(idx) do
    local h = { a = x[2] > 0 and x[1] or x[1] + 1, na = x[2], b = x[4] > 0 and x[3] or x[3] + 1, nb = x[4], del = {}, add = {} }
    if h.na > 0 and h.nb > 0 then
      pair_words(h, a, b)
    end
    out[#out + 1] = h
  end
  return out
end

---@class seam.DiffItem
---@field kind 'same'|'del'|'add'|'fold'
---@field a integer|nil the line of `a`: a removed line, an unchanged one
---@field b integer|nil the line of `b`: an added line, an unchanged one; a removed line, the one it was before
---@field spans integer[][]|nil the bytes that changed on it
---@field n integer|nil how many lines a fold holds
---@field start boolean|nil the first line of a change, where ]c goes

--- The hunks between `a` and `b` laid out a line a row: each unchanged line,
--- each removed line above what took its place, each added line; with
--- `fold`, every run of unchanged lines longer than `context` (3) lines on
--- each side of a change and one more is one fold.
---@param hunks seam.Hunk[]
---@param nb integer how many lines `b` has
---@param opts? { fold?: boolean, context?: integer }
---@return seam.DiffItem[]
function M.layout(hunks, nb, opts)
  opts = opts or {}
  local ctx = opts.context or 3
  local out = {}
  -- unchanged lines b0..b1, `shift` what the hunks before moved them in `a`
  local function same(b0, b1, before, after, shift)
    local n = b1 - b0 + 1
    if n <= 0 then
      return
    end
    local function line(b)
      out[#out + 1] = { kind = 'same', b = b, a = b + shift }
    end
    if opts.fold then
      local head = before and math.min(ctx, n) or 0
      local tail = after and math.min(ctx, n - head) or 0
      if n > head + tail + 1 then
        for b = b0, b0 + head - 1 do
          line(b)
        end
        out[#out + 1] = { kind = 'fold', n = n - head - tail }
        for b = b1 - tail + 1, b1 do
          line(b)
        end
        return
      end
    end
    for b = b0, b1 do
      line(b)
    end
  end
  local nextb, shift = 1, 0
  for i, h in ipairs(hunks) do
    same(nextb, h.b - 1, i > 1, true, shift)
    local first = #out + 1
    for k = h.a, h.a + h.na - 1 do
      out[#out + 1] = { kind = 'del', a = k, b = h.b, spans = h.del[k] }
    end
    for k = h.b, h.b + h.nb - 1 do
      out[#out + 1] = { kind = 'add', b = k, spans = h.add[k] }
    end
    if out[first] then
      out[first].start = true
    end
    nextb, shift = h.b + h.nb, shift + h.na - h.nb
  end
  same(nextb, nb, #hunks > 0, false, shift)
  return out
end

--- Lines `a` and `b` laid out (seam.diff.layout), the hunks between them.
---@param a string[]
---@param b string[]
---@param opts? { fold?: boolean, context?: integer }
---@return seam.DiffItem[], seam.Hunk[]
function M.items(a, b, opts)
  local h = M.hunks(a, b)
  return M.layout(h, #b, opts), h
end

return M
