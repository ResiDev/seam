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
| `/` | search names; the list narrows as you type |
| `d` | on a directory row, filter to it |
| `D` | clear the filter |
| `<CR>` | open the contract's page |
| `gd` | the declaration, in a normal window |

## A contract's page

| Key | Does |
|---|---|
| `<Tab>` `<S-Tab>` | next or previous tab: Contract, Built from, Used by |
| `j` `k` | Contract: move between members. Built from, Used by: the next seam |
| `]]` `[[` | Used by: the next or previous use in this file |
| `<CR>` | Built from: enter that contract's page. Used by: open the file at the use |
| `gd` | the declaration, in a normal window |
| `<BS>` | back: the previous page, or the explorer |
