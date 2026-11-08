# Keys

Every key seam maps, in the buffers it owns. Keep this in step with the code.

## Anywhere

| Key | Does |
|---|---|
| `:Seam` | open the tree in its own tab page; when it is open on that repo, its tab as it was |
| `:Seam debug` | write what it knows to `stdpath('state')/seam-debug.txt` |
| `q` | close seam |
| `R` | ask the source again for everything shown |
| `gf` `gd` | that place in your own code: the tab you opened seam from (if it is gone, another that is not seam's, else a new one), the file in its window, the cursor on the line, centred, the jump in the jumplist. Seam's tab stays as it was. On a row naming a function or contract, its declaration; a file, its first line; a folder, nothing; on a line of code, that line; on a head, what the screen is about |

## From your code

In any buffer of the repo, on a name. Seam opens on its repo (indexing it first when it has no index or an old one), or comes to its tab, and `gf` there goes back to the buffer. The word names a contract declared in the file, else one the file uses, else the only one of that name; for calls and called_by, a function, component or class the same way, local ones too, else the function the cursor is in.

| Command | Suggested key | Does |
|---|---|---|
| `:SeamHere` `:SeamHere overview` | `<leader>kk` | the tree, its cursor on that function or contract where it lives (a contract that is no function, its file), the folders and file down to it opened. Several of that name and none here, or nothing: the tree's `/` holding the word. One the lens hides says so, and searches |
| `:SeamHere page` | `<leader>kp` | as `overview`, the pane on its Map; a repo type, its Map in the pane, the tree's cursor on its file. Several or nothing: the tree's `/` holding the word |
| `:SeamHere calls` | `<leader>kc` | the code screen on that function, the tree on its row under it; several, the tree's `/` holding the word |
| `:SeamHere called_by` | `<leader>kC` | the tree on that function's row, the pane on its Map; several, the tree's `/` holding the word |
| `:SeamHere types` | | the tree, its pane on the Types view of the repo type that word names, the tree's cursor on the file you asked from; otherwise the tree's `/` holding the word |
| `:SeamShow <target>` | | seam on the place a link names: `src/store.ts:save@Map`, `type:Card@Types`, `src/billing/@Map/library` (SPEC.md, From a link). One that does not resolve says why, the tree's `/` holding its name |
| `:Seam` | `<leader>ko` | seam on the repo, as it was when it is open |
| `:Seam!` | `<leader>kr` | index the repo again |

The keys are not mapped by seam; the suggested ones are in the author's config.

### The view you came from (prototype)

Asked to, opening seam from a buffer outside seam's tab holds that buffer: `require('seam').show(target, { from = buf })` (a thread's links), `show(target, { hold = true })`, or `here` and `:Seam` with `vim.g.seam_hold = true`. Opened from outside any other way, it lets go and the tab goes. Held, it is one more tab after seam's, named by the buffer's `b:seam_name`, else its file. The pane's window shows the buffer itself, its own keys and options; seam maps nothing in it. One at a time, the last arrived from; from seam's own tab nothing changes.

| Key | Does |
|---|---|
| `<Tab>` | on the tree or the code, to that tab and away again, as the other tabs |
| `<C-w>l` | from the tree or the code, into the buffer held |
| `<C-w>h` | from it, back to the tree or the code |

## The tree

Folders, files, what each file declares at its top in the file's order (its functions; its types and values once `t` `v` turn them on), and what each function or value calls, opened a level at a time in the order first written. On the left; the pane beside it shows the row under the cursor. Its left column carries the range's git signs (from HEAD to the working tree until the lens picks another start, named in the head when it is not HEAD): `+` new, `~` changed, `_` gone, a folder or file `~` when anything under it changed and `+` when it is new; a function or file gone keeps its row, struck through, where it was. A name from another file is underlined; from another package, underlined in that package's hue, its row with the package's bar. A call already open above it (recursion) is dim and does not open.

The status line says where you are on the left, and on the right only the keys that act there, each key lit with its word, in three groups: the row │ the pane │ seam. A narrow window drops seam's group first, then the pane's. When the range has changes, `]c [c` and `gc` lead the row's group and take the room of `h`, `s` and `/`, which stay in `?`, and `D` ends the pane's group. With the diff on, the status line starts `diff on`.

