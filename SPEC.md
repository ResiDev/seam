# seam.nvim, the spec

What v1 is, where each fact comes from, how it is built and in what order.
The screens are locked in `design/explorer.md` and `design/contract.md`; this
says what the code must do to draw them. The keys are in `KEYS.md`.

## What it is

A full-screen view of the contracts in a TypeScript codebase: what each one
is, where it lives, what it is built from and who uses it. You open it to
understand a codebase, not to review a change.

Every fact comes from the language server, treesitter or git. No LLM.

## Words

- **Contract.** An exported declaration referenced from at least one other
  file. A file that only re-exports it (a barrel) does not count as a user.
- **Use.** One reference to a contract from another file, minus import and
  export specifiers. Each use has a role: `type` (in a type position),
  `read`, `set` (an assignment or an object literal key), `call` or `pass`
  (anything else, such as an argument).
- **User.** A file with at least one use.
- **Dependency** (built from). A name inside a contract's declaration that
  resolves to another top-level declaration in the codebase, in any file, its
  own included. Each place it is named is one. Locals, builtins and
  `node_modules` are left out.
- **Member.** A field or method of an interface, type literal, class or enum.
  A function has none.
- **Seam.** One dependency or one user, seen beside the contract.
- **Package.** A workspace package (`pnpm-workspace.yaml`, or `workspaces` in
  `package.json`). Without a workspace, each top-level directory.

## The model

```lua
---@class seam.Contract
---@field id string            -- 'path:line:name', stable across sessions while the declaration stays put
---@field name string
---@field kind 'interface'|'type'|'class'|'function'|'component'|'const'|'enum'
---@field path string          -- relative to the repo root
---@field package string|nil
---@field range seam.Range     -- the whole declaration, doc comment included
---@field name_at seam.Pos
---@field members seam.Member[]
---@field used_by { files: integer, uses: integer }|nil   -- nil until the source has asked
---@field built_from integer   -- names, from treesitter alone

---@class seam.Member
---@field name string
---@field kind 'field'|'method'
---@field optional boolean
---@field range seam.Range

---@class seam.Use
---@field path string
---@field range seam.Range
---@field role 'type'|'read'|'set'|'call'|'pass'
---@field member string|nil     -- for a use of a member

---@class seam.Dep
---@field name string
---@field at seam.Range         -- where the contract names it
---@field target seam.Contract|{ path: string, range: seam.Range }
```

Counts on the explorer need `used_by` for every contract. Everything else is
asked for one contract at a time, when its page opens or the cursor reaches
it.

## Where each fact comes from

| Fact | From | Cost |
|---|---|---|
| Files | `git ls-files '*.ts' '*.tsx' '*.mts' '*.cts'` without `*.d.ts` | one call |
| Packages and their hues | workspace file; hues stored per repo | one read |
| Exports, kind, range, members | treesitter: export statements and declarations | fast, sync, per file |
| Barrels | treesitter: `export … from` | per file |
| Built-from names (the count) | treesitter: identifiers in the declaration that are imported or declared at the top of the same file | per file |
| Built-from targets | `textDocument/definition` on each name | per name, on demand |
| Uses | `textDocument/references`, minus the declaration file's own and import specifiers | **one request per export: the cost** |
| Role of a use | treesitter: the node the reference sits in | per use |
| Fields a use reads | `textDocument/references` on each member, matched to the use's enclosing function | per member, on demand |
| The function a use sits in | treesitter: nearest function, method or arrow assigned to a name; else the statement | per use |
| Signature | `textDocument/hover` | per contract, on demand |
| Code colours | treesitter captures of the source file | per pane |
| The call graph | treesitter: each function, component and class at the top of a file, and each file's top-level code, with the callables it names outside type positions, resolved as built-from names are | per file, in the same pass |
| Change line | `git log -L` on the declaration range | per contract, on demand |

So treesitter answers everything inside one file and the language server
answers everything across files. The only bulk work is references for every
export.

The call graph is names, not types: a local that shadows a top-level or
imported name still counts as a call to it, and a method, a prop or a
callback ends the tree without saying so.

## The swappable part

One interface, the **source**: whatever answers questions across files.
Treesitter is not behind it. It reads one file at a time, it is always there,
and every source needs the same answers from it.

