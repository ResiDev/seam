# seam.nvim, the spec

What seam is, how each screen behaves, where each fact comes from and how it
is built. The screens are the mocks named here, in `design/mocks/`; the keys
are in `KEYS.md`. Built a slice at a time (Building): what a slice has not
replaced yet still runs as `design/contract.md`, `calls.md` and `types.md`
lock it.

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
   is drawn so far. Replaces the Types screens.
3. **Used by and Built from,** by file, with their other displays.
   Replaces the contract page.
4. **The code screen.** `J` `K` and the trail, every name answering in the
   pane, a value's type after its name, `n` `N` the imports, `<C-Tab>`
   code or types, later uses lit. Replaces Calls.
5. **Changed.** The range in the lens, the git signs, `gc`, `]c` `[c`, the
   Changed view drawn with codediff, a changed type opening with its own
   lines.
6. **The Map.** Its displays on each kind of row, `T`, `>` `<`, and the
   arrows as chosen.

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
right. `<Tab>` and `<S-Tab>` step through them, and the one chosen stays as
the cursor moves.

| View | A folder | A file | A function | A type |
|---|---|---|---|---|
| **Code** | | the file | its body, imports underlined | its declaration |
| **Types** | what comes in and goes out: the types its exports take and give | the same for the file, then the types it declares | what it takes and gives, each type expandable | where it comes from and what it becomes, one step each way; its fields with who sets and reads each |
| **Built from** | what it draws on, by file | what the file draws on, by file | what it draws on, by file | the types its fields are made of |
| **Used by** | who imports from it | the files that import it, each line | each place that calls it: the file, the line, and the code there | who takes it and who gives it |
| **Map** | four displays on `<C-Tab>`: tree, both ways, folders, size (section 6) | the same four | the same four | the same four; its tree is types as boxes, functions on the arrows |
| **Changed** | its files' diffs | the file's diff | its diff since the base | its declaration's diff |

- **Used by is where it's called.** The cursor on a use shows the caller's
  code around that line, so "used by" and "called at" are one view.
- **Types open in place.** `+` on a type's name opens its declaration, as
  written, under the line it is named on, a bar down its left and its file
  and line at the top. `+` on a name inside that opens the next one, nested
  under it: one level a press. `-` closes the one the cursor is in. `l`
  stays the calls; `+` and `-` are only types. It works on a type's name
  wherever one is drawn: the pane's head line, the Types view, the Code view's types
  display, Built from and Used by as signature lines, the Map with `T` on,
  and Changed, where an opened type carries its own `+`/`-` lines, so a
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
  one shown lit; `<Tab>` and `<S-Tab>` step through them. Two views side by
  side (B) cut the signatures; a band over today's trees (C) breaks the
  blank line between functions. Built from and Used by become single views
  in the same pane, redesigned to fit it.
- **A view and its display.** Each view can be shown more than one way,
  its display. `<Tab>` and `<S-Tab>` change the view; `<C-Tab>` and
  `<C-S-Tab>` step its display forward and back. The same keys work in the
  tree and in the pane, so `v` keeps its own meaning in the pane. The
  display chosen stays for that view as the cursor moves, and the pane's
  head names it after the view's tab. Ghostty takes `ctrl+tab` and
  `ctrl+shift+tab` for its own tabs by default, so they need unbinding in
  its config (`keybind = ctrl+tab=unbind`) before Neovim sees them.
- **Used by and Built from open by file,** the point of the view, each file
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
  from, Used by and Changed. It has no Code.


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
- **Nothing beside a name.** The pane shows its types and counts; the tree
  stays narrow. (Decided 2026-10-31; `design/mocks/tree-cols-*.png` were not liked.)
- **`s` changes the order,** as `<Tab>` does in today's explorer: by folder
  (the tree), most used first, most calling first. The two sorted orders are
  a flat list of functions, each with its package's hue bar and two counts,
  used by and calls, the one it sorts by lit. Tests don't count.
  `design/mocks/tree-sort-used.png`, `tree-sort-calls.png`.
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

Open:
- ~~`n`/`N`: every name, or only the imports as today?~~ Only the imports,
  as today.
- ~~The key for code or types.~~ `<C-Tab>` and `<C-S-Tab>`, as everywhere:
  the code on the left is the Code view brought over, and its displays are
  the code and its types. `<C-Tab>` steps the display of what the cursor is
  in; the tree has none, so there it steps the pane's. `v` is not used.
- ~~The keys that open and close a type.~~ `+` and `-`, decided with the
  mocks `design/mocks/open-type-*.png` (see "Types open in place" above).

## What changed (git)

