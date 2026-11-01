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

Folders, files, each file's functions in the file's order, and what each function calls, opened a level at a time in the order first written. On the left; the pane beside it shows the row under the cursor. A name from another file is underlined; from another package, underlined in that package's hue, its row with the package's bar. A call already open above it (recursion) is dim and does not open.

The status line says where you are on the left, and on the right only the keys that act there, each key lit with its word, in three groups: the row │ the pane │ seam. A narrow window drops seam's group first, then the pane's.

| Key | Does |
|---|---|
| `j` `k` | move; the pane follows the row |
| `l` | open the row: a folder, a file's functions, a function's calls; on an open row, its first row |
| `h` | close an open row; on a closed one, the row it hangs from |
| `s` | the order: by folder, most used first, most calling first. The sorted orders are every function in a flat list, each with its package's bar and two counts, used by and calls, the one it sorts by lit; tests and a file's top don't count. Back in the tree, the function the cursor was on is shown where it lives |
| `<Tab>` `<S-Tab>` | the pane's next and previous view: Code, Types, Built from, Used by; the one chosen stays as the cursor moves, and a row without it (a folder has no Code) shows the next it has |
| `<C-Tab>` `<C-S-Tab>` | the next and previous display of the pane's view, named after its tabs: Used by by file, by name, by user; Built from by file, by name, as signatures; Code and Types have one. The display chosen stays for its view. Ghostty takes these for its own tabs until unbound (`keybind = ctrl+tab=unbind`) |
| `n` `N` | in Used by and Built from: into the pane, on its next or previous place, round the ends; a count skips |
| `<C-d>` `<C-u>` | scroll the pane half a screen, the cursor staying in the tree |
| `<C-e>` `<C-y>` | scroll the pane a line |
| `/` | search the names: a float over the tree of every function, file and repo type it holds, the most used first; typing narrows it, fuzzily. `<C-n>` `<C-p>` `<Down>` `<Up>` move, `<CR>` shows the one picked where it lives, its folders and file opened; a type, its Types view in the pane, the tree's cursor where it was, until it moves; `<Esc>` `<C-c>` close it, nothing changed |
| `J` | the code screen on the row's function or file; `K` there comes back to this row |
| `L` | the lens: what the tree shows. Files it hides from contracts leave the tree; a function's calls follow built from |
| `S` | the next source, when there are several |
| `R` | read the index again |
| `gf` `gd` | in your own code: on a function's row, its declaration; on a file's, its first line; on a folder, nothing; on the head or the pane's head, the row's |
| `?` | every key on the screen in a float, grouped: this row, the pane, the tree, seam; `?` or `<Esc>` close it |
| `q` | close seam |

## The pane

Beside the tree: what the row is and where, the tabs of the views that have something for it (the one shown lit), and the view.

- **Code**: a function from its doc comment to its end, a file whole, a type's declaration, with line numbers, each call in it underlined where it lives, as in the tree. A folder has no Code.
- **Built from**: what the row draws on, from the index. By file: each file it draws on (its own first, `this file`), then each name once with its first use, the line of code in its colours, the name lit on it; for a file or folder, what each place sits in at the right. By name: each name in the order first used, its signature (or what it is) and its file, then that line. As signatures: what it calls, a line each in the Types view's shape, in the order called, then the types it names (and the values). A type: the types its fields are made of.
- **Used by**: who uses the row, from the index. By file: each file with how many places and the names it uses, the files with most places first, then each place's line of code in its colours, the names marked where they live, `in` the function or type it sits in at the right; four a file, then `⋯ N more`. A function: each place that calls or names it, its own file's too; a file: the other files naming its exports; a folder: the places outside it; a type (from `/`): where it is named. By name: each thing it hands out, the functions first with their signatures, then everyone who uses it. By user: each function that uses it as a line in the Types view's shape with its file, or each type, then what it uses.
- Tests sort after the rest in every display of both.
- **Types**: a line a function, what it takes → its name → what it gives, the names in one column, a long one cut with `…`, a type parameter as what it extends, `Readonly<…>` left out, a blank line between. A function: its line, then each type it takes and gives written out under it, its declaration with its doc comment. A file: its exported functions, then those it keeps, then the types it declares. A folder: its functions used outside it, then its types used outside it with how many files use each. A type (from `/`): the functions that give it, then those that take it, the type lit, then its declaration. Each fact from the written signature (treesitter), else the TypeScript server's hover; until the server has answered, one dim line says why there are none.

