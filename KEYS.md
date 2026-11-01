# Keys

Every key seam maps, in the buffers it owns. Keep this in step with the code.

## Anywhere

| Key | Does |
|---|---|
| `:Seam` | open the tree in its own tab page; when it is open on that repo, its tab as it was |
| `:Seam debug` | write what it knows to `stdpath('state')/seam-debug.txt` |
| `q` | close seam |
| `R` | ask the source again for everything shown |
| `gf` `gd` | that place in your own code: the tab you opened seam from (if it is gone, another that is not seam's, else a new one), the file in its window, the cursor on the line, centred, the jump in the jumplist. Seam's tab stays as it was. On a row naming a function or contract, its declaration; a file, its first line; a folder, nothing; on a line of code or a place in Used by and Built from, that line; on a head, what the screen is about |

## From your code

In any buffer of the repo, on a name. Seam opens on its repo (indexing it first when it has no index or an old one), or comes to its tab, and `gf` there goes back to the buffer. The word names a contract declared in the file, else one the file uses, else the only one of that name; for calls and called_by, a function, component or class the same way, local ones too, else the function the cursor is in.

| Command | Suggested key | Does |
|---|---|---|
| `:SeamHere` `:SeamHere overview` | `<leader>kk` | the tree, its cursor on that function or contract where it lives (a contract that is no function, its file), the folders and file down to it opened. Several of that name and none here, or nothing: the tree's `/` holding the word. One the lens hides says so, and searches |
| `:SeamHere page` | `<leader>kp` | as `overview`, the pane on its Used by; a repo type, its Used by in the pane, the tree's cursor on its file. Several or nothing: the tree's `/` holding the word |
| `:SeamHere calls` | `<leader>kc` | the code screen on that function, the tree on its row under it; several, the tree's `/` holding the word |
| `:SeamHere called_by` | `<leader>kC` | the tree on that function's row, the pane on its Used by; several, the tree's `/` holding the word |
| `:SeamHere types` | | the tree, its pane on the Types view of the repo type that word names, the tree's cursor on the file you asked from; otherwise the tree's `/` holding the word |
| `:Seam` | `<leader>ko` | seam on the repo, as it was when it is open |
| `:Seam!` | `<leader>kr` | index the repo again |

The keys are not mapped by seam; the suggested ones are in the author's config.

## The tree

Folders, files, each file's functions in the file's order, and what each function calls, opened a level at a time in the order first written. On the left; the pane beside it shows the row under the cursor. Its left column carries the range's git signs (from HEAD to the working tree until the lens picks another start, named in the head when it is not HEAD): `+` new, `~` changed, `_` gone, a folder or file `~` when anything under it changed and `+` when it is new; a function or file gone keeps its row, struck through, where it was. A name from another file is underlined; from another package, underlined in that package's hue, its row with the package's bar. A call already open above it (recursion) is dim and does not open.

The status line says where you are on the left, and on the right only the keys that act there, each key lit with its word, in three groups: the row │ the pane │ seam. A narrow window drops seam's group first, then the pane's. When the range has changes, `]c [c` and `gc` lead the row's group and take the room of `h`, `s` and `/`, which stay in `?`, and `D` ends the pane's group. With the diff on, the status line starts `diff on`.

| Key | Does |
|---|---|
| `j` `k` | move; the pane follows the row |
| `l` | open the row: a folder, a file's functions, a function's calls; on an open row, its first row |
| `h` | close an open row; on a closed one, the row it hangs from |
| `s` | the order: by folder, most used first, most calling first. The sorted orders are every function in a flat list, each with its package's bar and two counts, used by and calls, the one it sorts by lit; tests and a file's top don't count. Back in the tree, the function the cursor was on is shown where it lives |
| `<Tab>` `<S-Tab>` | the pane's tabs, Code and Types, one then the other; from Used by, Built from or the Map, back to the tab you were on. The one chosen stays as the cursor moves, and a row without it (a folder has no Code) shows the other |
| `gu` `gb` `gm` | Used by, Built from, the Map in the pane, named after the tabs, lit; the same key again goes back to the tab you were on. Hinted only where the row has it |
| `<C-Tab>` `<C-S-Tab>` | the next and previous display of the pane's view, named after its tabs: Used by by file, by name, by user; Built from by file, by name, as signatures; Map tree, both ways, folders, size; Code with the diff on a row that changed, changes only, whole file; Types has one. The display chosen stays for its view. Ghostty takes these for its own tabs until unbound (`keybind = ctrl+tab=unbind`) |
| `D` | the diff, on or off, for the whole session and both screens: Code and Types show what the range changed, the code screen's left too. With nothing to draw it says why, there and in the status line: `nothing changed from HEAD to the working tree, L picks the range`, or `no git repository here` |
| `n` `N` | in Used by and Built from: into the pane, on its next or previous place, round the ends; a count skips |
| `<C-d>` `<C-u>` `<M-j>` `<M-k>` | scroll the pane half a screen, the cursor staying in the tree |
| `<C-e>` `<C-y>` | scroll the pane a line |
| `gc` | only what changed in the range, the folders down to it, and back; the status line says so |
| `]c` `[c` | the next and previous row that changed, round the ends |
| `/` | search the names: a float over the tree of every function, file and repo type it holds, the most used first; typing narrows it, fuzzily. `<C-n>` `<C-p>` `<Down>` `<Up>` move, `<CR>` shows the one picked where it lives, its folders and file opened; a type, its Types view in the pane, the tree's cursor where it was, until it moves; `<Esc>` `<C-c>` close it, nothing changed |
| `J` | the code screen on the row's function or file; `K` there comes back to this row |
| `>` `<` `T` | with the Map in the pane: on its tree, a level more or less; on its tree and both ways, the types on its functions, as in the pane |
| `L` | the lens: what the tree shows, and the range of changes. Files it hides from contracts leave the tree; a function's calls follow built from |
| `S` | the next source, when there are several |
| `R` | read the index again |
| `gf` `gd` | in your own code: on a function's row, its declaration; on a file's, its first line; on a folder, nothing; on the head or the pane's head, the row's |
| `?` | every key on the screen in a float, grouped: this row, the pane, the tree, seam; `?` or `<Esc>` close it |
| `q` | close seam |

## The pane

Beside the tree: what the row is and where, its tabs, Code and Types, those it has (the one shown lit), Used by, Built from or the Map after them, lit, when one is shown, and the view. A row with neither tab (none so far) shows the first of those it has.

- **Code**: a function from its doc comment to its end, a file whole, a type's declaration, with line numbers, each call in it underlined where it lives, as in the tree. A folder has no Code. **With the diff on** (`D`), on a row the range changed: a function's or type's own lines, a file whole, a folder's changed files one after another, about 400 lines at a time, `⋯ N more files` and `+` the next, removed lines where they were, unnumbered on red, added ones numbered on green, the words changed on each lit stronger, from codediff (else Vim's own diff). Changes only folds each unchanged run to `⋯ N lines unchanged` three lines from each change; whole file shows it all. A row gone has Code alone, its lines as they were, all removed. The pane's head says new, signature or body changed, and the types it names that changed.
- **Built from**: what the row draws on, from the index. By file: each file it draws on (its own first, `this file`), then each name once with its first use, the line of code in its colours, the name lit on it; for a file or folder, what each place sits in at the right. By name: each name in the order first used, its signature (or what it is) and its file, then that line. As signatures: what it calls, a line each in the Types view's shape, in the order called, then the types it names (and the values). A type: the types its fields are made of.
- **Used by**: who uses the row, from the index. By file: each file with how many places and the names it uses, the files with most places first, then each place's line of code in its colours, the names marked where they live, `in` the function or type it sits in at the right; four a file, then `⋯ N more`. A function: each place that calls or names it, its own file's too; a file: the other files naming its exports; a folder: the places outside it; a type (from `/`): where it is named. By name: each thing it hands out, the functions first with their signatures, then everyone who uses it. By user: each function that uses it as a line in the Types view's shape with its file, or each type, then what it uses.
- On a function whose signature or body changed in the range, **Used by** is who uses it now, then who used it at the range's start, each file saying how many of its declarations changed or that it is gone; its line as it was and as it is above them when its signature changed. Diff or not.
- Tests sort after the rest in every display of both.
- **Map**: a function, a folder, a file or a type (from `/`) drawn with what it reaches, in four displays named in the pane's head, the one shown bold. Tree: what it calls in tree lines, two levels to start; past the first level three a branch then `⋯ N more`; a name seen higher on its branch dim, stopping there; a folder's goes to the folders it calls into, their files, then the functions, a file's to the files it calls into, then the functions; a type's is types as boxes, the functions that turn one into another on the arrows, what makes it on the left, what gives it back written above it `↺`. Both ways: its callers on the left, tests dim and last, its calls on the right; a folder's or a file's, the files across its edge with the names that cross; a type's, its makers left and takers right. Folders: boxes of folders with their files and functions, the count of calls on each arrow, every arrow pointing at the function or file; a folder's own folders as boxes in ranks, an arrow over the top when it skips a rank and under when it goes back; a type's, the folders that make it left and take it right. Size: a bar each, as long as how much it goes on to reach: a function's calls, a file's functions with how many use each, a folder's files by what each reaches outside itself with how many outside use it, a type's files by how many times each names it. The status line says the name under the cursor.
- **Types**: a line a function, what it takes → its name → what it gives, the names in one column, a long one cut with `…`, a type parameter as what it extends, `Readonly<…>` left out, a blank line between. A function: its line, then each type it takes and gives written out under it, its declaration with its doc comment. A file: its exported functions, then those it keeps, then the types it declares. A folder: its functions used outside it, then its types used outside it with how many files use each. A type (from `/`): the functions that give it, then those that take it, the type lit, then its declaration. Each fact from the written signature (treesitter), else the TypeScript server's hover; until the server has answered, one dim line says why there are none. **With the diff on**: a function whose signature changed has its line as it was, `-` on red, over its line as it is, `+` on green, a new one its line `+`; each type written out or opened carries its own `+` and `-` lines and `~ changed` by its name.

Seam maps no key to go into the pane: Vim's own window keys do.

| Key | Does |
|---|---|
| `<Esc>` | back to the tree, or to the code on the code screen |
| `K` | on the code screen, back as there |
| `+` | in the Types view, on a type's name (and on the pane's head when it names one, and in the signature lines of Used by and Built from): its declaration as written, under the line it is named on, a bar down its left and its file and line at its top; on a name inside that, the next one nested under it, one level a press. On a function's line, off a name: the function as written, a part a line, the type parameters as written. On `⋯ N more` in Used by: the rest of that group's places. Hinted only where it acts |
| `-` | close the type the cursor is in, and what was opened inside it, the cursor back on the line naming it; on a function opened as written, close it; on a place `+` showed, hide them again, the cursor on `⋯ N more`. What is open stays for the row as long as seam is open |
| `n` `N` | in Used by and Built from: the next or previous place, round the ends; a count skips. The line under the cursor is lit |
| `]c` `[c` | with the diff on, in Code and Types: the next or previous change, round the ends |
| `l` | in the Map's tree, open the branch under the cursor a level deeper, or its `⋯ N more`; on a type's box, its takers; elsewhere in the Map, show the name under the cursor in the tree (a type, its Map in the pane) |
| `h` | in the Map's tree, close the branch under the cursor, or a box's takers |
| `>` `<` | in the Map's tree, a level more or less everywhere at once, what `l` and `h` did forgotten; kept for each row |
| `T` | in the Map's tree and both ways, the functions' takes and gives in columns, or what makers take and takers give; the choice stays across rows and displays, ` · types` in the status line |
| `J` | in the Map, the code screen on the function or file under the cursor |
| `+` `-` | on a box of a type's tree in the Map, its declaration opened under the drawing on a line down from the box, and closed |
| `<Tab>` `<S-Tab>` `gu` `gb` `gm` `<C-Tab>` `<C-S-Tab>` `D` | as in the tree |
| `gf` `gd` | in your own code: on a line of code or a place, that line; on a name's line in Used by and Built from, its declaration; on a file's line, the file (in Used by, at its first place); on a function's line, its declaration; on the head, the row's |
| `L` | the lens, as from the tree |
| `?` | every key here |
| `q` | close seam |

## The code

`J` on a function's or a file's row: its code on the left, as wide as it needs up to 112 columns and 60% of the screen, the pane keeping 40% or more, a longer line cut with `…` at its edge; the pane on the right as beside the tree. The head is the trail, `Seams › createRun() › createQueue()`; the code's own head says what it is and where, and its display. Each line its number and the source as written, its colours from treesitter; a name from another file underlined where it lives, as in the tree; after a value's name with no type written, its type, dim, from the declared return of the call that made it (nothing when that is not written), and after a function's parameters its return the same way.

With the diff on (`D`), the code is drawn with the range's changes inline, as the pane's Code shows them, whole: removed lines unnumbered on red, added numbered on green, the words changed lit stronger. The status line starts `diff on`.

The name under the cursor answers in the pane, or off a name the nearest on its line; a line with none, or a removed one, the function: a call its function (`called at line N`), a type its views, an imported value its file, a value, a parameter, a field or a method its Types view, headed with where it was made (`queue  made by createQueue, line 37  used 12 times`), what it is a parameter of, or the type it is in and its file. A field or method shows the type it is in with its lines lit, then each repo type it names written out under `is`, `takes` or `gives`. A value's or a call's later uses in the code are lit, the name and its line. The status line says the name under the cursor and its type.

| Key | Does |
|---|---|
| `j` `k` and Vim's motions | move; the pane follows the name under the cursor, else the nearest on the line |
| `n` `N` | the next or previous import: a name from another file, round the ends |
| `]c` `[c` | the next or previous change in the range, its lines numbered in the signs' colours, or with the diff on where its lines are |
| `J` | on a call or an imported name, the code screen on its function or file, on top of the trail |
| `K` | back: the previous on the trail, the cursor on the very name you left from; a count goes back more (`3K`); from the first, the tree on its row |
| `<S-Tab>` | the code, or its types: the function's line, then its values in the order made, `name  Type`, each function inside under its own line, indented; a file, its declarations. With the diff on, a line whose signature changed as it was, `-` on red, over itself, `+` on green, and a type opened with its own `+` `-` lines |
| `D` | the diff, on or off, here and in the pane, as beside the tree |
| `+` `-` | in its types, open or close the type under the cursor, as in the pane |
| `<Tab>` | the pane's other tab, Code or Types, for the name under the cursor; from an aside, back |
| `gu` `gb` `gm` | Used by, Built from, the Map in the pane, and back, as beside the tree |
| `<C-Tab>` `<C-S-Tab>` | the pane's next and previous display, as beside the tree |
| `<M-j>` `<M-k>` | scroll the pane half a screen, the cursor staying in the code |
| `/` | search the names, as in the tree: a function or a file goes on to its code screen, a type shows in the pane |
| `L` | the lens, as from the tree; closed, the code and the pane drawn again under it |
| `gf` `gd` | in your own code: the line under the cursor; on the head, what the code is |
| `?` | every key here |
| `q` | close seam |

The code's head gives the cursor back to the code. In the pane, the pane's keys; `<Esc>` and `K` as above.

## The lens

A float over the tree. Its first row is the range of changes, `changes  from HEAD  to the working tree`, always ending at the files as they are (to see another branch, check it out), what the signs, `gc`, `]c` `[c` and the diff follow; it is kept while seam is open. Then one row a rule: a folder or file picked, or a pattern typed. In each of contracts, built from and used by, a rule shows `only` what it holds, `hide`s it, or leaves the column be (`·`). It is kept in `.seams/lens.json` at the root of the repository. Each column it hides something from says how many on a line it already has, `+3 hidden  L lens`; nothing hidden gets a row.

| Key | Does |
|---|---|
| `j` `k` | the next or previous row |
| `c` `b` `u` | turn contracts, built from or used by on this row: only, hide, neither |
| `<Space>` | all three together: only, hide, neither; on `+ add`, the picker |
| `C` `B` `U` | clear contracts, built from or used by on every row |
| `X` | clear every row; the rows stay |
| `a` | the picker: folders, or type a pattern and it lists what it matches as you type; `<CR>` on the pattern takes all it matches, on a folder or file just that; `<Tab>` picks several. A new rule does nothing until a column is turned |
| `e` | edit this row's pattern; the panel lists what it matches as you type |
| `d` | delete this row |
| `f` | where the range starts: a picker of HEAD, the branches, the tags and the recent commits; what is typed narrows it, or is taken as the ref when git knows it (`HEAD~3`, a hash) |
| `x` | the range back to starting at HEAD |
| `q` `<Esc>` `L` | close |

A pattern is a file name (`*.test.*`), a folder anywhere (`tests/`), a path (`packages/*/scripts/**`, or `**checklist**` for that text anywhere in it), a regex on the path between slashes (`/\.(test|spec)\./`), or any other text found in the path. All but a regex ignore case unless they have a capital.
