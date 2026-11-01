-- The Map as data, on a graph written by hand: what a function calls and
-- reaches, the folders and files the Map names, the calls across an edge;
-- the tree with its levels, a branch opened and closed, the cut past three
-- and a name seen higher; a folder's and a file's ranks; both ways; the
-- folders' boxes and the folder graph's ranks; the size's bars; a type's
-- boxes with its makers, its takers' outputs and what gives it back.
--   nvim -l tests/map.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local index = require 'seam.index'
local data = require 'seam.map.data'
local mtree = require 'seam.map.tree'

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
local function texts(rows)
  return vim.tbl_map(function(r)
    return (r:text():gsub('%s+$', ''))
  end, rows)
end
local function has(rows, s)
  for _, t in ipairs(texts(rows)) do
    if t:find(s, 1, true) then
      return true
    end
  end
  return false
end

-- two packages. run() calls a b c d e, in that order; a calls a1..a5, a1
-- calls run back; b and c are in pa/src/st, d at pa's top, e in pb; a test
-- and pb's main call run; b calls c.
local function id(path, line, name)
  return path .. ':' .. line .. ':' .. name
end
local RUN, A, B, C, D, E =
  id('pa/src/run/run.ts', 10, 'run'),
  id('pa/src/run/up.ts', 1, 'a'),
  id('pa/src/st/s.ts', 1, 'b'),
  id('pa/src/st/s.ts', 9, 'c'),
  id('pa/src/top.ts', 1, 'd'),
  id('pb/src/x.ts', 1, 'e')
local A1, A2, A3, A4, A5 =
  id('pa/src/run/up.ts', 10, 'a1'),
  id('pa/src/run/up.ts', 20, 'a2'),
  id('pa/src/run/up.ts', 30, 'a3'),
  id('pa/src/run/up.ts', 40, 'a4'),
  id('pa/src/run/up.ts', 50, 'a5')
local TEST, MAIN = id('pa/src/run/run.test.ts', 3, 't'), id('pb/src/main.ts', 0, '')
local function node(nid, calls_, kind)
  local path, line, name = nid:match '^(.*):(%d+):(.*)$'
  local cs = {}
  for i, c in ipairs(calls_ or {}) do
    cs[i] = { c, tonumber(line) + i, 3 }
  end
  return { id = nid, name = name, kind = kind or 'function', path = path, line = tonumber(line), end_line = tonumber(line) + 8, calls = cs }
end
local m = {
  graph = index.graph {
    node(RUN, { A, B, C, D, E, A }),
    node(A, { A1, A2, A3, A4, A5 }),
    node(A1, { RUN }),
    node(A2),
    node(A3),
    node(A4),
    node(A5),
    node(B, { C }),
    node(C),
    node(D),
    node(E),
    node(TEST, { RUN }),
    node(MAIN, { RUN }, 'module'),
  },
  exports = {},
  ispkg = { pa = true, pb = true },
  pkgsorted = { 'pa', 'pb' },
  pkgcache = {},
}

