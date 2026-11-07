-- The tree as data, on a graph written by hand: its rows, a file's
-- functions, the calls each opens to and where they live, recursion, the
-- fan-in and fan-out of each row, the sorted orders, and finding a function
-- or file.
--   nvim -l tests/outline.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local index = require 'seam.index'
local outline = require 'seam.outline'

local failures, checks = {}, 0
local function expect(ok, what, got)
  checks = checks + 1
  if not ok then
    failures[#failures + 1] = what .. (got ~= nil and ('  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')') or '')
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end
local function eq(got, want, what)
  expect(vim.deep_equal(got, want), what .. ': want ' .. vim.inspect(want):gsub('%s+', ' '), got)
end

-- two packages, pa and pb. a1 calls a2 b1 c1 a2, written in that order but
-- a2 twice; a2 calls a1 back; d1 calls b1; a test calls a1 and b1, and so
-- does a test's function; main's top calls a1. types.ts only exports.
local A1, A2, B1, C1, D1 = 'pa/src/a.ts:30:a1', 'pa/src/a.ts:10:a2', 'pa/src/b.ts:5:b1', 'pb/c.ts:3:c1', 'pa/src/sub/d.ts:1:d1'
local MAIN, TEST, T1 = 'pa/src/main.ts:0:', 'pa/src/a.test.ts:0:', 'pa/src/a.test.ts:4:t1'
local function node(id, kind, calls_)
  local path, line, name = id:match '^(.*):(%d+):(.*)$'
  return { id = id, name = name, kind = kind or 'function', path = path, line = tonumber(line), end_line = tonumber(line) + 9, calls = calls_ or {} }
end
local m = {
  graph = index.graph {
    node(A1, nil, { { A2, 31, 3 }, { B1, 32, 3 }, { C1, 33, 3 }, { A2, 34, 3 } }),
    node(A2, nil, { { A1, 11, 3 } }),
    node(B1),
    node(C1),
    node(D1, nil, { { B1, 2, 3 } }),
    node(MAIN, 'module', { { A1, 1, 1 } }),
    node(TEST, 'module', { { A1, 2, 1 }, { B1, 3, 1 } }),
    node(T1, nil, { { B1, 5, 3 } }),
  },
  exports = { { id = 'pa/src/types.ts:1:T', name = 'T', path = 'pa/src/types.ts', line = 1 } },
  ispkg = { pa = true, pb = true },
  pkgsorted = { 'pa', 'pb' },
  pkgcache = {},
}

local function keys(rows)
  return vim.tbl_map(function(r)
    return r.key
  end, rows)
end
local function k(...)
  return table.concat({ ... }, '\n')
end
local function row(rows, key)
  local i = outline.find(rows, key)
  return i and rows[i], i
end

-- the tree: packages open, a folder in one closed, no test file, a file
-- of exports alone a row too
local o = outline.new()
local rows = outline.rows(m, o)
eq(
  keys(rows),
  { 'd:pa', 'd:pa/src/sub', 'f:pa/src/a.ts', 'f:pa/src/b.ts', 'f:pa/src/main.ts', 'f:pa/src/types.ts', 'd:pb', 'f:pb/c.ts' },
  'the tree: packages open, sub closed, files closed, no test'
)
eq(row(rows, 'd:pa').item.segs, { 'pa', 'src' }, 'a lone folder joins its package')
eq({ row(rows, 'd:pa').open, row(rows, 'd:pa/src/sub').open, row(rows, 'd:pa/src/sub').can_open }, { true, false, true }, 'open and closed folders')
eq({ row(rows, 'f:pa/src/main.ts').can_open, row(rows, 'f:pa/src/types.ts').can_open }, { false, false }, 'a file of no function does not open')

-- l on a file: its functions in the file's order, all alike
local _, fi = row(rows, 'f:pa/src/a.ts')
eq(outline.key(m, o, rows, fi, 'l'), 'redraw', 'l opens a file')
rows = outline.rows(m, o)
local _, ai = row(rows, 'f:pa/src/a.ts')
eq({ rows[ai + 1].key, rows[ai + 2].key }, { k('f:pa/src/a.ts', A2), k('f:pa/src/a.ts', A1) }, "a file's functions by line")
eq({ rows[ai + 1].depth, rows[ai + 1].where, rows[ai + 1].kind }, { 2, nil, 'fn' }, 'a function under its file: a level in, no where')

-- l on a function: what it calls, once each, in the order first written,
-- and where each lives
local a1 = k('f:pa/src/a.ts', A1)
local _, i1 = row(rows, a1)
eq(outline.key(m, o, rows, i1, 'l'), 'redraw', 'l opens a function')
rows = outline.rows(m, o)
_, i1 = row(rows, a1)
eq({ rows[i1 + 1].key, rows[i1 + 2].key, rows[i1 + 3].key }, { k(a1, A2), k(a1, B1), k(a1, C1) }, 'its calls, first written first, a2 once')
eq({ rows[i1 + 1].where, rows[i1 + 2].where, rows[i1 + 3].where }, { 'here', 'file', 'pkg' }, 'this file, another file, another package')
eq(rows[i1 + 1].depth, 3, 'a call a level under its function')
eq(o.cursor, a1, 'the cursor stays on what it opened')

-- l on an open row goes into it; h on a call goes up to its function
eq({ outline.key(m, o, rows, i1, 'l'), o.cursor }, { 'move', k(a1, A2) }, 'l on an open row: its first call')
eq({ outline.key(m, o, rows, i1 + 2, 'h'), o.cursor }, { 'move', a1 }, 'h on a closed call: the function it is under')

-- recursion: a1 > a2 > a1 is seen, dim, and does not open
eq(outline.key(m, o, rows, i1 + 1, 'l'), 'redraw', 'l opens a2 under a1')
rows = outline.rows(m, o)
local back = row(rows, k(a1, A2, A1))
expect(back and back.seen and not back.can_open, 'a1 under a2 under a1 is seen and does not open', back)
eq(row(rows, k(a1, A2)).seen, false, 'a2 itself is not seen')
eq(row(rows, k('f:pa/src/a.ts', A2)).can_open, true, 'a2 at the top of its file opens')

-- h closes what is open, its calls gone; again on a closed folder: its parent
local _, ia = row(rows, a1)
eq(outline.key(m, o, rows, ia, 'h'), 'redraw', 'h closes a1')
rows = outline.rows(m, o)
expect(row(rows, k(a1, A2)) == nil and not row(rows, a1).open, 'its calls are gone')
local _, ip = row(rows, 'd:pa')
eq(outline.key(m, o, rows, ip, 'h'), 'redraw', 'h closes an open package')
rows = outline.rows(m, o)
eq(keys(rows), { 'd:pa', 'd:pb', 'f:pb/c.ts' }, 'a closed folder hides what is in it')
eq({ outline.key(m, o, rows, 3, 'h'), o.cursor }, { 'move', 'd:pb' }, 'h on a closed file: its folder')
eq(outline.key(m, o, rows, 1, 'h'), nil, 'h on a closed top folder: nothing')
o.open['d:pa'] = nil

-- fan-in and fan-out, one record a key: a function's callers and calls; a
-- file's or folder's from outside it, tests and a file's top left out
local fan = outline.fan(m)
local function f(key)
  return { outline.count(fan, key) }
end
eq({ f(A1), f(A2), f(B1), f(C1), f(D1) }, { { 1, 3 }, { 1, 1 }, { 2, 0 }, { 1, 0 }, { 0, 1 } }, "each function's used by and calls")
eq(f 'f:pa/src/b.ts', { 2, 0 }, 'b.ts used by a1 and d1, from other files, not the tests')
eq(f 'f:pa/src/a.ts', { 0, 2 }, "a.ts calls b1 and c1, not a2 in itself; main's top does not count as using it")
eq(f 'd:pa/src', { 0, 1 }, 'pa/src: b1 is called only from inside it; it calls c1 outside')
eq({ f 'd:pa/src/sub', f 'd:pb' }, { { 0, 1 }, { 1, 0 } }, 'sub calls b1 out of it; pb used by a1')
eq(f 'f:pa/src/main.ts', { 0, 0 }, 'a file calling nothing outside, through its top alone: none')
expect(outline.fan(m) == fan, 'the counts are made once a model and lens')

-- s: most used first, the tree kept, each level sorted, every row with both
-- counts; then most calling first; then the tree, nothing beside a name
o = outline.new()
local tree_keys = keys(outline.rows(m, o))
local function counts(rs)
  return vim.tbl_map(function(r)
    return { r.key, r.used, r.calls }
  end, rs)
end
expect(outline.rows(m, o)[1].used == nil, 'the tree: no counts')
local _, ib = row(outline.rows(m, o), 'f:pa/src/b.ts')
eq(outline.key(m, o, outline.rows(m, o), ib, 's'), 'redraw', 's')
eq(o.order, 'used', 's: most used first')
rows = outline.rows(m, o)
eq(counts(rows), {
  { 'd:pb', 1, 0 },
  { 'f:pb/c.ts', 1, 0 },
  { 'd:pa', 0, 1 },
  { 'f:pa/src/b.ts', 2, 0 },
  { 'd:pa/src/sub', 0, 1 },
  { 'f:pa/src/a.ts', 0, 2 },
  { 'f:pa/src/main.ts', 0, 0 },
  { 'f:pa/src/types.ts', 0, 0 },
}, 'most used: pb before pa, b.ts first in pa, the rest in the tree order, sub still closed')
eq(o.cursor, 'f:pa/src/b.ts', 's keeps the cursor on its row')
o.open['f:pa/src/a.ts'] = true
rows = outline.rows(m, o)
local _, ia1 = row(rows, 'f:pa/src/a.ts')
eq({ rows[ia1 + 1].key, rows[ia1 + 2].key }, { k('f:pa/src/a.ts', A2), k('f:pa/src/a.ts', A1) }, "a file's functions used as much: in the file's order")
outline.key(m, o, rows, ia1 + 2, 's')
eq(o.order, 'calls', 's again: most calling first')
rows = outline.rows(m, o)
eq(
  vim.list_slice(keys(rows), 1, 5),
  { 'd:pa', 'f:pa/src/a.ts', k('f:pa/src/a.ts', A1), k('f:pa/src/a.ts', A2), 'd:pa/src/sub' },
  'most calling: pa, a.ts calling two outside, a1 calling three'
)
eq({ row(rows, k('f:pa/src/a.ts', A1)).used, row(rows, k('f:pa/src/a.ts', A1)).calls }, { 1, 3 }, 'a function row has its counts')
local _, ic = row(rows, k('f:pa/src/a.ts', A1))
eq(outline.key(m, o, rows, ic, 'l'), 'redraw', 'a function opens in a sorted order too')
rows = outline.rows(m, o)
eq(
  { rows[ic + 1].key, rows[ic + 2].key, rows[ic + 3].key },
  { k('f:pa/src/a.ts', A1, A2), k('f:pa/src/a.ts', A1, B1), k('f:pa/src/a.ts', A1, C1) },
  'its calls, the most calling first: a2 calls one, b1 and c1 none, as written'
)
eq(rows[ic + 3].where, 'pkg', 'its calls say where they live')
outline.key(m, o, rows, ic + 2, 's')
eq(o.order, 'tree', 's a third time: the tree')
rows = outline.rows(m, o)
expect(row(rows, k('f:pa/src/a.ts', A1, B1)) ~= nil and o.cursor == k('f:pa/src/a.ts', A1, B1), 'back in the tree, the row the cursor was on', o.cursor)
o.open['f:pa/src/a.ts'], o.open[k('f:pa/src/a.ts', A1)] = nil, nil
eq(keys(outline.rows(m, o)), tree_keys, 'the tree as it was')

-- reveal: a function in a closed folder, its folder and file opened
o = outline.new()
eq(outline.reveal(m, o, D1), true, 'reveal d1')
rows = outline.rows(m, o)
eq(o.cursor, k('f:pa/src/sub/d.ts', D1), 'the cursor on d1')
expect(row(rows, o.cursor) ~= nil, 'd1 is a row')
eq(outline.reveal(m, o, 'pa/src/types.ts'), true, 'reveal a file')
eq(o.cursor, 'f:pa/src/types.ts', 'the cursor on the file')
eq(outline.reveal(m, o, T1), false, 'a test function has no row')
eq(outline.reveal(m, o, MAIN), true, "a file's top: its file")
eq(o.cursor, 'f:pa/src/main.ts', 'on main.ts')
o = outline.new()
o.order = 'used'
eq({ outline.reveal(m, o, D1), o.order }, { true, 'used' }, 'in a sorted order a function is shown there')
expect(row(outline.rows(m, o), k('f:pa/src/sub/d.ts', D1)) ~= nil, 'd1 is a row, its folder opened', o.cursor)
eq({ outline.reveal(m, o, 'pb/c.ts'), o.order, o.cursor }, { true, 'used', 'f:pb/c.ts' }, 'and a file')

-- the lens: a folder hidden from contracts leaves the tree
m.visible = function(path, col)
  return not (col == 'contracts' and path:find '^pb/')
end
eq(
  keys(outline.rows(m, outline.new())),
  { 'd:pa', 'd:pa/src/sub', 'f:pa/src/a.ts', 'f:pa/src/b.ts', 'f:pa/src/main.ts', 'f:pa/src/types.ts', 'd:pb' },
  'the lens hides c.ts, its package kept'
)
eq({ outline.count(outline.fan(m), 'f:pb/c.ts') }, { 0, 0 }, 'nothing counted into what the tree hides')
m.visible = function(path, col)
  return not (col == 'used' and path:find '^pa/src/sub/')
end
eq({ outline.count(outline.fan(m), 'f:pa/src/b.ts') }, { 1, 0 }, 'a caller the lens hides from used by is not counted')

-- the call graph one level on (seam.graph): as written, a call made twice
-- one kid; going up, tests apart; the lens's column each way
do
  local graph = require 'seam.graph'
  local g = m.graph
  local kids = graph.kids(g, A1, 'down')
  eq(
    vim.tbl_map(function(x)
      return x.id
    end, kids),
    { A2, B1, C1 },
    'a1 calls a2 b1 c1, in the order first written'
  )
  eq({ kids[1].n, kids[1].lines }, { 2, { 31, 34 } }, 'a2 called twice by a1: at 31 and 34')
  local up, tests = graph.kids(g, B1, 'up')
  eq(
    vim.tbl_map(function(x)
      return x.id
    end, up),
    { A1, D1 },
    'b1 called by a1 and d1, by path'
  )
  eq(
    vim.tbl_map(function(x)
      return x.id
    end, tests),
    { TEST, T1 },
    "the test and the test's function that call b1, apart"
  )
  local seen = {}
  graph.visible({
    visible = function(path, col)
      seen[#seen + 1] = col
      return path ~= 'pb/c.ts'
    end,
  }, 'down') 'pb/c.ts'
  eq(seen, { 'built' }, 'calls follow built from')
  eq(graph.visible(nil, 'up') 'x', true, 'no lens: everything')
end

-- tests: by name, or in a test folder
for path, want in pairs {
  ['src/a.test.ts'] = true,
  ['src/a.spec.tsx'] = true,
  ['src/__tests__/a.ts'] = true,
  ['packages/core/src/test/helpers.ts'] = true,
  ['packages/core/tests/a.ts'] = true,
  ['test/a.ts'] = true,
  ['src/testing.ts'] = false,
  ['src/attest/a.ts'] = false,
} do
  eq(index.is_test(path), want, 'is_test ' .. path)
end

-- the picker: the most used first; typing narrows by name, the best match first
do
  local picker = require 'seam.picker'
  local nodes = {}
  local all = {}
  for _, x in ipairs { { 'start', 4 }, { 'startRun', 2 }, { 'Box', 1 }, { 'stash', 0 }, { 'Store', 0 } } do
    local id = 'src/p.ts:' .. (#all + 1) .. ':' .. x[1]
    nodes[id] = { name = x[1], path = 'src/p.ts', line = #all + 1, kind = 'function' }
    all[#all + 1] = { id = id, name = x[1], used_by = x[2] }
  end
  local function ids(list)
    return vim.tbl_map(function(p)
      return p.name .. ' ' .. p.used_by
    end, list)
  end
  picker.sort(all, nodes)
  eq(ids(all), { 'start 4', 'startRun 2', 'Box 1', 'Store 0', 'stash 0' }, 'by used by, then name')
  eq(picker.fuzzy(all, '  '), all, 'an empty query keeps them all, in order')
  local got = picker.fuzzy(all, 'sta')
  eq(ids(got), { 'start 4', 'stash 0', 'startRun 2' }, 'sta: the best match first, used by between equals')
  eq(got[1].pos, { 0, 1, 2 }, 'the letters matched')
  eq(ids(picker.fuzzy(all, 'zzz')), {}, 'nothing matches')
end

-- f t v: what a file lists. k.ts declares a type T on line 1, a value v on
-- line 3 that calls kf, and kf on line 5; functions alone at first
do
  local KV, KF = 'pk/k.ts:3:v', 'pk/k.ts:5:kf'
  local mk = {
    graph = index.graph { node(KV, 'value', { { KF, 3, 12 } }), node(KF) },
    exports = {},
    ispkg = { pk = true },
    pkgsorted = { 'pk' },
    pkgcache = {},
  }
  package.loaded['seam.written'] = {
    types = function(path)
      return path == 'pk/k.ts' and { { name = 'T', kind = 'type', path = path, line = 1, end_line = 1 } } or {}
    end,
  }
  local ko = outline.new()
  ko.open['f:pk/k.ts'] = true
  local function listed()
    return keys(outline.rows(mk, ko))
  end
  eq(listed(), { 'd:pk', 'f:pk/k.ts', k('f:pk/k.ts', KF) }, 'functions alone: the tree as it was')
  eq(outline.shows_word(ko), nil, 'functions alone says nothing')
  local krows = outline.rows(mk, ko)
  eq(outline.key(mk, ko, krows, 3, 't'), 'redraw', 't redraws')
  eq(listed(), { 'd:pk', 'f:pk/k.ts', k('f:pk/k.ts', 'type:T'), k('f:pk/k.ts', KF) }, 't: the type, in the file order')
  outline.key(mk, ko, outline.rows(mk, ko), 3, 'v')
  krows = outline.rows(mk, ko)
  eq(keys(krows), { 'd:pk', 'f:pk/k.ts', k('f:pk/k.ts', 'type:T'), k('f:pk/k.ts', KV), k('f:pk/k.ts', KF) }, 'v: the value too')
  eq(outline.shows_word(ko), 'functions · types · values', 'what is on, in words')
  local t = row(krows, k('f:pk/k.ts', 'type:T'))
  eq({ t.kind, t.can_open, t.name, t.decl_kind }, { 'type', false, 'T', 'type' }, 'a type row does not open')
  local vr, vi = row(krows, k('f:pk/k.ts', KV))
  eq({ vr.kind, vr.can_open }, { 'fn', true }, 'a value opens, as a function does')
  outline.key(mk, ko, krows, vi, 'l')
  eq(keys(outline.rows(mk, ko))[5], k('f:pk/k.ts', KV, KF), 'a value opens to what it calls')
  -- v off with the cursor on the value's call: back to the file
  krows = outline.rows(mk, ko)
  local _, ci = row(krows, k('f:pk/k.ts', KV, KF))
  outline.key(mk, ko, krows, ci, 'v')
  eq(ko.cursor, 'f:pk/k.ts', 'a row no longer shown leaves the cursor on the nearest above it')
  outline.key(mk, ko, outline.rows(mk, ko), 1, 'f')
  outline.key(mk, ko, outline.rows(mk, ko), 1, 't')
  eq(outline.shows_word(ko), 'nothing', 'all off')
  eq(row(outline.rows(mk, ko), 'f:pk/k.ts').can_open, false, 'a file listing nothing does not open')
  eq(#outline.functions(mk, 'pk/k.ts'), 1, 'its functions are not its values')
  -- a value revealed by name (/, the Map) while values are off: listed, the cursor on it
  local ro = outline.new()
  eq(outline.reveal(mk, ro, KV), true, 'reveal a value')
  eq(outline.find(outline.rows(mk, ro), ro.cursor) ~= nil, true, 'a revealed value has its row')
  eq(outline.shows_word(ro), 'functions · values', 'values listed from then on')
  package.loaded['seam.written'] = nil
end

-- e: a file's exports only. x.ts exports xf (line 1), which calls kf, and
-- type XT (by an export list, `export { XT }`); keeps kf (line 5) and type
-- KT to itself
do
  local XF, KF = 'px/x.ts:1:xf', 'px/x.ts:5:kf'
  local xf, kf = node(XF, nil, { { KF, 2, 3 } }), node(KF)
  xf.exported = true
  local mx = {
    graph = index.graph { xf, kf },
    exports = { { name = 'xf', path = 'px/x.ts', line = 1 }, { name = 'XT', path = 'px/x.ts', line = 3 } },
    ispkg = { px = true },
    pkgsorted = { 'px' },
    pkgcache = {},
  }
  package.loaded['seam.written'] = {
    types = function()
      return {
        { name = 'XT', kind = 'type', path = 'px/x.ts', line = 3, end_line = 3 },
        { name = 'KT', kind = 'type', path = 'px/x.ts', line = 8, end_line = 8 },
      }
    end,
  }
  local xo = outline.new()
  xo.open['f:px/x.ts'] = true
  xo.shows.t = true
  outline.key(mx, xo, outline.rows(mx, xo), 1, 'e')
  local xrows = outline.rows(mx, xo)
  eq(keys(xrows), { 'd:px', 'f:px/x.ts', k('f:px/x.ts', XF), k('f:px/x.ts', 'type:XT') }, 'e: the exports alone, an export list counted')
  eq(outline.shows_word(xo), 'functions · types · exports only', 'e in words')
  xo.shows.t = false
  eq(outline.shows_word(xo), 'functions · exports only', 'e with functions alone says so')
  outline.key(mx, xo, outline.rows(mx, xo), 1, 'e')
  eq(outline.shows_word(xo), nil, 'e again: every function, nothing said')
  -- a kept function revealed by name while exports only: all of the file again
  xo.shows.e = true
  outline.reveal(mx, xo, KF)
  eq(outline.find(outline.rows(mx, xo), xo.cursor) ~= nil, true, 'a kept function revealed has its row')
  eq(xo.shows.e, nil, 'and exports only is off')
  -- under an exported function, its calls are all of them
  xo.shows.e = true
  xo.open[k('f:px/x.ts', XF)] = true
  eq(keys(outline.rows(mx, xo)), { 'd:px', 'f:px/x.ts', k('f:px/x.ts', XF), k('f:px/x.ts', XF, KF) }, 'exports only: xf, and kf under it as its call')
  package.loaded['seam.written'] = nil
end

io.stdout:write(('outline: %d checks, %d failures\n'):format(checks, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