| Key | Does |
|---|---|
| `j` `k` | move; the pane follows the row |
| `l` | open the row: a folder, a file's functions, a function's calls; on an open row, its first row |
| `h` | close an open row; on a closed one, the row it hangs from |
| `f` `t` `v` | what a file lists: its functions, its types, its values, each on or off for the session; functions alone at first. A type is in the code's type colour and does not open, a value is plain and opens to what it calls, as a function does. The bar over the tree lights the keys that are on, `f t v  e  #`, each in the colour its names have in code; anything but functions alone, the status line's left says what is on, `types · values` |
| `e` | a file's exports only, whichever of `f` `t` `v` are on, or all it declares again; a function's calls stay all of them. The status line's left ends `exports only` |
| `s` | the order: by folder, most used first, built from most first. The sorted orders are one list, no folders or files: every function, type and value the files list, as `f` `t` `v` `e` have them, the most used, or the one built from most, first, the tree's order between equals; each name with its file after it, dim, and its two counts, used by and built from, the one it sorts by lit; the tree wider while it shows. A function's used by is the functions and values calling it, its built from those it calls, each once; a value's used by the functions and values naming it, its built from what it calls; a type's used by the functions, values and types naming it, its built from blank; tests and a file's top don't count, and the lens is kept. A function or value opens to its calls, sorted the same way. The cursor stays on its row; from a file, on the file's first name in the list, from a folder on the list's first; back in the tree, a name's file is opened |
| `#` | in the tree's own order, every row's two counts, used by and built from, or none again, for the session; a file's or folder's are what outside it calls into it or names its values and types, and what outside it it calls. Lit on the bar over the tree when the rows have their counts; in a sorted order it does nothing, the list always having them |
| `<Tab>` | the pane's next tab: Code, Types, Map, those the row has. The one chosen stays as the cursor moves, and a row without it (a folder has no Code) shows the first it has; on the code screen, where Code and Types are the only tabs, the tab you were on there |
| `gm` | straight to the Map, lit among the tabs; the same key again goes back to the tab you were on. In `?`; beside the tree it is a tab, so the status line leaves it out |
| `<S-Tab>` | the next display of the pane's view, named after its tabs: Map folder, type, library (no library on a type); Code with the diff on a row that changed, changes only, whole file; Types has one. The display chosen stays for its view |
| `D` | the diff, on or off, for the whole session and both screens: Code and Types show what the range changed, the code screen's left too. With nothing to draw it says why, there and in the status line: `nothing changed from HEAD to the working tree, L picks the range`, or `no git repository here` |
| `<C-d>` `<C-u>` `<M-j>` `<M-k>` | scroll the pane half a screen, the cursor staying in the tree |
| `<C-e>` `<C-y>` | scroll the pane a line |
| `gc` | only what changed in the range, the folders down to it, and back; the status line says so |
| `]c` `[c` | the next and previous row that changed, round the ends |
| `/` | search the names: a float over the tree of every function, file and repo type it holds, the most used first; typing narrows it, fuzzily. `<C-n>` `<C-p>` `<Down>` `<Up>` move, `<CR>` shows the one picked where it lives, its folders and file opened; a type, its Types view in the pane, the tree's cursor where it was, until it moves; `<Esc>` `<C-c>` close it, nothing changed |
| `J` | the code screen on the row's function, type or file; `K` there comes back to this row |
| `T` | with the Map in the pane, by folder: names only, as it opens, or each signature, as in the pane |
| `L` | the lens: what the tree shows, and the range of changes. Files it hides from contracts leave the tree; a function's calls follow built from |
| `S` | the next source, when there are several |
| `R` | read the index again |
| `gf` `gd` | in your own code: on a function's row, its declaration; on a file's, its first line; on a folder, nothing; on the head or the pane's head, the row's |
| `?` | every key on the screen in a float, grouped: this row, the pane, the tree, seam; `?` or `<Esc>` close it |
| `q` | close seam |

## The pane

Beside the tree: what the row is and where, its tabs, Code, Types and Map, those it has, the one shown lit (`design/mocks/keys-tree-a.png`, its Changed tab now the diff on `D`), and the view. On the code screen the tabs are Code and Types, and the Map, when shown, is named after them, lit (`design/mocks/tabs-aside.png`).

