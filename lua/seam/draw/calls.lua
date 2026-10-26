-- The Calls screen drawn: its head, the anchor pinned above the tree, the
-- tree, and the code of the row under the cursor: where it is called, or
-- itself.
local api = vim.api
local calls = require 'seam.calls'
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local theme = require 'seam.theme'
local tree = require 'seam.tree'
local M = {}

local row, trunc, shape = draw.row, draw.trunc, draw.shape

-- the tree's width, and where its columns end or start
M.LW = 86
local COUNT_END, USED_END, FILE_AT, LINE_AT = 52, 61, 64, 79

local function base(path)
  return path:match '[^/]+$' or path
end

local function label(node)
  return node.kind == 'module' and base(node.path) or shape(node)
end

-- a node's name in the shape of its kind, coloured as its declaration is
local function name(r, node, hl, room)
  if node.kind == 'module' then
    return r:add(trunc(base(node.path), room), hl)
  end
  local s = shape(node)
  local pre, post = s:match('^(.-)' .. vim.pesc(node.name) .. '(.*)$')
  if not pre or api.nvim_strwidth(s) > room then
    return r:add(trunc(s, room), hl)
  end
  r:add(pre, hl)
  code.add_name(r, node.path, node.line, node.name, hl, room)
  return r:add(post, hl)
end

--- A node's name as the tree draws it: `name()`, `<Name>`, coloured as its
--- declaration is.
M.name = name

