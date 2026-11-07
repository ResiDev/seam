-- The tree as data, no windows: folders, files, what each file declares at
-- its top in the file's order, its functions, types and values as `shows`
-- has them, and what each function or value calls, opened a level at a time
-- in the order first written; or the same tree with each level the most used
-- or the most calling first. The state is `st.outline`.
local data = require 'seam.map.data'
local graph = require 'seam.graph'
local index = require 'seam.index'
local tree = require 'seam.tree'
local M = {}

---@class seam.Outline
---@field order 'tree'|'used'|'calls'
---@field open table<string, boolean> a row's key -> opened (true) or closed (false); nil is its default
---@field cursor string|nil the key of the row under the cursor
---@field shows table<string, boolean> what a file lists, by M.SHOWS key: `f` functions, `t` types, `v` values, `e` its exports alone

---@class seam.ORow
---@field key string 'd:<path>' | 'f:<path>' | 'f:<path>\n<id>\n<id>...' (the node ids from the file down)
---@field kind 'dir'|'file'|'fn'|'type' a function's or value's node is 'fn', a type the file declares 'type'
---@field depth integer
---@field path string
---@field item table|nil the tree.walk item of a folder or file
---@field id string|nil a function's node id
---@field where 'here'|'file'|'pkg'|nil a call: in the file of the function it sits under, another file, another package
---@field can_open boolean
---@field open boolean
---@field seen boolean a call already open above on its branch: dim, it does not open
---@field used integer|nil the sorted orders: its fan-in, M.fan's
---@field calls integer|nil the sorted orders: its fan-out, M.fan's

---@class seam.Fan
---@field used integer the functions calling it; a file's or folder's from outside it
---@field calls integer the functions it calls; a file's or folder's outside it

M.ORDERS = { 'tree', 'used', 'calls' }

--- What a file can list, each on or off on its key: its functions,
--- components and classes; the types it declares; its values; and of
--- those, its exports alone.
M.SHOWS = {
  { key = 'f', word = 'functions' },
  { key = 't', word = 'types' },
  { key = 'v', word = 'values' },
  { key = 'e', word = 'exports only' },
}
-- a node's kind -> its M.SHOWS key
local KIND_KEY = { ['function'] = 'f', component = 'f', class = 'f', value = 'v' }

---@return seam.Outline
function M.new()
  return { order = 'tree', open = {}, shows = { f = true } }
end

