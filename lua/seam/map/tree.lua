-- The Map's tree display on a function, a file and a folder: tree lines,
-- names only or with what each takes and gives; two levels unless `>` `<`
-- say otherwise, a branch opened or closed by itself with `l` `h`, a name
-- seen higher on its branch dim and stopping, past three on a branch
-- `⋯ N more`. A folder goes a rank down a level: the folders it calls
-- into, their files, the functions; a file the files, then the functions.
-- Pure: rows with their marks and what each stands for in `meta.map`.
local data = require 'seam.map.data'
local draw = require 'seam.draw'
local M = {}

M.CAP = 3
-- the most rows drawn: past it a branch's calls are left as ⋯ more, opened with l
M.BUDGET = 800
-- a folder's or a file's ranks show four before `⋯ N more`, as their mocks do
M.RANK_CAP = 4
-- where the takes and gives columns start, and how wide each is cut
local TAKES, GIVES, TAKES_W, GIVES_W = 34, 78, 40, 30
-- where a folder's or a file's count of names stands
local COUNT = 34

---@class seam.MapNode
---@field kind 'fn'|'file'|'dir'
---@field key string what it is, for its branch and for a name seen higher
---@field label string
---@field hl string
---@field id string|nil a function's node id
---@field path string|nil
---@field count string|nil said dim after it
---@field cap integer|nil how many of its kids show before `⋯ N more`
---@field kids fun(): seam.MapNode[]

---@class seam.MapTreeOpts
---@field levels integer
---@field open table<string, boolean> a branch opened (true) or closed (false) with l h
---@field more table<string, boolean> a branch's ⋯ N more opened
---@field types fun(id: string): string|nil, string|nil what a function takes and gives, when T is on
---@field paint fun(r: table, text: string)|nil a type's text on a row
---@field width integer

--- A function as a node: what it calls under it, `()` after it when `paren`.
---@param m table
---@param id string
---@param paren? boolean
---@return seam.MapNode
function M.fn(m, id, paren)
  local n = m.graph.nodes[id]
  return {
    kind = 'fn',
    key = id,
    id = id,
    path = n.path,
    label = data.label(n) .. (paren and '()' or ''),
    hl = 'SeamMapFn',
    kids = function()
      return vim.tbl_map(function(k)
        return M.fn(m, k, paren)
      end, data.calls(m, id))
    end,
  }
end

-- stable: by `n` most first, else in the order met
local function by_most(list)
  for i, x in ipairs(list) do
    x.i = i
  end
  table.sort(list, function(a, b)
    return a.n > b.n or (a.n == b.n and a.i < b.i)
  end)
  return list
end

-- the functions of `names` (id -> true) as nodes, by name
local function fns(m, ids)
  local list = vim.tbl_keys(ids)
  table.sort(list, function(a, b)
    return m.graph.nodes[a].name < m.graph.nodes[b].name
  end)
  return vim.tbl_map(function(id)
    return M.fn(m, id, true)
  end, list)
end