-- the facts
eq(data.calls(m, RUN), { A, B, C, D, E }, 'run calls each once, in the order first written')
local callers, tests = data.callers(m, RUN)
eq({ callers, tests }, { { A1, MAIN }, { TEST } }, 'who calls run: tests apart')
eq(data.reach(m, RUN), 10, 'run reaches every function under it, itself not counted')
eq(data.reach(m, A1), 10, 'a1 reaches run and all it reaches, a1 not counted')
eq(data.reach(m, B), 1, 'b reaches c')
eq(data.where(m, 'pa/src/st/s.ts', RUN), 'st/', 'a folder in the same package from its src/')
eq(data.where(m, 'pa/src/top.ts', RUN), 'pa/src/ files', "the package's top")
eq(data.where(m, 'pb/src/x.ts', RUN), 'pb/src/', 'another package from its name')
eq(data.short(m, 'pa/src/run/run.ts', 'pa/src/x'), 'run/run.ts', 'a file in the same package')
eq(data.short(m, 'pb/src/x.ts', 'pa/src/x'), 'pb/src/x.ts', 'a file in another package')
local into, out = data.crossing(m, data.within 'pa/src/st')
eq(#into, 2, 'into st/: run calls b and c')
eq(#out, 0, 'st/ calls nothing outside')
into, out = data.crossing(m, data.within 'pa/src/run/run.ts')
eq(
  vim.tbl_map(function(e)
    return e.from
  end, into),
  { A1, MAIN },
  "into run.ts: a1 and main's top level, the test left out"
)
eq(#out, 5, 'out of run.ts: a b c d e')

-- the tree on a function: two levels, every call of the root, three of the rest
local o = { levels = 2, open = {}, more = {}, width = 120 }
local rows = mtree.draw(mtree.fn(m, RUN), o)
eq(texts(rows), {
  ' run',
  ' ├─ a',
  ' │  ├─ a1',
  ' │  ├─ a2',
  ' │  ├─ a3',
  ' │  └─ ⋯ 2 more',
  ' ├─ b',
  ' │  └─ c',
  ' ├─ c',
  ' ├─ d',
  ' └─ e',
}, 'the tree, two levels, the cut past three')
eq(rows[6].meta.map.more, '\n' .. A, 'the ⋯ more stands for its branch')
eq({ mtree.can(rows[3].meta.map, o) }, { 'open', false }, 'l opens a1, a leaf at the last level')
eq({ mtree.can(rows[2].meta.map, o) }, { nil, true }, 'h closes a, open')
eq({ mtree.can(rows[4].meta.map, o) }, { nil, false }, 'a2 calls nothing: neither')
o.more['\n' .. A] = true
expect(has(mtree.draw(mtree.fn(m, RUN), o), '└─ a5'), 'the ⋯ more opened shows them all')
o.open['\n' .. A .. '\n' .. A1] = true
rows = mtree.draw(mtree.fn(m, RUN), o)
local seen
for _, r in ipairs(rows) do
  if r.meta.map and r.meta.map.seen then
    seen = r
  end
end
expect(seen and seen:text():find 'run', 'a1 opened: run, seen at the root, dim and stopping', texts(rows))
o.open['\n' .. A] = false
eq(#mtree.draw(mtree.fn(m, RUN), o), 7, 'a closed: its calls gone')
o = { levels = 1, open = {}, more = {}, width = 120 }
eq(#mtree.draw(mtree.fn(m, RUN), o), 6, 'one level: the root and its calls')
-- with T: the columns, and what each takes and gives
o.types = function(nid)
  return nid == A and 'In' or nil, nid == A and 'Out' or nil
end
rows = mtree.draw(mtree.fn(m, RUN), o)
expect(rows[1]:text():find 'takes' and rows[1]:text():find 'gives', 'T: the columns titled', texts(rows))
expect(rows[3]:text():find 'a%s+In%s+Out', 'T: a takes In and gives Out', texts(rows))

-- a folder's and a file's ranks
o = { levels = 2, open = {}, more = {}, width = 120 }
eq(texts(mtree.draw(mtree.dir(m, 'pa/src/run', 'run/'), o)), {
  ' run/',
  ' ├─ st/                           2 names',
  ' │  └─ s.ts',
  ' ├─ pa/src/ files                 1 name',
  ' │  └─ top.ts',
  ' └─ pb/src/                       1 name',
  '    └─ x.ts',
}, 'a folder: the folders it calls into, the most names first, then their files')
o.levels = 3
expect(has(mtree.draw(mtree.dir(m, 'pa/src/run', 'run/'), o), '└─ c()'), 'a level more: the functions in each file')
o.levels = 2
eq(
  texts(mtree.draw(mtree.file(m, 'pa/src/run/run.ts'), o))[2],
  ' ├─ s.ts                          2 names',
  'a file: the files it calls into, the most names first'
)

-- both ways
local both = require 'seam.map.both'
rows = both.draw({ { { 'x', 'SeamName' } }, { { 'yy', 'SeamName' } } }, { { { 'p', 'SeamName' } } }, { { 'mid', 'SeamBold' } }, 80)
eq(
  texts(rows),
  { '  x ╶─┐', ' yy ╶─┴──╴mid ╶────╴p' },
  'both ways: the left right-aligned, joined to the centre, the right after it'
)
local many = {}
for i = 1, both.CAP + 2 do
  many[i] = { { 'f' .. i } }
end
eq(#both.cut(many, 'left'), both.CAP + 1, 'a side past its cap: ⋯ more last')

-- the folders' boxes: every arrow at the row
local folders = require 'seam.map.folders'
rows = folders.draw(m, {
  centre = 'run',
  centre_hl = 'SeamBold',
  sub = 'run/',
  left = { { path = 'pa/src/run/up.ts', id = A1, name = 'a1' } },
  right = { { path = 'pa/src/st/s.ts', id = B, name = 'b' }, { path = 'pa/src/st/s.ts', id = C, name = 'c' }, { path = 'pb/src/x.ts', id = E, name = 'e' } },
  tests = 1,
  tfiles = 1,
  word = { 'call', 'calls' },
  heads = 'in',
  home = RUN,
  width = 120,
})
expect(has(rows, '◀ 2 calls') and has(rows, '◀ 1 call'), 'the counts on the arrows, pointing at the row', texts(rows))
expect(has(rows, 's.ts  b  c') and has(rows, '─ st/ ─'), 'a box a folder, its files and names', texts(rows))
expect(has(rows, '⋯ 1 in tests, 1 files'), 'tests folded to a count', texts(rows))
expect(has(rows, '▶│ run'), 'the left arrow into the row', texts(rows))

-- a folder's folders: ranks from what nothing calls, what calls nothing last
local fgraph = require 'seam.map.fgraph'
local units = { { key = 'r', label = 'run/' }, { key = 's', label = 'st/' }, { key = 'c', label = 'ck/' }, { key = 't', label = 'top' } }
local edges = {
  { from = 'r', to = 's', n = 3 },
  { from = 'r', to = 't', n = 5 },
  { from = 's', to = 'c', n = 2 },
  { from = 'c', to = 't', n = 1 },
  { from = 'c', to = 's', n = 1 },
}
eq(fgraph.ranks(units, edges), { r = 0, s = 1, c = 2, t = 3 }, 'the ranks: a step a call, the one calling nothing last')
rows = fgraph.draw(units, edges, { width = 160, word = { 'call', 'calls' } })
expect(has(rows, '3 calls') and has(rows, '5 calls') and has(rows, '1 call'), 'the counts on the arrows', texts(rows))
expect(has(rows, '◀') == false and has(rows, '▶'), 'arrows between ranks', texts(rows))

-- the size's bars
local size = require 'seam.map.size'
rows = size.draw {
  head = 'reaches',
  second = 'used by',
  items = { { label = 'big', hl = 'SeamName', n = 10, second = '1' }, { label = 'none', hl = 'SeamName', n = 0, second = '2' } },
  width = 100,
}
expect(rows[1]:text():find 'reaches' and rows[1]:text():find 'used by', 'the bars titled', texts(rows))
expect(rows[3]:text():find 'big%s+ 10', 'the longest bar, its number after it', texts(rows))
expect(rows[4]:text():find '▏ 0', 'no reach: a tick', texts(rows))

-- a type's boxes: In makes Model by mk; Model taken by tk1 giving Out, tk2
-- giving Model back, tk3 a boolean; Out taken by o1 giving In
local function sig(params, ret)
  local ps = {}
  for i, t in ipairs(params) do
    ps[i] = { name = 'p' .. i, type = t }
  end
  return { params = ps, ret = ret, text = '' }
end
local MK, TK1, TK2, TK3, O1 =
  id('pa/src/t.ts', 1, 'mk'), id('pa/src/t.ts', 2, 'tk1'), id('pa/src/t.ts', 3, 'tk2'), id('pa/src/t.ts', 4, 'tk3'), id('pa/src/t.ts', 5, 'o1')
local tm = {
  graph = index.graph { node(MK), node(TK1), node(TK2), node(TK3), node(O1) },
  sigs = {
    [MK] = sig({ 'In' }, 'Model'),
    [TK1] = sig({ 'Model' }, 'Out'),
    [TK2] = sig({ 'Model' }, 'Model'),
    [TK3] = sig({ 'Model' }, 'boolean'),
    [O1] = sig({ 'Out' }, 'In'),
  },
  flows = {
    Model = { gives = { MK, TK2 }, takes = { { id = TK1 }, { id = TK2 }, { id = TK3 } }, decls = {} },
    Out = { gives = { TK1 }, takes = { { id = O1 } }, decls = {} },
    In = { gives = { O1 }, takes = { { id = MK } }, decls = {} },
  },
  ispkg = { pa = true },
  pkgsorted = { 'pa' },
  pkgcache = {},
}
eq({ data.gives(tm, TK1) }, { 'Out', true }, 'tk1 gives Out, a repo type')
eq({ data.gives(tm, TK3) }, { 'boolean', false }, 'tk3 gives a boolean')
local tg = require 'seam.map.typegraph'
rows = tg.draw(tm, 'Model', { levels = 2, open = {}, more = {}, width = 140 })
expect(has(rows, '↺ tk2'), 'tk2 gives Model back: above its box', texts(rows))
expect(has(rows, ' mk ') and has(rows, '│ In │'), 'the maker on the left, from the type it takes', texts(rows))
expect(has(rows, 'tk1 ') and has(rows, '│ Out ├') and has(rows, '│ boolean │'), 'the takers on the arrows, a box an output', texts(rows))
expect(has(rows, ' o1 '), 'two levels: Out on into what takes it', texts(rows))
local tvrow
for _, r in ipairs(rows) do
  if r.meta.tv and r.meta.tv.names[1].name == 'Model' then
    tvrow = r
  end
end
expect(tvrow and tvrow.meta.tv.key == 'map' and tvrow.meta.tv.after, "the box's name for +: its declaration under the drawing")
rows = tg.draw(tm, 'Model', { levels = 1, open = {}, more = {}, width = 140 })
expect(not has(rows, ' o1 '), 'one level: Out stops')
rows = tg.draw(tm, 'Model', { levels = 1, open = { ['\nOut'] = true }, more = {}, width = 140 })
expect(has(rows, ' o1 '), 'l on the Out box: its branch alone a level deeper')

io.stdout:write(('map: %d checks, %d failures\n'):format(checks, #failures))
os.exit(#failures == 0 and 0 or 1)
