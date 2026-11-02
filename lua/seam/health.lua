-- :checkhealth seam: what the screens rest on, on this machine. The copy of
-- seam loaded, Neovim, the colours, the treesitter parsers and highlight
-- queries the code and the tree are painted from, the keys, the terminal,
-- and the TypeScript server the types come from.
local health = vim.health
local M = {}

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

local function copy()
  health.start 'seam: this copy'
  local git = vim.system({ 'git', '-C', ROOT, 'log', '-1', '--format=%h %cs %s' }, { text = true }):wait()
  if git.code == 0 then
    health.info(('%s at %s'):format(ROOT, vim.trim(git.stdout):sub(1, 100)))
  else
    health.info(ROOT .. ', not a git checkout')
  end
  if vim.fn.has 'nvim-0.11' == 1 then
    health.ok(tostring(vim.version()))
  else
    health.error(tostring(vim.version()) .. ': seam needs Neovim 0.11 or later')
  end
end

local function colours()
  health.start 'seam: colours'
  if vim.o.termguicolors then
    health.ok "'termguicolors' is on"
  else
    health.error("'termguicolors' is off: seam's colours are 24-bit, so every name in the tree, the code and the Map shows uncoloured", {
      'set it in your config: vim.o.termguicolors = true',
      'the terminal must pass 24-bit colour through (tmux: set -as terminal-features ",*:RGB")',
    })
  end
  for _, g in ipairs { '@function', '@type', '@variable' } do
    local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
    if hl.fg then
      health.ok(('%s is #%06x'):format(g, hl.fg))
    else
      health.warn(g .. ' has no colour: the colorscheme does not set it, so names painted from treesitter show plain')
    end
  end
end

local function treesitter()
  health.start 'seam: treesitter'
  for _, lang in ipairs { 'typescript', 'tsx' } do
    local ok, found = pcall(vim.treesitter.language.add, lang)
    local where = vim.api.nvim_get_runtime_file('parser/' .. lang .. '.so', false)[1]
    if ok and found then
      health.ok(('%s parser: %s'):format(lang, where or 'loaded'))
    else
      health.error(lang .. ' parser not found on the runtimepath', { 'nvim-treesitter: :TSInstall ' .. lang .. ' (it needs the tree-sitter CLI on the PATH)' })
    end
    local qok, q = pcall(vim.treesitter.query.get, lang, 'highlights')
    if qok and q then
      health.ok(lang .. ' highlights query: ' .. #q.captures .. ' captures')
    elseif qok then
      health.error(lang .. ' highlights query not found: the code and the names in the tree show uncoloured')
    else
      health.error(lang .. ' highlights query does not load: ' .. tostring(q), { 'the parser and the queries are from different versions; update both' })
    end
  end
end

local function keys()
  health.start 'seam: keys and terminal'
  health.info(
    ('TERM=%s%s%s'):format(vim.env.TERM or '', vim.env.TMUX and ', inside tmux' or '', vim.env.WSL_DISTRO_NAME and (', WSL ' .. vim.env.WSL_DISTRO_NAME) or '')
  )
  local m = vim.fn.maparg('<S-Tab>', 'n', false, true)
  if m.lhs then
    health.info('<S-Tab> in normal mode outside seam: ' .. (m.desc or m.rhs or 'a Lua function') .. ' (seam’s own, on its buffers, wins over it)')
  end
  health.info 'if <S-Tab> does nothing on seam: in insert mode press <C-v> then <S-Tab>; Neovim needs to see <S-Tab> (^[[Z), not <Tab>'
end

local function server()
  health.start 'seam: TypeScript server'
  local root = vim.fs.root(0, { 'tsconfig.json', 'package.json', '.git' }) or vim.fn.getcwd()
  local cmd, from = require('seam.tsserver').command(root)
  if cmd then
    health.ok(('for %s: %s (%s)'):format(vim.fn.fnamemodify(root, ':~'), table.concat(cmd, ' '), from))
  else
    health.warn(from .. '; the screens go on without types')
  end
end

local function indexed()
  health.start 'seam: the index'
  local index = require 'seam.index'
  local st = require 'seam.state'
  local root = st.root or vim.fs.root(0, { '.git', 'package.json' }) or vim.fn.getcwd()
  local file = index.dir(root) .. '/treesitter.json'
  local fh = io.open(file, 'r')
  if not fh then
    return health.info('no index for ' .. vim.fn.fnamemodify(root, ':~') .. ' yet: :Seam makes one')
  end
  local s = fh:read '*a'
  fh:close()
  local v = index.version(root)
  local say = v < index.VERSION and health.warn or health.ok
  say(('%s: format %d, seam reads %d%s'):format(vim.fn.fnamemodify(file, ':~'), v, index.VERSION, v < index.VERSION and '; :Seam! indexes it again' or ''))
  local ok, d = pcall(vim.json.decode, s)
  if ok and d.libs then
    local by = {}
    for _, l in ipairs(d.libs) do
      by[l.library] = (by[l.library] or 0) + #l.uses
    end
    local ls = vim.tbl_keys(by)
    table.sort(ls, function(a, b)
      return by[a] > by[b]
    end)
    health.info(('%d names taken from %d libraries%s'):format(#d.libs, #ls, #ls > 0 and (': ' .. table.concat(vim.list_slice(ls, 1, 8), ', ')) or ''))
  end
end

function M.check()
  copy()
  colours()
  treesitter()
  keys()
  server()
  indexed()
end

return M
