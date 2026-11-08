-- The tree's git signs, as gitsigns draws them in the code: `+` new, `~`
-- changed, `_` gone; a folder or file `~` when anything under it changed,
-- `+` when it is new. A declaration gone keeps its row, struck through,
-- where it was, and so does a file gone in a folder that is open. `gc`
-- keeps the rows with a sign; `]c` `[c` go from one to the next.
local changes = require 'seam.changes'
local outline = require 'seam.outline'
local M = {}

local SIGN = { new = '+', changed = '~', signature = '~', body = '~', gone = '_' }
M.HL = { ['+'] = 'SeamSignAdd', ['~'] = 'SeamSignChange', ['_'] = 'SeamSignDelete' }

--- A file's function row, or a sorted order's: its node id; nil for a call.
---@param x seam.ORow
---@return string|nil
function M.top_id(x)
  return x.kind == 'fn' and x.key:match '^f:[^\n]*\n([^\n]*)$' or nil
end

-- a folder's sign: `~` when a file under it changed, `+` when every file
-- the tree has under it is new
local function dir_sign(m, C, dir)
  C.dirsign = C.dirsign or {}
  local s = C.dirsign[dir]
  if s == nil then
    s = false
    local pre = dir .. '/'
    for _, p in ipairs(C.list) do
      if p:sub(1, #pre) == pre then
        s = '+'
        if C.files[p] ~= 'new' then
          s = '~'
          break
        end
      end
    end
    if s == '+' then
      for p in pairs(outline.files(m)) do
        if p:sub(1, #pre) == pre and not C.files[p] then
          s = '~'
          break
        end
      end
    end
    C.dirsign[dir] = s
  end
  return s or nil
end

--- The sign of row `x`, nil when nothing in it changed.
---@param m table
---@param x seam.ORow
---@param C seam.Changes
---@return string|nil
function M.of(m, x, C)
  if x.kind == 'gone' then
    return '_'
  elseif x.kind == 'file' then
    return SIGN[C.files[x.path] or '']
  elseif x.kind == 'dir' then
    return dir_sign(m, C, outline.full(x.item))
  elseif x.kind == 'type' then
    local d = changes.decl(C, x.path, x.name)
    return d and SIGN[d.state]
  end
  local id = M.top_id(x)
  local n = id and m.graph.nodes[id]
  local d = n and changes.decl(C, n.path, n.name)
  return d and SIGN[d.state]
end

-- the end of row i's block: the last row under it
local function block_end(rows, i)
  local j = i
  while rows[j + 1] and rows[j + 1].depth > rows[i].depth do
    j = j + 1
  end
  return j
end

-- the functions gone from an open file, each after the one before it at
-- `from`, when the files list functions
local function gone_fns(m, rows, i, C, put, shows)
  local x = rows[i]
  local f = changes.file(C, x.path)
  if not f then
    return
  end
  local at, last = {}, block_end(rows, i)
  for j = i + 1, last do
    local id = rows[j].depth == x.depth + 1 and M.top_id(rows[j])
    if id then
      at[m.graph.nodes[id].name] = block_end(rows, j)
    end
  end
  local after = i
  for _, d in ipairs(f.before) do
    local c = f.by[d.name]
    if at[d.name] then
      after = at[d.name]
    elseif c.state == 'gone' and (d.kind == 'fn' or d.kind == 'class') and shows.f then
      put(after, {
        key = x.key .. '\n-' .. d.name,
        kind = 'gone',
        depth = x.depth + 1,
        path = x.path,
        name = d.name,
        decl = d,
        can_open = false,
        open = false,
        seen = false,
      })
    end
  end
end

-- a file gone, among the files of its folder when that is open
local function gone_file(rows, path, put)
  local parent, name = path:match '^(.*)/([^/]+)$'
  parent, name = parent or '', name or path
  local i, depth = 0, 0
  if parent ~= '' then
    i = nil
    for j, r in ipairs(rows) do
      if r.kind == 'dir' and r.open and outline.full(r.item) == parent then
        i, depth = j, r.depth + 1
      end
    end
    if not i then
      return
    end
  end
  local last = i == 0 and #rows or block_end(rows, i)
  local after = last
  for j = i + 1, last do
    local r = rows[j]
    if r.depth == depth and r.kind == 'file' then
      if r.path:match '[^/]+$' > name then
        after = j - 1
        break
      end
      after = block_end(rows, j)
    end
  end
  put(after, { key = 'f:' .. path, kind = 'gone', file = true, depth = depth, path = path, name = name, can_open = false, open = false, seen = false })
end

--- The tree's rows with the range's signs, `x.sign`, and the rows gone
--- where they were; with `only`, just the rows with a sign.
---@param m table
---@param rows seam.ORow[]
---@param only? boolean
---@param shows table<string, boolean> what a file lists (seam.outline), a gone function only when it lists functions
---@return seam.ORow[]
function M.decorate(m, rows, only, shows)
  local C = changes.get()
  if not (C and #C.list > 0) then
    return only and {} or rows
  end
  local adds = {}
  local function put(after, r)
    adds[after] = adds[after] or {}
    table.insert(adds[after], r)
  end
  -- the tree, not a flat list of functions, values and types
  local tree = rows[1] and (rows[1].kind == 'dir' or rows[1].kind == 'file')
  if tree then
    for i, x in ipairs(rows) do
      if x.kind == 'file' and x.open then
        gone_fns(m, rows, i, C, put, shows)
      end
    end
    for _, p in ipairs(C.list) do
      if C.files[p] == 'gone' then
        gone_file(rows, p, put)
      end
    end
  end
  local out = {}
  local function keep(x)
    x.sign = M.of(m, x, C)
    if x.sign or not only then
      out[#out + 1] = x
    end
  end
  for _, x in ipairs(adds[0] or {}) do
    keep(x)
  end
  for i, x in ipairs(rows) do
    keep(x)
    for _, y in ipairs(adds[i] or {}) do
      keep(y)
    end
  end
  return out
end

--- `]c` `[c`: the row with a sign after row `i`, or before, round the ends.
---@param rows seam.ORow[]
---@param i integer
---@param d integer
---@return integer|nil
function M.next(rows, i, d)
  local n = #rows
  for k = 1, n do
    local j = (i - 1 + d * k) % n + 1
    if rows[j].sign then
      return j
    end
  end
end

return M