Seam maps no key to go into the pane: Vim's own window keys do.

| Key | Does |
|---|---|
| `<Esc>` | back to the tree, or to the code on the code screen |
| `K` | on the code screen, back as there |
| `+` | in the Types view, on a type's name (and on the pane's head when it names one, and in the signature lines of Used by and Built from): its declaration as written, under the line it is named on, a bar down its left and its file and line at its top; on a name inside that, the next one nested under it, one level a press. On a function's line, off a name: the function as written, a part a line, the type parameters as written. On `⋯ N more` in Used by: the rest of that group's places. Hinted only where it acts |
| `-` | close the type the cursor is in, and what was opened inside it, the cursor back on the line naming it; on a function opened as written, close it; on a place `+` showed, hide them again, the cursor on `⋯ N more`. What is open stays for the row as long as seam is open |
| `n` `N` | in Used by and Built from: the next or previous place, round the ends; a count skips. The line under the cursor is lit |
| `<Tab>` `<S-Tab>` `<C-Tab>` `<C-S-Tab>` | as in the tree |
| `gf` `gd` | in your own code: on a line of code or a place, that line; on a name's line in Used by and Built from, its declaration; on a file's line, the file (in Used by, at its first place); on a function's line, its declaration; on the head, the row's |
| `?` | every key here |
| `q` | close seam |

## The code

`J` on a function's or a file's row: its code on the left, as wide as it needs up to 112 columns, a longer line cut with `…` at its edge; the pane on the right as beside the tree. The head is the trail, `Seams › createRun() › createQueue()`; the code's own head says what it is and where, and its display. Each line its number and the source as written, its colours from treesitter; a name from another file underlined where it lives, as in the tree; after a value's name with no type written, its type, dim, from the declared return of the call that made it (nothing when that is not written), and after a function's parameters its return the same way.

The name under the cursor answers in the pane: a call its function (`called at line N`), a type its views, an imported value its file, a value, a parameter, a field or a method its Types view, headed with where it was made (`queue  made by createQueue, line 37  used 12 times`), what it is a parameter of, or the type it is in and its file. A field or method shows the type it is in with its lines lit, then each repo type it names written out under `is`, `takes` or `gives`. A value's or a call's later uses in the code are lit, the name and its line. The status line says the name under the cursor and its type.

| Key | Does |
|---|---|
| `j` `k` and Vim's motions | move; the pane follows the name under the cursor |
| `n` `N` | the next or previous import: a name from another file, round the ends |
| `J` | on a call or an imported name, the code screen on its function or file, on top of the trail |
| `K` | back: the previous on the trail, the cursor on the very name you left from; a count goes back more (`3K`); from the first, the tree on its row |
| `<C-Tab>` `<C-S-Tab>` | the code, or its types: the function's line, then its values in the order made, `name  Type`, each function inside under its own line, indented; a file, its declarations |
| `+` `-` | in its types, open or close the type under the cursor, as in the pane |
| `<Tab>` `<S-Tab>` | the pane's next and previous view of the name under the cursor |
| `/` | search the names, as in the tree: a function or a file goes on to its code screen, a type shows in the pane |
| `gf` `gd` | in your own code: the line under the cursor; on the head, what the code is |
| `?` | every key here |
| `q` | close seam |

The code's head gives the cursor back to the code. In the pane, the pane's keys; `<Esc>` and `K` as above.

## The lens

A float over the tree. One row a rule: a folder or file picked, or a pattern typed. In each of contracts, built from and used by, a rule shows `only` what it holds, `hide`s it, or leaves the column be (`·`). It is kept in `.seams/lens.json` at the root of the repository. Each column it hides something from says how many on a line it already has, `+3 hidden  L lens`; nothing hidden gets a row.

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
| `q` `<Esc>` `L` | close |

A pattern is a file name (`*.test.*`), a folder anywhere (`tests/`), a path (`packages/*/scripts/**`, or `**checklist**` for that text anywhere in it), a regex on the path between slashes (`/\.(test|spec)\./`), or any other text found in the path. All but a regex ignore case unless they have a capital.
