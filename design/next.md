# Next: one tree, one set of views

Not locked. This is the behaviour we want next, written down to argue about
before any mock. It changes the explorer, Calls and the contract page, which
are locked, so each part starts with a mock in `mocks/` once we agree on it.

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
- **This file becomes `SPEC.md`** when the first slice lands, and the
  chosen mocks the locked screens in `design/`. KEYS.md is rewritten a
  screen at a time, in the slice that lands it.
- **Every fact from the index, the TypeScript server or git,** as now.
  Nothing on screen asks the server per field.

The slices, each usable on its own, each with its `make view` shots set
against its mocks, its tests, and KEYS.md in step:

1. **The tree and the pane.** One tree: folders, files, functions, `l` the
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
  in it. Mocks: `mocks/open-type-a.png` (StoredRecord opened in
  RunOptions), `open-type-b.png` (WalkthroughProgress opened inside it),
  `open-type-changed.png` (keyAction: InputContext lost `collapsed`, gained
  `dismiss`).
- **A folder** rolls its files up.

### Types: the higher view

Decided 2026-10-31, from the mocks `mocks/types-view-*.png`:

- **A blank line between functions, always.** An opened function keeps
  everything it opens together under its line, its parts one a line and
  indented, closed by its `}` or `)`, then the blank line before the next
  function (`mocks/types-view-opened.png`).
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
  `mocks/types-view-layout-a.png`). Tabs in the pane's head name them, the
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
  then each place with its line of code (`mocks/used-by-a.png`,
  `mocks/built-from-a.png`). Their other displays:
  - Used by, by name: each thing it hands out with its signature, then
    everyone who uses it (`mocks/used-by-b.png`).
  - Used by, by user: each function or type that uses it as a signature
    line, then what it uses (`mocks/used-by-c.png`).
  - Built from, by name, in the order the code first uses each, its
    signature and that line (`mocks/built-from-b.png`).
  - Built from, as signature lines of what it calls, in the order it calls
    them, then the types it names (`mocks/built-from-c.png`).
  - Tests sort after the rest in every display.
- **Scroll the pane from the left.** With the cursor in the tree, `<C-d>`
  and `<C-u>` scroll the pane half a screen, `<C-e>` and `<C-y>` a line, as
  they scroll a window in Vim and a preview in Telescope. In the pane they
  scroll the pane as usual. Every screen with a pane does the same.
- **A value's type follows its name, dim, upright** (`mocks/code-types-a.png`).
  An arrow function gets its return after its parameters. Nothing is added
  where the type is written.
- **The Code view's types display** is the function's signature line, then
  each value it makes as `name  Type` in the order made, each closure inside
  indented under its own signature line (`mocks/code-types-only-a.png`).
  It differs from the Types view, which shows only what the function takes
  and gives, each type written out.
- **The right side only when the code is on the left.** raf's lines are 88
  wide or less nine times in ten and 134 one in a hundred (measured), so
  the code wants about 110 columns with its types after the names. With the
  tree beside it there's no room for a third pane. So in the tree the Code
  view is the code alone, its types after the names, and `J` puts it on the
  left with the views on the right, where the cursor on a name fills them
  (`mocks/code-cursor-field.png`).
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
  lists only that file. (Decided 2026-11-01; `mocks/tree-file-kept.png` was
  not needed.)
- **`l` on a function** opens what it calls, in the order they run. `h`
  closes it. Each call has all the views and opens with `l` again.
