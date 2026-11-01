-- The tree as data, no windows: folders, files, each file's functions in
-- the file's order, and what each function calls, opened a level at a time
-- in the order first written; or every function, the most used or the most
-- calling first. The state is `st.outline`.
local calls = require 'seam.calls'
local index = require 'seam.index'
local tree = require 'seam.tree'
local M = {}

---@class seam.Outline
---@field order 'tree'|'used'|'calls'
---@field open table<string, boolean> a row's key -> opened (true) or closed (false); nil is its default
---@field cursor string|nil the key of the row under the cursor

---@class seam.ORow
---@field key string 'd:<path>' | 'f:<path>' | 'f:<path>\n<id>\n<id>...' (the node ids from the file down)
---@field kind 'dir'|'file'|'fn'
---@field depth integer
---@field path string
---@field item table|nil the tree.walk item of a folder or file
---@field id string|nil a function's node id
---@field where 'here'|'file'|'pkg'|nil a call: in the file of the function it sits under, another file, another package
---@field can_open boolean
---@field open boolean
---@field seen boolean a call already open above on its branch: dim, it does not open
---@field used integer|nil the sorted orders: the functions calling it, tests left out
---@field calls integer|nil the sorted orders: the functions it calls

M.ORDERS = { 'tree', 'used', 'calls' }

---@return seam.Outline
function M.new()
  return { order = 'tree', open = {} }
end

--- Each file's nodes by line, the file's top (a module node) first.
---@param g seam.Graph
---@return table<string, table[]>
function M.by_file(g)
  if not g.byfile then
    local t = {}
    for _, n in pairs(g.nodes) do
      t[n.path] = t[n.path] or {}
      table.insert(t[n.path], n)
    end
    for _, list in pairs(t) do
      table.sort(list, function(a, b)
        return a.line < b.line
      end)
    end
    g.byfile = t
  end
  return g.byfile
end

