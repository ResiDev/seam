-- From your own code into seam, as data: the word under the cursor in a file
-- to the contract or function it names, on a model written by hand.
--   nvim -l tests/here.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local here = require 'seam.here'
local index = require 'seam.index'

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

-- src/run.ts declares createRun (used by app and api) and its local helper
-- prepare; startRun is declared twice (run.ts and old.ts), the app uses the
-- one in run.ts; Step is a type; a lone used nowhere, so no contract
local function export(id, kind, users)
  local path, line, name = id:match '^(.*):(%d+):(.*)$'
  local uses = {}
  for _, u in ipairs(users or {}) do
    uses[#uses + 1] = { path = u, line = 1, col = 1, role = 'call' }
  end
  return { id = id, name = name, kind = kind or 'function', path = path, line = tonumber(line), end_line = tonumber(line) + 9, uses = uses }
end
local function node(id, kind, calls_)
  local path, line, name = id:match '^(.*):(%d+):(.*)$'
  return { id = id, name = name, kind = kind or 'function', path = path, line = tonumber(line), end_line = tonumber(line) + 9, calls = calls_ or {} }
end
local CREATE, START, OLD, STEP, LONE = 'src/run.ts:10:createRun', 'src/run.ts:30:startRun', 'src/old.ts:1:startRun', 'src/types.ts:1:Step', 'src/run.ts:50:lone'
local PREP, PREP2, MAIN, HELP, HELP2 = 'src/run.ts:1:prepare', 'src/app.ts:20:prepare', 'src/app.ts:1:main', 'src/a.ts:1:help', 'src/b.ts:1:help'
local m = {
  exports = {
    export(CREATE, nil, { 'src/app.ts', 'src/api.ts' }),
    export(START, nil, { 'src/app.ts' }),
    export(OLD, nil, { 'src/legacy.ts' }),
    export(STEP, 'type', { 'src/app.ts', 'src/run.ts' }),
    export(LONE),
  },
  graph = index.graph {
    node(CREATE, nil, { { PREP, 11, 3 }, { START, 12, 3 } }),
    node(START),
    node(OLD),
    node(LONE),
    node(PREP),
    node(PREP2),
    node(MAIN, nil, { { CREATE, 2, 3 }, { HELP, 3, 3 }, { HELP2, 4, 3 } }),
    node(HELP),
    node(HELP2),
    node('src/app.ts:0:', 'module', { { MAIN, 40, 1 } }),
  },
}

local function got(r)
  local x = r.contract or r.node
  local out = { x and x.id or nil }
  if r.candidates then
    out.candidates = vim.tbl_map(function(c)
      return c.id
    end, r.candidates)
  end
  out.nodes, out.enclosing = r.nodes, r.enclosing
  return out
end
local function resolve(word, path, line, how)
  return got(here.resolve(m, word, path, line, how))
end

-- overview: a contract, in this file first, then one this file uses, then the only one
eq(resolve('createRun', 'src/run.ts', 10), { CREATE }, 'declared here')
eq(resolve('createRun', 'src/app.ts', 2), { CREATE }, 'used here')
eq(resolve('createRun', 'src/elsewhere.ts', 1), { CREATE }, 'the only one of that name')
eq(resolve('startRun', 'src/old.ts', 3), { OLD }, 'two of a name: the one declared here')
eq(resolve('startRun', 'src/app.ts', 5), { START }, 'two of a name: the one this file uses')
eq(resolve('startRun', 'src/elsewhere.ts', 1), { candidates = { OLD, START } }, 'two of a name, neither here: both')
eq(resolve('Step', 'src/run.ts', 1), { STEP }, 'a type, used here')
-- not a contract: the function, the one declared here before the others
eq(resolve('lone', 'src/run.ts', 50), { LONE }, 'exported, used nowhere: a function, not a contract')
eq(resolve('prepare', 'src/app.ts', 22), { PREP2 }, 'a local function declared here')
eq(resolve('prepare', 'src/run.ts', 1), { PREP }, 'the other one, declared there')
eq(resolve('prepare', 'src/api.ts', 1), { candidates = { PREP2, PREP }, nodes = true }, 'functions of one name, neither here')
eq(resolve('nothing', 'src/run.ts', 12), {}, 'a word naming nothing, overview: nothing')
eq(resolve('', 'src/run.ts', 12), {}, 'no word')
eq(resolve('(', 'src/run.ts', 12), {}, 'not a name')

-- page: the same
eq(resolve('createRun', 'src/app.ts', 2, 'page'), { CREATE }, 'page: the contract')

-- calls: a function first, by the same order, then a contract, then the one the cursor is in
eq(resolve('createRun', 'src/app.ts', 2, 'calls'), { CREATE }, 'calls: a contract that is a function')
eq(resolve('help', 'src/app.ts', 3, 'calls'), { candidates = { HELP, HELP2 }, nodes = true }, 'calls: two this file calls by one name')
eq(resolve('help', 'src/a.ts', 3, 'called_by'), { HELP }, 'called by: declared here')
eq(resolve('prepare', 'src/run.ts', 11, 'calls'), { PREP }, 'calls: a local function')
eq(resolve('Step', 'src/run.ts', 1, 'calls'), { STEP }, 'calls: a type, the contract (no function)')
eq(resolve('const', 'src/run.ts', 14, 'calls'), { CREATE, enclosing = true }, 'calls: a word naming nothing, the function the cursor is in')
eq(resolve('const', 'src/run.ts', 45, 'calls'), {}, 'calls: between functions, nothing')
eq(resolve('nothing', 'src/run.ts', 14), {}, 'overview: no enclosing fallback')

-- the lens leaves exports with all_uses: they still count as contracts
local e = m.exports[2]
e.all_uses, e.uses = e.uses, {}
eq(resolve('startRun', 'src/app.ts', 5), { START }, 'what the lens hid still resolves')

-- a file outside the repo: by name alone
eq(resolve('createRun', nil, 1), { CREATE }, 'no path: the only one')

io.stdout:write(('here: %d checks, %d failures\n'):format(checks, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
