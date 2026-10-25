# seam.nvim

`SPEC.md` is what v1 is and how it is built, `KEYS.md` every key (keep it in
step), `design/` the locked screens with their mocks.

- The screens are locked. A change to one starts with a new mock in
  `design/mocks/`, looked at as a picture, then the design doc.
- Every fact comes from the language server, treesitter or git. No LLM text.
- Nothing that needs a legend.
- Sibling of `../thread.nvim`: borrow its draw code and its `make view`
  harness rather than reinventing them.