```lua
---@class seam.Source
---@field name string
--- Uses of each contract, for the counts. Calls back as they arrive.
---@field uses fun(self, list: seam.Contract[], each: fun(c: seam.Contract, uses: seam.Use[]), done: fun())
--- Where a name in a file resolves to.
---@field definition fun(self, path: string, at: seam.Pos, done: fun(target: { path: string, range: seam.Range }|nil))
--- Uses of one member.
---@field member_uses fun(self, c: seam.Contract, m: seam.Member, done: fun(uses: seam.Use[]))
---@field signature fun(self, c: seam.Contract, done: fun(text: string|nil))
```

There are three implementations, so the interface earns its place:

- **`lsp`** (v1). Uses whichever TypeScript server is attached: `tsgo`,
  `vtsls` or `ts_ls`. Nothing to install, and it resolves imports the way
  the editor does. `uses` sends a references request for each export, a few
  at a time, in the background.
- **`fake`** (v1, tests). Returns recorded answers, so every screen spec runs
  without a server.
- **`index`** (v1.1, only if the spike says the LSP is too slow). A Node
  script using the TypeScript compiler API. In one pass over the program it
  resolves every identifier to its declaration and writes every use as JSON.
  It costs one program build instead of one request per export. It needs
  `typescript` 5.x in the project, because the native `tsgo` has no stable
  JS API yet (inferred).

`require('seam').setup({ source = 'lsp' })` picks one.

## Index and cache

The index is the list of contracts plus their uses. It lives in memory and in
`stdpath('cache')/seam/<repo>.json`:

- per file, a hash of its text, its exports and its imports;
- per export, its uses.

The explorer opens on the cache at once, then a background pass brings it up
to date and the counts change in place. A row whose count is still unknown
shows `·`.

**Staleness.** Saving file F asks again for:

- the exports in F;
- the exports F imports, before and after the change. F may have started or
  stopped using them.

Nothing else can have changed. A change made outside Neovim, such as a branch
switch, shows up as hashes that no longer match on the next open.

**First run.** One references request for every export in the repo. With
2,000 exports at about 50 ms each, that would be nearly 2 minutes in the
background (guess). The spike measures it.

## Screens

The screens are locked in the design docs. The code must keep these rules:

- **Layout.** The explorer is three columns: contracts 46 wide, built from
  60, used by the rest. The page is three columns: the list 40, the contract
  46, the seam the rest. Calls is two: the tree 86, its code the rest. All
  need 150 columns. Narrower than that is not designed. v1 says so and opens
  anyway.
- **Trees.** Every tree is built by one module, `tree.lua`, from paths. Two
  spaces a level. Directories end in `/`. A chain of lone directories shares
  one row. Files show by their name. Directories come before files, each
  sorted by name. Every package is always shown, and an untouched one is one
  dim `▸ name/` row.
- **Colour.**
  - A package's hue goes in three places only: its name, a bar `▎` down its
    rows, and the bars on used-by counts.
  - Hues are assigned once and stored, so they don't move between sessions.
    Past eight packages, the rest are grey.
  - The contract's own package and its test files are dimmed.
  - A name is coloured as its declaration is, from that line's treesitter
    captures, painted once in view. Its kind also shows in its shape:
    `fn()`, `<Component>`, `Type`.
- **The lens.** A column it hides something from says how many on a line
  it already has, `+3 hidden  L lens`, the count in `SeamLensHidden`, a
  muted red. One count however many rules. No row for what it hides.
- **Code panes.**
  - A code pane is a scratch buffer of copied lines. It keeps the source
    file's highlighting by copying that file's treesitter captures as marks,
    because a fragment of a function does not parse on its own.
  - Lines outside the seam are dimmed by a mark at a priority above
    treesitter's.
  - A line that names the contract has a background.
  - A member it reads is underlined, and so is the same member in the
    contract pane.
  - A gap is a `⋯` row.
- **One seam at a time.** Built from and Used by show only the seam under
  the cursor. Built from read as code shows the declaration of the name the
  cursor is on.
- **Snippets.** A use is shown in the function it sits in, 20 rows at most,
  keeping the lines with uses in view, as thread's caller code does.

## Code layout