-- the calls out of what `inside` holds, by unit then file: each unit
-- `{ label, files = { path, ids } }`, the most names first
local function gathered(m, inside, unit_of)
  local _, out = data.crossing(m, inside)
  local units, at = {}, {}
  for _, e in ipairs(out) do
    local path = m.graph.nodes[e.to].path
    local u = unit_of(path)
    local x = at[u]
    if not x then
      x = { label = u, files = {}, fat = {}, n = 0 }
      at[u] = x
      units[#units + 1] = x
    end
    local f = x.fat[path]
    if not f then
      f = { path = path, ids = {}, n = 0 }
      x.fat[path] = f
      x.files[#x.files + 1] = f
    end
    if not f.ids[e.to] then
      f.ids[e.to] = true
      f.n = f.n + 1
      x.n = x.n + 1
    end
  end
  for _, u in ipairs(units) do
    by_most(u.files)
  end
  return by_most(units)
end

local function names(n)
  return n .. ' name' .. (n == 1 and '' or 's')
end

--- A folder as a node: the folders it calls into, their files, the functions.
---@param m table
---@param dir string the folder's path
---@param label string
---@return seam.MapNode
function M.dir(m, dir, label)
  return {
    kind = 'dir',
    key = dir,
    path = dir,
    label = label,
    hl = 'SeamBold',
    kids = function()
      return vim.tbl_map(
        function(u)
          return {
            kind = 'dir',
            key = 'unit:' .. u.label,
            label = u.label,
            hl = 'SeamName',
            count = names(u.n),
            cap = M.RANK_CAP,
            kids = function()
              return vim.tbl_map(function(f)
                return {
                  kind = 'file',
                  key = f.path,
                  path = f.path,
                  label = f.path:match '[^/]+$',
                  hl = 'SeamName',
                  cap = M.RANK_CAP,
                  kids = function()
                    return fns(m, f.ids)
                  end,
                }
              end, u.files)
            end,
          }
        end,
        gathered(m, data.within(dir), function(p)
          return data.where(m, p, dir .. '/x')
        end)
      )
    end,
  }
end

--- A file as a node: the files it calls into, then the functions it uses in each.
---@param m table
---@param path string
---@return seam.MapNode
function M.file(m, path)
  return {
    kind = 'file',
    key = path,
    path = path,
    label = path:match '[^/]+$',
    hl = 'SeamBold',
    kids = function()
      return vim.tbl_map(
        function(u)
          local f = u.files[1]
          return {
            kind = 'file',
            key = f.path,
            path = f.path,
            label = f.path:match '[^/]+$',
            hl = 'SeamName',
            count = names(u.n),
            cap = M.RANK_CAP,
            kids = function()
              return fns(m, f.ids)
            end,
          }
        end,
        gathered(m, data.within(path), function(p)
          return p
        end)
      )
    end,
  }
end

-- the takes and gives columns on a function's row
local function typed(r, node, o)
  local takes, gives = o.types(node.id)
  if not (takes or gives) then
    return
  end
  local paint = o.paint or function(row, text)
    row:add(text, 'SeamText')
  end
  r:to(math.max(TAKES, r.w + 2))
  paint(r, draw.trunc(takes or '', TAKES_W))
  r:to(math.max(GIVES, r.w + 2))
  paint(r, draw.trunc(gives or '', math.max(8, math.min(GIVES_W, o.width - r.w - 2))))
end

--- The rows of the tree from `root`.
---@param root seam.MapNode
---@param o seam.MapTreeOpts
---@return table[]
function M.draw(root, o)
  local out = {}
  if o.types then
    out[1] = draw.row():to(TAKES + 1):add('takes', 'SeamLabel'):to(GIVES + 1):add('gives', 'SeamLabel')
  end
  local function row(node, branch, depth)
    return draw.row { map = { kind = node.kind, id = node.id, path = node.path, name = node.label, branch = branch, depth = depth } }
  end
  local top = row(root, '', 0):add ' '
  top:add(root.label, root.hl == 'SeamMapFn' and 'SeamMapFnBold' or 'SeamBold')
  if o.types and root.id then
    typed(top, root, o)
  end
  out[#out + 1] = top
  local function walk(node, prefix, depth, branch, above)
    local open = o.open[branch]
    if not (open == true or (open ~= false and depth < o.levels)) then
      return false
    end
    local kids = node.kids()
    if #kids == 0 then
      return false
    end
    local cap = (depth == 0 or o.more[branch]) and #kids or (node.cap or M.CAP)
    if #out >= M.BUDGET then
      cap = 0
    end
    local shown = math.min(cap, #kids)
    local more = #kids - shown
    for j = 1, shown do
      local k = kids[j]
      local last = j == shown and more == 0
      local kb = branch .. '\n' .. k.key
      local r = row(k, kb, depth + 1):add(' ' .. prefix .. (last and '└─ ' or '├─ '), 'SeamMapLine')
      local seen = k.kind == 'fn' and above[k.key]
      local s0 = r.b
      r:add(k.label, k.hl)
      if seen then
        r.h[#r.h + 1] = { s0, r.b, 'SeamDim', 330 }
        r.meta.map.seen = true
      end
      if k.count then
        r:to(math.max(COUNT, r.w + 2)):add(k.count, 'SeamLabel')
      end
      if o.types and k.id then
        typed(r, k, o)
      end
      out[#out + 1] = r
      if not seen then
        above[k.key] = k.kind == 'fn' or nil
        if not walk(k, prefix .. (last and '   ' or '│  '), depth + 1, kb, above) then
          r.meta.map.leaf = #k.kids() == 0
        end
        above[k.key] = nil
      end
    end
    if more > 0 then
      local r = draw.row { map = { more = branch, depth = depth + 1 } }
      r:add(' ' .. prefix .. '└─ ', 'SeamMapLine'):add('⋯ ' .. more .. ' more', 'SeamLabel')
      out[#out + 1] = r
    end
    return true
  end
  walk(root, '', 0, '', { [root.key] = root.kind == 'fn' or nil })
  return out
end

--- Can the row's branch open a level deeper, or close? What `l` and `h` do there.
---@param meta table the row's meta.map
---@param o seam.MapTreeOpts
---@return 'open'|'more'|nil l, boolean h
function M.can(meta, o)
  if not meta then
    return nil, false
  end
  if meta.more then
    return 'more', false
  end
  if not meta.branch or meta.seen then
    return nil, false
  end
  if meta.leaf then
    return nil, o.open[meta.branch] == true
  end
  local open = o.open[meta.branch]
  local shows = open == true or (open ~= false and meta.depth < o.levels)
  return (not shows) and 'open' or nil, shows and meta.depth > 0
end

return M