- **Where a call lives: underlined.** Decided 2026-10-31 from six marks
  (`mocks/where-*.png`). A name from this file is plain. A name from another
  file is underlined. A name from another package is underlined in that
  package's hue, and its tree row carries the hue bar, as the explorer draws
  it today. The same mark in the tree and in the code beside it, on every
  use of the name, not only calls (`[conditions]`, `[detached]`). Names from
  outside the repo (`useRef`, `useMemo`) stay plain: they have no row.
  Mocks: `mocks/where-underline-core.png` (update()),
  `where-underline-react.png` (useOwnedRun() calling core's createRun).
- **A call already open above** (recursion) is dim and doesn't open.
- **Nothing beside a name.** The pane shows its types and counts; the tree
  stays narrow. (Decided 2026-10-31; `mocks/tree-cols-*.png` were not liked.)
- **`s` changes the order,** as `<Tab>` does in today's explorer: by folder
  (the tree), most used first, most calling first. The two sorted orders are
  a flat list of functions, each with its package's hue bar and two counts,
  used by and calls, the one it sorts by lit. Tests don't count.
  `mocks/tree-sort-used.png`, `tree-sort-calls.png`.
- **An opened function shows its calls, in the order they run,** and nothing
  around them: no closures, `if`s or `case`s (`mocks/tree-flow.png` was not
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
  mocks `mocks/open-type-*.png` (see "Types open in place" above).

## What changed (git)

A range of git, `from` and `to`. By default from `HEAD` to the working
tree: what isn't committed yet. Then:

- **The range lives in the lens** (`L`), on its first row, above the
  rules: `changes  from HEAD  to working tree`. `f` and `t` work from any row
  of the lens, the cursor where it is: each opens a picker of branches,
  tags and recent commits, a ref typed narrows it, and its first entry is
  the default (`HEAD`, the working tree), so picking it resets. The
  head names the range when it isn't the default
  (`mocks/changed-range.png`).
- **The tree carries git signs,** in the left column, as gitsigns draws
  them in the code: `+` new, `~` changed, `_` gone (a declaration gone
  keeps its row, struck through, where it was). A folder or file is `~`
  when anything under it changed, `+` when it's new. No words after the
  rows. The signs follow the range: an empty range, no signs, so they need
  no key to hide them (`mocks/changed-signs.png`).
- **`gc` keeps only what changed** in the tree: the changed rows and the
  folders and files above them (`mocks/changed-signs-only.png`). It works
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
  (`mocks/changed-signs.png`); and the whole file
  (`mocks/changed-whole.png`). codediff has no folding (its roadmap lists
  it), so the folds are seam's.
- **On a function or type,** the Changed view is its lines alone; on a
  file, the file; on a folder, its changed files one after another.
- **Used by on a changed function** lists who uses it now, then who used
  it at `from`. storageFailed lost its first parameter: five places in
  three files called it before, two in a new file now
  (`mocks/changed-lens.png`). A changed signature, against a changed body,
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
cheap). Open: the unit, packages, the folders under `src/`, or both by zoom.

## Not doing: state machines

A map of one field's states, from its union of literals, the places that
write each literal, and the checks around them. Dropped 2026-10-31: it works
only where the states are written as a union of literals and each write's
object can be typed from what is written around it. Several booleans
together, a plain `string`, state held in which closure is current or in an
empty list: too many ways code keeps state fall outside it.

## Mocks to make

Every surface this needs, each with the ways it could look. Each mock is a
picture from raf's real data, drawn with `mocks/src/lens/lib.py` as the
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
react's WaymarkRoot open for a call into another package (`src/tree/mock.py`):
`mocks/tree-where-a.png` (this file plain, another file underlined, another
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
from core): `mocks/where-{underline,dotted,italic,bold-here,glyph,file}-{core,react}.png`
(`src/tree/where.py`). **Underline chosen**, see "Where a call lives" in The
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
theirs: `mocks/map-a.png` (left to right, names only), `mocks/map-b.png`
(an indented tree of signature lines), `mocks/map-c.png` (columns),
`mocks/map-three.png` (B at three levels), `mocks/map-file.png` (run.ts's
imports, two levels, the names each takes), `mocks/map-type.png` (Model,
made by and taken by, then who takes what those give). Past the first
level a branch shows three and `⋯ 15 more`, opened with `l`. Measured:
createPage calls 18 and update 17, so at two levels the map is about 80
rows without that cut; the file map at two levels repeats state.ts and
problems.ts under nearly every file.

6c. **When it's too wide.** Scroll sideways; the levels past the screen
cut with `…`; or the first level only as names, the rest on `l`.

6d. **Sixteen more drawings** (`mocks/mapx-*.png`, from `src/map/ideas.py`
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

- **In folders, every arrow points at the row** (`mocks/mapz-fn-folders-in.png`,
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
- Mocks: `mocks/mapy-fn-tree.png` (`T` off), `mapy-fn-tree-types.png` (`T`
  on), `mapy-fn-folders-both.png` (`mapy-fn-folders.png` was the right side
  only), `mapy-folder-both.png` (storage/),
  `mapy-type-both.png` (Model, `T` on), `mapy-folder-size.png` (run/), with
  `mapx-folders.png` (core/src/) and `mapx-type-graph.png` (Model's tree).

Filled 2026-11-01, drawn to be looked at (`src/map/ideas.py`, round three):
- **A folder's and a file's tree** go one rank down a level, as the tree on
  the left does: a folder, the folders it calls into, their files, then the
  functions; a file, the files it calls into, then the functions it uses in
  each (`mocks/mapz-folder-tree.png`, `mapz-file-tree.png`).
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

Mocked on createRun: `mocks/code-types-a.png`, `-b`, `-c` (7a, the cursor
on `queue`, its later uses lit), `mocks/code-types-only-a.png` and `-b`
(7b), `mocks/code-cursor-field.png` (7d). A value's type is the name in the
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
is reachable here: `mocks/changed-signs.png`, `-signs-only`, `-whole`, `-range` and
`-lens`; signs, words and colours were tried for 8b and signs kept. A declaration is new, gone or changed by
its text under treesitter; a changed function's signature changed when its
written parameters or return differ, else its body. Used by on a changed
signature lists who uses it now and who used it at the base: storageFailed
lost its first parameter, five places in three files called it at the
base, two in a new file call it now.

### 9. Boundaries

- A. The table of packages or folders against each other.
- **B, chosen.** Not its own thing: a folder's Map view, the folders
  display (`mocks/mapx-folders.png`), with both ways for what crosses a
  folder's edge (`mocks/mapy-folder-both.png`). The table goes.
- C. Not its own thing: a folder's Types view.

A picture of each on raf's packages. If B or C reads as well, the table
goes.

### 10. Keys

One picture of the status line hints on each screen, and KEYS.md drafted
from the chosen mocks.

**Hints chosen 2026-11-01: B, with `?`** (`mocks/keys-*-b.png`,
`keys-tree-help.png`, `src/keys/mock.py`). The status line names where you
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