--- A file's functions, components and classes, in the file's order.
---@param m table
---@param path string
---@return table[]
function M.functions(m, path)
  local out = {}
  for _, n in ipairs(m.graph and M.by_file(m.graph)[path] or {}) do
    if n.kind ~= 'module' then
      out[#out + 1] = n
    end
  end
  return out
end

--- Every file the tree holds, path -> true: those with a function or an
--- export, no test, through the lens.
---@param m table
---@return table<string, true>
local function files(m)
  local top = calls.visible(m, 'top')
  local out = {}
  local function add(path)
    if not out[path] and not index.is_test(path) and top(path) then
      out[path] = true
    end
  end
  for path in pairs(m.graph and M.by_file(m.graph) or {}) do
    add(path)
  end
  for _, e in ipairs(m.exports or {}) do
    add(e.path)
  end
  return out
end
M.files = files

--- How many of the tree's files are in folder `dir`.
---@param m table
---@param dir string
---@return integer
function M.files_under(m, dir)
  local n = 0
  for path in pairs(files(m)) do
    if path:sub(1, #dir + 1) == dir .. '/' then
      n = n + 1
    end
  end
  return n
end

-- the tree's folders and files, walked once for a model and its lens
local function walk(m)
  local c = m.outline_walk
  if not (c and c.visible == m.visible) then
    c = { visible = m.visible, items = tree.walk(m, files(m)) }
    m.outline_walk = c
  end
  return c.items
end

--- A folder row's whole path, a chain of lone folders joined.
---@param it table a tree.walk item
---@return string
function M.full(it)
  if not it.segs or #it.segs < 2 then
    return it.path
  end
  return it.path .. '/' .. table.concat(it.segs, '/', 2)
end

-- a folder open until closed: a package, or one holding a package; with no
-- packages, the top folders
local function open_first(m, it)
  if it.ispkg then
    return true
  end
  if #m.pkgsorted == 0 then
    return it.depth == 0
  end
  local full = M.full(it)
  for _, p in ipairs(m.pkgsorted) do
    if p:sub(1, #full + 1) == full .. '/' then
      return true
    end
  end
  return false
end

-- a call's row and, opened, the rows of what it calls under it
local function fn_rows(out, m, o, key, id, depth, under, chain)
  local g = m.graph
  local node = g.nodes[id]
  local row = { key = key, kind = 'fn', depth = depth, path = node.path, id = id, seen = chain[id] == true }
  if under then
    if node.path == under.path then
      row.where = 'here'
    elseif index.pkg_of(m, node.path) ~= index.pkg_of(m, under.path) then
      row.where = 'pkg'
    else
      row.where = 'file'
    end
  end
  local kids = not row.seen and calls.kids(g, id, 'down', calls.visible(m, 'down')) or {}
  row.can_open = #kids > 0
  row.open = row.can_open and o.open[key] == true
  out[#out + 1] = row
  if row.open then
    chain[id] = true
    for _, k in ipairs(kids) do
      fn_rows(out, m, o, key .. '\n' .. k.id, k.id, depth + 1, node, chain)
    end
    chain[id] = nil
  end
  return row
end

--- The functions calling `id`, each once, tests and a file's top left out.
---@param g seam.Graph
---@param id string
---@param visible fun(path: string): boolean
---@return integer
function M.used_by(g, id, visible)
  local seen, n = {}, 0
  for _, u in ipairs(g.up[id] or {}) do
    local from = g.nodes[u.from]
    if not seen[u.from] and not from.test and from.kind ~= 'module' and visible(from.path) then
      seen[u.from] = true
      n = n + 1
    end
  end
  return n
end

-- every function, the most used or the most calling first, then by name
local function sorted(m, o)
  local g = m.graph
  if not g then
    return {}
  end
  local top, up, down = calls.visible(m, 'top'), calls.visible(m, 'up'), calls.visible(m, 'down')
  local list = {}
  for id, n in pairs(g.nodes) do
    if n.kind ~= 'module' and not n.test and top(n.path) then
      list[#list + 1] = { n = n, used = M.used_by(g, id, up), calls = #calls.kids(g, id, 'down', down) }
    end
  end
  local by = o.order
  table.sort(list, function(a, b)
    if a[by] ~= b[by] then
      return a[by] > b[by]
    end
    if a.n.name ~= b.n.name then
      return a.n.name < b.n.name
    end
    if a.n.path ~= b.n.path then
      return a.n.path < b.n.path
    end
    return a.n.line < b.n.line
  end)
  local out = {}
  for _, x in ipairs(list) do
    local row = fn_rows(out, m, o, 'f:' .. x.n.path .. '\n' .. x.n.id, x.n.id, 0, nil, {})
    row.used, row.calls = x.used, x.calls
  end
  return out
end

--- The rows the outline shows, top to bottom.
---@param m table the model
---@param o seam.Outline
---@return seam.ORow[]
function M.rows(m, o)
  if o.order ~= 'tree' then
    return sorted(m, o)
  end
  local out, skip = {}, nil
  for _, it in ipairs(walk(m)) do
    if not (skip and it.depth > skip) then
      skip = nil
      local key = (it.kind == 'dir' and 'd:' or 'f:') .. it.path
      local row = { key = key, kind = it.kind, depth = it.depth, path = it.path, item = it, seen = false }
      local fns = it.kind == 'file' and M.functions(m, it.path) or {}
      if it.kind == 'dir' then
        row.can_open = it.touched == true
      else
        row.can_open = #fns > 0
      end
      if row.can_open then
        local want = o.open[key]
        if want == nil then
          want = it.kind == 'dir' and open_first(m, it)
        end
        row.open = want == true
      else
        row.open = false
      end
      out[#out + 1] = row
      if not row.open then
        skip = it.depth
      else
        for _, n in ipairs(fns) do
          fn_rows(out, m, o, key .. '\n' .. n.id, n.id, it.depth + 1, nil, {})
        end
      end
    end
  end
  return out
end

--- The row `i` hangs from: the nearest above it, less deep.
---@param rows seam.ORow[]
---@param i integer
---@return integer|nil
function M.parent(rows, i)
  local d = rows[i] and rows[i].depth or 0
  for j = i - 1, 1, -1 do
    if rows[j].depth < d then
      return j
    end
  end
end

--- The row with `key`, by index.
---@param rows seam.ORow[]
---@param key string|nil
---@return integer|nil
function M.find(rows, key)
  for i, r in ipairs(rows) do
    if r.key == key then
      return i
    end
  end
end

--- Open the folders and the file down to `target`, a node id or a file's
--- path, and put the cursor on it; in a sorted order, on the function when
--- it is listed, else back to the tree. False when the tree has no row for it.
---@param m table
---@param o seam.Outline
---@param target string
---@return boolean
function M.reveal(m, o, target)
  local node = m.graph and m.graph.nodes[target]
  if node and node.kind == 'module' then
    target, node = node.path, nil
  end
  local path = node and node.path or target
  if not files(m)[path] then
    return false
  end
  local key = 'f:' .. path .. (node and ('\n' .. node.id) or '')
  if o.order ~= 'tree' then
    if node and M.find(M.rows(m, o), key) then
      o.cursor = key
      return true
    end
    o.order = 'tree'
  end
  for _, it in ipairs(walk(m)) do
    local full = M.full(it)
    if it.kind == 'dir' and path:sub(1, #full + 1) == full .. '/' then
      o.open['d:' .. it.path] = true
    end
  end
  if node then
    o.open['f:' .. path] = true
  end
  o.cursor = key
  return true
end

--- What a key does to the outline, the cursor on row `i` of `rows`: `l`
--- opens the row, or goes into it when open; `h` closes it, or goes to the
--- row it hangs from; `s` the next order. Says what the screen does next:
--- draw the rows again, or move the cursor to `o.cursor`.
---@param m table
---@param o seam.Outline
---@param rows seam.ORow[]
---@param i integer
---@param k 'l'|'h'|'s'
---@return 'redraw'|'move'|nil
function M.key(m, o, rows, i, k)
  local row = rows[i]
  if k == 's' then
    local at = vim.fn.index(M.ORDERS, o.order) + 1
    o.order = M.ORDERS[at % #M.ORDERS + 1]
    if row then
      o.cursor = row.key
    end
    -- back in the tree, the function the cursor was on is shown where it lives
    local top = row and row.kind == 'fn' and row.key:match '^f:[^\n]*\n([^\n]*)'
    if o.order == 'tree' and top then
      M.reveal(m, o, top)
      o.cursor = row.key
    end
    return 'redraw'
  end
  if not row then
    return nil
  end
  if k == 'l' then
    if row.can_open and not row.open then
      o.open[row.key] = true
      o.cursor = row.key
      return 'redraw'
    elseif row.open and rows[i + 1] and rows[i + 1].depth > row.depth then
      o.cursor = rows[i + 1].key
      return 'move'
    end
  elseif k == 'h' then
    if row.open then
      o.open[row.key] = false
      o.cursor = row.key
      return 'redraw'
    end
    local p = M.parent(rows, i)
    if p then
      o.cursor = rows[p].key
      return 'move'
    end
  end
  return nil
end

return M