local function titles(view)
  local r = row()
  local word = view.dir == 'up' and 'above' or 'below'
  r:to(COUNT_END - #word):add(word, 'SeamLabel')
  r:to(USED_END - 7):add('used by', 'SeamLabel')
  r:to(FILE_AT):add('file', 'SeamLabel')
  r:to(LINE_AT):add('line', 'SeamLabel')
  return r
end

-- callers or callees by name, then where, one after another to `w`: a
-- caller where it makes the call, a callee where it is declared
local function names(r, g, list, w, at_call)
  for j, e in ipairs(list) do
    local node = g.nodes[e.id]
    local line = at_call and e.lines[1] or node.line
    local where = ' ' .. base(node.path) .. (line > 0 and ':' .. line or '')
    local need = api.nvim_strwidth(label(node)) + #where + (node.exported and 0 or 6) + 3
    if r.w + need > w - 12 and j > 1 then
      r:add(('   +%d more'):format(#list - j + 1), 'SeamLabel')
      return
    end
    if j > 1 then
      r:add(' · ', 'SeamLabel')
    end
    name(r, node, 'SeamName', w)
    if not node.exported and node.kind ~= 'module' then
      r:add(' local', 'SeamDim')
    end
    r:add(where, 'SeamPath')
  end
end

--- The head: where it is, then the shared functions left folded, when any.
---@param buf integer
---@param g seam.Graph
---@param view seam.CallsView
---@param r seam.CallRows
---@param width integer
---@return integer rows
function M.head(buf, g, view, r, width)
  local visible = calls.visible(index.model(), 'up')
  local a = view.anchor and g.nodes[view.anchor]
  local h = row():add(' Seams', 'SeamLabel'):add(' › ', 'SeamLabel')
  if a then
    name(h, a, 'SeamBold', 60)
    h:add(view.dir == 'up' and '  called by' or '  calls', 'SeamTitle')
  else
    h:add('where the code starts', 'SeamBold')
    draw.hidden(h, calls.hidden(g, view, index.model()))
  end
  local rows = { h }
  if #r.shared > 0 then
    local t = row():add('   shared, never opened: ', 'SeamLabel')
    rows[2] = t
    for j, id in ipairs(r.shared) do
      local node = g.nodes[id]
      local add = label(node) .. ' ' .. calls.used_by(g, id, visible)
      if t.w + api.nvim_strwidth(add) + 12 > width then
        t:add(('  +%d more'):format(#r.shared - j + 1), 'SeamLabel')
        break
      end
      if j > 1 then
        t:add '   '
      end
      name(t, node, 'SeamName', 40)
      t:add(' ' .. calls.used_by(g, id, visible), 'SeamLabel')
    end
  end
  draw.put(buf, rows)
  return #rows
end

--- The anchor pinned over the tree: the other way from it (going down, who
--- calls it; going up, what it calls), it, then the column titles. From the
--- top, the titles alone.
---@param buf integer
---@param g seam.Graph
---@param view seam.CallsView
---@return integer rows
function M.pin(buf, g, view)
  local m = index.model()
  local rows = {}
  local a = view.anchor and g.nodes[view.anchor]
  if not a then
    rows = { titles(view) }
    draw.put(buf, rows)
    return #rows
  end
  local function others(dir, word, none)
    local r = row()
    local list, tests = calls.kids(g, a.id, dir, calls.visible(m, dir))
    vim.list_extend(list, tests)
    if #list == 0 then
      return r:add(none, 'SeamLabel')
    end
    r:add(word, 'SeamLabel')
    names(r, g, list, M.LW, dir == 'up')
    return r
  end
  local me = row():add('━ ', 'SeamTitle')
  name(me, a, 'SeamBold', 50)
  local where = a.line > 0 and (':' .. a.line .. '-' .. a.end_line) or ''
  me:add('  ' .. base(a.path) .. where, 'SeamPath')
  local up, down = calls.visible(m, 'up'), calls.visible(m, 'down')
  if view.dir == 'up' then
    local n = calls.used_by(g, a.id, up)
    me:add(('   called by %d  ·  %d above'):format(n, calls.above(g, a.id, up)), 'SeamLabel')
    rows = { others('down', '↓ calls ', '↓ calls nothing'), me, titles(view) }
  else
    local kids = calls.kids(g, a.id, 'down', down)
    me:add(('   calls %d  ·  %d below'):format(#kids, calls.below(g, a.id, down)), 'SeamLabel')
    rows = { others('up', '↑ called by ', '↑ nothing calls it'), me, titles(view) }
  end
  draw.hidden(me, calls.hidden(g, view, m))
  draw.put(buf, rows)
  return #rows
end

-- the guides down the left, from its parents' places among their siblings
local function guides(r, rows, x, anchored)
  local chain, p = {}, x.parent
  while p do
    table.insert(chain, 1, rows[p])
    p = rows[p].parent
  end
  for j = anchored and 1 or 2, #chain do
    r:add(chain[j].last and '  ' or '│ ', 'SeamDim')
  end
  if anchored or x.parent then
    r:add(x.last and '└ ' or '├ ', 'SeamDim')
  end
end

local function also(x)
  return '↑ also at :' .. (x.also_line or '?')
end

-- where an also row's note starts: three spaces clear of the line column
local function also_at(x)
  return LINE_AT - 3 - api.nvim_strwidth(also(x))
end

local function columns(r, x)
  local text, path = 'SeamText', 'SeamPath'
  if x.fold == 'also' then
    r:to(math.max(also_at(x), r.w + 2)):add(also(x), 'SeamLabel')
    return r:to(math.max(LINE_AT, r.w + 3)):add(':' .. x.lines[1], 'SeamPath')
  end
  if x.count and x.count > 0 then
    local s = tostring(x.count)
    r:to(COUNT_END - #s):add(s, text)
  end
  if x.used_by and x.used_by > 0 then
    local s = tostring(x.used_by)
    r:to(USED_END - #s):add(s, text)
  end
  if x.show_file and x.path and not x.id:match ':0:$' then
    r:to(FILE_AT):add(trunc(base(x.path), LINE_AT - FILE_AT - 1), path)
  end
  local l = x.lines[1]
  if l and l > 0 then
    r:to(LINE_AT):add(':' .. l, path)
  end
end

--- The tree: a row each.
---@param buf integer
---@param g seam.Graph
---@param view seam.CallsView
---@param r seam.CallRows
function M.list(buf, g, view, r)
  local m = index.model()
  local anchored = view.anchor ~= nil
  local out = {}
  for i, x in ipairs(r.rows) do
    local node = x.id and g.nodes[x.id]
    local pkg = x.pkg or (x.path and index.pkg_of(m, x.path))
    local d = row { i = i, key = x.key }
    if x.kind == 'dir' and not x.touched then
      d:add ' '
    else
      tree.bar(d, pkg)
    end
    guides(d, r.rows, x, anchored)
    local folded = x.fold == 'folded' or (x.kind == 'dir' and not x.touched)
    d:add(x.fold == 'open' and '▾ ' or folded and '▸ ' or '  ', 'SeamLabel')
    local room = math.min(COUNT_END, x.fold == 'also' and also_at(x) or COUNT_END) - 6 - d.w
    if x.kind == 'dir' then
      if not x.touched then
        d:add(x.segs[1] .. '/', 'SeamDim')
      else
        for j, sg in ipairs(x.segs) do
          d:add(sg .. '/', j == 1 and x.ispkg and theme.hue(x.pkg).name or 'SeamPath')
        end
      end
    elseif x.kind == 'tests' then
      d:add('tests', 'SeamTest'):add('  ' .. draw.plural(x.files, 'file'), 'SeamLabel')
    elseif x.kind == 'file' and not node then
      d:add(trunc(base(x.path), room), index.is_test(x.path) and 'SeamTest' or 'SeamPath')
    else
      name(d, node, node.test and 'SeamTest' or 'SeamName', room)
      if x.n > 1 then
        d:add(' ×' .. x.n, 'SeamLabel')
      end
      if node.kind == 'module' then
        d:add('  top of the file', 'SeamLabel')
      elseif not node.exported then
        d:add(' local', 'SeamDim')
      end
      columns(d, x)
    end
    out[#out + 1] = d
  end
  if #r.rows == 0 then
    out[#out + 1] = row():add('  calls nothing', 'SeamLabel')
  end
  draw.put(buf, out)
end

-- lines s..e to show around `want`, `max` at most: those, and as many lines
-- either side as fit
local function around(s, e, want, max)
  local ls = vim.tbl_keys(want)
  table.sort(ls)
  for radius = 3, 0, -1 do
    local set, n = {}, 0
    for _, l in ipairs(ls) do
      for k = math.max(s, l - radius), math.min(e, l + radius) do
        if not set[k] then
          set[k], n = true, n + 1
        end
      end
    end
    if n <= max or radius == 0 then
      return set
    end
  end
end

-- code rows of `path` for the lines in `set`, a ⋯ between runs; `lit`
-- lines lit, with `mark(r, start, src, l)` underlining on each row
local function code_rows(out, path, set, lit, mark)
  local lines = vim.tbl_keys(set)
  table.sort(lines)
  local gw = math.max(3, #tostring(lines[#lines] or 1))
  local P = code.file(path)
  local first, prev
  for _, l in ipairs(lines) do
    if prev and l > prev + 1 then
      out[#out + 1] = row():add(string.rep(' ', gw) .. '⋯', 'SeamLabel')
    end
    local cr = row { kind = 'code', lnum = l }
    cr:add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
    local start = cr.b
    code.add(cr, path, l)
    if lit[l] then
      cr.line_hl = 'SeamLit'
      first = first or #out + 1
    end
    mark(cr, start, P.lines[l] or '', l)
    out[#out + 1] = cr
    prev = l
  end
  return first
end

-- the two views over the code, the one shown lit; with nothing calling it,
-- itself alone
local function tabs(p)
  local t = row():add '  '
  if #p.places == 0 then
    return t:add(' Itself ', 'SeamTab'):add('    nothing calls it', 'SeamLabel')
  end
  for _, v in ipairs { { 'called', 'Called at', ' ' .. #p.places }, { 'itself', 'Itself', '' } } do
    if v[1] == p.code then
      t:add(' ' .. v[2] .. v[3] .. ' ', 'SeamTab')
    else
      t:add(' ' .. v[2], 'SeamText'):add(v[3] .. ' ', 'SeamLabel')
    end
    t:add '   '
  end
  return t
end

-- called at: the place shown, its caller's function around the call, the
-- call lit and the name underlined
local function called_at(out, g, p)
  local u = p.places[p.n]
  local from = g.nodes[u.from]
  local h = row():add(' called at  ', 'SeamLabel'):add(('%d of %d'):format(p.n, #p.places), 'SeamText'):add('  ·  ', 'SeamLabel')
  if from.kind == 'module' then
    h:add('top of the file', 'SeamLabel')
  else
    name(h, from, from.test and 'SeamTest' or 'SeamName', 50)
  end
  h:add('  ' .. base(from.path) .. ':' .. u.line, 'SeamPath')
  out[#out + 1] = h
  out[#out + 1] = row()
  -- its other calls from the same caller, underlined too
  local also = {}
  for _, v in ipairs(p.places) do
    if v.from == u.from then
      also[v.line] = v.col
    end
  end
  local s, e = code.enclosing(from.path, u.line, u.col or 1)
  return code_rows(out, from.path, code.pick_rows(s, e, { [u.line] = true }), { [u.line] = true }, function(cr, start, src, l)
    if also[l] then
      code.underline(cr, start, src, p.node.name, also[l])
    end
  end)
end

-- itself: its own body, each call in it underlined; going up the call to its
-- parent in the tree stands out, and the line `]]` stepped to is lit
local function itself(out, g, p, x, up)
  local node = p.node
  local from = up and x and x.from and g.nodes[x.from]
  local h = row()
  if #p.places == 0 then
    h:add(' nothing calls it: the code starts here', 'SeamLabel')
  elseif from then
    h:add(' calls ', 'SeamLabel')
    name(h, from, 'SeamName', 50)
    h:add('  at ' .. base(node.path) .. ':' .. x.lines[1], 'SeamPath')
  else
    h:add(#p.lines == 0 and ' itself  ·  calls nothing' or ' itself  ·  calls on ' .. draw.plural(#p.lines, 'line'), 'SeamLabel')
  end
  if p.n > 0 then
    h:add(('   line %d of %d'):format(p.n, #p.lines), 'SeamLabel')
  end
  out[#out + 1] = h
  out[#out + 1] = row()
  local lit, under = {}, {}
  if p.n > 0 then
    lit[p.lines[p.n]] = true
  end
  for _, l in ipairs(from and x.lines or {}) do
    under[l] = from.name
  end
  local refs = {}
  for _, c in ipairs(g.down[node.id] or {}) do
    refs[c.line] = refs[c.line] or {}
    table.insert(refs[c.line], { g.nodes[c.to].name, c.col })
  end
  local set
  if node.kind == 'module' then
    local want = {}
    for l in pairs(refs) do
      want[l] = true
    end
    set = around(1, #code.file(node.path).lines, want, 60)
  else
    set = {}
    local s, e = code.doc_start(node.path, node.line), math.max(node.end_line or node.line, node.line)
    for l = s, e do
      set[l] = true
    end
  end
  return code_rows(out, node.path, set, lit, function(cr, start, src, l)
    for _, ref in ipairs(refs[l] or {}) do
      if ref[1] ~= under[l] then
        code.underline(cr, start, src, ref[1], ref[2], 'SeamRef')
      end
    end
    if under[l] then
      code.underline(cr, start, src, under[l])
    end
  end)
end

--- The code of row `i` (nil: the anchor), in the view `calls.pane` says:
--- where it is called, one place at a time, or itself.
---@param buf integer
---@param win integer|nil
---@param g seam.Graph
---@param view seam.CallsView
---@param r seam.CallRows
---@param i integer|nil
function M.pane(buf, win, g, view, r, i)
  local x = i and r.rows[i]
  local out = { row() }
  local p = calls.pane(g, view, r, i, index.model())
  if not p then
    if x and x.kind == 'tests' then
      out[#out + 1] = row():add(' ' .. draw.plural(x.files, 'test file') .. ', each its own start', 'SeamLabel')
    elseif x and x.path then
      local h = row():add ' '
      draw.path(h, x.path .. (x.kind == 'dir' and '/' or ''))
      out[#out + 1] = h
    end
    draw.put(buf, out)
    return
  end
  local node = p.node
  local h = row():add ' '
  name(h, node, 'SeamBold', 60)
  if not node.exported and node.kind ~= 'module' then
    h:add(' local', 'SeamDim')
  end
  h:add('   ' .. (node.kind == 'module' and 'top of the file' or node.kind) .. ' in ', 'SeamLabel')
  draw.path(h, node.path, node.line > 0 and node.line or nil)
  out[#out + 1] = h
  out[#out + 1] = tabs(p)
  out[#out + 1] = row()
  local first
  if p.code == 'called' then
    first = called_at(out, g, p)
  else
    first = itself(out, g, p, x, view.dir == 'up' and view.anchor)
  end
  draw.put(buf, out)
  if win and api.nvim_win_is_valid(win) then
    local wh = api.nvim_win_get_height(win)
    if first then
      code.scroll_to(win, first, first > wh - 2 and math.max(1, first - math.floor(wh / 3)) or 1)
    else
      code.scroll_to(win, 1, 1)
    end
  end
end

return M
