-- What a name in the code is, on source text written here: a value and the
-- call that made it, a parameter, a field, a method, a type, an import, a
-- local function; the type after each value's name; later uses; the code's
-- types display.
--   nvim -l tests/names.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local code = require 'seam.code'
local codetypes = require 'seam.codetypes'
local index = require 'seam.index'
local names = require 'seam.names'

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

local FILES = {
  ['src/queue.ts'] = [[
/** Work, one at a time. */
export type Queue = Readonly<{
  run: (...work: (() => void)[]) => void;
  /** Reports what one threw. */
  fail: (callback: CallbackName, error: unknown) => void;
}>;

export function createQueue(name: string): Queue {
  return { run() {}, fail() {} } as Queue;
}
]],
  ['src/types.ts'] = [[
export type RunOptions = {
  root?: Document;
  /**
   * Where the record is kept.
   */
  storage?: string | StorageAdapter;
};
export interface StorageAdapter {
  load(): string;
}
]],
  ['src/consts.ts'] = [[
export const LOADING = 1;
]],
  ['src/run.ts'] = [[
import { createQueue, type Queue } from "./queue";
import type { RunOptions } from "./types";
import { LOADING } from "./consts";

export function createRun(options: RunOptions = {}): Run {
  const queue = createQueue("x");
  const root = () => options.root;
  const adapter = options.storage;
  const later = () => createQueue("y");
  const items: Queue[] = [];
  for (const item of items) {
    item.fail("x", 1);
  }
  queue.fail("a", 2);
  const { storage } = options;
  function step(n: number) {
    const inner = createQueue("z");
    queue.run();
    return inner;
  }
  const page = helper({ queue, root });
  const replace = (r: string) => {
    const parsed = helper(r);
    step(parsed);
  };
  return LOADING;
}

function helper(x: unknown): Page {
  return x as Page;
}
]],
}

local dir = vim.fn.tempname()
for path, src in pairs(FILES) do
  vim.fn.mkdir(dir .. '/' .. vim.fs.dirname(path), 'p')
  vim.fn.writefile(vim.split(src, '\n'), dir .. '/' .. path)
end
code.root = dir
code.reset()

-- the line and 0-based column of the `nth` `word` on the first line holding `on`
local function pos(path, on, word, nth)
  for l, s in ipairs(vim.split(FILES[path], '\n')) do
    if s:find(on, 1, true) then
      local at = 0
      for _ = 1, nth or 1 do
        at = s:find('%f[%w_$]' .. vim.pesc(word) .. '%f[^%w_$]', at + 1)
      end
      return l, at - 1
    end
  end
  error('no ' .. on)
end
local function use(path, on, word, nth)
  local l, c = pos(path, on, word, nth)
  return { path = path, line = l, col = c + 1 }
end

-- the first line of `path` holding `on`
local function line_of(path, on)
  for l, s in ipairs(vim.split(FILES[path], '\n')) do
    if s:find(on, 1, true) then
      return l
    end
  end
end

local RUN = 'src/run.ts'
local function node(path, name, on, last)
  local l = line_of(path, on)
  return { id = path .. ':' .. l .. ':' .. name, name = name, kind = 'function', path = path, line = l, end_line = line_of(path, last), calls = {} }
end
local cq = node('src/queue.ts', 'createQueue', 'export function createQueue', 'as Queue')
local cr = node(RUN, 'createRun', 'export function createRun', 'return LOADING')
local hp = node(RUN, 'helper', 'function helper', 'return x as Page')
local m = {
  graph = index.graph { cq, cr, hp },
  exports = {
    {
      id = cq.id,
      name = 'createQueue',
      kind = 'function',
      path = cq.path,
      line = cq.line,
      uses = {
        use(RUN, 'const queue =', 'createQueue'),
        use(RUN, 'const later', 'createQueue'),
        use(RUN, 'const inner', 'createQueue'),
      },
    },
    { id = 'src/queue.ts:2:Queue', name = 'Queue', kind = 'type', path = 'src/queue.ts', line = 2, uses = { use(RUN, 'const items', 'Queue') } },
    {
      id = 'src/types.ts:1:RunOptions',
      name = 'RunOptions',
      kind = 'type',
      path = 'src/types.ts',
      line = 1,
      uses = { use(RUN, 'export function createRun', 'RunOptions') },
    },
    { id = 'src/consts.ts:1:LOADING', name = 'LOADING', kind = 'const', path = 'src/consts.ts', line = 1, uses = { use(RUN, 'return LOADING', 'LOADING') } },
  },
  flows = {
    Queue = { decls = { { name = 'Queue', kind = 'type', path = 'src/queue.ts', line = 2, end_line = 6 } } },
    RunOptions = { decls = { { name = 'RunOptions', kind = 'type', path = 'src/types.ts', line = 1, end_line = 7 } } },
    StorageAdapter = { decls = { { name = 'StorageAdapter', kind = 'interface', path = 'src/types.ts', line = 8, end_line = 10 } } },
  },
}

local function at(on, word, nth)
  local l, c = pos(RUN, on, word, nth)
  return names.at(m, RUN, l, c)
end
local function lines(list)
  return vim.tbl_map(function(u)
    return u.line
  end, list or {})
end
local function L(on)
  return line_of(RUN, on)
end

