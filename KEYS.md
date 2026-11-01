# Keys

Every key seam maps, in the buffers it owns. Keep this in step with the code.

## Anywhere

| Key | Does |
|---|---|
| `:Seam` | open the tree in its own tab page; when it is open on that repo, its tab as it was |
| `:Seam debug` | write what it knows to `stdpath('state')/seam-debug.txt` |
| `q` | close seam |
| `R` | ask the source again for everything shown |
| `gf` `gd` | that place in your own code: the tab you opened seam from (if it is gone, another that is not seam's, else a new one), the file in its window, the cursor on the line, centred, the jump in the jumplist. Seam's tab stays as it was. On a row naming a function or contract, its declaration; a file, its first line, or its first use in used by; a folder, nothing; on a line of code, that line; on a head, what the screen is about |

## From your code

In any buffer of the repo, on a name. Seam opens on its repo (indexing it first when it has no index or an old one), or comes to its tab, and `gf` there goes back to the buffer. The word names a contract declared in the file, else one the file uses, else the only one of that name; for calls, a function, component or class the same way, local ones too, else the function the cursor is in.

| Command | Suggested key | Does |
|---|---|---|
| `:SeamHere` `:SeamHere overview` | `<leader>kk` | the tree, its cursor on that function or contract where it lives (a contract that is no function, its file), the folders and file down to it opened. Several of that name and none here, or nothing: the tree's `/` holding the word. One the lens hides says so, and searches |
| `:SeamHere page` | `<leader>kp` | that contract's page; `K` the tree on it. A function that is no contract: its calls. Otherwise as above, the page's `/` holding the word for several |
| `:SeamHere calls` | `<leader>kc` | the call tree anchored on that function, down; several, the tree's `/` holding the word |
| `:SeamHere called_by` | `<leader>kC` | the same, up |
| `:SeamHere types` | | the flow of the type that word names; otherwise the types, their `/` holding the word |
| `:Seam` | `<leader>ko` | seam on the repo, as it was when it is open |
| `require('seam').from_top()` | `<leader>kt` | the call tree from where the code starts |
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
| `<Tab>` `<S-Tab>` | the pane's next and previous view; the one chosen stays as the cursor moves. Code is the only view so far |
| `<C-Tab>` `<C-S-Tab>` | the next and previous display of the pane's view; Code has one so far. Ghostty takes these for its own tabs until unbound (`keybind = ctrl+tab=unbind`) |
| `<C-d>` `<C-u>` | scroll the pane half a screen, the cursor staying in the tree |
| `<C-e>` `<C-y>` | scroll the pane a line |
| `/` | search the names: a float over the tree of every function and file it holds, the most used first; typing narrows it, fuzzily. `<C-n>` `<C-p>` `<Down>` `<Up>` move, `<CR>` shows the one picked where it lives, its folders and file opened; `<Esc>` `<C-c>` close it, nothing changed |
| `<CR>` | the page of the row's function, when it is a contract; `K` on it comes back to the tree. Until the views hold Built from and Used by |
| `c` | the Calls screen on the row's function; `K` back to the tree. Until the code screen |
| `t` | on a function, the repo types it takes and gives (one, its flow; several, the float holding them); elsewhere every type. `K` back to the tree. Until the Types view |
| `L` | the lens: what the tree shows. Files it hides from contracts leave the tree; calls follow built from |
| `S` | the next source, when there are several |
| `R` | read the index again |
| `gf` `gd` | in your own code: on a function's row, its declaration; on a file's, its first line; on a folder, nothing; on the head or the pane's head, the row's |
| `?` | every key on the screen in a float, grouped: this row, the pane, the tree, seam; `?` or `<Esc>` close it |
| `q` | close seam |

## The pane

Beside the tree: what the row is and where, the tabs of the views that have something for it (the one shown lit), and the view. Code: a function from its doc comment to its end, a file whole, with line numbers, each call in it underlined where it lives, as in the tree. A folder has no Code: the pane shows its head alone.

Seam maps no key to go into the pane: Vim's own window keys do.

| Key | Does |
|---|---|
| `<Esc>` | back to the tree |
| `<Tab>` `<S-Tab>` `<C-Tab>` `<C-S-Tab>` | as in the tree |
| `gf` `gd` | in your own code: on a line of code, that line; on the head, the row's |
| `?` | every key here |
| `q` | close seam |

## A contract's page

| Key | Does |
|---|---|
| `<Tab>` `<S-Tab>` | the other tab: Built from, Used by |
| `v` | Built from: as code, or as a list |
| `j` `k` | as a list: the next or previous seam. As code: the next or previous line, as in any code |
| `n` `N` `]]` `[[` | Built from as code: the next or previous name it is built from, round the ends; a count skips |
| `c` | as a list: only the contract; again, the contract and the seam |
| `s` | as a list: only the seam; again, the contract and the seam |
| `]]` `[[` | Used by: the next or previous use in this file |
| `J` | down a level: Built from, enter the page of the dependency shown. Nothing on Used by |
| `<CR>` | Built from: enter the page of the dependency shown. Used by: the file at the use, in your own code, as `gf` does |
| `gf` `gd` | in your own code: on the list, the dependency's declaration or the user file at its first use; in the code, the line under the cursor; on the head, the contract's declaration |
| `K` `<BS>` | up a level: the previous page, the Calls screen it was opened from, or the tree |
| `-` | straight to the tree from any depth, on this contract |
| `/` | another contract: a float over the left lists every one the lens lets through, types and constants too, the most used first; typing narrows it, fuzzily. `<C-n>` `<C-p>` `<Down>` `<Up>` move, `<CR>` opens its page on the tab shown, and `K` comes back; `<Esc>` `<C-c>` close it, nothing changed. In Built from as code too: `n` `N` are the names there, so Vim's search had no next |
| `t` | the flow of the contract, when it is a type a function takes or makes; `K` comes back to the page |
| `L` | the lens |

## Calls

The call tree of a function, component or class: what it calls all the way down, or what calls it all the way up, or everything from where the code starts.

| Key | Does |
|---|---|
| `j` `k` | the next or previous row |
| `l` | open the row one level, a `tests` row too; on an open row, its first child; on an `↑ also` row, where it is open |
| `h` | fold an open row, a folder or file too; on a folded or empty one, its parent |
| `O` | open everything under the row until the budget runs out |
| `H` | fold back to what the budget opened |
| `]` `[` | the next or previous sibling |
| `<CR>` | anchor on the row |
| `/` | anchor on any function: a float lists every one the lens lets through in contracts, the most used first; typing narrows it, fuzzily. `<C-n>` `<C-p>` `<Down>` `<Up>` move, `<CR>` anchors on it, the direction kept (from the top, calls), and `K` comes back; `<Esc>` `<C-c>` close it, nothing changed |
| `~` | flip: calls, called by |
| `J` | the page of the row's function, when it is a contract; `K` on it comes back to the tree as it was |
| `T` | the tree's columns: what each function takes and gives (`takes → gives`), or below, used by, file and line. Types once the repo has them; the choice stays |
| `t` | the repo types the row's function takes and gives: one, its flow; several, the `/` float over the tree holding them. `K` on the flow comes back to the tree |
| `K` `<BS>` | back: the previous anchor; from the first, the screen the tree was opened from (a type's flow), else seam's tree |
| `-` | straight to seam's tree, on the anchor |
| `C` | from the top |
| `L` | the lens: calls follow its built from column, callers its used by, the starts its contracts; what it hides has no row, the head counts it after the tabs (from the top, on its first line), `+12 hidden  L lens` |
| `<Tab>` | the code beside the tree: the types the row's function takes and gives, each its declaration (once the repo has types, and first); where it is called; or itself. The choice stays as the cursor moves, across anchors and back; what nothing calls shows its types or itself |
| `n` `N` | Called at: the next or previous place it is called, round the ends. Itself: the next or previous line that calls something, lit. A count skips. In the code beside it, `]]` `[[` |
| `gf` `gd` | in your own code: on a row, its function's declaration, or a file's first line; in the code beside, the line under the cursor |
| `q` | close |

`]` and `[` wait for a second `]` or `[` before going to the sibling.

The head gives the cursor back to the tree. The code beside it keeps it, to scroll and search; there `<Esc>` goes back to the tree, `<Tab>` does as in the tree, `]]` `[[` as `n` `N` do there, with the cursor on the line lit, and `K` `<BS>` `-` `q` do as in the tree; `gf` goes to the line under the cursor in your own code.

## Types

Every repo type a function takes or makes, the most travelled first; and one type's flow, the functions that make it, then the ones that take it. What each takes and gives is the TypeScript server's hover, asked once in the background beside the index.

| Key | Does |
|---|---|
| `j` `k` | the next or previous row; in a flow, its section titles too |
| `l` `<CR>` | the types: that type's flow |
| `<CR>` | a flow: the call tree on the row's function; `K` comes back to the flow |
| `t` | a flow: the row's function's other repo types: one, its flow; several, the `/` float holding them |
| `<Tab>` | a flow: the next section title, made by, taken by, round the end |
| `/` | another type: a float over the list of every one, the most travelled first; typing narrows it, fuzzily; `<CR>` its flow, `K` back; `<Esc>` closes it, nothing changed |
| `K` `<BS>` | back: the previous flow, the types, the call tree, page or tree it was opened from |
| `-` | straight to the tree |
| `gf` `gd` | in your own code: on a function's row, its declaration; on a type's row, a section title or the head, the type's declaration; in the code beside, the line under the cursor |
| `q` | close |

The code beside keeps the cursor to scroll and search; `<Esc>` gives it back to the list.

## The lens

A float over the tree, a page or the call tree. One row a rule: a folder or file picked, or a pattern typed. In each of contracts, built from and used by, a rule shows `only` what it holds, `hide`s it, or leaves the column be (`·`). It is kept in `.seams/lens.json` at the root of the repository. Each column it hides something from says how many on a line it already has, `+3 hidden  L lens`; nothing hidden gets a row.

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
