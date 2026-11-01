-- The range's changes on the code shown: the lines it changed numbered in
-- the signs' colours; with the diff on, drawn inline, removed lines where
-- they were, unnumbered on red, added ones on green; ]c [c from change to
-- change, in the code screen's code and its types.
local changed = require 'seam.views.changed'
local changes = require 'seam.changes'
local code = require 'seam.code'
local diff = require 'seam.diff'
local draw = require 'seam.draw'
local M = {}

--- The lines of `path` as it is that the range changed, when it ends at the
--- working tree: each `add`, `change` or, the line after lines removed,
--- `delete`; and the lines where each change starts, in order.
---@param path string
---@return table<integer, string>, integer[]
function M.marks(path)
  local C = changes.get()
  if not (C and not C.range.to and C.files[path] and C.files[path] ~= 'gone') then
    return {}, {}
  end
  C.marks = C.marks or {}
  local got = C.marks[path]
  if not got then
    local by, starts = {}, {}
    local B = changes.lines(path)
    for _, h in ipairs(diff.hunks(changes.lines(changes.key(C, path, 'from')), B)) do
      starts[#starts + 1] = math.min(h.b, math.max(1, #B))
      for l = h.b, h.b + h.nb - 1 do
        by[l] = h.na == 0 and 'add' or 'change'
      end
      if h.nb == 0 then
        by[starts[#starts]] = by[starts[#starts]] or 'delete'
      end
    end
    got = { by, starts }
    C.marks[path] = got
  end
  return got[1], got[2]
end

M.MARK_HL = { add = 'SeamSignAdd', change = 'SeamSignChange', delete = 'SeamSignDelete' }

--- The code rows of `path` in window `win` where a change starts.
---@param win integer
---@param path string
---@return integer[]
function M.line_stops(win, path)
  local _, starts = M.marks(path)
  local at, rows = {}, {}
  if not vim.api.nvim_win_is_valid(win) then
    return rows
  end
  for _, l in ipairs(starts) do
    at[l] = true
  end
  local buf = vim.api.nvim_win_get_buf(win)
  -- with the diff drawn, the rows where each change starts
  for i = 1, vim.api.nvim_buf_line_count(buf) do
    if draw.meta(buf, i).change then
      rows[#rows + 1] = i
    end
  end
  if #rows > 0 then
    return rows
  end
  for i = 1, #starts > 0 and vim.api.nvim_buf_line_count(buf) or 0 do
    if at[draw.meta(buf, i).lnum or -1] then
      rows[#rows + 1] = i
    end
  end
  return rows
end

--- `]c` `[c` on code rows of `path` in window `win`: the cursor on the next
--- row where a change starts, or the one before, round the ends.
---@param win integer
---@param path string
---@param d integer
function M.next_line(win, path, d)
  local rows = M.line_stops(win, path)
  if #rows == 0 then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  local pick = d > 0 and rows[1] or rows[#rows]
  for k = d > 0 and 1 or #rows, d > 0 and #rows or 1, d do
    if (d > 0 and rows[k] > cur) or (d < 0 and rows[k] < cur) then
      pick = rows[k]
      break
    end
  end
  vim.api.nvim_win_set_cursor(win, { pick, 0 })
end

--- The range's changes to `path` as it is, line by line, when the diff is
--- on and the range ends at the working tree: the lines added with the
--- bytes changed on each, the lines removed before each line, and the
--- lines a change starts on.
---@param path string
---@return { add: table<integer, integer[][]|true>, del: table<integer, table[]>, start: table<integer, true> }|nil
function M.diff_of(path)
  local C = changes.get()
  if not (changed.on() and not C.range.to and C.files[path] and C.files[path] ~= 'gone') then
    return nil
  end
  local A = changes.lines(changes.key(C, path, 'from'))
  local out = { add = {}, del = {}, start = {} }
  for _, it in ipairs(diff.items(A, changes.lines(path))) do
    if it.kind == 'del' then
      out.del[it.b] = out.del[it.b] or {}
      table.insert(out.del[it.b], { a = it.a, text = A[it.a] or '', spans = it.spans, start = it.start })
    elseif it.kind == 'add' then
      out.add[it.b] = it.spans or true
      if it.start then
        out.start[it.b] = true
      end
    end
  end
  return out
end

--- Code rows out[first..] of lines s..e of `path` with the changes `d`
--- inline: each added line on green, the words changed lit stronger; the
--- lines removed before it unnumbered on red, the first of a change a stop
--- for ]c; those removed before the first line or after the last only
--- from a file's top or at its end, or when they were the function's own,
--- lines `own.s`..`own.e` at the range's start.
---@param out table[]
---@param first integer
---@param d table diff_of's
---@param path string
---@param s integer
---@param e integer
---@param own? { s: integer, e: integer }
function M.inline(out, first, d, path, s, e, own)
  local rows = vim.list_slice(out, first)
  for i = #out, first, -1 do
    out[i] = nil
  end
  local gw = math.max(3, #tostring(e))
  local function dels(l, edge)
    local started = false
    for _, x in ipairs(d.del[l] or {}) do
      if not edge or (own and x.a >= own.s and x.a <= own.e) then
        out[#out + 1] = changed.del_row(x.text, x.spans, gw + 3, { path = path, line = math.max(1, l - 1) }, x.start or not started)
        started = true
      end
    end
  end
  for _, r in ipairs(rows) do
    local l = r.meta.lnum
    if l then
      dels(l, l == s and s > 1)
    end
    if l and d.add[l] then
      changed.add_lit(r, r.meta.start, d.add[l] ~= true and d.add[l] or nil)
      r.meta.change = (d.start[l] and not (d.del[l] and #d.del[l] > 0)) or nil
    end
    out[#out + 1] = r
  end
  dels(e + 1, e < #code.file(path).lines)
end

return M