A range of git, `from` and `to`. By default from `HEAD` to the working
tree: what isn't committed yet. Then:

- **The range lives in the lens** (`L`), on its first row, above the
  rules: `changes  from HEAD  to working tree`. `f` and `t` work from any row
  of the lens, the cursor where it is: each opens a picker of branches,
  tags and recent commits, a ref typed narrows it, and its first entry is
  the default (`HEAD`, the working tree), so picking it resets. The
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
  next changed row; in the pane, the next change in its diff. Your
  gitsigns keys.
- **The Changed view is CodeDiff's inline diff,** drawn into the pane:
  codediff.nvim's `compute_diff` and `render_inline_diff`, which draw into
  any buffer. Without codediff, Vim's own `vim.text.diff` and seam's
  drawing in the same shape. Removed lines show where they were, unnumbered
  on red; added on green; the words that changed in each lit stronger.
- **Its displays:** changes only, the default, every run of unchanged lines
  folded to `⋯ 12 lines unchanged` with three lines kept around each change
  (`design/mocks/changed-signs.png`); and the whole file
  (`design/mocks/changed-whole.png`). codediff has no folding (its roadmap lists
  it), so the folds are seam's.
- **On a function or type,** the Changed view is its lines alone; on a
  file, the file; on a folder, its changed files one after another.
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

**A chosen,** tabs in the pane's head (see Types: the higher view).

