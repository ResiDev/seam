-- What changed, on two versions of a file written here: each declaration
-- new, gone or changed by its text, a function's signature against its
-- body, the names used at `from`; the hunks between two versions and the
-- bytes that changed on a line, laid out with folds, by Vim's own diff.
--   nvim -l tests/changes.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local changes = require 'seam.changes'
local code = require 'seam.code'
local diff = require 'seam.diff'
diff.codediff = false

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

local BEFORE = [[
import type { Step } from "./types";

/** Why a stored walkthrough was not picked up again. */
export type DropReason = "expired" | "taskNotTodo";

export type Kept = { a: string };

export function storageFailed(record: "tasks" | "walkthrough", error: unknown): Problem {
  return { type: "storageFailed", record, error };
}

export function recordDropped(walkthrough: string, reason: DropReason): Problem {
  return { type: "recordDropped", walkthrough, reason };
}

export const saveTo = (adapter: Adapter, record: unknown) => {
  adapter.save(record);
};

export const DEFAULTS = { maxAge: 7 };

function same(x: number): number {
  return x + 1;
}
]]

local AFTER = [[
import type { Step } from "./types";

/** Why a stored entry was dropped: its walkthrough starts again. */
export type DropReason = "expired" | "unreadable";

export type Kept = { a: string };

export function storageFailed(error: unknown): Problem {
  return { type: "storageFailed", error };
}

export function recordDropped(walkthrough: string, reason: DropReason): Problem {
  return { type: "recordDropped", walkthrough, reason, at: Date.now() };
}

export function entryDropped(entry: string): Problem {
  return { type: "entryDropped", entry };
}

export const DEFAULTS = { maxAge: 7 };

function same(x: number): number {
  return x + 1;
}
]]

local function lines(s)
  local out = vim.split(s, '\n', { plain = true })
  out[#out] = nil
  return out
end

code.virtual('a:problems.ts', 'problems.ts', lines(BEFORE))
code.virtual('b:problems.ts', 'problems.ts', lines(AFTER))

-- the declarations of one version: their names, kinds, lines with the doc comment
local decls = vim.tbl_map(function(d)
  return ('%s %s %d-%d'):format(d.kind, d.name, d.s, d.e)
end, changes.decls_of 'a:problems.ts')
eq(decls, {
  'type DropReason 3-4',
  'type Kept 6-6',
  'fn storageFailed 8-10',
  'fn recordDropped 12-14',
  'fn saveTo 16-18',
  'value DEFAULTS 20-20',
  'fn same 22-24',
}, "a version's declarations")

-- compared by name: the order now, the gone after
local f = changes.compare('a:problems.ts', 'b:problems.ts')
local states = vim.tbl_map(function(d)
  return d.name .. ' ' .. (d.state or '-')
end, f.list)
eq(states, {
  'DropReason changed',
  'Kept -',
  'storageFailed signature',
  'recordDropped body',
  'entryDropped new',
  'DEFAULTS -',
  'same -',
  'saveTo gone',
}, 'each declaration new, gone, its signature or body changed, or the same')
eq(f.before[5].name, 'saveTo', 'the declarations at from kept in their order')

-- a file only at one end: everything new, or everything gone
eq(
  vim.tbl_map(function(d)
    return d.state
  end, changes.compare(nil, 'b:problems.ts').list)[1],
  'new',
  'a new file, its declarations new'
)
eq(
  vim.tbl_map(function(d)
    return d.state
  end, changes.compare('a:problems.ts', nil).list)[3],
  'gone',
  'a gone file, its declarations gone'
)

-- the names used at from: a file that imports it, its own file without
-- its declaration, a file that does not import it
local USER = [[
import { storageFailed } from "./problems";

export function report(error: unknown) {
  reportProblem(storageFailed("tasks", error));
  if (error) reportProblem(storageFailed("walkthrough", error));
}
]]
local OTHER = [[
export function storageFailed() {}
const x = storageFailed();
]]
local C = {
  root = '/nowhere',
  range = { from = 'HEAD' },
  files = { ['user.ts'] = 'changed', ['problems.ts'] = 'changed', ['other.ts'] = 'gone' },
  old = { ['user.ts'] = lines(USER), ['problems.ts'] = lines(BEFORE), ['other.ts'] = lines(OTHER) },
  new = {},
  decls = {},
}
eq(changes.named_at_from(C, 'user.ts', 'storageFailed', 'problems.ts'), { { line = 4, col = 17 }, { line = 5, col = 28 } }, 'the places that named it at from')
eq(changes.named_at_from(C, 'problems.ts', 'storageFailed', 'problems.ts'), {}, 'its own declaration is not a use')
eq(changes.named_at_from(C, 'other.ts', 'storageFailed', 'problems.ts'), {}, 'a file that does not import it')
eq(changes.key(C, 'user.ts', 'from'), 'git:HEAD:user.ts', 'a version at from read by its own key')
eq(changes.key(C, 'user.ts', 'to'), 'user.ts', 'the working tree is the file')
eq(changes.key(C, 'other.ts', 'to'), nil, 'a file gone has nothing at to')

-- the bytes that changed between two lines, word by word
local sa, sb = diff.words('const x = foo(a, b);', 'const x = bar(b);')
eq({ sa, sb }, { { { 10, 13 }, { 14, 16 } }, { { 10, 13 } } }, 'the words that changed on a line')

-- the hunks: a line changed, lines added, a line removed
local A = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l' }
local B = { 'a', 'B', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm' }
local hs = diff.hunks(A, B)
eq(
  vim.tbl_map(function(h)
    return { h.a, h.na, h.b, h.nb }
  end, hs),
  { { 2, 1, 2, 1 }, { 13, 0, 13, 1 } },
  'the hunks between two versions'
)
eq(hs[1].add[2], { { 0, 1 } }, 'a changed line, its word lit')
local function shape(items)
  return vim.tbl_map(function(x)
    if x.kind == 'fold' then
      return 'fold ' .. x.n
    end
    return x.kind .. ' ' .. (x.kind == 'del' and x.a or x.b) .. (x.start and ' *' or '')
  end, items)
end
eq(shape(diff.layout(hs, #B, { fold = true })), {
  'same 1',
  'del 2 *',
  'add 2',
  'same 3',
  'same 4',
  'same 5',
  'fold 4',
  'same 10',
  'same 11',
  'same 12',
  'add 13 *',
}, 'changes only: three lines around each change, the rest folded')
eq(#diff.layout(hs, #B), 14, 'the whole file: every line, the removed one too')
local gone = diff.layout(diff.hunks({ 'x', 'y', 'z' }, { 'x', 'z' }), 2)
eq(shape(gone), { 'same 1', 'del 2 *', 'same 2' }, 'a removed line where it was')
eq(gone[3].a, 3, 'an unchanged line after a removed one, its line at from')
eq(shape(diff.layout(diff.hunks({ 'x', 'y' }, {}), 0)), { 'del 1 *', 'del 2' }, 'all of it gone')
eq(shape(diff.layout(diff.hunks({}, { 'x' }), 1)), { 'add 1 *' }, 'all of it new')

io.stdout:write(('changes: %d checks, %d failures\n'):format(checks, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
