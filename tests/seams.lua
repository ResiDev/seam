-- Used by and Built from as data, on a model written by hand: who uses a
-- function, a file, a folder and a type; what a function, a file and a
-- folder draw on; grouped by file with tests last and `⋯ more` past four,
-- by name, by user, by first use and as signature lines.
--   nvim -l tests/seams.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local index = require 'seam.index'
local seams = require 'seam.seams'

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

-- s/ holds store.ts (save, a function, and Rec, a type) and keep.ts (load,
-- which calls save and names Rec). run.ts's go calls save twice and load
-- once and names Rec; a test calls save five times; save calls helper in
-- its own file, which is no export.
local SAVE, REC, LOAD = 's/store.ts:10:save', 's/store.ts:1:Rec', 's/keep.ts:3:load'
local GO, HELP, TEST = 'r/run.ts:5:go', 's/store.ts:30:helper', 'test/s.test.ts:2:t'
local function node(id, calls_)
  local path, line, name = id:match '^(.*):(%d+):(.*)$'
  return { id = id, name = name, kind = 'function', path = path, line = tonumber(line), end_line = tonumber(line) + 9, calls = calls_ or {} }
end
local m = {
  graph = index.graph {
    node(SAVE, { { HELP, 12, 5 } }),
    node(HELP),
    node(LOAD, { { SAVE, 5, 3 } }),
    node(GO, { { SAVE, 6, 3 }, { SAVE, 8, 3 }, { LOAD, 9, 3 } }),
    node(TEST, { { SAVE, 3, 1 }, { SAVE, 4, 1 }, { SAVE, 5, 1 }, { SAVE, 6, 1 }, { SAVE, 7, 1 } }),
  },
  exports = {
    {
      id = SAVE,
      name = 'save',
      kind = 'function',
      path = 's/store.ts',
      line = 10,
      uses = {
        { path = 's/keep.ts', line = 5, col = 3, role = 'call' },
        { path = 'r/run.ts', line = 6, col = 3, role = 'call' },
        { path = 'r/run.ts', line = 8, col = 3, role = 'call' },
        { path = 'test/s.test.ts', line = 3, col = 1, role = 'call' },
        { path = 'test/s.test.ts', line = 4, col = 1, role = 'call' },
        { path = 'test/s.test.ts', line = 5, col = 1, role = 'call' },
        { path = 'test/s.test.ts', line = 6, col = 1, role = 'call' },
        { path = 'test/s.test.ts', line = 7, col = 1, role = 'call' },
      },
      deps = { { name = 'Rec', line = 10, col = 20, target = REC } },
    },
    {
      id = REC,
      name = 'Rec',
      kind = 'type',
      path = 's/store.ts',
      line = 1,
      uses = { { path = 's/keep.ts', line = 3, col = 20, role = 'type' }, { path = 'r/run.ts', line = 5, col = 15, role = 'type' } },
      deps = {},
    },
    {
      id = LOAD,
      name = 'load',
      kind = 'function',
      path = 's/keep.ts',
      line = 3,
      uses = { { path = 'r/run.ts', line = 9, col = 3, role = 'call' } },
      deps = { { name = 'Rec', line = 3, col = 20, target = REC }, { name = 'save', line = 5, col = 3, target = SAVE } },
    },
    {
      id = GO,
      name = 'go',
      kind = 'function',
      path = 'r/run.ts',
      line = 5,
      uses = {},
      deps = {
        { name = 'Rec', line = 5, col = 15, target = REC },
        { name = 'save', line = 6, col = 3, target = SAVE },
        { name = 'save', line = 8, col = 3, target = SAVE },
        { name = 'load', line = 9, col = 3, target = LOAD },
      },
    },
  },
  byid = {},
  bykey = {},
}
for _, e in ipairs(m.exports) do
  m.byid[e.id] = e
  m.bykey[e.path .. ':' .. e.name] = e
end

local function at(list)
  return vim.tbl_map(function(p)
    return p.path .. ':' .. p.line .. ' ' .. p.name
  end, list)
end

-- who uses -------------------------------------------------------------

