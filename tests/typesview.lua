-- The Types view as data: a function's line from its signature, the names
-- on a line that are types, and the types opened in place laid out.
--   nvim -l tests/typesview.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local tv = require 'seam.typesview'
local types = require 'seam.types'

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

-- the line: Readonly left out, one object bare, type parameters as their bounds
eq(tv.unwrap 'Readonly<Record<string, Readonly<{ a: A }>>>', 'Record<string, { a: A }>', 'Readonly left out, nested')
eq(tv.unwrap 'MyReadonly<A>', 'MyReadonly<A>', 'only Readonly itself')
eq(tv.simple 'Readonly<{\n  /** the root */\n  root?: Document;\n  storage: string;\n}>', '{ root?: Document, storage: string }', 'an object on one line')
eq(tv.simple 'import("./a").Point', 'Point', 'import() dropped')
eq(tv.parts '{ a: A, b: (x: X, y: Y) => void, c: C<D, E> }', { 'a: A', 'b: (x: X, y: Y) => void', 'c: C<D, E>' }, 'parts at the top level')
eq(tv.parts '(A, B)', { 'A', 'B' }, 'a list')

local step = {
  tparams = { tv.tparam 'TStep extends Step' },
  params = { { name = 'handlers', type = 'ProblemHandlers<TStep>', optional = true } },
  ret = 'ReportProblem<TStep>',
}
eq(tv.takes(step), '(ProblemHandlers<Step>)', 'a type parameter as what it extends')
eq(tv.gives(step), 'ReportProblem<Step>', 'and in what it gives')
eq(tv.takes { tparams = { tv.tparam 'T' }, params = { { name = 'f', type = '() => T' } } }, '(() => unknown)', 'a bare type parameter is unknown')
eq(
  tv.takes { tparams = {}, params = { { name = '{ a, b }', type = 'Readonly<{ a: StorageAdapter | undefined; b: Queue }>' } } },
  '{ a: StorageAdapter | undefined, b: Queue }',
  'one object parameter bare'
)
eq(tv.takes { tparams = {}, params = { { name = 'a', type = 'A' }, { name = 'n', type = 'number' } } }, '(A, number)', 'several in brackets')
eq(tv.takes { tparams = {}, params = { { name = 'x' } } }, '(x)', 'a parameter without a type by its name')
eq(tv.gives { tparams = {}, params = {} }, 'void', 'nothing given is void')

eq(tv.tparam 'const TStep extends TShape', { name = 'TStep', bound = 'TShape', text = 'const TStep extends TShape' }, 'const and a bound')
eq(
  tv.tparam 'TW extends Walkthrough = Walkthrough',
  { name = 'TW', bound = 'Walkthrough', text = 'TW extends Walkthrough = Walkthrough' },
  'the default left off the bound'
)
eq(tv.tparam('F extends (a: A) => B = X').bound, '(a: A) => B', "an arrow's = is not a default")
eq(
  vim.tbl_map(function(p)
    return p.name .. ':' .. tostring(p.bound)
  end, tv.tparams 'const f: <T, K extends Key<T> = string>(t: T) => K'),
  { 'T:nil', 'K:Key<T>' },
  'type parameters from a hover'
)
eq(tv.tparams 'function f(a: A): B', {}, 'none')

local o, parts, c = tv.opened {
  tparams = { tv.tparam 'TStep extends Step' },
  params = { { name = 'w', type = 'Walkthrough<TStep>' }, { name = 'i', type = 'number' } },
}
eq({ o, parts, c }, { '(', { '<TStep extends Step>', 'Walkthrough<TStep>,', 'number,' }, ')' }, 'opened as written: type parameters as written, a part a line')
o, parts, c = tv.opened { tparams = {}, params = { { name = '{ a }', type = '{ a: A; b: B }' } } }
eq({ o, parts, c }, { '{', { 'a: A,', 'b: B,' }, '}' }, 'one object opened by its members')

eq(tv.cut('{ adapter: StorageAdapter }', 12), '{ adapter: …', 'cut with … at the column')
eq(tv.cut('(A)', 12), '(A)', 'short kept')