-- a value: its type the declared return of the call that made it, where it
-- was made, and its later uses in this function, a closure's too
local q = at('const queue =', 'queue')
eq({ q.kind, q.type, q.made_by and q.made_by.name, q.at.line }, { 'value', 'Queue', 'createQueue', L 'const queue =' }, 'a value made by a call')
eq(lines(q.uses), { L 'queue.fail("a"', L 'queue.run()', L 'const page' }, 'its later uses, in a closure and as a shorthand too')
eq(q.decl and q.decl.name, 'Queue', 'its repo type')
local c = at('const queue =', 'createQueue')
eq({ c.kind, c.id }, { 'call', cq.id }, 'the call that made it: the function')
eq(lines(c.uses), lines(q.uses), 'the call lights the later uses of what it made')
eq(lines(at('queue.fail("a"', 'queue').uses), lines(q.uses), 'from a use, the same: every use after it was made')

-- a parameter, a field read, a name destructured, a method
local p = at('export function createRun', 'options')
eq({ p.kind, p.type, p.fn, p.decl and p.decl.name }, { 'param', 'RunOptions', 'createRun', 'RunOptions' }, 'a parameter')
local f = at('const adapter', 'storage')
eq(
  { f.kind, f.object, f.type, f.decl.name, f.member.name, f.member.line, f.member.doc },
  { 'field', 'options', 'string | StorageAdapter', 'RunOptions', 'storage', 6, 3 },
  'a field: its line and its doc comment'
)
local d = at('const { storage }', 'storage')
eq({ d.kind, d.member and d.member.line, d.type }, { 'field', 6, 'string | StorageAdapter' }, 'a field destructured')
local mt = at('queue.fail("a"', 'fail')
eq(
  { mt.kind, mt.object, mt.decl.name, mt.member.line, mt.member.doc, mt.member.ret },
  { 'method', 'queue', 'Queue', 5, 4, 'void' },
  'a method: the member of its type'
)
eq(at('queue.run()', 'run').member.line, 3, 'a method with no doc comment')
eq(at('const adapter', 'options').type, 'RunOptions', 'a parameter read')

-- a loop's value from what it walks; a type; an import; a call; a local function
eq({ at('item.fail', 'item').type, at('item.fail', 'fail').member.line }, { 'Queue', 5 }, 'a loop value from the array it walks')
local t = at('const items', 'Queue')
eq({ t.kind, t.decl.path }, { 'type', 'src/queue.ts' }, 'a type')
eq({ at('return LOADING', 'LOADING').kind, at('return LOADING', 'LOADING').path }, { 'file', 'src/consts.ts' }, 'an imported value: its file')
eq({ at('const page', 'helper').kind, at('const page', 'helper').id }, { 'call', hp.id }, "a call to this file's function")
local st = at('step(parsed)', 'step')
eq({ st.kind, st.type, st.at.line }, { 'value', '(n: number) => …', L 'function step' }, 'a function inside this one is a value of its own')
eq(at('const items', 'const'), nil, 'off a name: nothing')

-- types after names: from the call's declared return, a field's type, a
-- function's return after its parameters; nothing where it is written
local hints = {}
for _, h in ipairs(codetypes.hints(m, RUN, cr.line, cr.end_line)) do
  hints[#hints + 1] = h.line .. ':' .. h.col .. h.text
end
local function hint(on, after, ty)
  local l, cc = pos(RUN, on, after)
  return l .. ':' .. (cc + #after) .. ': ' .. ty
end
eq(hints, {
  hint('const queue =', 'queue', 'Queue'),
  L 'const root' .. ':' .. (({ pos(RUN, 'const root', 'root') })[2] + #'root = ()') .. ': Document',
  hint('const adapter', 'adapter', 'string | StorageAdapter'),
  L 'const later' .. ':' .. (({ pos(RUN, 'const later', 'later') })[2] + #'later = ()') .. ': Queue',
  hint('const inner', 'inner', 'Queue'),
  hint('const page', 'page', 'Page'),
  hint('const parsed', 'parsed', 'Page'),
}, 'the types after the names, and an arrow function its return')

-- the code's types display: the function's line, its values in the order
-- made, then each function inside under its own line
local rows = vim.tbl_map(function(r)
  if r.kind == 'fn' then
    return ('%d fn %s %s → %s'):format(r.depth, r.params, r.name, r.ret or '')
  elseif r.kind == 'value' then
    return ('%d %s  %s'):format(r.depth, r.name, r.type or '')
  end
  return r.kind
end, codetypes.fn(m, RUN, cr.line, 'createRun'))
eq(rows, {
  '0 fn (options: RunOptions) createRun → Run',
  '0 queue  Queue',
  '0 root  () => Document',
  '0 adapter  string | StorageAdapter',
  '0 later  () => Queue',
  '0 items  Queue[]',
  '0 item  Queue',
  '0 storage  string | StorageAdapter',
  '0 page  Page',
  'blank',
  '1 fn (n: number) step → ',
  '1 inner  Queue',
  'blank',
  '1 fn (r: string) replace → ',
  '1 parsed  Page',
}, 'the types display')
local file = vim.tbl_map(function(r)
  return r.kind .. ' ' .. r.name
end, codetypes.file(m, 'src/queue.ts'))
eq(file, { 'type Queue', 'fn createQueue' }, "a file's declarations")

io.stdout:write(('names: %d checks, %d failures\n'):format(checks, #failures))
vim.fn.delete(dir, 'rf')
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
