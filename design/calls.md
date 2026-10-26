# Calls

The call tree of any function or component: everything it calls, all the way
down, or everything that calls it, all the way up. With no anchor, the tree
starts where the code starts, from what nothing calls.

Drawn 2026-10-26, not locked yet: it is being built to see how it goes.

![Anchored, calls](mocks/calls-down.png)

## One tree, three ways in

It is one outline, the way a browser's devtools draw the DOM: a row per
function, two spaces a level, the code of the row under the cursor in a pane
on the right. The code is never inline.

- **Anchored, calls.** `c` on a contract in the explorer. The anchor is pinned
  at the top, with one line for who calls it. Under it, what it calls in the
  order it is written, then what those call, and so on down.
- **Anchored, called by.** `~` flips the direction on the same anchor. The
  anchor is pinned at the bottom and its callers grow upward: a caller sits
  above what it calls, so reading down a branch reads like a stack trace,
  from where it starts down to the anchor. Up in the code is up on the
  screen.
- **From the top.** `C` in the explorer, or `-` from any anchor. The roots are
  what nothing calls: an app's entry file, a module's top-level code, a
  package's public functions no one in the repo calls, test files. They sit
  in the file tree, under their packages, so the top of the codebase reads by
  where it lives.

`<CR>` anchors on any row, in any of the three. `<BS>` goes back to the
previous anchor, and from the first one back to the explorer.

![Opened one level](mocks/calls-down-opened.png)

## What a row says

Four columns after the name, in this order:

- **below**: how many functions sit under it, each counted once however many
  paths reach it. Called by shows **above** instead.
- **used by**: how many functions call it.
- **file**: only when it is not the file of the row above it.
- **line**: where the row above calls it. A root shows where it is declared.

A function already open higher in the tree is not opened twice: its row says
`↑ also at :102`, the line it was first opened from. A cycle ends the same
way.

## Taming it

- **A budget.** The tree opens level by level until the next level would not
  fit in the window. Everything past it is folded, with its count. You open
  more instead of folding less.
- **Shared functions are never opened for you.** One called from 5 or more
  functions (the threshold is a guess) is a utility: it shows as a row with
  its counts but the budget skips it. A pinned line lists the ones in view:
  `shared, never opened: useStore 5 · noChange 9`. `l` still opens one.
- **Tests fold to one row** among callers and roots: `tests  16 files`. `l`
  opens it.
- **The lens** hides the same files here as everywhere else.

![From the top](mocks/calls-top.png)

## Keys

| Key | Does |
|---|---|
| `j` `k` | the next or previous row |
| `l` | open the row one level; on an open row, its first child |
| `h` | fold the row; on a folded one, its parent |
| `L` | open everything under the row until the budget runs out |
| `H` | fold back to what the budget opened |
| `]` `[` | the next or previous sibling |
| `<CR>` | anchor on the row |
| `~` | flip: calls, called by |
| `<BS>` | the previous anchor |
| `-` | from the top |
| `gd` | the declaration, in a normal window |
| `q` | close |

![Called by](mocks/calls-up.png)

The mock above draws called by downward. The build draws it upward instead,
because the user found "up in the call stack is still down through the tree"
confusing.

## Where it comes from

Treesitter alone, the same pass that finds built from. Every top-level
declaration, exported or not, gets its built-from names. Top-level statements
outside any declaration belong to the file as one node, `top of the file`. A
name counts as a call when it resolves to a function or component; types and
constants are left out.

## Not yet

- **Types.** A type's tree would be who it is handed to, with who makes it and
  who holds it pinned on top (`mocks/src/calls/tree.py`, tree-3). Unsure
  whether it reads; it waits.
- **What it can't follow.** A method on an interface, a prop or a callback
  ends the tree without saying so. It should say `✕ can't follow` rather than
  look like a leaf.
- **Test names.** A test file is one node; its `it()` names would say which
  test calls what.

The mocks are throwaway: `mocks/src/calls/tree.py` and `top.py`, with `lib.py`
and `graphq.py` beside them.
