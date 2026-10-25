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
| `<Tab>` `<S-Tab>` | next or previous order: by folder, most used, most built from, by name |
| `b` | only the built-from tree; again, both trees |
| `u` | only the used-by tree; again, both trees |
| `/` | search names; the list narrows as you type |
| `d` | on a directory row, filter to it |
| `D` | clear the filter |
| `<CR>` | open the contract's page |
| `f` | the lens: what the explorer and pages show |
| `gd` | the declaration, in a normal window |

## A contract's page

| Key | Does |
|---|---|
| `<Tab>` `<S-Tab>` | the other tab: Built from, Used by |
| `j` `k` | the next or previous seam |
| `c` | only the contract; again, the contract and the seam |
| `s` | only the seam; again, the contract and the seam |
| `]]` `[[` | Used by: the next or previous use in this file |
| `<CR>` | Built from: enter that contract's page. Used by: open the file at the use |
| `gd` | the declaration, in a normal window |
| `<BS>` | back: the previous page, or the explorer |
| `-` | straight to the explorer from any depth, on this contract |
| `f` | the lens |

## The lens

A float over the explorer or a page. Each row is a folder to show only, or a pattern to hide, with a mark for each of contracts, built from and used by. It is kept in `.seams/lens.json` at the root of the repository.

| Key | Does |
|---|---|
| `j` `k` | the next or previous row |
| `c` `b` `u` | mark or unmark contracts, built from or used by on this row; on a suggestion, it becomes a pattern |
| `<Space>` | all three marks on, or all off; on `+ add a pattern` or `+ pick folders`, that |
| `C` `B` `U` | unmark contracts, built from or used by on every row |
| `X` | unmark every row; the rows stay |
| `a` | type a pattern; the panel lists what it matches as you type, `<CR>` adds it, `<Esc>` cancels |
| `e` | edit this row's pattern |
| `d` | delete this row |
| `p` | pick folders to show only, in a picker; `<Tab>` picks several |
| `q` `<Esc>` `f` | close |

A pattern is a file name (`*.test.*`), a folder anywhere (`tests/`), a path (`packages/*/scripts/**`), a regex on the path between slashes (`/\.(test|spec)\./`), or any other text found in the path.
