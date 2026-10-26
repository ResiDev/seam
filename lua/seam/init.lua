-- seam: the contracts of a TypeScript repo, from its treesitter index.
-- :Seam starts here; the screens are in seam.screen.
local api = vim.api
local index = require 'seam.index'
local screen = require 'seam.screen'
local st = require 'seam.state'
local M = {}

M.st = st
M.index = index.index
M.find = screen.find
M.on_move = screen.on_move
M.open_page = screen.open_page
M.overview = screen.overview
M.lens_changed = screen.lens_changed
M.open_lens = screen.open_lens
M.close = screen.close

local function repo_root()
  local buf = api.nvim_buf_get_name(0)
  return vim.fs.root(buf ~= '' and buf or vim.fn.getcwd(), { '.git', 'package.json' }) or vim.fn.getcwd()
end

local function normal(root)
  return (vim.fn.fnamemodify(root or repo_root(), ':p'):gsub('/$', ''))
end

--- Open seam on a repo, the current one by default.
---@param root? string
function M.open(root)
  screen.open(normal(root))
end

--- Open seam on a repo (the current one by default), indexing it first when
--- it has no index yet, an older one, or when asked to.
---@param root? string
---@param opts? { reindex?: boolean }
function M.start(root, opts)
  root = normal(root)
  opts = opts or {}
  if opts.reindex or index.version(root) < index.VERSION then
    if st.tab and api.nvim_tabpage_is_valid(st.tab) then
      screen.close()
    end
    index.index(root, function()
      st.loaded_root = nil
      screen.open(root)
    end)
  else
    screen.open(root)
  end
end

return M
