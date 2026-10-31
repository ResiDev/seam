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
| **Map** | the folders it draws on, then theirs; or the other way | the files it imports from, then theirs; or the other way | what it calls, then what those call, levels as asked | the functions that take it, the types they give, on from those |
| **Changed** | its files' diffs | the file's diff | its diff since the base | its declaration's diff |

- **Used by is where it's called.** The cursor on a use shows the caller's
  code around that line, so "used by" and "called at" are one view.
- **Types expand.** One key opens the type under the cursor a level deeper
  and one closes it, using the hover verbosity that ts-expand-hover uses in
  your editor. So `Queue` opens into `run`, `invoke` and `fail` with their
  signatures.
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
- **One key opens the line under the cursor as written:** the parts it cut,
  its type parameters, everything. The same key closes it. Which key is
  still open.
- **`Readonly<…>` is left out,** since raf wraps every type in it.
- **A function's takes and gives are written out under its line,** each
  type's declaration with its doc comment, open by default.
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
  run.ts                                             3 exports  12 kept
    createRun()          (RunOptions) → Run
      problemReporter()  (ProblemHandlers) → ReportProblem
      createQueue()      (string, ReportProblem) → Queue
      starting()         () → RunState
      initialModel()     (Given, UserRecord) → Model
      runStateOf()       (Model, Given) → RunState
        …
```

- **A file's rows** are its exports, then what it keeps to itself, dimmer.
- **`l` on a function** opens what it calls, in the order they run. `h`
  closes it. Each call has all the views and opens with `l` again.
- **Where a call lives, without saying it.** A call into this file is plain.
  A call into another file is underlined, as imports are in the code. A
  call into another package carries that package's hue bar, as the explorer
  draws it today.
- **A call already open above** (recursion) is dim and doesn't open.
- **Each row can show what it takes and gives,** as above, or its used by
  and built from counts. One key flips them, and the choice stays, like `T`
  in Calls.

Open:
- Should the rows under a function show the `if`, `case`, `later` and
  `return` they sit under, without the conditions? trace.lua computes it.
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
- `n`/`N`: every name, or only the imports as today?
- The key for code or types. `v` already turns code into the list, so it
  could cycle code, types, list.
- The keys that open and close a type. Your editor uses `K` and `J`, which
  are back and enter here. `zo`/`zc` read like opening a fold.

## What changed (git)

Pick a base, such as `master` or a commit. Then:

- **The tree marks what changed.** A file, function or type whose lines
  changed since the base is marked. A function whose signature changed is
  marked differently from one whose body changed. That's measured by
  parsing the base's version of the file (`git show base:path`) with
  treesitter and comparing what it takes and gives.
- **A lens, "only what changed".** The tree keeps only the changed rows and
  the folders and files above them.
- **The Changed view** shows a row's diff.
- **Used by on a changed function** is what the change can break. A
  changed signature with three callers lists those three, with the code at
  each.

That's the check you do on an agent's work, on the map you already read:
what it touched, whether it changed a contract, and who relies on it.

Open: is the base chosen once per repo, or each time? `master` by default?

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
only, what it keeps seen through `l`.

### 2. Switching views

- A. Tabs in the pane's head, `Code  Types  Built from  Used by  Map
  Changed`, the one shown lit, as the Calls pane does today.
- B. Only the view's name in the head, the others in the status line's key
  hints.
- C. Each view on its own key (`c`, `t`, `b`, `u`, `m`, `d`) and `<Tab>` as
  well.

### 3. The Types view

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

- A. **By level,** as ts-expand-hover does: the whole type re-shown one
  level deeper each time.
- B. **By field,** a tree: `l` on one field opens only its type under it.
- C. Both: A from the head, B on a field.

A picture of `Queue` and of `Model`, each two levels open.

### 5. The Used by view

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

6c. **When it's too wide.** Scroll sideways; the levels past the screen
cut with `…`; or the first level only as names, the rest on `l`.

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

### 9. Boundaries

- A. The table of packages or folders against each other.
- B. Not its own thing: a folder's Map view, rolled up.
- C. Not its own thing: a folder's Types view.

A picture of each on raf's packages. If B or C reads as well, the table
goes.

### 10. Keys

One picture of the status line hints on each screen, and KEYS.md drafted
from the chosen mocks.
