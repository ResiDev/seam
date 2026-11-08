# seam.nvim, the spec

What seam is, how each screen behaves, where each fact comes from and how it
is built. The screens are the mocks named here, in `design/mocks/`; the keys
are in `KEYS.md`. Built a slice at a time (Building).

The idea behind all of it: seam stays beside the code. It never replaces
reading the code. It makes three things one key away while you read: what a
name is (its type), where it comes from (its file, its import), and where it
goes (its users, its later uses).

Two screens do it:
- **The tree.** Folders, files, functions, and the functions each one calls,
  opened with `l`. The views on the right.
- **The code.** `J` on a function or file puts its code on the left. The
  same views on the right.

The explorer and Calls become the one tree. The contract page becomes the
code.

## Building

Decided 2026-11-01, before any code. The screens below are settled; what
looks wrong once built is corrected then, not with more mocks.

- **It replaces today's screens.** The explorer, the contract page, Calls
  and the Types screens go. The lens stays, as it is, and gains the range
  of changes. Each old screen is deleted in the slice that replaces it, so
  seam keeps working between slices.
- **On branch `redesign`.** It holds `types`' code unchanged (the types
  asked of the TypeScript server, `types.json`, `seam.types`), which the
  Types view and opening a type need; `redesign` only added `design/`. So
  there is nothing to merge first: build here, and `master` gets it all at
  the end.
- **This file was `design/next.md`** until the first slice landed, and the
  chosen mocks are the locked screens. KEYS.md is rewritten a screen at a
  time, in the slice that lands it.
- **Every fact from the index, the TypeScript server or git,** as now.
  Nothing on screen asks the server per field.

The slices, each usable on its own, each with its `make view` shots set
against its mocks, its tests, and KEYS.md in step:

1. **The tree and the pane** (landed 2026-11-01). One tree: folders, files, functions, `l` the
   calls in run order, `s` the order, the underline for where a call lives.
   The pane with its tabs and the Code view. `<Tab>`, `<C-Tab>`, scrolling
   the pane from the tree, the hint line and `?`. The lens kept. Replaces
   the explorer.
2. **The Types view,** and `+` `-` opening a type in place wherever a type
   is drawn so far (landed 2026-11-01). Replaces the Types screens.
