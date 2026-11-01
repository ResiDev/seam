-- What the screens share: the repo, its loaded indexes, the tab page with its
-- windows and buffers, and what is shown in them. Every module reads this one
-- table; `require('seam').st` is the same table.
return {
  models = {}, -- source name -> model, as index.load builds it
  names = {}, -- the source names, sorted
  -- outline: the tree (seam.Outline), orows its rows as drawn; view: the pane's view chosen and each one's display (seam.ViewState)
  -- ptype: a type picked with / shown in the pane, { row, at } the tree's cursor line then; opens: the types opened in place, by the pane's row key (seam.typesview); pctx: what the pane was drawn with
  -- obuf, owin: the tree's buffers and windows, head, tree, phead (the pane's head) and pane
  panes = { built = 'both', used = 'seam' }, -- a page's panes per tab: 'both', 'contract' or 'seam'
  built_as = 'code', -- Built from as 'code', the contract with its names marked, or as a 'list'
  stack = {}, -- what K comes back to from the screen shown: pages ({ kind = 'page', c, ... }), the Calls screen left ({ kind = 'calls', calls, top, label })
  -- tab: seam's tab page; from_tab: the one it was opened from, where gf shows the code
  -- calls: the Calls screen's view (seam.CallsView), calls_rows its rows as drawn
  -- columns: the call tree's columns, 'counts' when T chose them over what each function takes and gives
}