- **Code**: a function from its doc comment to its end, a file whole, a type's declaration, with line numbers, each call in it underlined where it lives, as in the tree. A folder has no Code. **With the diff on** (`D`), on a row the range changed: a function's or type's own lines, a file whole, a folder's changed files one after another, about 400 lines at a time, `⋯ N more files` and `+` the next, removed lines where they were, unnumbered on red, added ones numbered on green, the words changed on each lit stronger, from codediff (else Vim's own diff). Changes only folds each unchanged run to `⋯ N lines unchanged` three lines from each change; whole file shows it all. A row gone has Code alone, its lines as they were, all removed. The pane's head says new, signature or body changed, and the types it names that changed.
- **Map**: a function, a folder, a file or a type (from `/`) drawn with what it reaches, in three displays named in the pane's head, the one shown bold (`design/mocks/map9-folder.png`, `map9-type.png`, `map12-libraries.png`). Over each side what it is to the row: `built from` and `used by`, a type's `made by` and `taken by`; a value's used by is the functions and values naming it. Folder and type draw the flow: what the row calls above, each a line, gathered under heads, a line down the left through the heads into the row, written as what it takes → its name → what it gives, and from the middle of its name on down under the row to its callers, gathered the same way, tests dim and last. Nothing is cut: each signature follows its name and a long one goes on under itself, a long object as the names of its fields; an empty row between heads and between the files the calls are in. Any other row past the pane, a long file name and its names in both ways, a long head, goes on right, unwrapped and with no `…`, for `zl` `zh` to scroll to; after a long file name its names keep 30 columns. Folder: each head a folder, each line its file and the line it is declared on (the file once, the lines under it), the name, what it takes, what it gives; a caller its file and the line of its call. Type: the functions in groups by the type they give back, the repo's types first, builtins, then nothing; closed, a group is its names and the type, `loading(), begin()  →  State<Step>`, three names then `+2 more`, `→  nothing`; open, the type over its lines, each line its folder and file, the name, what it takes, `→` and the type. A folder's or a file's flow is the names crossing its edge, those it calls out to above; a type's its makers above, its takers below. Folder opens names only, today's both ways, each side a folder, its files and each file's names after them, an empty row between folders; `T` the signatures. **Too tall for the pane**, no name is left out: whole groups close, the ones with the fewest names first, until it fits the pane less the foot's least share, then any closed one that fits in the rows left opens again, so one group too tall does not close the rest; each side of both ways on its own, as they are centred on the row, the flow's above and below sharing it. A closed group is one line, `▸`, its head and how many names in how many files, `▸ queue/src/  14 names in 3 files`; `l` opens it for the row, and it is not closed again to fit: the pane scrolls; `h` on its head closes it again. **Library**, on a function, a file or a folder: each library the row takes from, a package from outside the repo (`react`, `roughjs`), a head, the most used first, a line down through them into the row (`map13-libraries-grouped.png`). Under it each name taken from it (`useState`, `RoughCanvas`), used most first, tests last: the name once, then the functions using it, the file once and the line each first uses it on, tests dim; a use outside every function names the declaration holding it, `listMessages` of `export const listMessages = query({ … })`, or in a test the test's title, `'counts each day'`, and only a bare statement, `vi.mock(…)`, is `(top level)`; on a function, each name and every line it uses it on. Closed, a library is `▸ react  15 names in 15 files`. A row that takes nothing from a library says so; an index older than format 4 says `:Seam!` indexes it again. Groups close to fit as in the flow. The foot (below) tells the name under the cursor, a call or a caller with the line that calls it in its colours and what that line sits in; on a library's name what the server says of it where it is first used. The status line says the name under the cursor.
- **Types**: a line a function, what it takes → its name → what it gives, the names in one column, a long one cut with `…`, a type parameter as what it extends, `Readonly<…>` left out, a blank line between. A function: its line, then each type it takes and gives written out under it, its declaration with its doc comment. A file: its exported functions, then those it keeps, then the types it declares. A folder: its functions used outside it, then its types used outside it with how many files use each. A type (from `/`): the functions that give it, then those that take it, the type lit, then its declaration. Each fact from the written signature (treesitter), else the TypeScript server's hover; until the server has answered, one dim line says why there are none. **With the diff on**: a function whose signature changed has its line as it was, `-` on red, over its line as it is, `+` on green, a new one its line `+`; each type written out or opened carries its own `+` and `-` lines and `~ changed` by its name.
- **The foot**: beside the tree, wherever the pane's cursor rests on a repo function or a repo type, in its Map, Types and Code, a window over the pane's last rows (over its first rows when the cursor is on one of those), at least 15% of it and at most half, in its colours, a rule and an empty row over it, an empty row under, its lines wrapped, tells it in full. A function: its signature as its file writes it, in its colours, comments left out, a destructured parameter's names on one line, and where it lives; where the file does not write what it gives, `→` and what the server says it gives, an object a field a line. A type: where it is declared, how many make and take it, and its declaration as written, in its colours, comments left out, as long as the foot holds, then `⋯ N more lines`. A type from a package or TypeScript's lib (`RoughCanvas`, `ReactNode`), in the code or a signature, the same once the TypeScript server has said where it is: `type in roughjs`, `type in @types/react`, `type in TypeScript’s lib.dom.d.ts`; nothing until then, and nothing without a server. A value no type is written for (`const root = createRoot(…)`), or a package's function (`createRoot`, `useNavigate`): what the server says of it, `const root: Root`, in its colours, a function with the package it is in, a value then its type's declaration, `Root   type in @types/react-dom` (of `A & B`, A where the function that made it writes it). A function's line in Types, off a type's name, is that function. A repo type alias or interface with no type parameters is told at three levels, named at the right of its head, the one shown bold (`design/mocks/foot14-levels.png`): as written; flat, one object, every field it has, the names it uses kept (the server's hover of type-fest's `Simplify`, `{ [K in keyof T]: T[K] } & {}`); in full, every alias spelled out (the same hover at verbosity 1), `| undefined` after a `?:` left out. `=` goes to the next, round, for the session; the server is asked only past as written, `asking the TypeScript server` until it says, and a type it says is no object (a function's) keeps as written alone. It follows the cursor, and goes when the cursor leaves the pane. The code screen has none: its pane tells the name in full, a package type's declaration under a value's type included.

Seam maps no key to go into the pane: Vim's own window keys do.

| Key | Does |
|---|---|
| `<Esc>` | back to the tree, or to the code on the code screen |
| `K` | on the code screen, back as there |
| `+` | in the Types view, on a type's name (and on the pane's head when it names one): its declaration as written, under the line it is named on, a bar down its left and its file and line at its top; on a name inside that, the next one nested under it, one level a press. On a function's line, off a name: the function as written, a part a line, the type parameters as written. Hinted only where it acts |
| `-` | close the type the cursor is in, and what was opened inside it, the cursor back on the line naming it; on a function opened as written, close it. What is open stays for the row as long as seam is open |
| `=` | the type at the foot at its next level: as written, flat, in full, round; the choice stays for the session. Hinted, `= flat`, only where the foot tells a type at its levels |
| `]c` `[c` | with the diff on, in Code and Types: the next or previous change, round the ends |
| `l` | in the Map, on a group closed to fit, `▸`, open it, for the row, as long as seam is open; on a name, show it in the tree (a type, its Map in the pane) |
| `h` | in the Map, on the head of a group `l` opened, close it again; else, on a type `l` showed, back to the row's Map, the cursor where it was |
| `T` | in the Map by folder: names only, as it opens, or each signature; the choice stays across rows, ` · types` in the status line while on |
| `J` | in the Map, the code screen on the function or file under the cursor |
| `<Tab>` `<S-Tab>` `gm` `D` | as in the tree |
| `gf` `gd` | in your own code: on a line of code, that line; on a file's line, the file; on a function's line, its declaration; on the head, the row's |
| `L` | the lens, as from the tree |
| `?` | every key here |
| `q` | close seam |

## The code

`J` on a function's, a type's or a file's row: its code on the left (a type's, its declaration), as wide as it needs up to 112 columns and 60% of the screen, the pane keeping 40% or more, a longer line cut with `…` at its edge; the pane on the right as beside the tree. The head is the trail, `Seams › createRun() › createQueue()`; the code's own head says what it is and where, and its display. Each line its number and the source as written, its colours from treesitter; a name from another file underlined where it lives, as in the tree; after a value's name with no type written, its type, dim, from the declared return of the call that made it (nothing when that is not written), and after a function's parameters its return the same way.