-- written first, the hover where nothing is written
local hover = types.parse 'function f<T extends X>(a: A, b: B): R'
eq(tv.sig({ tparams = {}, params = { { name = 'a', type = 'Mine' }, { name = 'b' } } }, hover), {
  tparams = {},
  params = { { name = 'a', type = 'Mine' }, { name = 'b', type = 'B' } },
  ret = 'R',
}, 'written types, the rest from the hover')
eq(tv.sig(nil, hover).tparams[1].bound, 'X', "the hover's type parameters when nothing is written")
eq(tv.sig(nil, nil), nil, 'nothing either way')

-- the names on a line that are types
local known = { Model = true, Given = true, Run = true }
local function is_type(n)
  return known[n] == true
end
eq(tv.names('  model: Model; given?: Given; "Run": Run.x', is_type), {
  { s = 10, e = 15, name = 'Model' },
  { s = 25, e = 30, name = 'Given' },
  { s = 39, e = 42, name = 'Run' },
}, 'types where they are, keys and strings left out')
eq(tv.names('Model: string', is_type), {}, 'a key is not a type')
eq(tv.at({ { s = 4, e = 9, name = 'Model' } }, 4), { s = 4, e = 9, name = 'Model' }, 'the name at its first byte')
eq(tv.at({ { s = 4, e = 9, name = 'Model' } }, 9), nil, 'not past it')

local code, inside = tv.code_part('a: A; /** Run */ b: B // Given', false)
eq({ code, inside }, { 'a: A;            b: B         ', false }, 'comments blanked')
code, inside = tv.code_part('/** the Run', false)
eq({ code, inside }, { '           ', true }, 'a comment left open')
code, inside = tv.code_part(' * ends */ x: Model', true)
eq({ code, inside }, { '           x: Model', false }, 'and closed')

-- opened in place: one level a press, under the line that names it
local blocks = {
  StoredRecord = { lines = { { id = 12, names = {} }, { id = 14, names = { 'Progress' } }, { id = 16, names = {} } } },
  Progress = { lines = { { id = 97, names = { 'Progress' } }, { id = 98, names = { 'StoredRecord' } } } },
}
local function lay(open, defaults)
  local lines = { { id = 154, names = {} }, { id = 155, names = { 'StoredRecord' } }, { id = 156, names = { 'StoredRecord' } } }
  return vim.tbl_map(
    function(x)
      return (x.head and ('+' .. x.name) or tostring(x.line.id)) .. '@' .. x.depth .. (#x.chain > 0 and (' in ' .. x.chain[#x.chain]) or '')
    end,
    tv.layout(lines, 'R', {
      open = open,
      defaults = defaults,
      resolve = function(n)
        return blocks[n]
      end,
    })
  )
end
eq(lay {}, { '154@0', '155@0', '156@0' }, 'nothing open')
local k1 = tv.child('R', 155, 'StoredRecord')
eq(k1, 'R|155:StoredRecord', 'a key: the block, the line, the name')
eq(
  lay { [k1] = true },
  { '154@0', '155@0', '+StoredRecord@1 in ' .. k1, '12@1 in ' .. k1, '14@1 in ' .. k1, '16@1 in ' .. k1, '156@0' },
  'opened under its line only'
)
local k2 = tv.child(k1, 14, 'Progress')
eq(lay { [k1] = true, [k2] = true }, {
  '154@0',
  '155@0',
  '+StoredRecord@1 in ' .. k1,
  '12@1 in ' .. k1,
  '14@1 in ' .. k1,
  '+Progress@2 in ' .. k2,
  '97@2 in ' .. k2,
  '98@2 in ' .. k2,
  '16@1 in ' .. k1,
  '156@0',
}, 'nested a level down; a type open around it does not open again')
eq(lay({}, { [k1] = true }), lay { [k1] = true }, 'open by default')
local open = { [k1] = true, [k2] = true }
tv.close(open, k1)
eq(open, { [k1] = false }, 'closing forgets what was open inside')
eq(lay(open, { [k1] = true }), { '154@0', '155@0', '156@0' }, 'closed over its default')

if #failures > 0 then
  io.stdout:write(('typesview: %d checks, %d failures\n'):format(checks, #failures))
  os.exit(1)
end
io.stdout:write(('typesview: %d checks, 0 failures\n'):format(checks))
