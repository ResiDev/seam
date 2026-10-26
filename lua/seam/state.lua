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
  built_as = 'code', -- Built from as 'code', the contract with its names marked, or as a 'list'
  stack = {}, -- what K comes back to from the page shown: pages ({ kind = 'page', c, ... }), and under them the Calls screen J left ({ kind = 'calls', calls, top, label })
  -- calls: the Calls screen's view (seam.CallsView), calls_rows its rows as drawn
}
