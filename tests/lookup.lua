-- Package types on demand: the package a declaration's file is in, the
-- declaration a definition lands in, on source written here; then, when
-- the trial copy of excalidraw with its node_modules and a TypeScript
-- server are here, a few names looked up for real.
--   nvim -l tests/lookup.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local code = require 'seam.code'
local lookup = require 'seam.lookup'
local st = require 'seam.state'

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

-- the package from a path
eq(lookup.package '/r/node_modules/roughjs/bin/canvas.d.ts', 'roughjs', 'a package')
eq(lookup.package '/r/node_modules/@types/react/index.d.ts', '@types/react', 'a scoped package, its scope kept')
eq(lookup.package '/r/node_modules/a/node_modules/@firebase/storage/dist/storage.d.ts', '@firebase/storage', 'the package after the last node_modules')
eq(lookup.package '/r/node_modules/typescript/lib/lib.dom.d.ts', 'TypeScript’s lib.dom.d.ts', 'a TypeScript lib file')
eq(lookup.package '/m/tsgo/node_modules/@typescript/native-preview-linux-x64/lib/lib.es5.d.ts', 'TypeScript’s lib.es5.d.ts', 'tsgo’s lib file')
eq(lookup.package '/r/node_modules/foo/lib/lib.d.ts', 'foo', 'a lib.d.ts of another package is its package')
eq(lookup.package '/r/src/types.ts', nil, 'a file in no package')

-- the declaration a position is in
local SRC = [[
import type { Point } from "./geometry";
export declare class RoughCanvas {
    private gen;
    draw(drawable: Drawable): void;
}
declare namespace React {
    type ReactNode =
        | string
        | number;
    interface Props {
        children?: ReactNode;
    }
}
export interface Options {
  roughness?: number;
}
declare var HTMLCanvasElement: {
  new (): HTMLCanvasElement;
};
export declare function line(x: number): Point;
]]
local tree = vim.treesitter.get_string_parser(SRC, 'typescript'):parse()[1]:root()
local function decl(row, col)
  return { lookup.decl(tree, row, col) }
end
eq(decl(1, 21), { 1, 4 }, 'a class, from its name, with its export and declare')
eq(decl(3, 6), { 1, 4 }, 'from inside it, the class')
eq(decl(6, 9), { 6, 8 }, 'a type alias in a namespace, not the namespace')
eq(decl(9, 14), { 9, 11 }, 'an interface in a namespace')
eq(decl(13, 17), { 13, 15 }, 'an exported interface')
eq(decl(16, 12), {}, 'a variable is no declaration of a type')
eq(decl(19, 24), { 19, 19 }, 'a function signature')
eq(decl(0, 15), {}, 'an import is none')

-- for real: the trial copy of excalidraw, its node_modules, a server
local REPO = '/tmp/seam-npm-trial/excalidraw'
local cmd = vim.uv.fs_stat(REPO .. '/node_modules/roughjs') and require('seam.tsserver').command(REPO)
if not cmd then
  io.stdout:write 'no trial repo with node_modules, or no TypeScript server: nothing looked up for real\n'
else
  st.root, code.root = REPO, REPO
  local CASES = {
    { 'RoughCanvas', 'packages/excalidraw/scene/types.ts', nil, 'roughjs', 'export declare class RoughCanvas' },
    { 'ReactNode', 'packages/excalidraw/components/DialogActionButton.tsx', nil, '@types/react', 'type ReactNode =' },
    { 'HTMLCanvasElement', 'packages/excalidraw/scene/types.ts', nil, 'TypeScript’s lib.dom.d.ts', 'interface HTMLCanvasElement' },
  }
  for _, c in ipairs(CASES) do
    local landed = false
    local t = vim.uv.hrtime()
    eq(
      lookup.get(c[1], c[2], c[3], function()
        landed = true
      end),
      nil,
      c[1] .. ': nothing the first time, the server asked'
    )
    vim.wait(30000, function()
      return landed
    end, 5)
    local got = lookup.get(c[1], c[2], c[3], function() end)
    local first = got and vim.trim(code.file(got.key).lines[got.s] or '') or ''
    eq({ landed, got and got.pkg, first:sub(1, #c[5]) }, { true, c[4], c[5] }, c[1] .. ' looked up')
    io.stdout:write(('%s in %.0f ms\n'):format(c[1], (vim.uv.hrtime() - t) / 1e6))
  end
  -- at the position given: the import specifier of DialogActionButton.tsx
  local landed = false
  lookup.get('ReactNode', 'packages/excalidraw/components/DialogActionButton.tsx', { line = 7, col = 14 }, function()
    landed = true
  end)
  eq(landed, false, 'cached per name and file: no second ask')
  lookup.stop()
  vim.wait(3000, function()
    return #vim.lsp.get_clients { name = 'seam-lookup' } == 0
  end, 10)
  eq(vim.lsp.get_clients { name = 'seam-lookup' }, {}, 'stopped, no client left')
end

io.stdout:write(('lookup: %d checks, %d failures\n'):format(checks, #failures))
vim.cmd(#failures == 0 and 'qa!' or 'cquit 1')