local fn = { kind = 'fn', id = SAVE, path = 's/store.ts' }
local used = seams.used(m, fn)
eq(#used, 8, "save's uses: the index's, its own file's callers too, each spot once")
eq({ seams.count(used) }, { 3, 8 }, 'in three files, eight places')

local groups = seams.by_file(used)
eq(
  vim.tbl_map(function(g)
    return g.path
  end, groups),
  { 'r/run.ts', 's/keep.ts', 'test/s.test.ts' },
  'by file: the most places first, the test last though it has the most'
)
eq(at(groups[1].places), { 'r/run.ts:6 save', 'r/run.ts:8 save' }, "a file's places in its order")
local shown, more = seams.cut(groups[3].places)
eq({ #shown, more }, { 4, 1 }, 'four shown, one more')
eq({ #seams.cut(groups[3].places, true) }, { 5 }, 'all of them, opened')
eq({ #seams.cut(groups[1].places) }, { 2 }, 'two are all there is')

local folder = seams.used(m, { kind = 'dir' }, 's')
eq(#folder, 9, 's/: the uses from outside it, not keep.ts calling save')
local names = seams.by_name(folder)
eq(
  vim.tbl_map(function(g)
    return g.name .. ' ' .. #g.places .. '/' .. g.files
  end, names),
  { 'load 1/1', 'save 7/2', 'Rec 1/1' },
  'by name: the functions in the order declared, then the types'
)
eq(at(names[2].places), {
  'r/run.ts:6 save',
  'r/run.ts:8 save',
  'test/s.test.ts:3 save',
  'test/s.test.ts:4 save',
  'test/s.test.ts:5 save',
  'test/s.test.ts:6 save',
  'test/s.test.ts:7 save',
}, "a name's places, tests last")

local file = seams.used(m, { kind = 'file', path = 's/store.ts' })
eq(#file, 10, "store.ts: its exports' uses from other files")
local ty = seams.used(m, { kind = 'type', name = 'Rec', path = 's/store.ts' })
eq(at(ty), { 's/keep.ts:3 Rec', 'r/run.ts:5 Rec' }, 'a type: where it is named')

-- what each use sits in
local tops =
  { ['r/run.ts'] = { { name = 'go', kind = 'fn', line = 5, end_line = 14 } }, ['test/s.test.ts'] = { { name = 't', kind = 'fn', line = 2, end_line = 11 } } }
seams.place_in(folder, function(path, line)
  return seams.innermost(tops[path] or {}, line)
end)
local users = seams.by_user(folder)
eq(
  vim.tbl_map(function(g)
    return (g.top and g.top.name or g.path) .. ': ' .. table.concat(
      vim.tbl_map(function(n)
        return n.name
      end, g.names),
      ', '
    )
  end, users),
  { 'go: Rec, save, load', 't: save' },
  'by user: each function and what it uses, in the order used, the test last'
)
eq(seams.innermost({ { name = 'a', line = 1, end_line = 20 }, { name = 'b', line = 5, end_line = 8 } }, 6).name, 'b', 'the innermost holding the line')
eq(seams.innermost({ { name = 'a', line = 1, end_line = 2 } }, 6), nil, 'nothing holding it')

-- what it draws on -----------------------------------------------------

local go = seams.built(m, { kind = 'fn', id = GO, path = 'r/run.ts' })
eq(at(seams.first_uses(go)), { 'r/run.ts:5 Rec', 'r/run.ts:6 save', 'r/run.ts:9 load' }, 'by name: each once, at its first use')
eq({ seams.count_names(go) }, { 2, 3 }, 'built from two files, three names')
local from = seams.from_files(go, 'r/run.ts')
eq(
  vim.tbl_map(function(g)
    return g.path .. ' ' .. table.concat(at(g.uses), ', ')
  end, from),
  { 's/keep.ts r/run.ts:9 load', 's/store.ts r/run.ts:5 Rec, r/run.ts:6 save' },
  'by file: each file, its names in the order first used'
)
local fns, tys = seams.signatures(go)
eq({ at(fns), at(tys) }, { { 'r/run.ts:6 save', 'r/run.ts:9 load' }, { 'r/run.ts:5 Rec' } }, 'as signatures: the calls in order, then the types')

local save = seams.built(m, fn)
eq(at(save), { 's/store.ts:10 Rec' }, "an export: the index's names")
local help = seams.built(m, { kind = 'fn', id = HELP, path = 's/store.ts' })
eq(#help, 0, 'a function calling nothing draws on nothing')
local kept = seams.built(m, { kind = 'fn', id = HELP, path = 's/store.ts' }, nil, function()
  return { { path = 's/store.ts', line = 31, col = 9, name = 'Rec', kind = 'type', decl = { path = 's/store.ts', line = 1 } } }
end)
eq(at(kept), { 's/store.ts:31 Rec' }, 'no export: the types it names, as asked')
local home = seams.from_files(seams.built(m, { kind = 'fn', id = LOAD, path = 's/keep.ts' }), 's/keep.ts')
eq(home[1].path, 's/store.ts', 'no home file among them: by path')

local sfile = seams.built(m, { kind = 'file', path = 's/keep.ts' })
eq(at(sfile), { 's/keep.ts:3 Rec', 's/keep.ts:5 save' }, 'a file: the names it takes from other files')
local sdir = seams.built(m, { kind = 'dir' }, 's')
eq(#sdir, 0, 's/: nothing from outside it')
local rdir = seams.built(m, { kind = 'dir' }, 'r')
eq(#rdir, 4, 'r/: every name it takes from outside, each spot once')

-- a test's file sorts after the rest when it is drawn on
local tfrom = seams.from_files({
  { path = 'a.ts', line = 1, col = 1, name = 'x', decl = { path = 'test/h.ts', line = 1 }, test = false },
  { path = 'a.ts', line = 2, col = 1, name = 'y', decl = { path = 'z.ts', line = 1 }, test = false },
}, 'a.ts')
eq(
  vim.tbl_map(function(g)
    return g.path
  end, tfrom),
  { 'z.ts', 'test/h.ts' },
  'a test helper drawn on goes last'
)

local short = seams.shortener { 'packages/core/src/storage/a.ts', 'packages/core/src/run/run.ts', 'packages/core/src/state.ts' }
eq({ short 'packages/core/src/run/run.ts', short 'packages/core/src/state.ts' }, { 'run/run.ts', 'state.ts' }, 'paths relative to the folder they share')
eq(seams.shortener { 'a/b.ts', 'c.ts' } 'a/b.ts', 'a/b.ts', 'nothing shared, the whole path')

io.stdout:write(('seams: %d checks, %d failures\n'):format(checks, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
