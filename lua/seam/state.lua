-- What the screens share: the repo, its loaded indexes, the tab page with its
-- windows and buffers, and what is shown in them. Every module reads this one
-- table; `require('seam').st` is the same table.
return {
  models = {}, -- source name -> model, as index.load builds it
  names = {}, -- the source names, sorted
  order = 1, -- the explorer's order, an index into draw.explorer.ORDERS
  filter = '', -- the explorer's search
  view = 'trees', -- the explorer's right side: 'trees', 'diagram' or 'map'
  sides = 'both', -- 'both', 'built' or 'used'
  panes = { built = 'both', used = 'seam' }, -- a page's panes per tab: 'both', 'contract' or 'seam'
  stack = {}, -- the pages under the one shown
}