With the diff on (`D`), the code is drawn with the range's changes inline, as the pane's Code shows them, whole: removed lines unnumbered on red, added numbered on green, the words changed lit stronger. The status line starts `diff on`.

The name under the cursor answers in the pane, or off a name the nearest on its line; a line with none, or a removed one, the function: a call its function (`called at line N`), a type its views, an imported value its file, a value, a parameter, a field or a method its Types view, headed with where it was made (`queue  made by createQueue, line 37  used 12 times`), what it is a parameter of, or the type it is in and its file. A field or method shows the type it is in with its lines lit, then each repo type it names written out under `is`, `takes` or `returns`. A value or parameter no type is written for: `no type is written for it; the TypeScript server says`, dim, then the type the server says, each repo type in it written out under `is`; `asking the TypeScript server` until it has answered, and `no type is written for it` alone without a server. A value's or a call's later uses in the code are lit, the name and its line. The status line says the name under the cursor and its type.

| Key | Does |
|---|---|
| `j` `k` and Vim's motions | move; the pane follows the name under the cursor, else the nearest on the line |
| `n` `N` | the next or previous import: a name from another file, round the ends |
| `]c` `[c` | the next or previous change in the range, its lines numbered in the signs' colours, or with the diff on where its lines are |
| `J` | on a call, a type or an imported name, the code screen on its function, type or file, on top of the trail |
| `K` | back: the previous on the trail, the cursor on the very name you left from; a count goes back more (`3K`); from the first, the tree on its row |
| `gs` | the code, or its types: the function's line, then its values in the order made, `name  Type`, each function inside under its own line, indented; a file, its declarations. With the diff on, a line whose signature changed as it was, `-` on red, over itself, `+` on green, and a type opened with its own `+` `-` lines |
| `D` | the diff, on or off, here and in the pane, as beside the tree |
| `+` `-` | in its types, open or close the type under the cursor, as in the pane |
| `<Tab>` | the pane's other tab, Code or Types, for the name under the cursor; from an aside, back |
| `gm` | the Map in the pane, and back, as beside the tree |
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
