# seam.nvim

The contracts in a TypeScript codebase: the exports used across files and
folders, where they live, what they are built from and who uses them.

Everything shown comes from the LSP or treesitter. No LLM, for now.

`SPEC.md` is what seam is, each screen and how it is built, `KEYS.md`
every key, `design/mocks/` the locked screens as pictures.

`:SeamShow <target>` opens seam on a place written as a string, for links
from outside (thread.nvim's threads): `src/store.ts:save@Map`,
`type:Card@Types`, `src/billing/@Map/library`, `src/store.ts`. The grammar
is `what ['@' Code|Types|Map ['/' display]]`, `what` being `type:Name`,
`path:name[:line]` or a file's or folder's path from the repo root.
`require('seam').check(target, root)` says why one does not resolve, nil
when it does, without opening seam.
