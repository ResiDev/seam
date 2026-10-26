# Keys

Every key seam maps, in the buffers it owns. Keep this in step with the code.

## Anywhere

| Key | Does |
|---|---|
| `:Seam` | open the explorer in its own tab page |
| `:Seam debug` | write what it knows to `stdpath('state')/seam-debug.txt` |
| `q` | close seam |
| `R` | ask the source again for everything shown |

## Explorer

| Key | Does |
|---|---|
| `j` `k` | move; both trees follow the contract under the cursor |
| `<Tab>` `<S-Tab>` | next or previous order: by folder, most used, most built from; the header lights the count it sorts by |
| `b` | only the built-from tree; again, both trees |
| `u` | only the used-by tree; again, both trees |
| `/` | search names; the list narrows as you type |
| `d` | on a directory row, filter to it |
| `D` | clear the filter |
| `J` `<CR>` | open the contract's page |
| `L` | the lens: what the explorer and pages show |
| `c` | the calls of the contract under the cursor, down from it |
| `C` | the calls from the top: where the code starts |
| `gd` | the declaration, in a normal window |

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
| `<CR>` | Built from: enter the page of the dependency shown. Used by: open the file at the use |
| `gd` | the declaration, in a normal window |
| `K` `<BS>` | up a level: the previous page, the Calls screen it was opened from, or the explorer |
| `-` | straight to the explorer from any depth, on this contract |
| `L` | the lens |

## Calls

The call tree of a function, component or class: what it calls all the way down, or what calls it all the way up, or everything from where the code starts.

| Key | Does |
|---|---|
| `j` `k` | the next or previous row |
| `l` | open the row one level; on an open row, its first child; on an `↑ also` row, where it is open |
| `h` | fold an open row, a folder or file too; on a folded or empty one, its parent |
| `L` | open everything under the row until the budget runs out |
| `H` | fold back to what the budget opened |
| `]` `[` | the next or previous sibling |
| `<CR>` | anchor on the row |
| `~` | flip: calls, called by |
| `J` | the page of the row's function, when it is a contract; `K` on it comes back to the tree as it was |
| `K` `<BS>` | back: the previous anchor; from the first, the explorer |
| `-` | straight to the explorer, on the anchor when it is a contract |
| `C` | from the top |
| `<Tab>` | the code beside the tree: where the row's function is called, or itself. The choice stays as the cursor moves, across anchors and back; what nothing calls shows itself |
| `n` `N` | Called at: the next or previous place it is called, round the ends. Itself: the next or previous line that calls something, lit. A count skips. In the code beside it, `]]` `[[` |
| `gd` | the declaration, in a normal window |
| `q` | close |

`]` and `[` wait for a second `]` or `[` before going to the sibling.

The head and the pin give the cursor back to the tree. The code beside it keeps it, to scroll and search; there `<Esc>` goes back to the tree, `<Tab>` does as in the tree, `]]` `[[` as `n` `N` do there, with the cursor on the line lit, and `K` `<BS>` `-` `q` do as in the tree.

## The lens

A float over the explorer or a page. One row a rule: a folder or file picked, or a pattern typed. In each of contracts, built from and used by, a rule shows `only` what it holds, `hide`s it, or leaves the column be (`·`). It is kept in `.seams/lens.json` at the root of the repository.

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
