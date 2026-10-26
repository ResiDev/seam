-- The call tree, as data: what a function calls all the way down, or what
-- calls it all the way up, or everything from where the code starts; which
-- rows are open, what the budget opens for you, and what each key does to the
-- view. Pure: no windows, no state, so the specs drive it on a graph by hand.
local tree = require 'seam.tree'
local M = {}

---@class seam.Node
---@field id string 'path:line:name'; a file's top is 'path:0:'
---@field name string
---@field kind 'function'|'component'|'class'|'module'
---@field path string
---@field line integer
---@field end_line integer
---@field exported boolean
---@field test boolean

---@class seam.Call
---@field to string
---@field line integer
---@field col integer

---@class seam.Graph
---@field nodes table<string, seam.Node>
---@field down table<string, seam.Call[]> what each calls, as written
---@field up table<string, { from: string, line: integer, col: integer }[]> who calls each, by path then line
---@field memo table counts, until the lens changes

---@alias seam.Dir 'down'|'up'

---@class seam.CallsView
---@field anchor string|nil a node id; nil: from the top
---@field dir seam.Dir
---@field open table<string, boolean> row key -> opened (true) or folded (false) by hand
---@field auto table<string, true>|nil what the budget opened, for this anchor, direction and height
---@field height integer|nil the height `auto` was made for
---@field levels integer|nil the levels the budget opened
---@field cursor string|nil the key of the row under the cursor
---@field back table[] the views before each anchor, newest last
---@field code 'called'|'itself' what the code beside the tree shows: where the row is called, or the row itself
---@field step { key: string, code: string, n: integer }|nil the place or line `]]` and `[[` stepped to, on that row in that view

---@class seam.CallRow
---@field key string the ids from the top of the tree to it, one a line
---@field kind 'node'|'file'|'dir'|'tests'|'hidden'
---@field id string|nil the node, for 'node', and 'file' when the file's top is a root
---@field path string|nil
---@field pkg string|nil
---@field depth integer
---@field parent integer|nil the index of its row in the tree above it
---@field kids integer[] the indices of its rows, nearest first
---@field from string|nil the node it hangs from: its caller going down, its callee going up
---@field n integer how many times the call is written
---@field lines integer[] the lines of those calls, in the caller's file; a root's declaration line
---@field col integer|nil the first call's column
---@field root boolean|nil nothing calls it
---@field fold 'open'|'folded'|'leaf'|'also'
---@field also integer|nil an also row: the index of the row where it is open
---@field also_line integer|nil and the line that row shows
---@field count integer|nil distinct functions below it (down) or above it (up)
---@field used_by integer|nil distinct callers
---@field shared boolean|nil called by SHARED or more: the budget never opens it
---@field files integer|nil a tests row: how many test files
---@field hidden integer|boolean|nil a hidden row: how many it holds; a row under it: true
---@field show_file boolean its file is not the file of the row it hangs from
---@field last boolean the last of its parent's rows, in the tree's order
---@field touched boolean|nil a dir row with roots under it
---@field segs string[]|nil a dir row's names

---@class seam.CallRows
---@field rows seam.CallRow[] in screen order, each row above the rows under it
---@field anchor string|nil
---@field dir seam.Dir
---@field shared string[] the shared nodes in view, not open
---@field levels integer the levels the budget opened

--- Called by this many or more, a function is a utility the budget leaves folded.
M.SHARED = 5

local function all()
  return true
end

--- The lens column each way of reading the tree follows: what a function
--- calls is what it is built from, what calls it is what uses it, and the
--- starts from the top are the contracts. Every count and list goes by it.
M.LENS = { down = 'built', up = 'used', top = 'contracts' }

--- Whether a path shows, read `way`, under the model's lens.
---@param m table|nil the model, its lens in m.visible
---@param way seam.Dir|'top'
---@return fun(path: string): boolean
function M.visible(m, way)
  local v, col = m and m.visible, M.LENS[way]
  return v and function(path)
    return v(path, col)
  end or all
