-- The Map as data, on a graph written by hand: what a function calls and
-- reaches, the folders and files the Map names, the calls across an edge;
-- both ways, by folder and file; the size's bars; what a type's takers
-- give.
--   nvim -l tests/map.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local index = require 'seam.index'
local data = require 'seam.map.data'

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

-- both ways: each side a folder, its files, each file's names after it
local both = require 'seam.map.both'
local function it(folder, path, name)
  return { folder = folder, path = path, segs = { { name, 'SeamMapFn' } } }
end
local L = both.side(
  { it('st/', 'a/st/s.ts', 'b'), it('ck/', 'a/ck/c.ts', 'c'), it('st/', 'a/st/s.ts', 'b2'), it('st/', 'a/st/t.ts', 'd') },
  40,
  { side = 'left' }
)
rows = both.draw(L, both.side({ it('up/', 'a/up/u.ts', 'u') }, 40, { side = 'right' }), { { 'mid', 'SeamBold' } }, 80)
eq(texts(rows), {
  ' st/',
  '   s.ts  b  b2 ╶┐',
  '   t.ts  d ╶────┤             up/',
  '                ├──╴mid ╶──────╴u.ts  u',
  ' ck/            │',
  '   c.ts  c ╶────┘',
}, 'both ways: the folders with the most first, an empty row between them, a file a line, its names after it, joined to the centre')
local many = {}
for i = 1, both.CAP + 2 do
  many[i] = it('st/', 'a/st/s.ts', 'f' .. i)
end
local cut = both.side(many, 30, { side = 'left' })
eq(cut[#cut].segs[1][1], '⋯ 2 more', 'a side past its cap: ⋯ more last')
for _, l in ipairs(cut) do
  local w = l.indent or 0
  for _, s in ipairs(l.segs) do
    w = w + vim.api.nvim_strwidth(s[1])
  end
  expect(w <= 30, 'names wrap to the room', l)
end
eq({ both.rooms(10, 80, 100, 10) }, { 10, 68 }, 'the narrower side what it needs, the wider the rest')

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

-- a type's flow: In makes Model by mk; Model taken by tk1 giving Out, tk2
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
io.stdout:write(('map: %d checks, %d failures\n'):format(checks, #failures))
os.exit(#failures == 0 and 0 or 1)