```
lua/seam/
  init.lua          :Seam, start and open, what tests and view steps call
  state.lua         the one table every screen reads: repo, models, tab, windows, what is shown
  index.lua         the model from a source's JSON, the lens applied, where indexes live, indexing
  theme.lua         highlight groups, hues
  lens.lua          the lens: patterns, what it hides, .seams/lens.json
  tree.lua          paths to rows: compaction, folding, the package bar
  code.lua          a code pane: copied lines, copied captures painted in view, enclosing function
  draw/init.lua     rows, putting them in a buffer, the pieces both screens share
  draw/explorer.lua the contracts list, and the trees or diagram beside it
  draw/page.lua     the Built from and Used by tabs, the contract, the seam
  calls.lua         the call tree as data: rows down or up or from the top, the budget, what each key does
  draw/calls.lua    the Calls screen: its head, the pinned anchor, the tree, the call and the body
  diagram.lua       the v and V views, drawn by thread's flow renderer
  lens_panel.lua    the lens float and its keys
  screen.lua        the tab page, its windows, keys, status line, cursor to redraw
scripts/
  extract.lua       the treesitter index, in a headless nvim of its own
tests/
  calls.lua         the call tree's specs, on a graph written by hand
  check.lua         every screen through its keys on a real repo
```

## Tests

- **The fixture.** `tests/fixture/pantry` is the Pantry repo the mocks were
  drawn from, as real TypeScript. Its packages point at source through
  `tsconfig` paths, so a server resolves it without an install.
- **Syntax specs.** Each treesitter question, asked of the fixture: exports,
  members, imports, built-from names, roles, enclosing functions.
- **Index specs.** A fake source, then staleness: an edit re-asks for
  exactly the exports it should.
- **Draw specs and surfaces.** Each screen drawn as text from the fake
  source, snapshotted the way thread does it.
- **One live spec.** The LSP source against the fixture, skipped when no
  TypeScript server is installed.
- **Looking at it.** thread's `make view` harness, copied over, for anything
  you can see.

## Order of work

Days are a guess, for one person working steadily.

0. **Spike** (½ to 1 day). On a real repo of yours:
   - time references for every export with your server;
   - check whether a use across packages resolves to source or to
     `dist/*.d.ts`;
   - check that the server survives a few hundred requests.

   This settles whether v1 is `lsp` alone or needs `index`.
1. **Repo and syntax** (2 days). Files, packages, hues, the treesitter
   queries and their specs.
2. **Source and index** (3 days). The interface, the fake source, the LSP
   source, the cache, staleness.
3. **Explorer** (3 days). `tree.lua`, the three columns, `<Tab>` orders,
   search, the folder filter.
4. **Contract page** (5 days). `code.lua` first, then the Contract tab, then
   Built from and Used by.
5. **Finish** (2 days). Keys, `:Seam debug`, docs, the live spec.

That is about 15 to 16 days, plus 3 if the `index` source is needed.

**How hard.** Medium. The screens are the kind thread already draws (trees,
columns, code panes), and thread's draw code shows the way for each. The hard
parts are three:

- uses that cross packages actually being found;
- the first index being fast enough;
- code panes that highlight fragments correctly.

## Risks

- **The server falls over.** `tsgo` 7.0.0-dev.20260510.1 panicked with a nil
  pointer and answered nothing. That was on `~/Work/libs/raf-run-redesign`,
  with 94 files open and no `node_modules` installed (measured, 2026-10-25).
  The LSP source must restart a dead server, keep what it has, and mark the
  rest unknown, not zero.
- **Uses across packages go missing.** In that repo, each package's `types`
  points at `./dist/index.d.ts` (measured from its `package.json`). Before a
  build, an app's import of a package resolves nowhere or to the `.d.ts`, not
  the source (inferred). Then the package's contracts look unused from
  outside. The fixes are in the repo's config: `tsconfig` paths, a `source`
  custom condition, or project references. The `index` source could map a
  `.d.ts` back through declaration maps. The spike checks this first.
- **Effect.** Your config sets up Effect's language service. Effect's
  services (`Context.Tag` classes) and schemas are contracts whose shape
  lives in types, not syntax. Treesitter will call them `class` or `const`
  with no members. They are later work.
- **Member uses are many requests.** A class with 30 members is 30
  references requests when its page opens. They are asked for on demand,
  cached, and drawn as they arrive.

## Not in v1

- Narrow screens (under 150 columns).
- Members of a component's props, and Effect services and schemas.
- Grouping Used by by member.
- JavaScript without types, and languages other than TypeScript.
- Anything written by an LLM.