end

local function memo(g, what)
  g.memo = g.memo or {}
  g.memo[what] = g.memo[what] or {}
  return g.memo[what]
end

--- Forget the counts: the lens changed.
---@param g seam.Graph|nil
function M.forget(g)
  if g then
    g.memo = {}
  end
end

local function reach(g, id, visible, edges, field)
  local seen, stack, n = { [id] = true }, { id }, 0
  while #stack > 0 do
    local cur = table.remove(stack)
    for _, e in ipairs(edges[cur] or {}) do
      local to = e[field]
      local node = g.nodes[to]
      if not seen[to] and node and visible(node.path) then
        seen[to] = true
        n = n + 1
        stack[#stack + 1] = to
      end
    end
  end
  return n
end

--- Distinct functions reachable down from `id`, itself not counted.
---@param g seam.Graph
---@param id string
---@param visible? fun(path: string): boolean
---@return integer
function M.below(g, id, visible)
  local c = memo(g, 'below')
  c[id] = c[id] or reach(g, id, visible or all, g.down, 'to')
  return c[id]
end

--- Distinct functions reachable up from `id`, itself not counted.
---@param g seam.Graph
---@param id string
---@param visible? fun(path: string): boolean
---@return integer
function M.above(g, id, visible)
  local c = memo(g, 'above')
  c[id] = c[id] or reach(g, id, visible or all, g.up, 'from')
  return c[id]
end

--- Distinct callers of `id`.
---@param g seam.Graph
---@param id string
---@param visible? fun(path: string): boolean
---@return integer
function M.used_by(g, id, visible)
  local c = memo(g, 'used_by')
  if not c[id] then
    visible = visible or all
    local seen, n = {}, 0
    for _, u in ipairs(g.up[id] or {}) do
      if not seen[u.from] and visible(g.nodes[u.from].path) then
        seen[u.from] = true
        n = n + 1
      end
    end
    c[id] = n
  end
  return c[id]
end

--- What nothing calls, by id: where the code starts, the tests apart, and
--- apart again those `visible` hides. A test calling a function does not make
--- it any less a start.
---@param g seam.Graph
---@param visible? fun(path: string): boolean
---@return string[] roots, string[] tests, string[] hidden
function M.roots(g, visible)
  visible = visible or all
  local roots, tests, hidden = {}, {}, {}
  for id, node in pairs(g.nodes) do
    local called = false
    for _, u in ipairs(g.up[id] or {}) do
      if u.from ~= id and not g.nodes[u.from].test then
        called = true
        break
      end
    end
    if not called then
      table.insert(not visible(node.path) and hidden or node.test and tests or roots, id)
    end
  end
  local function by_place(a, b)
    local na, nb = g.nodes[a], g.nodes[b]
    if na.path ~= nb.path then
      return na.path < nb.path
    end
    return na.line < nb.line
  end
  table.sort(roots, by_place)
  table.sort(tests, by_place)
  table.sort(hidden, by_place)
  return roots, tests, hidden
end

--- A node's rows one level on: the distinct functions it calls, in the order
--- first written, or that call it, by path then line; tests apart, going up,
--- and those `visible` hides apart.
---@param g seam.Graph
---@param id string
---@param dir seam.Dir
---@param visible? fun(path: string): boolean
---@return { id: string, n: integer, lines: integer[], col: integer }[] kids, table[] tests, table[] hidden
function M.kids(g, id, dir, visible)
  visible = visible or all
  local kids, tests, hidden, at = {}, {}, {}, {}
  local edges, field = g.down[id] or {}, 'to'
  if dir == 'up' then
    edges, field = g.up[id] or {}, 'from'
  end
  for _, e in ipairs(edges) do
    local to = e[field]
    local node = g.nodes[to]
    if node then
      local k = at[to]
      if k then
        k.n = k.n + 1
        if k.lines[#k.lines] ~= e.line then
          k.lines[#k.lines + 1] = e.line
        end
      else
        k = { id = to, n = 1, lines = { e.line }, col = e.col }
        at[to] = k
        local list = not visible(node.path) and hidden or (dir == 'up' and node.test) and tests or kids
        list[#list + 1] = k
      end
    end
  end
  return kids, tests, hidden
end

---------------------------------------------------------------- the tree

local function test_files(g, list)
  local seen, n = {}, 0
  for _, k in ipairs(list) do
    local p = g.nodes[k.id].path
    if not seen[p] then
      seen[p] = true
      n = n + 1
    end
  end
  return n
end

-- The tree of a view, `is_open` saying which keys are open (true), folded
-- (false) or neither (nil: a folder or file is open, the rest folded): every
-- row with the rows under it (`sub`), flat in screen order. Also the rows one
-- call from the top, where the budget starts.
local function walk(g, view, is_open, m)
  local dir = view.dir
  local visible = M.visible(m, dir)
  local owner = {} -- id -> the row it opens at
  local first = {}
  local function node_row(key, k, from, depth)
    return { key = key, kind = 'node', id = k.id, n = k.n, lines = k.lines, col = k.col, from = from, root = from == nil or nil, depth = depth, sub = {} }
  end
  -- the tests, or what the lens hides, folded into one row
  local function group_row(kind, key, list, from, depth)
    return { key = key, kind = kind, list = list, files = kind == 'tests' and test_files(g, list) or nil, from = from, depth = depth, sub = {} }
  end
  local function grow(r)
    if r.list then
      for _, k in ipairs(r.list) do
        local s = node_row(r.key .. '\n' .. k.id, k, r.from, r.depth + 1)
        s.hidden = r.kind == 'hidden' or nil
        r.sub[#r.sub + 1] = s
      end
      return
    end
    local kids, tests, hidden = M.kids(g, r.id, dir, visible)
    for _, k in ipairs(kids) do
      r.sub[#r.sub + 1] = node_row(r.key .. '\n' .. k.id, k, r.id, r.depth + 1)
    end
    vim.list_extend(r.sub, r.extra or {})
    if #tests > 0 then
      r.sub[#r.sub + 1] = group_row('tests', r.key .. '\ntests', tests, r.id, r.depth + 1)
    end
    if #hidden > 0 then
      r.sub[#r.sub + 1] = group_row('hidden', r.key .. '\nhidden', hidden, r.id, r.depth + 1)
    end
  end
  local function has_kids(r)
    if r.list or (r.extra and #r.extra > 0) then
      return true
    end
    local kids, tests, hidden = M.kids(g, r.id, dir, visible)
    return #kids + #tests + #hidden > 0
  end

  local top = {}
  if view.anchor then
    if not g.nodes[view.anchor] then
      return {}, {}
    end
    local a = { key = view.anchor, kind = 'node', id = view.anchor, depth = -1, sub = {} }
    owner[view.anchor] = a
    grow(a)
    top, first = a.sub, a.sub
  else
    local roots, tests, hidden = M.roots(g, M.visible(m, 'top'))
    local entries = {}
    for _, id in ipairs(roots) do
      local p = g.nodes[id].path
      entries[p] = entries[p] or {}
      table.insert(entries[p], id)
    end
    local dirs = {} -- the dir row open at each depth
    local shut -- the depth of a folder folded by hand: what is deeper is in it
    for _, it in ipairs(tree.walk(m, entries)) do
      if shut and it.depth <= shut then
        shut = nil
      end
      if not shut then
        local r = {
          key = it.kind .. ':' .. it.path,
          kind = it.kind,
          path = it.path,
          pkg = it.pkg,
          depth = it.depth,
          touched = it.touched,
          segs = it.segs,
          ispkg = it.ispkg,
          sub = {},
        }
        local closed = is_open(r.key) == false
        if it.kind == 'file' then
          table.sort(it.payload, function(a, b)
            return g.nodes[a].line < g.nodes[b].line
          end)
          local rest = {}
          for _, id in ipairs(it.payload) do
            if g.nodes[id].kind == 'module' then
              r.id, r.root, r.lines = id, true, { 0 }
            else
              rest[#rest + 1] = node_row(r.key .. '\n' .. id, { id = id, n = 1, lines = { g.nodes[id].line } }, nil, it.depth + 1)
            end
          end
          if r.id then
            -- the file's top is a root: the file is its row, and its other roots open with it
            r.extra = rest
            first[#first + 1] = r
          elseif closed then
            r.fold = 'folded'
          else
            r.sub = rest
            vim.list_extend(first, rest)
          end
        elseif closed and it.touched then
          r.fold, shut = 'folded', it.depth
        end
        local parent = dirs[it.depth - 1]
        table.insert(parent and parent.sub or top, r)
        if it.kind == 'dir' then
          dirs[it.depth] = r
        end
      end
    end
    for _, kind in ipairs { 'tests', 'hidden' } do
      local ids = kind == 'tests' and tests or hidden
      if #ids > 0 then
        local list = {}
        for _, id in ipairs(ids) do
          list[#list + 1] = { id = id, n = 1, lines = { g.nodes[id].line } }
        end
        local t = group_row(kind, kind, list, nil, 0)
        top[#top + 1] = t
        first[#first + 1] = t
      end
    end
  end

  -- breadth first, so a node opens at its shallowest, then earliest, row;
  -- anywhere else it is `also`
  local queue, qi = vim.list_slice(first), 1
  while qi <= #queue do
    local r = queue[qi]
    qi = qi + 1
    local mine = r.list or not owner[r.id]
    if not r.list then
      owner[r.id] = owner[r.id] or r
    end
    if not has_kids(r) then
      r.fold = 'leaf'
    elseif not mine then
      r.fold, r.owner = 'also', owner[r.id]
    elseif is_open(r.key) then
      r.fold = 'open'
      grow(r)
      vim.list_extend(queue, r.sub)
    else
      r.fold = 'folded'
    end
  end

  local flat = {}
  local function emit(r, parent, last)
    flat[#flat + 1] = r
    r.parent_row, r.last = parent, last
    for j, s in ipairs(r.sub) do
      emit(s, r, j == #r.sub)
    end
  end
  for j, r in ipairs(top) do
    emit(r, nil, j == #top)
  end
  for i, r in ipairs(flat) do
    r.i = i
  end
  return flat, first
end

-- The rows as the screen draws them: indices for parents and kids, counts.
local function finish(g, view, flat, m)
  local down, up = M.visible(m, 'down'), M.visible(m, 'up')
  local rows, shared, seen = {}, {}, {}
  for i, r in ipairs(flat) do
    local row = {
      key = r.key,
      kind = r.kind,
      id = r.id,
      path = r.path,
      pkg = r.pkg,
      depth = r.depth,
      parent = r.parent_row and r.parent_row.i,
      kids = {},
      from = r.from,
      n = r.n or 1,
      lines = r.lines or {},
      col = r.col,
      root = r.root,
      fold = r.fold or (#r.sub > 0 and 'open' or 'leaf'),
      files = r.files,
      hidden = r.kind == 'hidden' and #r.list or r.hidden,
      touched = r.touched,
      segs = r.segs,
      ispkg = r.ispkg,
      last = r.last,
      show_file = false,
    }
    for _, s in ipairs(r.sub) do
      row.kids[#row.kids + 1] = s.i
    end
    if r.id then
      row.path = g.nodes[r.id].path
      row.count = view.dir == 'up' and M.above(g, r.id, up) or M.below(g, r.id, down)
      row.used_by = M.used_by(g, r.id, up)
      row.shared = row.used_by >= M.SHARED
      local from = r.parent_row and (r.parent_row.id and g.nodes[r.parent_row.id].path or r.parent_row.path) or (view.anchor and g.nodes[view.anchor].path)
      row.show_file = r.kind == 'node' and row.path ~= from
      if row.shared and row.fold == 'folded' and not seen[r.id] then
        seen[r.id] = true
        shared[#shared + 1] = r.id
      end
    end
    if r.owner then
      row.also = r.owner.i
      row.also_line = r.owner.lines and r.owner.lines[1] or g.nodes[r.id].line
    end
    rows[i] = row
  end
  return rows, shared
end

-- What the budget opens: whole levels, breadth first, while every row fits
-- in `height`; never a shared node, a tests or hidden row, or an also row.
-- From the top of the tree, or with `start` from that row, its rows alone
-- counted, the rest open as `base` says.
local function budget(g, view, height, m, base, start)
  local visible, up = M.visible(m, view.dir), M.visible(m, 'up')
  local opened, levels = {}, 0
  local function is_open(key)
    local o = base and base[key]
    if o == nil then
      return opened[key]
    end
    return o
  end
  local parents -- the keys of the level opened last
  while true do
    local flat, first = walk(g, view, is_open, m)
    local count, frontier = #flat, first
    if start then
      local root
      for _, r in ipairs(flat) do
        root = r.key == start and r or root
      end
      if not root then
        break
      end
      count = 0
      local function size(r)
        count = count + 1
        for _, s in ipairs(r.sub) do
          size(s)
        end
      end
      size(root)
      parents = parents or { [start] = true }
    end
    if parents then
      frontier = {}
      for _, r in ipairs(flat) do
        if r.parent_row and parents[r.parent_row.key] then
          frontier[#frontier + 1] = r
        end
      end
    end
    -- a row already open is passed through to the level under it
    local cand, cost, through = {}, 0, {}
    for _, r in ipairs(frontier) do
      if r.fold == 'open' then
        through[r.key] = true
      elseif r.fold == 'folded' and not r.list and M.used_by(g, r.id, up) < M.SHARED then
        cand[#cand + 1] = r
        through[r.key] = true
        local kids, tests, hidden = M.kids(g, r.id, view.dir, visible)
        cost = cost + #kids + (#tests > 0 and 1 or 0) + (#hidden > 0 and 1 or 0) + #(r.extra or {})
      end
    end
    if next(through) == nil or count + cost > height then
      break
    end
    for _, r in ipairs(cand) do
      opened[r.key] = true
    end
    levels = levels + (#cand > 0 and 1 or 0)
    parents = through
  end
  return opened, levels
end

--- A fresh view: on `anchor` in `dir`, or from the top.
---@param anchor string|nil
---@param dir? seam.Dir
---@return seam.CallsView
function M.new(anchor, dir)
  return { anchor = anchor, dir = anchor and dir or 'down', open = {}, back = {}, code = 'called' }
end

local function opener(view)
  return function(key)
    local o = view.open[key]
    if o == nil then
      return view.auto and view.auto[key] or nil
    end
    return o
  end
end

--- The rows of a view in a list `height` rows high. Opens what the budget
--- opens the first time, and again for another height.
---@param g seam.Graph
---@param view seam.CallsView
---@param height integer
---@param m table the model: its packages, and the lens in m.visible
---@return seam.CallRows
function M.rows(g, view, height, m)
  if not view.auto or view.height ~= height then
    view.auto, view.levels = budget(g, view, height, m)
    view.height = height
  end
  local flat = walk(g, view, opener(view), m)
  local rows, shared = finish(g, view, flat, m)
  return { rows = rows, anchor = view.anchor, dir = view.dir, shared = shared, levels = view.levels or 0 }
end

---------------------------------------------------------------- the code

--- Every place `id` is called: a caller and a line each, a caller calling
--- it on two lines two places; by path then line, the tests' after.
---@param g seam.Graph
---@param id string
---@param visible? fun(path: string): boolean
---@return { from: string, line: integer, col: integer }[]
function M.places(g, id, visible)
  visible = visible or all
  local out, tests, seen = {}, {}, {}
  for _, u in ipairs(g.up[id] or {}) do
    local k = u.from .. '\n' .. u.line
    local by = g.nodes[u.from]
    if not seen[k] and visible(by.path) then
      seen[k] = true
      table.insert(by.test and tests or out, u)
    end
  end
  return vim.list_extend(out, tests)
end

--- The lines of `id` that call something, in order.
---@param g seam.Graph
---@param id string
---@param visible? fun(path: string): boolean
---@return integer[]
function M.call_lines(g, id, visible)
  visible = visible or all
  local out, seen = {}, {}
  for _, c in ipairs(g.down[id] or {}) do
    if not seen[c.line] and visible(g.nodes[c.to].path) then
      seen[c.line] = true
      out[#out + 1] = c.line
    end
  end
  table.sort(out)
  return out
end

---@class seam.CallsPane
---@field node seam.Node
---@field code 'called'|'itself' what is shown: itself when nothing calls it, whatever the view chose
---@field places table[] where it is called
---@field lines integer[] its lines that call something
---@field n integer the place shown, or the line lit (0: none)

--- What the code beside the tree shows for row `i` (nil: the anchor): the
--- view's choice, on the place the tree is about until `]]` or `[[` moves
--- it. Going down that is the call its parent makes; going up, the row is
--- the caller and its own call to its parent is lit in itself. Nil for a
--- folder, a file that is not a start, tests or what the lens hides.
---@param g seam.Graph
---@param view seam.CallsView
---@param r seam.CallRows
---@param i integer|nil
---@param m? table
---@return seam.CallsPane|nil
function M.pane(g, view, r, i, m)
  local x = i and r.rows[i]
  local id = x and x.id or (not x and view.anchor)
  local node = id and g.nodes[id]
  if not node then
    return nil
  end
  local places = M.places(g, id, M.visible(m, 'up'))
  if #places == 0 then
    -- the lens hides every caller: still not where the code starts
    places = M.places(g, id)
  end
  local p = { node = node, places = places, lines = M.call_lines(g, id, M.visible(m, 'down')), n = 0 }
  p.code = #p.places == 0 and 'itself' or view.code or 'called'
  local key = x and x.key or ''
  local s = view.step
  if s and s.key == key and s.code == p.code then
    p.n = s.n
  elseif p.code == 'called' then
    p.n = 1
    if x and x.from and view.dir == 'down' then
      for j, u in ipairs(p.places) do
        if u.from == x.from and u.line == x.lines[1] then
          p.n = j
          break
        end
      end
    end
  elseif x and x.from and view.dir == 'up' then
    p.n = vim.fn.index(p.lines, x.lines[1]) + 1
  end
  return p
end

---------------------------------------------------------------- keys

local function snapshot(view)
  return {
    anchor = view.anchor,
    dir = view.dir,
    open = vim.deepcopy(view.open),
    auto = view.auto,
    height = view.height,
    levels = view.levels,
    cursor = view.cursor,
  }
end

-- every field, a missing one too: the lens may have dropped its `auto`
local function restore(view, s)
  for _, k in ipairs { 'anchor', 'dir', 'open', 'auto', 'height', 'levels', 'cursor' } do
    view[k] = s[k]
  end
end

local function reset(view)
  view.open, view.auto, view.height, view.levels, view.cursor, view.step = {}, nil, nil, nil, nil, nil
end

-- the sibling of row `i` the `d`th on screen from it, down (1) or up (-1)
local function sibling(r, i, d)
  local row = r.rows[i]
  local list = {}
  if row.parent then
    list = r.rows[row.parent].kids
  else
    for j, x in ipairs(r.rows) do
      if not x.parent then
        list[#list + 1] = j
      end
    end
  end
  local best
  for _, j in ipairs(list) do
    if (d > 0 and j > i and (not best or j < best)) or (d < 0 and j < i and (not best or j > best)) then
      best = j
    end
  end
  return best
end

--- What a key does to the view, the cursor on row `i` of `r`. Says what the
--- screen does next: draw the rows again, move the cursor to `view.cursor`,
--- draw the code beside the tree again, or go back to the explorer.
---@param g seam.Graph
---@param view seam.CallsView
---@param r seam.CallRows
---@param i integer
---@param k string
---@param height integer
---@param m? table
---@return 'redraw'|'move'|'explorer'|'pane'|nil
function M.key(g, view, r, i, k, height, m)
  local row = r.rows[i]
  local function go(j)
    if j and r.rows[j] then
      view.cursor = r.rows[j].key
      return 'move'
    end
  end
  if k == 'j' then
    return go(math.min(i + 1, #r.rows))
  elseif k == 'k' then
    return go(math.max(i - 1, 1))
  elseif k == ']' then
    return go(sibling(r, i, 1))
  elseif k == '[' then
    return go(sibling(r, i, -1))
  elseif k == '<BS>' or k == 'K' then
    local s = table.remove(view.back)
    if not s then
      return 'explorer'
    end
    restore(view, s)
    return 'redraw'
  elseif k == 'C' then
    view.back[#view.back + 1] = snapshot(view)
    view.anchor, view.dir = nil, 'down'
    reset(view)
    return 'redraw'
  elseif k == '~' then
    if not view.anchor then
      return nil
    end
    view.dir = view.dir == 'down' and 'up' or 'down'
    reset(view)
    return 'redraw'
  elseif k == '<Tab>' then
    view.code = view.code == 'itself' and 'called' or 'itself'
    return 'pane'
  elseif k == ']]' or k == '[[' then
    local p = M.pane(g, view, r, r.rows[i] and i or nil, m)
    local list = p and (p.code == 'called' and p.places or p.lines) or {}
    if #list == 0 then
      return nil
    end
    local n = p.n
    if k == ']]' then
      n = n % #list + 1
    else
      n = n <= 1 and #list or n - 1
    end
    view.step = { key = r.rows[i] and r.rows[i].key or '', code = p.code, n = n }
    return 'pane'
  end
  if not row then
    return nil
  end
  if k == 'l' then
    if row.fold == 'also' then
      return go(row.also)
    elseif row.fold == 'folded' then
      view.open[row.key] = true
      view.cursor = row.key
      return 'redraw'
    elseif row.fold == 'open' then
      return go(row.kids[1])
    end
  elseif k == 'h' then
    if row.fold == 'open' then
      view.open[row.key] = false
      view.cursor = row.key
      return 'redraw'
    end
    return go(row.parent)
  elseif k == 'O' then
    if not (row.fold == 'folded' or row.fold == 'open') or not (row.id or row.kind == 'tests' or row.kind == 'hidden') then
      return nil
    end
    local base = vim.deepcopy(view.open)
    base[row.key] = true
    for key, v in pairs(view.auto or {}) do
      if base[key] == nil then
        base[key] = v
      end
    end
    local opened = budget(g, view, height, m, base, row.key)
    view.open[row.key] = true
    for key in pairs(opened) do
      view.open[key] = true
    end
    view.cursor = row.key
    return 'redraw'
  elseif k == 'H' then
    local pre = row.key .. '\n'
    for key in pairs(view.open) do
      if key == row.key or key:sub(1, #pre) == pre then
        view.open[key] = nil
      end
    end
    view.cursor = row.key
    return 'redraw'
  elseif k == '<CR>' then
    if not row.id then
      return nil
    end
    view.back[#view.back + 1] = snapshot(view)
    view.anchor = row.id
    reset(view)
    return 'redraw'
  end
end

return M
