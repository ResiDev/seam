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
| `K` `<BS>` | up a level: the previous page, or the explorer |
| `-` | straight to the explorer from any depth, on this contract |
| `L` | the lens |

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
