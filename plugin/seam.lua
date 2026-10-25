-- :Seam on the repo you're in (indexed with treesitter the first time),
-- :Seam! to index it again, :Seam <dir> for another one. :SeamLab opens the
-- lab's excalidraw copy, which also has the LSP and compiler sources.
local lab = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))) .. '/lab'
vim.api.nvim_create_user_command('Seam', function(o)
  require('seam').start(o.args ~= '' and vim.fn.expand(o.args) or nil, { reindex = o.bang })
end, { bang = true, nargs = '?', complete = 'dir' })
vim.api.nvim_create_user_command('SeamLab', function()
  require('seam').start(lab .. '/excalidraw')
end, {})