- A. Tabs in the pane's head, `Code  Types  Built from  Used by  Map
  Changed`, the one shown lit, as the Calls pane does today.
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

**Chosen.** The Map has four displays, the same on every kind of row,
`<C-Tab>` stepping through them. The head lists them, the one shown bold.

| Display | A function | A folder | A file | A type |
|---|---|---|---|---|
| **tree** | what it calls, tree lines, `> <` levels, `l` opens the call under the cursor | the folders it calls into, then their files, then the functions | the files it calls into, then the functions it uses in each | types as boxes, the functions that turn one into another on the arrows; `+` on a box opens its declaration under it |
| **both ways** | its callers left (tests dim, last), its calls right | the files outside it that call in, left; the files it calls out to, right; each with the names that cross | the same for a file | the functions that make it, left; the functions that take it, right. Not the types it is made of: the Types view has those |
| **folders** | who calls it, by folder, on the left (tests folded to a count); the folders its calls go into on the right; a box each holding the files and names, the count on the arrow, every arrow pointing at the function | its folders as boxes, the count of calls on each arrow | as a function's, the file's functions together | the folders that make it, left; that take it, right |
| **size** | each call by how much it goes on to reach | each file by how much it reaches outside itself, and how many outside call into it | each of its functions by how much it reaches, and how many call it | the files that use it most |

- **In folders, every arrow points at the row** (`design/mocks/mapz-fn-folders-in.png`,
  chosen 2026-11-01 over left to right and over no heads,
  `mapz-fn-folders-none.png`): its callers use it, the folders on the right
  are what it is built from. The other displays keep the rule below.
- **Arrows run from the caller to what it calls,** always left to right:
  who uses a thing is on its left, what it uses on its right. The first
  folders mock had only the right side, and its arrows read as pointing the
  wrong way; with the callers on the left too, the direction reads itself
  and Used by is in the same picture (`mapy-fn-folders-both.png`).
- **`T` shows and hides inputs and outputs,** in every display that has
  functions in it, and the choice stays. In the
  tree display it adds the takes and gives columns (`mapx-type-columns.png`); in
  both ways the makers show what they take and the takers what they give.
- Mocks: `design/mocks/mapy-fn-tree.png` (`T` off), `mapy-fn-tree-types.png` (`T`
  on), `mapy-fn-folders-both.png` (`mapy-fn-folders.png` was the right side
  only), `mapy-folder-both.png` (storage/),
  `mapy-type-both.png` (Model, `T` on), `mapy-folder-size.png` (run/), with
  `mapx-folders.png` (core/src/) and `mapx-type-graph.png` (Model's tree).

Filled 2026-11-01, drawn to be looked at (`design/mocks/src/map/ideas.py`, round three):
- **A folder's and a file's tree** go one rank down a level, as the tree on
  the left does: a folder, the folders it calls into, their files, then the
  functions; a file, the files it calls into, then the functions it uses in
  each (`design/mocks/mapz-folder-tree.png`, `mapz-file-tree.png`).
- **A file's both ways** is a folder's, for one file (`mapz-file-both.png`).
- **A file's folders** is a function's, the file's functions together
  (`mapz-file-folders.png`).
- **A type's folders** is its both ways gathered into folders: the folders
  that make it, left; that take it, right (`mapz-type-folders.png`).
- **A file's size** is a function's, for each of its functions
  (`mapz-file-size.png`, update.ts).
- **A type's size** is the files that use it most
  (`mapz-type-size-files.png`). By field (`mapz-type-size-fields.png`) was
  liked but dropped: it needs the server's references for every field,
  slow on a big type and not worth it.
- **A type's tree opens its boxes with `+`** (`mapz-type-tree-open.png`).

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
| `l` `h` | open and close a function's calls: in the tree, and in the Map's tree |
| `J` `K` | the code screen on it, and back to the very row or name; `3K` three back; back to the tree is `K` until there |
| `<Tab>` `<S-Tab>` | the next and previous view |
| `<C-Tab>` `<C-S-Tab>` | the next and previous display of what the cursor is in; from the tree, the pane's |
| `+` `-` | open and close the type under the cursor, one level a press |
| `>` `<` | a level more or less, in the Map |
| `T` | inputs and outputs in the Map |
| `n` `N` | the next and previous stop in what's shown: an import in the code, a use in Used by |
| `]c` `[c` | the next and previous change |
| `gc` | only what changed in the tree, and back |
| `s` | the tree's order: by folder, most used, most calling |
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

The tree's counts need `used_by` for every contract. Everything else is
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
| What a function takes and gives | `textDocument/hover` on each callable of the call graph, `scripts/types.lua` | one request a callable, once, in the background |

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
what each row takes and gives; the Types screen lists the types and follows
one. `design/types.md` says how they look.

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
  across the top. The page is three columns: the list 40, the contract 46,
  the seam the rest. Calls is two: the tree 86, its code the rest; Types the
  same, the list 86. All need 150 columns. Narrower than that is not
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

## From your code

`require('seam').here(how)`, `:SeamHere [overview|page|calls|called_by|types]`,
opens seam (`overview` is the tree, on the row) on what the word under the cursor names in a buffer of the repo.
`seam.here.resolve` is pure: the word, the file relative to the root and the
cursor line, against the model. A contract (an export with a use, the lens's
`all_uses` counted) declared in this file, the one holding the cursor if
several; else one this file uses; else the only one of that name. For calls
and called by a graph node first the same way (declared here, else one this
file's nodes call, else the only one), then a contract, then the innermost
node holding the cursor. For types, the flow of the repo type of that name.
Several and none here: the `/` picker of the screen asked for, holding the
word. `:Seam` on a repo seam is open on comes to its
tab as it was; another repo closes it first.

## Code layout

```
lua/seam/
  init.lua          :Seam, start and open the tree, here (from your code), what tests and view steps call
  here.lua          the word under the cursor in a file to the contract or function it names
  state.lua         the one table every screen reads: repo, models, tab, windows, what is shown
  index.lua         the model from a source's JSON, the lens applied, its types hung on, where indexes live, indexing
  theme.lua         highlight groups, hues
  lens.lua          the lens: patterns, what it hides, .seams/lens.json
  tree.lua          paths to rows: compaction, folding, the package bar
  code.lua          a code pane: copied lines, copied captures painted in view, enclosing function
  draw/init.lua     rows, putting them in a buffer, the pieces both screens share
  outline.lua       the tree as data: folders, files, functions, the calls under each, the orders, reveal
  views.lua         the pane's views, a registry: which rows each has, its displays, how it draws
  draw/outline.lua  the tree's rows and head, the pane's head and tabs
  hints.lua         the keys that act where the cursor is: the status line's three groups and the ? float
  screen_tree.lua   the tree's tab layout, its keys and the pane beside it
  draw/page.lua     the Built from and Used by tabs, the contract, the seam
  calls.lua         the call tree as data: rows down or up or from the top, the budget, what each key does, what / lists
  draw/calls.lua    the Calls screen: its head, the column titles, the tree, the call and the body, what each function takes and gives
  types.lua         types as data: a hover to what a function takes and gives, each repo type's flow, a signature fitted to a row
  draw/types.lua    the Types screen: every type the most travelled first, or one type's flow, and the code beside
  lens_panel.lua    the lens float and its keys
  picker.lua        the / float on every screen: a prompt, a list of picks, fuzzy matching
  screen.lua        the tab page, its windows, keys, status line, cursor to redraw
scripts/
  extract.lua       the treesitter index, in a headless nvim of its own
  types.lua         types.json: the TypeScript server's hover of each callable, in a headless nvim of its own
tests/
  calls.lua         the call tree's and the picker's specs, on a graph written by hand
  outline.lua       the tree's specs, on a graph written by hand
  here.lua          here's resolution specs, on a model written by hand
  types.lua         hovers parsed, flows built, signatures fitted, on a model written by hand
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