--- What `o` lists, in words, when it is not every function: `types ·
--- values`, `functions · exports only`, `nothing`; nil for every function.
---@param o seam.Outline
---@return string|nil
function M.shows_word(o)
  local sh = o.shows
  if not (sh.f or sh.t or sh.v) then
    return 'nothing'
  end
  local on = {}
  for _, k in ipairs(M.SHOWS) do
    if sh[k.key] then
      on[#on + 1] = k.word
    end
  end
  return not (#on == 1 and sh.f) and table.concat(on, ' · ') or nil
end

-- the names each file exports, path -> name -> true, once for a model
local function exported(m)
  if not m.exported_by_path then
    local t = {}
    for _, e in ipairs(m.exports or {}) do
      t[e.path] = t[e.path] or {}
      t[e.path][e.name] = true
    end
    m.exported_by_path = t
  end
  return m.exported_by_path
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
    if KIND_KEY[n.kind] == 'f' then
      out[#out + 1] = n
    end
  end
  return out
end

---@class seam.Listed
---@field node table|nil a function's or value's node
---@field type table|nil a type the file declares (seam.written.types)
---@field line integer

--- What a file lists under `shows`, in the file's order.
---@param m table
---@param path string
---@param shows table<string, boolean>
---@return seam.Listed[]
function M.listed(m, path, shows)
  local out = {}
  for _, n in ipairs(m.graph and M.by_file(m.graph)[path] or {}) do
    if shows[KIND_KEY[n.kind]] and (n.exported or not shows.e) then
      out[#out + 1] = { node = n, line = n.line }
    end
  end
  if shows.t then
    local ex = exported(m)[path] or {}
    for _, d in ipairs(require('seam.written').types(path)) do
      if d.kind ~= 'class' and (d.exported or ex[d.name] or not shows.e) then
        out[#out + 1] = { type = d, line = d.line }
      end
    end
    table.sort(out, function(a, b)
      return a.line < b.line
    end)
  end
  return out
end

--- Every file the tree holds, path -> true: those with a function or an
--- export, no test, through the lens.
---@param m table
---@return table<string, true>
local function files(m)
  local top = graph.visible(m, 'top')
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

--- A node's two counts in `fan`, nothing there being none.
---@param fan table<string, seam.Fan>
---@param key string
---@return integer used, integer calls
function M.count(fan, key)
  local f = fan[key]
  if not f then
    return 0, 0
  end
  return f.used, f.calls
end

-- `list` the most `by` first, equals in the order they came
local function most_first(list, fan, by, key_of)
  local at, n = {}, {}
  for i, x in ipairs(list) do
    local used, calls = M.count(fan, key_of(x))
    at[x], n[x] = i, by == 'used' and used or calls
  end
  local out = { unpack(list) }
  table.sort(out, function(a, b)
    if n[a] ~= n[b] then
      return n[a] > n[b]
    end
    return at[a] < at[b]
  end)
  return out
end

-- every folder holding `path`, the deepest first
local function folders(path)
  local out = {}
  local p = path:match '^(.*)/[^/]*$'
  while p do
    out[#out + 1] = p
    p = p:match '^(.*)/[^/]*$'
  end
  return out
end

--- Fan-in and fan-out, once for a model and its lens, by key: a function's
--- node id, `f:<path>` a file's, `d:<path>` a folder's whole path. A
--- function: the functions calling it and those it calls. A file or a
--- folder: the functions outside it that call into it, and those outside
--- it that it calls. Each counted once; tests and a file's top left out.
---@param m table
---@return table<string, seam.Fan>
function M.fan(m)
  local c = m.outline_fan
  if c and c.visible == m.visible then
    return c.fan
  end
  local fan, g = {}, m.graph
  if g then
    local top, up = graph.visible(m, 'top'), graph.visible(m, 'up')
    for id, n in pairs(g.nodes) do
      if n.kind ~= 'module' and not n.test then
        fan[id] = { used = M.used_by(g, id, up), calls = #data.calls(m, id) }
      end
    end
    local into, outof, dirs = {}, {}, {}
    local function add(sets, key, id)
      sets[key] = sets[key] or {}
      sets[key][id] = true
    end
    -- the folders of `from` without `to` in them, deepest first
    local function apart(from, to)
      dirs[from] = dirs[from] or folders(from)
      local out = {}
      for _, d in ipairs(dirs[from]) do
        if to:sub(1, #d + 1) == d .. '/' then
          break
        end
        out[#out + 1] = d
      end
      return out
    end
    for _, e in ipairs(data.edges(m)) do
      local a, b = g.nodes[e.from], g.nodes[e.to]
      if a.kind ~= 'module' and a.path ~= b.path then
        add(outof, 'f:' .. a.path, e.to)
        for _, d in ipairs(apart(a.path, b.path)) do
          add(outof, 'd:' .. d, e.to)
        end
        if up(a.path) and top(b.path) then
          add(into, 'f:' .. b.path, e.from)
          for _, d in ipairs(apart(b.path, a.path)) do
            add(into, 'd:' .. d, e.from)
          end
        end
      end
    end
    for _, x in ipairs { { into, 'used' }, { outof, 'calls' } } do
      for key, set in pairs(x[1]) do
        fan[key] = fan[key] or { used = 0, calls = 0 }
        fan[key][x[2]] = vim.tbl_count(set)
      end
    end
  end
  m.outline_fan = { visible = m.visible, fan = fan }
  return fan
end

-- a tree.walk item's key in M.fan
local function fan_key(it)
  return it.kind == 'dir' and ('d:' .. M.full(it)) or ('f:' .. it.path)
end

-- the tree's folders and files with each level the most `by` first, equals
-- in the tree's order; once for a model, its lens and the order
local function walk_by(m, by)
  local c = m.outline_sorted
  if not (c and c.visible == m.visible) then
    c = { visible = m.visible }
    m.outline_sorted = c
  end
  if not c[by] then
    local fan = M.fan(m)
    local root = { kids = {} }
    local at = { [0] = root }
    for _, it in ipairs(walk(m)) do
      local n = { it = it, kids = {} }
      table.insert(at[it.depth].kids, n)
      at[it.depth + 1] = n
    end
    local items = {}
    local function key_of(x)
      return fan_key(x.it)
    end
    local function emit(n)
      for _, k in ipairs(most_first(n.kids, fan, by, key_of)) do
        items[#items + 1] = k.it
        emit(k)
      end
    end
    emit(root)
    c[by] = items
  end
  return c[by]
end

-- a call's row and, opened, the rows of what it calls under it
local function fn_rows(out, m, o, key, id, depth, under, chain)
  local g = m.graph
  local node = g.nodes[id]
  local row = { key = key, kind = 'fn', depth = depth, path = node.path, id = id, seen = chain[id] == true }
  local fan = o.order ~= 'tree' and M.fan(m)
  if fan then
    row.used, row.calls = M.count(fan, id)
  end
  if under then
    if node.path == under.path then
      row.where = 'here'
    elseif index.pkg_of(m, node.path) ~= index.pkg_of(m, under.path) then
      row.where = 'pkg'
    else
      row.where = 'file'
    end
  end
  local kids = not row.seen and graph.kids(g, id, 'down', graph.visible(m, 'down')) or {}
  if fan then
    kids = most_first(kids, fan, o.order, function(k)
      return k.id
    end)
  end
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

--- The rows the outline shows, top to bottom.
---@param m table the model
---@param o seam.Outline
---@return seam.ORow[]
function M.rows(m, o)
  local fan = o.order ~= 'tree' and M.fan(m)
  local out, skip = {}, nil
  for _, it in ipairs(fan and walk_by(m, o.order) or walk(m)) do
    if not (skip and it.depth > skip) then
      skip = nil
      local key = (it.kind == 'dir' and 'd:' or 'f:') .. it.path
      local row = { key = key, kind = it.kind, depth = it.depth, path = it.path, item = it, seen = false }
      local fns = it.kind == 'file' and M.listed(m, it.path, o.shows) or {}
      if fan then
        row.used, row.calls = M.count(fan, fan_key(it))
        fns = most_first(fns, fan, o.order, function(e)
          return e.node and e.node.id or ''
        end)
      end
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
        for _, e in ipairs(fns) do
          if e.node then
            fn_rows(out, m, o, key .. '\n' .. e.node.id, e.node.id, it.depth + 1, nil, {})
          else
            local d = e.type
            out[#out + 1] = {
              key = key .. '\ntype:' .. d.name,
              kind = 'type',
              depth = it.depth + 1,
              path = d.path,
              name = d.name,
              line = d.line,
              end_line = d.end_line,
              decl_kind = d.kind,
              can_open = false,
              open = false,
              seen = false,
            }
          end
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
--- path, and put the cursor on it, in whichever order; a function or value
--- of a kind the files do not list, that kind listed too, and one kept to
--- its file, not exports only. False when the tree
--- has no row for it.
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
  for _, it in ipairs(walk(m)) do
    local full = M.full(it)
    if it.kind == 'dir' and path:sub(1, #full + 1) == full .. '/' then
      o.open['d:' .. it.path] = true
    end
  end
  if node then
    o.open['f:' .. path] = true
    -- asked for by name, its kind is listed from now on, and kept ones too
    o.shows[KIND_KEY[node.kind]] = true
    if not node.exported then
      o.shows.e = nil
    end
  end
  o.cursor = key
  return true
end

--- What a key does to the outline, the cursor on row `i` of `rows`: `l`
--- opens the row, or goes into it when open; `h` closes it, or goes to the
--- row it hangs from; `s` the next order; `f` `t` `v` a kind a file lists
--- on or off, or exports only (M.SHOWS). Says what the screen does next:
--- draw the rows again, or move the cursor to `o.cursor`.
---@param m table
---@param o seam.Outline
---@param rows seam.ORow[]
---@param i integer
---@param k 'l'|'h'|'s'|'f'|'t'|'v'|'e'
---@return 'redraw'|'move'|nil
function M.key(m, o, rows, i, k)
  local row = rows[i]
  for _, kd in ipairs(M.SHOWS) do
    if k == kd.key then
      o.shows[k] = not o.shows[k]
      -- the cursor on its row, else on the nearest above it still shown
      local after, j = M.rows(m, o), row and i
      while j and not M.find(after, rows[j].key) do
        j = M.parent(rows, j)
      end
      o.cursor = j and rows[j].key or o.cursor
      return 'redraw'
    end
  end
  if k == 's' then
    local at = vim.fn.index(M.ORDERS, o.order) + 1
    o.order = M.ORDERS[at % #M.ORDERS + 1]
    if row then
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
