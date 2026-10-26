-- The call tree as data, on a graph written by hand: counts, rows, the
-- budget, called by, and what each key does to the view.
--   nvim -l tests/calls.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local calls = require 'seam.calls'
local index = require 'seam.index'

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

-- a -> b b c d s; b -> e; c -> e c; e -> f; f -> b; s -> d; u1..u4 -> s;
-- main's top -> a; a test's top -> a b t
local function node(id, kind, calls_)
  local path, line, name = id:match '^(.*):(%d+):(.*)$'
  return {
    id = id,
    name = name,
    kind = kind or 'function',
    path = path,
    line = tonumber(line),
    end_line = tonumber(line) + 9,
    exported = true,
    calls = calls_ or {},
  }
end
local A, B, C, D, E, F, S = 'src/a.ts:1:a', 'src/b.ts:1:b', 'src/c.ts:1:c', 'src/d.ts:1:d', 'src/e.ts:1:e', 'src/f.ts:1:f', 'src/s.ts:1:s'
local MAIN, TEST, T = 'src/main.ts:0:', 'src/a.test.ts:0:', 'src/t.ts:1:t'
local U = { 'src/u.ts:1:u1', 'src/u.ts:11:u2', 'src/u.ts:21:u3', 'src/u.ts:31:u4' }
local function graph()
  local list = {
    node(A, nil, { { B, 2, 3 }, { C, 3, 3 }, { B, 4, 3 }, { D, 5, 3 }, { S, 6, 3 } }),
    node(B, nil, { { E, 2, 3 } }),
    node(C, nil, { { E, 2, 3 }, { C, 3, 3 } }),
    node(D),
    node(E, nil, { { F, 2, 3 } }),
    node(F, nil, { { B, 2, 3 } }),
    node(S, nil, { { D, 2, 3 } }),
    node(MAIN, 'module', { { A, 3, 1 } }),
    node(TEST, 'module', { { A, 5, 1 }, { B, 9, 1 }, { T, 12, 1 } }),
    node(T),
  }
  for i, u in ipairs(U) do
    list[#list + 1] = node(u, nil, { { S, i * 10 - 8, 3 } })
  end
  return index.graph(list)
end
local M = { ispkg = {}, pkgsorted = {} }
local g = graph()

local function keys(r)
  return vim.tbl_map(function(x)
    return x.key
  end, r.rows)
end
local function find(r, key)
  for i, x in ipairs(r.rows) do
    if x.key == key then
      return i, x
    end
  end
end
local function k(...)
  return table.concat({ ... }, '\n')
end

-- counts: distinct, itself left out, through the cycle and the diamond
eq(calls.below(g, A), 6, 'below a: b c d s e f')
eq(calls.below(g, B), 2, 'below b: e f, not b again through the cycle')
eq(calls.below(g, C), 3, 'below c: e f b, not itself')
eq(calls.above(g, E), 6, 'above e: b c a f and both tops')
eq(calls.used_by(g, B), 3, 'used by b: a f and the test')
eq(calls.used_by(g, S), 5, 'used by s')
eq(calls.used_by(g, C), 2, 'used by c: a and itself')
calls.forget(g)
local hide_e = function(p)
  return p ~= 'src/e.ts'
end
eq(calls.below(g, B, hide_e), 0, 'below b with e hidden')
calls.forget(g)

-- kids: as written, a call made twice one kid; going up, tests apart
local kids = calls.kids(g, A, 'down')
eq(
  vim.tbl_map(function(x)
    return x.id
  end, kids),
  { B, C, D, S },
  'a calls b c d s, in the order first written'
)
eq({ kids[1].n, kids[1].lines }, { 2, { 2, 4 } }, 'b called twice by a: x2 at 2 and 4')
local up, tests = calls.kids(g, B, 'up')
eq(
  vim.tbl_map(function(x)
    return x.id
  end, up),
  { A, F },
  'b called by a and f, by path'
)
eq(#tests == 1 and tests[1].id, TEST, 'the test that calls b, apart')

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

-- roots: what nothing calls, tests apart
local roots, troots = calls.roots(g)
eq(roots, { MAIN, T, U[1], U[2], U[3], U[4] }, 'roots: what nothing calls, a test aside')
eq(troots, { TEST }, 'test roots')

-- the budget: whole levels; 4 rows, then b and c open (3 more), then e (1), then f (1)
local function levels_at(h)
  local r = calls.rows(g, calls.new(A, 'down'), h, M)
  return { r.levels, #r.rows }
end
eq(levels_at(6), { 0, 4 }, 'one row over: the level is refused')
eq(levels_at(7), { 1, 7 }, 'an exact fit: the level is admitted')
eq(levels_at(8), { 2, 8 }, 'two levels at 8')
eq(levels_at(9), { 3, 9 }, 'three at 9, and nothing more to open')
do
  local v = calls.new(A, 'down')
  local r = calls.rows(g, v, 100, M)
  local _, s = find(r, k(A, S))
  eq(s.fold, 'folded', 'a shared node is never opened by the budget')
  expect(s.shared, 'a node called by 5 is shared')
  eq(r.shared, { S }, 'the shared line lists it')
  -- also rows: e under c, b under f, c under itself
  local ei, e = find(r, k(A, B, E))
  local _, e2 = find(r, k(A, C, E))
  eq({ e.fold, e2.fold, e2.also }, { 'open', 'also', ei }, 'e opens under b, the earlier; under c it is also')
  local bi = find(r, k(A, B))
  local _, b2 = find(r, k(A, B, E, F, B))
  eq({ b2.fold, b2.also, b2.also_line }, { 'also', bi, 2 }, 'the cycle ends in an also row at the line b was first called')
  local _, c2 = find(r, k(A, C, C))
  eq(c2.fold, 'also', 'a self call is an also row')
  local _, d = find(r, k(A, D))
  eq(d.fold, 'leaf', 'a leaf is a leaf')
  local _, b = find(r, k(A, B))
  eq({ b.n, b.lines, b.count, b.used_by, b.show_file }, { 2, { 2, 4 }, 2, 3, true }, 'b: x2, its lines and counts')
  local seen = {}
  for _, x in ipairs(r.rows) do
    expect(not seen[x.key], 'keys are unique: ' .. x.key)
    seen[x.key] = true
  end
end

-- keys: l opens by hand and keeps what the budget opened
do
  local v = calls.new(A, 'down')
  local base = calls.rows(g, v, 7, M)
  local i = find(base, k(A, B, E))
  eq(calls.key(g, v, base, i, 'l', 7, M), 'redraw', 'l on a folded row redraws')
  local r = calls.rows(g, v, 7, M)
  expect(find(r, k(A, B, E, F)) ~= nil, 'l opened e')
  local _, c = find(r, k(A, C))
  eq(c.fold, 'open', 'opening e by hand did not close c, which the budget opened')
  -- h folds, then goes to the parent
  i = find(r, k(A, B, E))
  calls.key(g, v, r, i, 'h', 7, M)
  r = calls.rows(g, v, 7, M)
  eq(select(2, find(r, k(A, B, E))).fold, 'folded', 'h folds')
  i = find(r, k(A, B, E))
  eq({ calls.key(g, v, r, i, 'h', 7, M), v.cursor }, { 'move', k(A, B) }, 'h on a folded row goes to its parent')
  -- l on an open row goes to its first row; on an also row, to where it is open
  i = find(r, k(A, B))
  eq({ calls.key(g, v, r, i, 'l', 7, M), v.cursor }, { 'move', k(A, B, E) }, 'l on an open row goes to its first')
  i = find(r, k(A, C, E))
  eq({ calls.key(g, v, r, i, 'l', 7, M), v.cursor }, { 'move', k(A, B, E) }, 'l on an also row goes where it is open')
  -- ] and [ go by siblings
  i = find(r, k(A, B))
  eq({ calls.key(g, v, r, i, ']', 7, M), v.cursor }, { 'move', k(A, C) }, '] the next sibling, past its rows')
  i = find(r, k(A, C))
  eq({ calls.key(g, v, r, i, '[', 7, M), v.cursor }, { 'move', k(A, B) }, '[ the previous sibling')
  -- L opens the subtree the budget's way, H puts back what the budget opened
  v.open = {}
  r = calls.rows(g, v, 7, M)
  i = find(r, k(A, B))
  calls.key(g, v, r, i, 'L', 7, M)
  r = calls.rows(g, v, 7, M)
  expect(find(r, k(A, B, E, F, B)) ~= nil, 'L opened all the way down from b')
  i = find(r, k(A, B))
  calls.key(g, v, r, i, 'H', 7, M)
  eq(keys(calls.rows(g, v, 7, M)), keys(base), 'H gives back the rows the budget opened')
  -- <CR> anchors, <BS> comes back to the same rows and cursor; then the explorer
  v.cursor = k(A, D)
  i = find(r, k(A, B))
  eq(calls.key(g, v, r, i, '<CR>', 7, M), 'redraw', '<CR> anchors')
  eq(v.anchor, B, 'on b')
  r = calls.rows(g, v, 7, M)
  eq(calls.key(g, v, r, 1, '<BS>', 7, M), 'redraw', '<BS> goes back')
  eq({ v.anchor, v.cursor, keys(calls.rows(g, v, 7, M)) }, { A, k(A, D), keys(base) }, 'back on a, its rows and cursor as they were')
  eq(calls.key(g, v, r, 1, '<BS>', 7, M), 'explorer', '<BS> with nothing before: the explorer')
  -- ~ flips; C goes to the top, and K back, as <BS> does
  calls.key(g, v, r, 1, '~', 7, M)
  eq({ v.dir, v.cursor }, { 'up', nil }, '~ flips to called by')
  calls.key(g, v, r, 1, 'C', 7, M)
  eq({ v.anchor, v.dir }, { nil, 'down' }, 'C from the top')
  eq(calls.key(g, v, r, 1, '-', 7, M), nil, "- is not the model's: the screen takes it to the explorer")
  eq(calls.key(g, v, r, 1, 'K', 7, M), 'redraw', 'K goes back')
  eq({ v.anchor, v.dir }, { A, 'up' }, 'K from the top: back where it was')
  eq(calls.key(g, v, r, 1, 'K', 7, M), 'explorer', 'K with nothing before: the explorer')
end

-- called by, drawn down from the anchor like calls: each caller under what it calls
do
  local v = calls.new(B, 'up')
  local r = calls.rows(g, v, 100, M)
  local ok = true
  for i, x in ipairs(r.rows) do
    if x.parent and x.parent >= i then
      ok = false
    end
    for _, kid in ipairs(x.kids) do
      if kid <= i then
        ok = false
      end
    end
  end
  expect(ok, 'every caller sits under what it calls')
  eq(r.rows[1].key, k(B, A), 'the first row calls the anchor')
  local ti, t = find(r, k(B, 'tests'))
  eq({ t.kind, t.fold, t.files }, { 'tests', 'folded', 1 }, 'tests fold to one row, never opened for you')
  local ai, a = find(r, k(B, A))
  eq({ a.kids[1], a.count, a.lines }, { ai + 1, 2, { 2, 4 } }, "a's first caller is the row just under it; a calls b at 2 and 4")
  eq(calls.key(g, v, r, ai, 'l', 100, M), 'move', 'l on an open row going up')
  eq(v.cursor, r.rows[ai + 1].key, 'l goes down the screen, as going down')
  expect(ti == #r.rows and t.last, 'the tests row last, after the callers it follows')
end

-- the code beside the tree: where it is called, a place a caller and line,
-- opening on the call the tree is about; or itself, its calls stepped through
do
  local function at(p)
    local u = p.places[p.n]
    return u and (u.from .. ':' .. u.line) or nil
  end
  eq(
    vim.tbl_map(function(u)
      return u.from .. ':' .. u.line
    end, calls.places(g, B)),
    { A .. ':2', A .. ':4', F .. ':2', TEST .. ':9' },
    'b is called at four places: a calling it twice is two, the test last'
  )
  eq(calls.call_lines(g, A), { 2, 3, 4, 5, 6 }, 'a calls on lines 2 to 6')
  local v = calls.new(A)
  local r = calls.rows(g, v, 100, M)
  local bi = find(r, k(A, B))
  local p = calls.pane(g, v, r, bi, M)
  eq({ p.code, at(p) }, { 'called', A .. ':2' }, 'b under a opens on where a calls it')
  eq(calls.key(g, v, r, bi, ']]', 100, M), 'pane', ']] steps the place')
  eq(at(calls.pane(g, v, r, bi, M)), A .. ':4', 'the next place: a again, on its other line')
  calls.key(g, v, r, bi, ']]', 100, M)
  calls.key(g, v, r, bi, ']]', 100, M)
  calls.key(g, v, r, bi, ']]', 100, M)
  eq(at(calls.pane(g, v, r, bi, M)), A .. ':2', ']] round the end to the first')
  calls.key(g, v, r, bi, '[[', 100, M)
  eq(at(calls.pane(g, v, r, bi, M)), TEST .. ':9', '[[ round the start to the last')
  eq(calls.key(g, v, r, bi, '<Tab>', 100, M), 'pane', '<Tab> swaps')
  p = calls.pane(g, v, r, bi, M)
  eq({ v.code, p.code, p.lines, p.n }, { 'itself', 'itself', { 2 }, 0 }, 'itself: b, nothing lit until ]]')
  calls.key(g, v, r, bi, ']]', 100, M)
  eq(calls.pane(g, v, r, bi, M).n, 1, ']] in itself: its first call')
  calls.key(g, v, r, bi, 'j', 100, M)
  eq(calls.pane(g, v, r, bi + 1, M).code, 'itself', 'the view sticks on the next row')
  calls.key(g, v, r, bi, '<CR>', 100, M)
  eq(v.code, 'itself', 'and on another anchor')
  calls.key(g, v, r, 1, '<BS>', 100, M)
  eq(v.code, 'itself', 'and back')
  calls.key(g, v, r, bi, '<Tab>', 100, M)
  eq(at(calls.pane(g, v, r, bi, M)), A .. ':2', 'swapped back: the place the tree is about again')
  -- nothing calls the file's top: itself, whatever was chosen
  local top = calls.new(nil)
  local tr = calls.rows(g, top, 100, M)
  local mi = find(tr, 'file:src/main.ts')
  p = calls.pane(g, top, tr, mi, M)
  eq({ p.code, #p.places }, { 'itself', 0 }, "main's top: nothing calls it, itself")
  eq(calls.pane(g, top, tr, find(tr, 'dir:src'), M), nil, 'a folder shows no code')
  eq(calls.key(g, top, tr, find(tr, 'dir:src'), ']]', 100, M), nil, ']] on a folder does nothing')
  -- going up the row is the caller: called at opens on its first place,
  -- itself lights its call to the row above
  local up = calls.new(B, 'up')
  local ur = calls.rows(g, up, 100, M)
  local ai = find(ur, k(B, A))
  eq(at(calls.pane(g, up, ur, ai, M)), MAIN .. ':3', 'a going up: the first place a is called, not a test')
  up.code = 'itself'
  p = calls.pane(g, up, ur, ai, M)
  eq({ p.code, p.lines[p.n] }, { 'itself', 2 }, 'itself going up: its call to b lit')
end

-- from the top: folders, a file whose top is a root is its row, tests last
do
  local v = calls.new(nil)
  local r = calls.rows(g, v, 100, M)
  local _, file = find(r, 'file:src/main.ts')
  eq({ file.id, file.root, file.fold }, { MAIN, true, 'open' }, "main.ts's top is a root: its row, opened")
  expect(find(r, k('file:src/main.ts', A)) ~= nil, 'what main calls, under it')
  local _, u1 = find(r, k('file:src/u.ts', U[1]))
  eq({ u1.root, u1.lines }, { true, { 1 } }, 'a root shows where it is declared')
  local _, s2 = find(r, k('file:src/u.ts', U[2], S))
  eq(s2.fold, 'also', 's opens under u1 alone')
  eq(r.rows[#r.rows].key, 'tests', 'tests last')
  eq(r.rows[#r.rows].fold, 'folded', 'and folded')
  local _, d = find(r, 'dir:src')
  eq(d.kind, 'dir', 'the folder')
  -- h folds an open folder or file, and only a folded one goes to its parent
  local di = find(r, 'dir:src')
  eq({ calls.key(g, v, r, di, 'h', 100, M), v.cursor }, { 'redraw', 'dir:src' }, 'h on an open folder folds it')
  r = calls.rows(g, v, 100, M)
  eq(keys(r), { 'dir:src', 'tests' }, 'the folder folded: nothing under it drawn')
  eq(r.rows[1].fold, 'folded', 'and drawn folded')
  eq(calls.key(g, v, r, 1, 'h', 100, M), nil, 'h on a folded folder at the top: nowhere to go')
  calls.key(g, v, r, 1, 'l', 100, M)
  r = calls.rows(g, v, 100, M)
  expect(find(r, k('file:src/main.ts', A)) ~= nil, 'l opens it again, as it was')
  local ui = find(r, 'file:src/u.ts')
  calls.key(g, v, r, ui, 'h', 100, M)
  r = calls.rows(g, v, 100, M)
  eq({ select(2, find(r, 'file:src/u.ts')).fold, find(r, k('file:src/u.ts', U[1])) }, { 'folded', nil }, 'h on an open file folds it')
  ui = find(r, 'file:src/u.ts')
  eq({ calls.key(g, v, r, ui, 'h', 100, M), v.cursor }, { 'move', 'dir:src' }, 'h on a folded file goes to its folder')
  -- 10 rows of skeleton, 5 more for the first level
  eq({ calls.rows(g, calls.new(nil), 14, M).levels, calls.rows(g, calls.new(nil), 15, M).levels }, { 0, 1 }, 'the budget pays for the folders too')
end

io.stdout:write(('calls: %d checks, %d failures\n'):format(checks, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