3. **Used by and Built from,** by file, with their other displays
   (landed 2026-11-01, gone the same day into the Map's flow and its foot).
   Replaced the contract page.
4. **The code screen** (landed 2026-11-01). `J` `K` and the trail, every name answering in the
   pane, a value's type after its name, `n` `N` the imports, `<C-Tab>`
   code or types, later uses lit. Replaces Calls.
5. **Changed** (landed 2026-11-01). The range in the lens, the git signs, `gc`, `]c` `[c`, the
   Changed view drawn with codediff, a changed type opening with its own
   lines.
6. **The Map** (landed 2026-11-01). Its displays on each kind of row, `T`, `>` `<`, and the
   arrows as chosen.
7. **Two tabs and the diff** (landed 2026-11-01). The pane's tabs only Code and Types, `<Tab>`
   between them; the Map aside on `gm`.
   The Changed tab goes: `D` turns the diff on and off, on the code and the
   types, on both sides of the code screen.

## The primitives

What every screen is built from, and where each fact comes from.

| Thing | Source |
|---|---|
| folder, package | the file system |
| file, what it exports and imports | treesitter |
| function, closures included | treesitter |
| type, its fields | the declaration (treesitter); expanded a level at a time by the server's hover |
| value: a local, a parameter, a field read | treesitter scope; the server's references |

| Link | Source |
|---|---|
| file imports from file | treesitter, resolved by the server's definition |
| function calls function, at a line | treesitter; the server's call hierarchy |
| function takes and gives types | the written signature (types.json) |
| value made, passed, read, set | treesitter scope; the server's references |
| holds: a file its declarations, a function its values, a type its fields | treesitter |
| when: under an `if`, a `case`, a callback for later, a `return` | treesitter |
| changed since a commit | git |

A type's name always comes from what is written: the annotation, else the
declared return of the call that made the value. The server's hover expands
raf's `Readonly<{…}>` aliases, so it gives the shape, never the name.

## The views

Every row in the tree, and every name in the code, has the same views on the
right. Two are tabs, **Code** and **Types**, what you read most; `<Tab>`
flips between them. The **Map** is aside, on `gm`, the same on the tree,
the code screen and in the pane; the same key again, or `<Tab>`, goes back
to the tab you were on. The one chosen stays as the cursor moves. What changed is not a
view: `D` turns the diff on in Code and Types (What changed, below).

| View | A folder | A file | A function | A type |
|---|---|---|---|---|
| **Code** | | the file | its body, imports underlined | its declaration |
| **Types** | what comes in and goes out: the types its exports take and give | the same for the file, then the types it declares | what it takes and gives, each type expandable | where it comes from and what it becomes, one step each way; its fields with who sets and reads each |
| **Map** | three displays on `<S-Tab>`: folder, type, library (section 6) | the same three | the same three | folder and type |

- **Built from, Used by and size are gone** (2026-11-01). The Map's flow
  shows what Built from and Used by did for a function, each call and
  caller with what it takes and gives, the line of each call in the gutter,
  and its foot the line that calls it as written, so the two lists went.
  The import lines of a file and the types a type is made of went with
  them: the Map shows which files call in, and the Types view a type's
  fields. Used by on a changed function (who used it at the range's start)
  went too. Size added little the flow does not show.

- **Beside the tree, every view a tab; on the code screen, two tabs and the
  others aside** (decided 2026-11-01). Beside the tree the head has all the
  tabs the row has, Code, Types and Map, the one shown
  lit (`design/mocks/keys-tree-a.png`, its Changed tab now the diff on `D`);
  `<Tab>` `<S-Tab>` step through them, and `gm` goes straight to the Map
  and back. On the code screen, where the code is read, the head has the two
  tabs, Code and Types, the one shown lit (`design/mocks/tabs-aside.png`). An aside view shown
  is named after them, lit, a gap between, and the two tabs both dim; its
  display after it. The status line's pane group has `gm` there
  only where the row has the Map; beside the tree it is left to `?`. A row with neither Code nor Types shows the
  first aside view it has, named in the head; every row has one or the
  other (a folder has Types, a row gone has Code), so this is a fallback.
- **Where it's called is the Map's foot.** The cursor on a caller or a
  call in the Map shows the line that calls it, so "used by" and "called
  at" are one place.
- **Types open in place.** `+` on a type's name opens its declaration, as
  written, under the line it is named on, a bar down its left and its file
  and line at the top. `+` on a name inside that opens the next one, nested
  under it: one level a press. `-` closes the one the cursor is in. `l`
  stays the calls; `+` and `-` are only types. It works on a type's name
  wherever one is drawn: the pane's head line, the Types view, the Code view's types
  display.
  With the diff on, an opened type carries its own `+`/`-` lines, so a
  signature that reads the same but takes a changed type shows what changed
  in it. Mocks: `design/mocks/open-type-a.png` (StoredRecord opened in
  RunOptions), `open-type-b.png` (WalkthroughProgress opened inside it),
  `open-type-changed.png` (keyAction: InputContext lost `collapsed`, gained
  `dismiss`).
- **A folder** rolls its files up.

### Types: the higher view

Decided 2026-10-31, from the mocks `design/mocks/types-view-*.png`:

- **A blank line between functions, always.** An opened function keeps
  everything it opens together under its line, its parts one a line and
  indented, closed by its `}` or `)`, then the blank line before the next
  function (`design/mocks/types-view-opened.png`).
- **A long signature is cut with `…`** at the column, so the arrows and the
  names stay in one column.
- **A type parameter shows as what it extends,** `(ProblemHandlers<Step>)
  → problemReporter → ReportProblem<Step>`.
- **`+` on a function's line opens it as written:** the parts the `…` cut
  and the type parameters shown as their bound, the signature as the source
  has it. `-` closes it. The same keys as a type, since on a type's name `+`
  opens the type.
- **`Readonly<…>` is left out,** since raf wraps every type in it.
- **A function's takes and gives are written out under its line,** each
  type's declaration with its doc comment, open by default.
- **One view at a time, over the full right side** (layout A,
  `design/mocks/types-view-layout-a.png`). Tabs in the pane's head name them, the
  one shown lit; `<Tab>` and `<S-Tab>` step through them (since 2026-11-01
  two tabs, the rest aside: see The views). Two views side by
  side (B) cut the signatures; a band over today's trees (C) breaks the
  blank line between functions. Built from and Used by become single views
  in the same pane, redesigned to fit it.
- **A view and its display.** Each view can be shown more than one way,
  its display. `<Tab>` changes the view; `<S-Tab>` steps its display
  (since 2026-11-01; it was `<C-Tab>` and `<C-S-Tab>`, and `<S-Tab>` the
  view before). The same keys work in the
  tree and in the pane, so `v` keeps its own meaning in the pane. The
  display chosen stays for that view as the cursor moves, and the pane's
  head names it after the view's tab. Ghostty takes `ctrl+tab` and
  `ctrl+shift+tab` for its own tabs by default, so they need unbinding in
  its config (`keybind = ctrl+tab=unbind`) before Neovim sees them.
- (Gone 2026-11-01, see The views.) **Used by and Built from open by file,** the point of the view, each file
  then each place with its line of code (`design/mocks/used-by-a.png`,
  `design/mocks/built-from-a.png`). Their other displays:
  - Used by, by name: each thing it hands out with its signature, then
    everyone who uses it (`design/mocks/used-by-b.png`).
  - Used by, by user: each function or type that uses it as a signature
    line, then what it uses (`design/mocks/used-by-c.png`).
  - Built from, by name, in the order the code first uses each, its
    signature and that line (`design/mocks/built-from-b.png`).
  - Built from, as signature lines of what it calls, in the order it calls
    them, then the types it names (`design/mocks/built-from-c.png`).
  - Tests sort after the rest in every display.
- **Scroll the pane from the left.** With the cursor in the tree, `<C-d>`
  and `<C-u>` scroll the pane half a screen, `<C-e>` and `<C-y>` a line, as
  they scroll a window in Vim and a preview in Telescope. In the pane they
  scroll the pane as usual. Every screen with a pane does the same.
- **A value's type follows its name, dim, upright** (`design/mocks/code-types-a.png`).
  An arrow function gets its return after its parameters. Nothing is added
  where the type is written.
- **The Code view's types display** is the function's signature line, then
  each value it makes as `name  Type` in the order made, each closure inside
  indented under its own signature line (`design/mocks/code-types-only-a.png`).
  It differs from the Types view, which shows only what the function takes
  and gives, each type written out.
- **The right side only when the code is on the left.** raf's lines are 88
  wide or less nine times in ten and 134 one in a hundred (measured), so
  the code wants about 110 columns with its types after the names. With the
  tree beside it there's no room for a third pane. So in the tree the Code
  view is the code alone, its types after the names, and `J` puts it on the
  left with the views on the right, where the cursor on a name fills them
  (`design/mocks/code-cursor-field.png`).
- **A folder has the views a file has where they make sense:** Types, Built
  from, Used by and the Map. It has no Code, but with the diff on its Code
  is its changed files one after another, about 400 lines at a time, then
  `⋯ N more files` that `+` opens, so moving over a folder stays quick.


The Types view is the high-level picture at every level of the tree, with
no screen of its own. It has one shape everywhere: a line per function,
what it takes, the function, what it gives, the functions lined up in one
column. A parameter that is an object of named parts shows its parts,
`{ name: Type }`. Several plain parameters show as `(Type1, Type2)`. These
are sketches. The order and names are not computed yet.

A folder, `run/`: its exports.

```
{ root?: Document | Element, storage?, … }  → createRun    → Run
(unknown)                                     → parseRecord  → { ok: true, value: Read } | { ok: false, error }
(Model, Given, Msg, Inputs)                   → update       → { model: Model, effects: Effect[] }
```

A file: the same for every function in it, its exports first.

A type, `Model`: every function that gives one, then every function that
takes one, `Model` lit. Under them its declaration, as written.

```
(Given, UserRecord)            → initialModel → Model
(Model, Given, Msg, Inputs)    → update       → { model: Model, effects: Effect[] }
(Model, Given)                 → runStateOf   → RunState

export type Model = Readonly<{
  userRecord: UserRecord;
  startRequests: StartRequests;
  live: Live;
  held: readonly Command[];
  views: Views;
}>;
```

Facts: the written signatures (types.json), the declaration (treesitter).

## The map view

A sixth view, for a function or a type: the map out from it, read left to
right, as many levels as you ask for.

A function: what it calls, then what those call.

```
createRun → problemReporter
          → createQueue
          → initialModel → userRecordAt
          → createLink   → linkOf → …
          → update       → command → workOf
                                   → change → runChange
```

A file: the files it imports from, then the files those import from. A
folder does the same with folders.

```
run/run.ts → run/update.ts  → run/rules.ts → walkthroughs/…
           → run/link.ts    → storage/adapter.ts
           → state.ts
```

The same key turns the direction round: the files that import it, then
the files that import those.

A type: the functions that take it and the types they give, then on from
those types.

```
Msg → update → Command → workOf → Work → run → RunState
                                             → …
    → apply  → Outcome
```

- **Levels.** It opens two levels deep. `>` adds a level and `<` takes one
  away, everywhere at once.
- **On the map,** the cursor on a name shows it in the views, `l` opens
  only that branch a level deeper, `J` goes to its code.
- **A name seen already** higher on the same branch is dim and stops there.

Risk: for types, the map follows signatures alone, and the arena found
long chains built that way read wrong (Model is taken by many, so the
branches multiply). Few levels, and the user widening it a branch at a
time, is the bet. A guess until it's drawn on raf.

## The tree

```
run/
  run.ts
    createRun()          (RunOptions) → Run
      problemReporter()  (ProblemHandlers) → ReportProblem
      createQueue()      (string, ReportProblem) → Queue
      starting()         () → RunState
      initialModel()     (Given, UserRecord) → Model
      runStateOf()       (Model, Given) → RunState
        …
```

- **A file's rows are its functions in the file's order, all alike.** No
  mark for what it keeps to itself. A function kept to its file is only
  called from that file, so its calls are never underlined, and Used by
  lists only that file. (Decided 2026-11-01; `design/mocks/tree-file-kept.png` was
  not needed.)
- **What a file lists: functions, types, values, each on or off.** Decided
  2026-11-07 from `design/mocks/tree15-kinds.png`. A file's rows are what
  it declares at its top, in the file's order: its functions, components
  and classes, `name()`; its types, interfaces and enums, in the code's
  type colour; its values, a `const` or `let` holding no function, plain.
  `f` `t` `v` turn each on or off for the session, functions alone by
  default, the tree as it was. Anything else, the status line's left says
  what is on, `types · values`. A value is a node of the call graph as a
  function is: `l` opens what it calls (`register()` under each of
  excalidraw's actions), its Code, Types and Map are a function's, and
  what it calls is no longer its file's top's. A type does not open; its
  views are a type's from `/`, and `J` opens its declaration on the code
  screen.
- **The bar over the tree says what a file lists** (decided 2026-11-07,
  drawn in seam, `design/mocks/tree17-bar.png`): `f t v  e`, each key lit
  when on in the colour its names have in code, the colour scheme's
  function, type and variable, `e` in the key colour, each dim when off,
  `e` apart as it narrows the others; then `#`, lit when the rows have
  their counts, and the counts' titles to its right
  (`design/mocks/tree18-counts.png`).
- **`e`: a file's exports only,** whichever kinds are on, the rest in the
  file's order (decided 2026-11-07, `design/mocks/tree15b-exports.png`).
  What it keeps to itself goes from the file's rows, not from under a
  function: a function's calls are all of them. The status line's left
  ends `exports only`. A name found with `/` or the Map that a file does
  not list, its kind or its file keeping it, is listed from then on.
- **`l` on a function** opens what it calls, in the order they run. `h`
  closes it. Each call has all the views and opens with `l` again.
- **Where a call lives: underlined.** Decided 2026-10-31 from six marks
  (`design/mocks/where-*.png`). A name from this file is plain. A name from another
  file is underlined. A name from another package is underlined in that
  package's hue, and its tree row carries the hue bar, as the explorer draws
  it today. The same mark in the tree and in the code beside it, on every
  use of the name, not only calls (`[conditions]`, `[detached]`). Names from
  outside the repo (`useRef`, `useMemo`) stay plain: they have no row.
  Mocks: `design/mocks/where-underline-core.png` (update()),
  `where-underline-react.png` (useOwnedRun() calling core's createRun).
- **A call already open above** (recursion) is dim and doesn't open.
- **The tree's own order has nothing beside a name until `#`** puts the
  two counts on every row, used by and uses, neither lit, the tree as it
  was; `#` again takes them off, for the session (decided 2026-11-08,
  drawn in seam, `design/mocks/tree18-counts.png`). The tree first had
  nothing beside a name (2026-10-31, `design/mocks/tree-cols-*.png` were not
  liked), then the counts in its sorted orders alone (2026-11-02).
- **`s` changes the order:** by folder (the tree), most used first, uses
  most first. The two sorted orders are not a tree but one list
  (decided 2026-11-08, drawn in seam, `design/mocks/tree18-list-used.png`,
  `tree19-list-uses.png`): every function, type and value the files
  list, as `f` `t` `v` and `e` have them, through the lens and without
  tests, the most used or the one using most first, the tree's order
  between equals; no folders and no files. A name has its file after it,
  dim, as much of it as the name leaves, and its two counts, the one it
  sorts by lit. The tree is 18 columns wider while the list shows, for
  the names. A function or value opens to what it calls, as in the tree,
  its calls sorted the same way. `s` keeps the cursor on its row; from a
  file it goes to the file's first name in the list, from a folder to
  the list's first; back in the tree a name's file is opened, its
  folders too. A file or folder shown from `/` or a link goes back to the
  tree, the list holding none. `#` does nothing there: the list always
  has its counts. The tree's sorted orders before kept the tree, each
  level sorted (2026-11-02, `design/mocks/tree17-used.png`); finding the
  names most used across the repo meant opening every folder.
- **The counts: used by and uses,** one word each way (renamed from
  `calls` 2026-11-08: `calls 257` read as called 257 times, and the two
  directions did not show; `design/mocks/tree19-list-uses.png`). The
  Map keeps `calls` and `called by`, which list the calls themselves. A
  function's: the functions and values calling it, and those it calls.
  A value's: the functions and values naming it, and what it calls. A
  type's: the functions, values and types naming it, its uses blank
  (decided 2026-11-07); who names a value or type is the index's
  `users`, each use in the repo, its own file too, held by the
  declaration at a file's top it sits in. A file's or a folder's, in the
  tree with `#`: the functions outside it that call into it, or name its
  values and types, and those outside it that it calls, a call inside it
  not counted. Each counted once; tests and a file's top don't count; the
  lens is kept. Counted once a model and lens, from the same calls the
  Map's folder and file read across their edge.
- **An opened function shows its calls, in the order they run,** and nothing
  around them: no closures, `if`s or `case`s (`design/mocks/tree-flow.png` was not
  liked).

Open:
- ~~Should the rows under a function show the `if`, `case`, `later` and
  `return` they sit under?~~ No.
- Should the folders above be the one tree, or a separate boundaries view
  (below)?

## The code

`J` on any row, or on any name in the code, puts that function or file on
the left. `K` comes back to the very row or name you left from, and `3K`
goes up three. The head shows the trail: `Seams › createRun() ›
createQueue()`.

- **Every name answers.** The cursor on any name shows it in the views on
  the right, the way an import does today:
  - a call to a local function, such as `runStateOf`, shows that function;
  - a method, such as `queue.fail`, shows the member's signature;
  - a value such as `queue` shows its type, headed with where it was made:
    `queue  made by createQueue, line 37`;
  - a parameter such as `options` shows `RunOptions`;
  - a field such as `options.storage` shows RunOptions with the `storage`
    line lit.
- **Types up front.** Each value shows its type after its name, as virtual
  text, where none is written: `const queue: Queue = createQueue(…)`.
- **Imports stand out.** Names from another file keep the underline. Names
  from this file stay plain, still answer, and are still stops.
- **Where it goes later.** The cursor on a value, or on the call that made
  it, lights its later uses in this function.
- **Types only.** One key turns the left between the code and its types:
  what it takes, each value it makes with its type in the order made, and
  what it gives, every line `name  Type`. For a file, its declarations'
  signatures.
- **The diff on the left too** (`design/mocks/diff-code.png`). With `D` the
  code on the left is drawn with the range's changes inline, as the pane's
  Code shows them: removed lines where they were, unnumbered on red, added
  numbered on green, the words changed lit stronger; the whole of it, no
  folds. Its types display shows a function's line as it was, on red, over
  the line as it is, on green, when its signature changed, and a type
  opened there carries its own `+`/`-` lines. The cursor on a removed line
  answers with the function or file. `]c` `[c` go from change to change.

Open:
- ~~`n`/`N`: every name, or only the imports as today?~~ Only the imports,
  as today.
- ~~The key for code or types.~~ `<C-Tab>` and `<C-S-Tab>`, as everywhere:
  the code on the left is the Code view brought over, and its displays are
  the code and its types. `<C-Tab>` steps the display of what the cursor is
  in; the tree has none, so there it steps the pane's. `v` is not used.
  Since 2026-11-01 `<S-Tab>` steps the pane's display and `gs` the code
  or its types.
- ~~The keys that open and close a type.~~ `+` and `-`, decided with the
  mocks `design/mocks/open-type-*.png` (see "Types open in place" above).

## What changed (git)

A range of git, from a commit to the working tree, the files as seam reads
them. By default from `HEAD`: what isn't committed yet. The range always
ends at the working tree, so the code drawn is always the range's end and
the diff can be drawn over it. To see another branch, check it out, or open
seam in its worktree, and pick its start with `f`. Then:

- **The range lives in the lens** (`L`), on its first row, above the
  rules: `changes  from HEAD  to the working tree`. `f` works from any row
  of the lens, the cursor where it is: it opens a picker of branches,
  tags and recent commits, a ref typed narrows it, and its first entry is
  the default, `HEAD`, so picking it resets; `x` resets too. The
  head names the range when it isn't the default
  (`design/mocks/changed-range.png`).
- **The tree carries git signs,** in the left column, as gitsigns draws
  them in the code: `+` new, `~` changed, `_` gone (a declaration gone
  keeps its row, struck through, where it was). A folder or file is `~`
  when anything under it changed, `+` when it's new. No words after the
  rows. The signs follow the range: an empty range, no signs, so they need
  no key to hide them (`design/mocks/changed-signs.png`).
- **`gc` keeps only what changed** in the tree: the changed rows and the
  folders and files above them (`design/mocks/changed-signs-only.png`). It works
  on the tree whatever view is shown, and `gc` again shows everything.
- **`]c` and `[c`** go to the next and previous change: in the tree, the
  next changed row; in the pane and on the code screen, the next change in
  the diff shown. Your gitsigns keys.
- **The diff is a toggle, `D`, not a view** (decided 2026-11-01,
  `design/mocks/diff-code.png`, `diff-types.png`; it was the Changed tab).
  Off when seam opens; on or off for the whole session, for both sides at
  once: the code screen's left, its code and its types, and the pane's
  Code and Types, beside the tree too. The status line starts `diff on`
  while it is. It diffs the lens's range. A row or file the range left
  alone shows as it is.
- **Code with the diff is CodeDiff's inline diff,** drawn into the pane:
  codediff.nvim's `compute_diff`, which works on any lines. Without
  codediff, Vim's own `vim.text.diff` and seam's drawing in the same shape.
  Removed lines show where they were, unnumbered on red; added on green;
  the words that changed in each lit stronger.
- **Its displays,** on `<S-Tab>` while the diff is on and the row changed:
  changes only, the default, every run of unchanged lines folded to
  `⋯ 12 lines unchanged` with three lines kept around each change
  (`design/mocks/changed-signs.png`); and the whole file
  (`design/mocks/changed-whole.png`). codediff has no folding (its roadmap lists
  it), so the folds are seam's.
- **On a function or type,** Code with the diff is its lines alone; on a
  file, the file; on a folder, its changed files one after another, a page at a time; on a
  row gone, its lines as they were, all removed, diff or not (a row gone
  has only Code).
- **Types with the diff** (`design/mocks/diff-types.png`) is what changed
  about the types: a function whose signature changed has its line as it
  was, `-` on red, over its line as it is, `+` on green; a new one, its
  line `+`; each type written out or opened under it carries its own `+`
  and `-` lines and `~ changed` by its name. A type's declaration the same.
  The pane's head says new, signature or body changed, and the types it
  names that changed.
- **Used by on a changed function** lists who uses it now, then who used
  it at `from`. storageFailed lost its first parameter: five places in
  three files called it before, two in a new file now
  (`design/mocks/changed-lens.png`). A changed signature, against a changed body,
  is told by parsing `from`'s version of the file (`git show from:path`)
  with treesitter and comparing what it takes and gives; the pane's head
  says which.

That's the check you do on an agent's work, on the map you already read:
what it touched, whether it changed a contract, and who relies on it.

## Above the file: boundaries

A table of the packages or top folders, each against each other.

- **A cell** counts the names one takes from the other. Read across a row
  for what a package depends on, down a column for who depends on it.
- **The cursor on a cell** lists the names that cross, each with its users.
  That's the contract between two parts of the code.
- **A cycle,** two parts each taking from the other, shows as cells filled
  on both sides of the diagonal, with no mark needed.
- **With a base,** cells whose crossing names changed are marked.

Facts: the import graph seam already has, rolled up by folder (inferred
cheap). Open: the unit, packages, the folders under `design/mocks/src/`, or both by zoom.

## Not doing: state machines

A map of one field's states, from its union of literals, the places that
write each literal, and the checks around them. Dropped 2026-10-31: it works
only where the states are written as a union of literals and each write's
object can be typed from what is written around it. Several booleans
together, a plain `string`, state held in which closure is current or in an
empty list: too many ways code keeps state fall outside it.

## Mocks to make

Every surface this needs, each with the ways it could look. Each mock is a
picture from raf's real data, drawn with `design/mocks/src/lens/lib.py` as the
locked screens were. Where today's screen already does it, the mock starts
from that screen's shot.

### 1. The tree

1a. **Layout.**
- A. The tree narrow on the left, the views on the right, as the contract
  page splits today.
- B. Three columns as the explorer today, the tree, then the views in the
  middle and right, two views side by side (say Types and Used by).
- C. The tree full width, each row with its takes → gives, the views in a
  pane under it.

1b. **A row's columns.** Counts (used by, built from) as today; takes →
gives; both, the counts dim. One key flips.

1c. **Where a call lives.** This file plain, another file underlined,
another package its hue bar (the default above). Or: this file dim. Or:
the file's name after the row, dim, only when it's another file.

1d. **What a function's opened rows show.** Its calls, in run order. With
or without the `if`, `case`, `later`, `return` they sit under. With or
without the types and constants it uses, not only its calls.

1e. **A file's rows.** Exports, then what it keeps, dimmer. Or exports
only, what it keeps seen through `l`. **Neither:** its functions in the
file's order, all alike (see The tree).

Mocked on raf, createRun open and update.ts's 3 exports and 10 kept, with
react's WaymarkRoot open for a call into another package (`design/mocks/src/tree/mock.py`):
`design/mocks/tree-where-a.png` (this file plain, another file underlined, another
package its hue bar), `tree-where-b.png` (this file dim), `tree-where-c.png`
(the file dim after the row), `tree-cols-counts.png` (`T`: used by and
calls), `tree-cols-types.png` (`T`: takes and gives, the tree widened to
92), `tree-flow.png` (calls under the closures and ifs they sit in),
`tree-file-kept.png` (exports, then `▸ 10 kept to itself`). Measured: 17 of
createRun's 17 calls are in other files, so under A every row under it is
underlined.

1c again, after the user found A1 marked only the tree and A2 invisible: six
marks, each the same in the tree and the code beside it, on update() (6
calls in its own file, 11 in others) and react's useOwnedRun() (createRun
from core): `design/mocks/where-{underline,dotted,italic,bold-here,glyph,file}-{core,react}.png`
(`design/mocks/src/tree/where.py`). **Underline chosen**, see "Where a call lives" in The
tree. Then 1b: nothing beside a name. 1d: calls only, in run order. 1e:
all functions alike. 1a was decided as layout A under Types.

### 2. Switching views

**A chosen,** tabs in the pane's head (see Types: the higher view). Then,
2026-11-01, the code screen's tabs were cut to Code and Types and the rest
went aside on their own keys, a mix of A and C: `design/mocks/tabs-aside.png`
(`design/mocks/src/tabsdiff/mock.py`). Beside the tree all stay tabs, A,
with the keys of C as well.

- A. Tabs in the pane's head, `Code  Types  Built from  Used by  Map
  Changed`, the one shown lit.
- B. Only the view's name in the head, the others in the status line's key
  hints.
- C. Each view on its own key (`c`, `t`, `b`, `u`, `m`, `d`) and `<Tab>` as
  well.

### 3. The Types view

**Decided,** see Types: the higher view.

3a. **A folder, a file, a function, a type.** Four pictures in the one
shape: takes → function → gives, the functions in one column.

3b. **A long signature.** An object parameter of eight parts, a return of
a union of objects.
- A. Wrapped under itself, the arrows kept lined up.
- B. Cut with `…`, opened with the expand key.
- C. The parts one per line under the function, as a declaration reads.

3c. **Generics.** `ReportProblem<TStep>`, `RunOptions<TWalkthrough>`.
- A. As written.
- B. The type arguments dropped where they're the default.
- C. The parameter replaced by its constraint, `ReportProblem<Step>`.

### 4. Opening a type

**Decided:** `+` and `-`, one level a press (see Types open in place).

- A. **By level,** as ts-expand-hover does: the whole type re-shown one
  level deeper each time.
- B. **By field,** a tree: `l` on one field opens only its type under it.
- C. Both: A from the head, B on a field.

A picture of `Queue` and of `Model`, each two levels open.

### 5. The Used by view

**Decided:** by file, with by name and by user as its other displays
(see Types: the higher view).

- A. The list of call sites, each `file:line` and its line of code; the
  cursor on one shows the caller's code around it below.
- B. Every call site with three lines of code around it, one after the
  other.
- C. Grouped by the calling function, each with its own line.

### 6. The Map view

6a. **A function, a type, a file, a folder.** Four pictures at two levels,
and createRun at three.

6b. **How it's drawn.**
- A. Left to right, `→` between levels, as sketched above.
- B. An indented tree, top to bottom, as the tree draws.
- C. Columns, one a level: the cursor in one column fills the next, as a
  file manager's columns do.

Mocked on createRun from seam's treesitter index, its 17 calls and
theirs: `design/mocks/map-a.png` (left to right, names only), `design/mocks/map-b.png`
(an indented tree of signature lines), `design/mocks/map-c.png` (columns),
`design/mocks/map-three.png` (B at three levels), `design/mocks/map-file.png` (run.ts's
imports, two levels, the names each takes), `design/mocks/map-type.png` (Model,
made by and taken by, then who takes what those give). Past the first
level a branch shows three and `⋯ 15 more`, opened with `l`. Measured:
createPage calls 18 and update 17, so at two levels the map is about 80
rows without that cut; the file map at two levels repeats state.ts and
problems.ts under nearly every file.

6c. **When it's too wide.** Scroll sideways; the levels past the screen
cut with `…`; or the first level only as names, the rest on `l`.

6d. **Sixteen more drawings** (`design/mocks/mapx-*.png`, from `design/mocks/src/map/ideas.py`
on the same index): tree lines, names first with types in columns, names
and what each gives, by file, file boxes in folder bands, a grid of files,
folders as boxes, a graph of boxes and lines, both ways, every way between
two, in order with a lane a file, the body cut to its calls, size by reach,
an icicle, types as boxes with functions on the arrows, values as lanes.

**Chosen.** The Map has three displays, the same on every kind of row
but a type, which has no library, `<S-Tab>` stepping through them. The
head lists them, the one shown bold.

| Display | A function | A folder | A file | A type |
|---|---|---|---|---|
| **folder** | names only, as it opens: both ways as it was, each side a folder, its files and each file's names after them, an empty row between folders. `T` the flow: its calls above under their folders, each a line, its file and the line it is declared on (the file once, the lines under it), the name, what it takes, what it gives; a line down the left through the folders into the row, written as what it takes → its name → what it gives; from under the middle of its name down a few rows, left, and on down under the row to its callers, so they stand apart from the row and do not read as what it gives, the row going on right of that line where it is too long, under their folders, each with its file and line (tests dim, last). Where and the name in columns, the signature straight after, nothing cut: a line too long goes on under itself, broken between words, `→` kept with what follows, an object over 30 letters as the names of its fields; an empty row between folders and between the files the calls are in | the same for the names crossing its edge: those it calls out to above, those calling in below under the caller's file | the same for a file | its makers above, its takers below |
| **type** | the flow with each head the type its functions give, the repo's types first, builtins, then nothing; each line the name, what it takes, its folder and file (`design/mocks/map9-type.png`) | the same | the same | the same |
| **library** | each library it takes from a head, the most used first; a line down through them into the row; under it each name taken from it, used most first, tests last, and every line it uses it on (`design/mocks/map13-libraries-grouped.png`) | the same, each name once, then the functions using it, the file once and the line each first uses it on, tests dim; outside every function the declaration holding it, in a test its title | the same for a file | none |

- **The flow and its foot** (chosen 2026-11-01, `design/mocks/map9-folder.png`,
  `map9-type.png`, `map9-type-cursor-type.png`, rounds seven to nine in
  `design/mocks/src/map/sigs.py`). Signatures side by side cut each other
  at the pane's edge; one a line, top to bottom, they have the width, and
  the line down into the row and on to its callers keeps it a map: what
  goes in, the row, what comes out. Grouped by folder it says where the
  row reaches; by type, what it gets back from each. With the cursor in
  the pane on a name, the foot, a window over the pane's last rows, tells
  it in full: its signature with the names of what it takes, the line that
  calls it as written, what that line sits in; on a type's head, its
  declaration as written, comments left out, with how many make and take
  it. `T` on folder gives back the names-only both ways, which is less to
  read when the signatures are not wanted; it opens with the signatures.

- **Nothing in the flow is cut** (2026-11-01, after the user tried it on
  createRun in a pane about 110 wide). Signatures lined up in a column were
  cut with `…` at that width and said too little. Now each signature
  follows its name, ragged, and a long one wraps under itself; empty rows
  between folders and between files keep it scannable, and the callers
  hang under the row, not off its right end.

- **No gutter, names only first, a foot to read** (2026-11-01, the user
  again). The line numbers in a gutter looked bad and named the call's
  line beside another file; each function's own line now follows its
  file. An object was `{ … }`, which hid what a function needs; now its
  fields' names, their types in the foot. The foot was one row cut at the
  edge on a float's colour: now at least 15% of the pane, wrapped, in the
  pane's colours. Folder opens names only, `T` the signatures. `<S-Tab>`
  steps the display, `<Tab>` the tabs, and the code screen's code or
  types moved to `gs`.

- **The foot is code** (2026-11-01, the user: "not readable", "a lack of
  syntax highlighting"). One wrapped line of the hover's signature read
  as a wall, and the copied code was never painted. Now the foot is the
  signature as the file writes it, in its own colours (comments left out,
  a destructured parameter's names on one line), with what it gives from
  the server, an object a field a line, only where the file does not
  write it; an empty row over and under, at most half the pane.

- **Groups close to fit, nothing left out** (2026-11-02, the user on a
  real codebase). A side ended `⋯ 12 more` at a fixed 40 names, cut by
  position, so which names went was arbitrary and a whole folder could
  vanish. Now, past the pane's height less the foot's least share (each
  side of both ways on its own, the flow's above and below together),
  whole groups close, the fewest names first, each to one line, `▸` its
  head and how many names in how many files; every group stays named. `l`
  opens one for the row, and it is never closed again to fit. Then each
  closed group that fits in the rows left opens again (2026-11-04): one
  group taller than the pane, React in a folder's libraries, closed every
  other with it.

- **Nothing cut on the right** (2026-11-02, the user: "just removing the
  truncation is at least better"). In both ways a long file name or
  folder pushed a side past the pane's edge, and the drawing cut it with
  `…`. Now the drawing is as wide as what is on it and the pane does not
  wrap the Map: a long row goes on right, for `zl` `zh`. The names after
  a long file name keep 30 columns rather than one a line. The flow's
  signatures still go on under themselves; a better answer for a side too
  wide may come later.

- **The callers hang from the name** (2026-11-02, the user on tasksOf in
  raf: "the line comes out of the return type"). Falling from what the row
  gives, the line made its callers read as more of what it gives. Now it
  falls from the middle of the row's name, and a row too long goes on under itself right
  of that line. Nothing else changed; the other ways to say "its callers"
  are round eleven, `design/mocks/src/map/callers.py`; this is
  `design/mocks/map12-line-from-name.png`.

- **What it takes from libraries** (2026-11-02, the user: "what
  libraries are used where"). The Map showed only the repo calling
  itself, so a component leaning on React looked as if it did little. A
  third display, library, lists each name taken from a package outside the
  repo, grouped by that name with its library after it, and under it the
  functions using it. The treesitter index (format 4) keeps each library
  import's name and every place it is named, after a namespace or default
  import's dot where there is one. A library is an import that resolves to
  no repo file and names a package a package.json of the repo depends on,
  one in node_modules, or Node's own; not a tsconfig path (a catch-all
  `"*"` there hid every library in synapse) nor a bundler's alias.
  Each use goes to the innermost function whose lines hold it. Package
  types are still never indexed; the foot asks the server of one when the
  cursor rests on it. `design/mocks/map12-libraries.png`, from
  `design/mocks/src/map/libraries.py` on excalidraw.

- **Libraries grouped by library** (2026-11-04, the user on a folder of
  pdf-plus: "group all of these from the same library like actually
  group"). A head for each name, its library after it, made a folder taking
  fifteen names from React fifteen heads, all closed to one line each. Now
  each library is the head and its names are under it, each name once
  with the functions using it beside it; closed, a library is one line,
  how many names in how many files. `design/mocks/map13-libraries-grouped.png`,
  from `design/mocks/src/map/libraries_grouped.py` on excalidraw's
  TTDDialog folder.

- **Outside a function, the declaration holding it** (2026-11-04, the
  user on synapse: "what is with the top level thing"). A use outside
  every function the index knows read `(top level)`, bright where the
  file has a top level that calls and dim where not. In Convex code that
  was nearly every use: `export const listMessages = query({ handler })`
  is a const, not a function, so all of it is the file's top. The index
  (format 6) keeps with each such use the top-level declaration holding
  it, and the display names it, `listMessages`, `cardSchema`, `Props`;
  plain, as it is no function the Map knows, `l` showing its file. In a
  test, `test('counts each day', () => { … })` (the user: "i still see
  some"), the innermost test's title, quoted as written (format 7). Only a
  bare statement, `export default defineSchema(…)` or `vi.mock(…)`, is
  still `(top level)`, always dim.

- **The foot everywhere** (2026-11-02, the user: "would be nice to have
  in other parts like Types, so you could see the definition of the type
  too"). One rule: where the cursor rests on a repo function or a repo
  type, the foot tells it, in the pane's Map, Types and Code and on the
  code screen's code, its code or its types, over the window the cursor
  is in. Each view says what is under its cursor (`under` in the views'
  registry); a name is resolved as `+` resolves it, in the file its line
  is from. It moves over the window's first rows when the cursor is on
  its last. A type's declaration is no longer cut at seven lines: it runs
  as long as the foot holds, half the window, and only past that says
  `⋯ N more lines`.

- **The foot is the tree's** (2026-11-02, the user: "why in the code view
  am i getting the bottom bar thing, that's only for the tree view").
  The code screen has no foot: its pane already tells the name under the
  code's cursor, so a foot over the code repeated it and hid the code.
  What the foot told there that the pane did not, a package type's own
  declaration under a value's type, the pane now shows in full.

- **A type at three levels, `=`** (2026-11-07, the user: "is there some
  way that we can prettify them all like you can with typefest", then
  "some way to change the verbosity level of types too";
  `design/mocks/foot14-levels.png`). As written, a type is often half
  somewhere else: `Offsets & { ui?: … }`, `Omit<BinaryFileData,
  "dataURL">`. The foot tells a repo type alias or interface with no type
  parameters at three levels, named at the right of its head: as written;
  flat, the server's hover of type-fest's `Simplify` on it, one object,
  the names it uses kept; in full, the same hover at `verbosityLevel` 1,
  every alias spelled out. tsgo takes `verbosityLevel` as on or off (0
  names, 1 and up spells every alias out, at every depth, not one level a
  press), so it is one level, not a dial; flat is the one in between.
  `| undefined` after a `?:` is left out, the `?` says it. `=` steps them,
  round, and the level stays for the session. A generic is left as
  written (flat needs its arguments), a class and an enum too, and a type
  the server says is no object (a function's type flattens to `{}`).

- **Tree and folders are gone** (2026-11-01). Both ways says what a row
  is built from and who uses it, by folder and file, in one picture; the
  tree repeated the Built from tab a level at a time, and folders drew the
  same facts again as boxes. Size stayed, then went with Built from and
  Used by. With them went `>` `<`, `h` and a
  type's boxes with `+` `-` on them. The decisions below on them are kept
  as the record.
- **What it is built from comes first, who uses it after,** the order of
  the tabs (chosen 2026-11-01, `design/mocks/mapw-fn-both.png`): both ways
  has the calls on the left and the callers on the right, so a line runs
  from the user, right, to the used, left. A type keeps its makers first:
  where it comes from, then where it goes.
- **Folders runs top to bottom** (chosen 2026-11-01,
  `design/mocks/mapw-fn-folders.png`, `mapw-file-folders.png`): side by side
  the boxes cut their names at the pane's edge all the time; one above the
  other, each box has the pane's width, as many sit across as fit, and the
  names wrap. Built from above, the row, used by below; on a function and a
  file the arrows point up, at what is used, which is both lines' direction.
  It was side by side, every arrow at the row
  (`mapz-fn-folders-in.png`, `mapy-fn-folders-both.png`).
- **Both ways groups each side by folder and file** (chosen 2026-11-01,
  `design/mocks/mapw-fn-both-grouped.png`): a list of names in the order
  they are called says little; under their folders and files it says where
  a function reaches. The names wrap to the room, never cut.
- **A folder's folders lists, it does not route** (chosen 2026-11-01,
  `design/mocks/mapw-folder-own.png`, `mapw-folder-own-dirs.png`): the
  graph of boxes with a line for every call became a tangle on any folder
  with more than a few files, its labels cut at the edge. Now the boxes
  stand in bands, each after everything it calls, what calls nothing here
  first; each box names what it calls in the folder and how often. A call
  back round a cycle is listed in its box and not counted for the band.
- **`T` shows and hides inputs and outputs,** in every display that has
  functions in it, and the choice stays. In the
  tree display it adds the takes and gives columns (`mapx-type-columns.png`); in
  both ways the makers show what they take and the takers what they give.
- Mocks: `design/mocks/mapy-fn-tree.png` (`T` off), `mapy-fn-tree-types.png` (`T`
  on), `mapw-fn-folders.png` (was `mapy-fn-folders-both.png`, and
  `mapy-fn-folders.png` the right side only), `mapy-folder-both.png` (storage/),
  `mapy-type-both.png` (Model, `T` on), `mapy-folder-size.png` (run/), with
  `mapx-folders.png` (core/src/) and `mapx-type-graph.png` (Model's tree).

Filled 2026-11-01, drawn to be looked at (`design/mocks/src/map/ideas.py`, round three):
- **A folder's and a file's tree** go one rank down a level, as the tree on
  the left does: a folder, the folders it calls into, their files, then the
  functions; a file, the files it calls into, then the functions it uses in
  each (`design/mocks/mapz-folder-tree.png`, `mapz-file-tree.png`).
- **A file's both ways** is a folder's, for one file (`mapz-file-both.png`).
- **A file's folders** is a function's, the file's functions together
  (`mapz-file-folders.png`, top to bottom since `mapw-file-folders.png`).
- **A type's folders** is its both ways gathered into folders: the folders
  that make it, above; that take it, below (`mapz-type-folders.png` had
  them left and right).
- **A file's size** is a function's, for each of its functions
  (`mapz-file-size.png`, update.ts).
- **A type's size** is the files that use it most
  (`mapz-type-size-files.png`). By field (`mapz-type-size-fields.png`) was
  liked but dropped: it needs the server's references for every field,
  slow on a big type and not worth it.
- **A type's tree opens its boxes with `+`** (`mapz-type-tree-open.png`).

- **Each side says what it is to the row** (decided 2026-11-07; drawn
  in seam and kept as the pictures, `design/mocks/map16-labels-*.png`).
  Over the left side, or above, `calls`, a type's `made by`; over the
  right, or below, `called by`, a type's `taken by`, a value's `used by`,
  the functions and values naming it (`design/mocks/map17-value-used.png`);
  the words the pane's head counts with. In type, each head says `gives` before its type,
  `gives nothing`, so a head is never a bare type to guess at.

### 7. The Code view and the code screen

7a. **A value's type where none is written.**
- A. After the name, as virtual text: `const queue: Queue =`.
- B. At the end of the line, dim.
- C. In a column at the left, as try-c's margin.

7b. **Types only.**
- A. The function as lines of `name  Type`, in the order made, with the
  frames.
- B. The code with every line that makes no named value folded, as try-c's
  `zM`.

Mocked on createRun: `design/mocks/code-types-a.png`, `-b`, `-c` (7a, the cursor
on `queue`, its later uses lit), `design/mocks/code-types-only-a.png` and `-b`
(7b), `design/mocks/code-cursor-field.png` (7d). A value's type is the name in the
declared return of the call that made it, else the server's inlay hint when
it's short; the server's hint alone writes raf's aliases out in full
(`queue` comes back as `Readonly<{ run: …; invoke: …; … }>`), so it never
names a type. Nothing is added where the type is written, and an arrow
function gets its return after its parameters, as TypeScript's own hints do.

7c. **Later uses lit,** and the head's trail after `J` `J` `J`.

7d. **The cursor on each kind of name:** a local call, a method
(`queue.fail`), a value, a parameter, a field. Five pictures of the right
side.

### 8. What changed

8a. **Choosing the base.** A float of branches and recent commits; or
`master` until changed with a command.

8b. **Marks on the tree.**
- A. A sign in the left column, one for a changed body and one for a
  changed signature.
- B. The row's name coloured.
- C. A word after the row, `signature changed`.

8c. **The lens, only what changed,** with Used by open on a changed
signature.

8d. **The Changed view.**
- A. The diff as Git shows it.
- B. The code as it is now, changed lines marked in the margin, removed
  ones as virtual lines.

Mocked on two real versions of raf core, the base the Oct 17 copy
(`raf-run-redesign`), now seam's copy of Oct 23, as no git history of raf
is reachable here: `design/mocks/changed-signs.png`, `-signs-only`, `-whole`, `-range` and
`-lens`; signs, words and colours were tried for 8b and signs kept. A declaration is new, gone or changed by
its text under treesitter; a changed function's signature changed when its
written parameters or return differ, else its body. Used by on a changed
signature lists who uses it now and who used it at the base: storageFailed
lost its first parameter, five places in three files called it at the
base, two in a new file call it now.

Then, 2026-11-01, the Changed view became the diff on `D`, on the code and
the types, on the code screen's left as in the pane:
`design/mocks/diff-code.png` (problems.ts on the left, storageFailed's
lines in the pane) and `diff-types.png` (storageFailed's line as it was and
is, and WaymarkProblem, which it gives, with its own lines).

### 9. Boundaries

- A. The table of packages or folders against each other.
- **B, chosen.** Not its own thing: a folder's Map view, the folders
  display (`design/mocks/mapx-folders.png`), with both ways for what crosses a
  folder's edge (`design/mocks/mapy-folder-both.png`). The table goes.
- C. Not its own thing: a folder's Types view.

A picture of each on raf's packages. If B or C reads as well, the table
goes.

### 10. Keys

One picture of the status line hints on each screen, and KEYS.md drafted
from the chosen mocks.

**Hints chosen 2026-11-01: B, with `?`** (`design/mocks/keys-*-b.png`,
`keys-tree-help.png`, `design/mocks/src/keys/mock.py`). The status line names where you
are on the left and, on the right, only the keys that act there, each key
lit and its word dim, in three groups always in the same order: the row │
the pane │ seam. One word a key on every screen (`J` is always "code").
Hints live only there, not in the pane heads, which list only the views and
displays. A narrow window drops the seam group first. `?` opens a float of
every key on the screen, grouped as KEYS.md is. To be corrected once built,
not by more mocks.

**Draft, 2026-11-01.** One meaning a key, on every screen. A key that has
nothing to do where the cursor is does nothing, and its hint isn't shown.

| Key | Does, everywhere |
|---|---|
| `j` `k` | move |
| `l` `h` | open and close a function's calls in the tree |
| `J` `K` | the code screen on it, and back to the very row or name; `3K` three back; back to the tree is `K` until there |
| `<Tab>` | the next view |
| `<S-Tab>` | the next display of the pane's view |
| `gs` | the code, or its types, on the code screen |
| `+` `-` | open and close the type under the cursor, one level a press |
| `>` `<` | a level more or less, in the Map |
| `T` | names only, as it opens, or each signature, in the Map by folder |
| `n` `N` | the next and previous import in the code |
| `]c` `[c` | the next and previous change |
| `gc` | only what changed in the tree, and back |
| `s` | the tree's order: by folder, or every name in one list, most used or uses most first |
| `#` | the tree's counts, used by and uses, on or off |
| `/` | search the names |
| `L` | the lens: the range of changes and the rules |
| `<C-d>` `<C-u>` `<C-e>` `<C-y>` | scroll the pane from the tree |
| `gf` `gd` | that place in your own code |
| `R` | ask again |
| `q` | close |

Gone from today's keys: `b` `u` (Built from and Used by are views), `c` `C`
`t` (the tree and the Types view hold them), `d` `D` (the lens filters),
`v` (`<C-Tab>`), `~` (Used by is a view), `O` `H` (`>` `<` in the Map).

- **Into the pane and back** are Vim's own window keys; seam maps none, so
  the user's own (`gl` `gh`) work. `<Esc>` in the pane goes back to the tree
  as today.
- **Back is `K`,** a press a step, a count for more. No key straight to the
  tree: `-` closes a type.

# How it is built

The parts below carry over from v1's spec and still hold.

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

The tree's counts need `used_by` for every contract. Used by and Built from
draw from the index's uses and names as they are; nothing on screen asks
the server per field.

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
| What a use sits in | the call graph's function, component or class holding its line, else the type declared at the top of its file holding it (treesitter) | per use, as drawn |
| Signature | `textDocument/hover` | per contract, on demand |
| Code colours | treesitter captures of the source file | per pane |
| The call graph | treesitter: each function, component and class at the top of a file, and each file's top-level code, with the callables it names outside type positions, resolved as built-from names are | per file, in the same pass |
| Change line | `git log -L` on the declaration range | per contract, on demand |
| What a function takes and gives | `textDocument/hover` on each callable of the call graph, `scripts/types.lua` | one request a callable, once, in the background |
| A package's type, at the foot | `textDocument/definition` where the name is written, then treesitter on the `.d.ts` it points at (`seam.lookup`) | one request a name and file, when the cursor rests on it, never waited on; cached for the session |
| A repo type flat and in full, at the foot | `textDocument/hover` at `verbosityLevel` 0 and 1 on `{ [K in keyof T]: T[K] } & {}`, in a copy of its file never written to disk (`seam.lookup`) | two requests a type, once `=` is past as written, never waited on; cached for the session |
| A value's type no one wrote, in the pane and at the foot | `textDocument/hover` and `textDocument/typeDefinition` where it is made, treesitter on the `.d.ts` (`seam.lookup`) | two requests a value, when the pane or the cursor is on it, never waited on; cached per place for the session |

So treesitter answers everything inside one file and the language server
answers everything across files. The only bulk work is references for every
export.

The call graph is names, not types: a local that shadows a top-level or
imported name still counts as a call to it, and a method, a prop or a
callback ends the tree without saying so.

## Types

`types.json`, beside the treesitter index, is what the TypeScript server
says each function, component and class of the call graph is: its
`textDocument/hover`, as it came, by node id; and for each class the
callables that say `new` to it, from the source just before the call.
`scripts/types.lua` writes it in a headless Neovim of its own, with the first
TypeScript 7 server it finds: the repo's `effect-tsgo` or `tsgo`, then `tsc` 7
or `tsgo` from Mason or the PATH, unless `$SEAM_TS` names another (11 to 30 s on excalidraw).
Indexing starts it when the treesitter index is written, and opening a repo
whose index has none starts it; until it lands, and when the server will not
start (said once), every screen works without types.

`seam.types` parses each hover into its parameters and return, and builds a
flow for each repo type (an exported interface, type alias, class or enum,
by name): the functions whose return names it or that `new` it make it, the
ones with a parameter naming it take it. The model holds `sigs` by node id,
`flows` by name and `flowlist`, the most travelled first. The call tree shows
what each row takes and gives; the Types view (The views) shows them on
every row of the tree, a function's line from its written signature
(treesitter) where it says, the hover where it does not, and opens a type
in place, its declaration from treesitter.

**Package types, on demand, never indexed** (2026-11-02). A type from a
package (`RoughCanvas` from roughjs, `ReactNode` from react) or from
TypeScript's lib is no repo type: it has no flow, it is no contract, and
nothing indexes it. Only the foot shows it, when the cursor rests on it, in
the code (the code views, the code screen) or in a signature (the Map, the
Types view). `seam.lookup` keeps one TypeScript server for the session, the
one `seam.tsserver` names, started on the first lookup and stopped when seam
closes. It asks `textDocument/definition` where the name is written: in the
code, the cursor's own place; in a signature, the first place the file of
the function it belongs to writes the name, its import as a rule
(`workspace/symbol` finds nothing in `node_modules`, so a name needs a
written place). It never waits: the foot shows nothing until the answer
lands, then draws if the cursor is still there. The declaration is read
out of the file the answer points at with treesitter, the interface, type
alias, class, enum or function signature holding it, and shown as a repo
type's is: its name, `type in roughjs` (the package after the last
`node_modules/`, `@scope/name` kept; `TypeScript's lib.dom.d.ts` for a lib
file), its lines in their colours. A name's answer is kept per file for the
session, and each file read once. A trial on excalidraw: about 200 ms the
first time, the server starting, then 15 to 110 ms; no server, no lookup,
and nothing said.

A value no type is written for (`const root = createRoot(el)`,
`const schema = z.object(…)`) is asked the same way, on demand and never
indexed: `textDocument/hover` and `textDocument/typeDefinition` at the
place it is made, so its every use shares one answer, kept per place for the
session. The hover's code, `const root: Root`, gives its type, `Root` (a
`const`'s, a `let`'s, a parameter's or a property's type; a function's
signature whole); the type definition its type's declaration, read as a
package type's is. The server gives no type definition for an
intersection (jotai's `atom(false)`, `PrimitiveAtom<boolean> &
WithInitialValue<boolean>`), so for one the first type is looked up where
the function that made the value writes it. The pane's Types view of the
name draws the type as a written one is drawn, under a dim `no type is
written for it; the TypeScript server says`, `asking the TypeScript server`
until the answer lands and the pane is drawn again, and when the type is a
package's, its declaration under it, `ZodObject   type in zod`, in full;
the foot beside the tree shows the hover's code in its colours and the
type's declaration under it. A
package's function (`createRoot`) at the foot is its hover, the signature,
and the package it is in. A trial on excalidraw: 15 to 120 ms.

A repo type flat or in full (the foot's `=`, 2026-11-07) is asked the same
way, on demand, never indexed, and only once `=` is past as written: a copy
of the type's file, never written to disk, opened beside it
(`types.__seam_shape_ViewportOffsets.ts`) so its tsconfig takes it and the
file's own types, exported or not, are in reach, with `export {}` (a module,
so the copy's declarations are its own) and `type __seam_shape = { [K in
keyof T]: T[K] } & {}` at its end; `textDocument/hover` on that alias at
`verbosityLevel` 0 and 1 together, the copy closed once both have answered.
The alias is named the type's own again, and kept per type and file for the
session. The session's server is started with `maximumHoverLength` as the
types pass is, or a big type ends `... 10 more ...`. A trial on excalidraw:
20 to 90 ms.

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

The tree opens on the cache at once, then a background pass brings it up
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

## Drawing rules

The screens are locked in the design docs. The code must keep these rules:

- **Layout.** The tree is 46 wide, the pane the rest, under a head line
  across the top. The code screen is two: the code as wide as it needs,
  60 to 112 and at most 60% of the screen, the pane the rest, 40% or more. All need 150 columns. Narrower than that is not
  designed. v1 says so and opens anyway.
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
  - A gap is a `⋯` row.
- **Every place on one line.** (Used by and Built from are gone; the Map's foot writes a call's line this way.) Used by and Built from showed each place as
  its line of code, copied with its colours from its first letter and cut
  with `…` at the pane's edge, the names it is about marked where they live
  (Built from lights the name the row is about), and what it sits in,
  `in createRun`, right-aligned at the pane's edge. A file shows four places,
  then `⋯ N more`, which `+` opens and `-` closes again.

## From your code

`require('seam').here(how)`, `:SeamHere [overview|page|calls|called_by|types]`,
opens seam (`overview` is the tree, on the row; `page` and `called_by` the
same with the pane on Used by, a type's in the pane; `calls` the code screen
on the function, the tree on its row under it) on what the word under the cursor names in a buffer of the repo.
`seam.here.resolve` is pure: the word, the file relative to the root and the
cursor line, against the model. A contract (an export with a use, the lens's
`all_uses` counted) declared in this file, the one holding the cursor if
several; else one this file uses; else the only one of that name. For calls
and called by a graph node first the same way (declared here, else one this
file's nodes call, else the only one), then a contract, then the innermost
node holding the cursor. For types, the repo type of that name, its Types
view in the tree's pane. Several and none here: the `/` picker of the
screen asked for, holding the word. `:Seam` on a repo seam is open on comes to its
tab as it was; another repo closes it first.

**From a link.** `require('seam').show(target, { root?, from? })`, `:SeamShow <target>`,
opens seam on a place written as a string, for a link in a thread to land
on; `require('seam').check(target, root)` says why a target is nothing
seam can show, nil when it is, for the agent who wrote the link to fix it.

```
target  := what ['@' view ['/' display]]
what    := 'type:' Name                 a repo type
         | path ':' name [':' line]     a function, value or contract declared in that file; the line breaks ties
         | path                         a file or a folder, a trailing '/' allowed
view    := 'Code' | 'Types' | 'Map'
display := one of that view's displays for that row (Map: folder, type, library; a type's: folder, type)
```

`src/store.ts:save@Map`, `type:Card@Map/type`, `src/billing/@Map/library`,
`src/store.ts`. A path is from the repo's root; a name is the tree's, found
as `here` finds a word in that file, but only one declared there. No view,
the view seam has chosen. `seam.target` parses the string once and
resolves it against a model; neither touches the open state. `check` reads
the repo's treesitter index from disk (`index.peek`, kept per repo until
its files change, no lens: what the lens hides is the reader's choice, not
a wrong link), so it runs headless and while seam shows another repo; no
index, or an older one, says to open it with `:Seam` once. Its whys say
what is wrong and what is near: `src/store.ts has no function, value or contract
named sav; it has save, load, …`, `a type's Map has no display 'library':
folder or type`. `show` starts seam on the repo, sets the view and display,
then the row (a type in the pane, its file's row under it), the pane drawn
at once; one that does not resolve, or the lens hides, says why and leaves
the tree's `/` holding its name. It adds no screen: it opens the existing
ones in a given state.

**Prototype: the view you came from** (2026-11-07, unmocked, the head's
change only one more tab name). Landing in seam from a thread, the thread
was gone. Seam's pane holds one buffer not its own, the last you arrived
from: `show(target, { from = buf })` holds `buf`; `show` without `from`,
`here` and `:Seam` hold the buffer current when called, outside seam's tab
and in a window of its own (an empty one, a float, a list or a prompt
none); from seam's tab nothing changes; `require('seam').hold(buf)` holds
it, nil lets go. While held it is a tab on every row, after seam's,
named by `b:seam_name` (thread sets its thread's title), else its file,
else `buffer`; arriving, you land on the target, not on it. Shown, the
pane's window displays the buffer itself (`seam.views.held`), where its
cursor was when held; seam draws nothing into it, the tree's cursor leaves
it be, `<Tab>` away gives the window back seam's buffer. Neovim's own
window options per buffer do the rest: the buffer comes with its window's
options (numbers, wrap, its status line) and seam's pane gets its own back.
`<C-w>l` goes into it (from the pane's head on), `<C-w>h` back; seam maps
nothing in it. Wiped, its tab goes; shown in the pane then, Neovim closes
the pane's window with it and the screen is laid out again.

## Code layout

```
lua/seam/
  init.lua          :Seam, start and open the tree, here (from your code), show and check (from a link), hold (the view you came from), what tests and view steps call
  here.lua          the word under the cursor in a file to the contract or function it names
  target.lua        a link's target: the string parsed, then resolved in a model to a row, its view and display, or why not
  state.lua         the one table every screen reads: repo, models, tab, windows, what is shown
  index.lua         the model from a source's JSON, the lens applied, its types hung on, where indexes live, indexing
  theme.lua         highlight groups, hues
  lens.lua          the lens: patterns, what it hides, .seams/lens.json
  tree.lua          paths to rows: compaction, folding, the package bar
  code.lua          a code pane: copied lines, copied captures painted in view, enclosing function
  draw/init.lua     rows, putting them in a buffer, the pieces both screens share
  outline.lua       the tree as data: folders, files, functions, the calls under each, the orders, reveal
  views.lua         the pane's views, a registry: the two tabs and the views aside, which rows each has, its displays, how it draws, what is under its cursor for the foot
  views/code.lua    the Code view: a function, a file, a type's declaration, each call underlined where it lives
  views/types.lua   the Types view: a line a function, takes → name → gives; a folder's, a file's, a type's; types opened in place
  views/held.lua    the view you came from (prototype): the buffer held, its name, shown itself in the pane's window and given back
  typesview.lua     the Types view as data: a function's line, the names that are types, the types opened as a set of keys laid out
  written.lua       what a file has written, from treesitter: a function's signature, the types it declares
  draw/outline.lua  the tree's rows and head, the pane's head and tabs
  hints.lua         the keys that act where the cursor is: the status line's three groups and the ? float
  screen_tree.lua   the tree's tab layout, its keys and the pane beside it
  opening.lua       + and - in the pane: the type or function line under the cursor opened or closed in place
  graph.lua         the call graph read through the lens: what each way shows, a function's calls one level on
  scope.lua         a file's bindings from treesitter: what each name resolves to in its function, the uses of a binding
  names.lua         what a name in the code is: a repo function, a type, an import's file, a value, a parameter, a field or method, its type and later uses
  codetypes.lua     the types the code does not write: after a value's name, after a function's parameters; the code's types display
  pane.lua          the pane beside the tree and the code: drawing it, its keys, the foot following its cursor
  foot.lua          the foot: the name under the pane's cursor in full, beside the tree only, in every view; a function's signature and the line that calls it, a type's declaration as written, flat or in full (`=`), a package's type once looked up, a value's type the server says
  screen_code.lua   the code screen: the trail, the code or its types (views/codetypes.lua), the name under the cursor answered in the pane, J K n N
  views/names.lua   the Types view of a name in the code: a method's line, the type it is in, the types it names; a value's type the server says, where none is written
  types.lua         types as data: a hover to what a function takes and gives, each repo type's flow, a signature fitted to a row
  lens_panel.lua    the lens float and its keys
  picker.lua        the / float on every screen: a prompt, a list of picks, fuzzy matching
  tsserver.lua      which TypeScript server seam asks: $SEAM_TS, the repo's, Mason's or the PATH's
  lookup.lua        package types on demand: the session's server, a name's definition asked where it is written, the declaration read out of its .d.ts, the package it is in; a value's hover and type definition where it is made; a repo type's hover flat and in full, asked in a copy of its file never written to disk
  health.lua        :checkhealth seam: this copy, Neovim, the colours, the parsers and highlight queries, the keys and terminal, the server
  screen.lua        the tab page, its windows, keys, status line, cursor to redraw
  changes.lua       what changed in the range, from git: the files, each end's lines, each declaration new, gone, signature or body changed, where a name was used at from
  diff.lua          two versions of some lines compared: the hunks, the words changed, laid out with removed lines where they were and unchanged runs folded
  signs.lua         the range's signs on the tree's rows, the rows gone kept struck through, gc and ]c [c
  refs.lua          the refs a range can start from and the picker over them, f x in the lens
  warm.lua          the range's changes worked out ahead while you are idle: each changed file parsed and its diffs made, a few at a time
  views/changed.lua the diff on D: Code with the diff on a function, a type, a file or a folder; a type's own lines; a function's line as it was
  codediff.lua      the range's changes on the code shown: its changed lines numbered in the signs' colours, or with the diff on drawn inline; ]c [c
  views/codetypes.lua the code screen's types display: the function's line, its values, the functions inside; with the diff, a line as it was
  views/map.lua     the Map view: folder and type on a function, a folder, a file and a type, what each side holds, T's names only, its head's count
  map/canvas.lua    a grid of lines joining into box characters, text and what it stands for over them, laid out as rows as wide as what is on them
  map/data.lua      the Map's facts from the graph and the flows: what a function calls and reaches, the calls across an edge, the names from src/, a type's makers and takers, the names taken from libraries and the function each use is in
  map/flow.lua      the flow: calls above under their heads, a line down into the row, on to its callers below, each side in columns, groups closed to fit
  map/both.lua      folder with T off, names only: calls left, callers right, each side by folder and file, groups closed to fit
  map/fold.lua      which of the Map's groups close to a line so a side fits the pane: the fewest names first, never one opened with l, reopening any that fits after
  map/keys.lua      the Map's keys in the pane, l T J, where each acts, and the name under the cursor for the status line
scripts/
  extract.lua       the treesitter index, in a headless nvim of its own
  types.lua         types.json: the TypeScript server's hover of each callable, in a headless nvim of its own
tests/
  names.lua         names in the code: each kind, its type, its later uses, the types after names and the types display, on files written by hand
  outline.lua       the tree's, the graph's and the picker's specs, on a graph written by hand
  here.lua          here's resolution specs, on a model written by hand
  target.lua        targets parsed, well and badly, and checked against a real repo's index, seam's state untouched
  types.lua         hovers parsed, flows built, signatures fitted, on a model written by hand
  typesview.lua     a function's line, the names that are types, the types opened in place laid out
  changes.lua       what changed: declarations compared, signature and body, files new and gone, uses at from, the hunks, the words, the layout folded
  map.lua           the Map's layouts on graphs written by hand: the facts, both ways, the flow, which groups close to fit
  lookup.lua        package types: the package from a path, the declaration around a position, a hover's code and type, the call that made a value, a type's hover flat; for real on the trial excalidraw with node_modules, skipped without it or a server
  check_map.lua     the Map on a real repo: each display on a function, a file, a folder and a type, T on folder, its groups closed to fit, l opening one and h closing it
  check_changed.lua what changed on a real repo, in a git directory of its own that reads the repo's objects: the signs, gc, ]c [c, D's diff in Code and Types on both screens, the lens's range
  check.lua         every screen through its keys on a real repo, the foot on the Map and the Types view beside the tree, none on the code screen
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

## Not in v1

- Narrow screens (under 150 columns).
- Members of a component's props, and Effect services and schemas.
- Grouping Used by by member.
- JavaScript without types, and languages other than TypeScript.
- Anything written by an LLM.
