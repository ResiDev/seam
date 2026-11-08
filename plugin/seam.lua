-- :Seam on the repo you're in (indexed with treesitter the first time; on
-- seam's tab as it was when it is open), :Seam! to index it again, :Seam <dir>
-- for another one. :SeamHere [overview|page|calls|called_by|types] opens it
-- on what the word under the cursor names, :SeamShow <target> on the place
-- a link names (src/store.ts:save@Map). :SeamLab opens the lab's
-- excalidraw copy, which also has the LSP and compiler sources.
local lab = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))) .. '/lab'
vim.api.nvim_create_user_command('Seam', function(o)
  require('seam').start(o.args ~= '' and vim.fn.expand(o.args) or nil, { reindex = o.bang })
end, { bang = true, nargs = '?', complete = 'dir' })
vim.api.nvim_create_user_command('SeamHere', function(o)
  require('seam').here(o.args ~= '' and o.args or nil)
end, {
  nargs = '?',
  complete = function(lead)
    return vim.tbl_filter(function(w)
      return w:sub(1, #lead) == lead
    end, require('seam').ways)
  end,
})
vim.api.nvim_create_user_command('SeamShow', function(o)
  require('seam').show(o.args)
end, { nargs = 1 })
vim.api.nvim_create_user_command('SeamLab', function()
  require('seam').start(lab .. '/excalidraw')
end, {})
