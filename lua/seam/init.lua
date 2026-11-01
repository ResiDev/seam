-- seam: the contracts of a TypeScript repo, from its treesitter index.
-- :Seam starts here; the screens are in seam.screen.
local api = vim.api
local index = require 'seam.index'
local screen = require 'seam.screen'
local st = require 'seam.state'
local M = {}

M.st = st
M.index = index.index
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
--- it has no index yet, an older one, or when asked to; on seam's tab as it
--- was when it is open on that repo already. `after` runs once it is open.
---@param root? string
---@param opts? { reindex?: boolean, after?: fun() }
function M.start(root, opts)
  root = normal(root)
  opts = opts or {}
  local from = api.nvim_get_current_tabpage()
  local function show()
    screen.open(root)
    index.types(root)
    if not (st.tab and api.nvim_tabpage_is_valid(st.tab) and st.root == root and st.screen) then
      return
    end
    -- indexing took a while: gf goes back to where you asked from
    if api.nvim_tabpage_is_valid(from) and from ~= st.tab then
      st.from_tab = from
    end
    if opts.after then
      opts.after()
    end
  end
  if opts.reindex or index.version(root) < index.VERSION then
    if st.tab and api.nvim_tabpage_is_valid(st.tab) then
      screen.close()
      if api.nvim_tabpage_is_valid(from) then
        api.nvim_set_current_tabpage(from)
      end
    end
    index.index(root, function()
      st.loaded_root = nil
      show()
    end)
  else
    show()
  end
end

local WAYS = { overview = true, page = true, calls = true, called_by = true, types = true }
M.ways = { 'overview', 'page', 'calls', 'called_by', 'types' }

--- From your own code: seam on what the word under the cursor names. `how`:
--- 'overview' (the tree on that function or contract, where it lives),
--- 'page' (the same, its Used by in the pane), 'calls' (the code screen on
--- that function, K back to its row in the tree), 'called_by' (the tree on
--- it, its Used by in the pane), or 'types' (the Types view of the type it
--- names, in the tree's pane). Several by that name, or nothing, the tree's
--- `/` picker holding the word.
---@param how? 'overview'|'page'|'calls'|'called_by'|'types'
function M.here(how)
  how = how or 'overview'
  if not WAYS[how] then
    vim.notify('seam: here takes ' .. table.concat(M.ways, ', '), vim.log.levels.WARN)
    return
  end
  if st.tab and api.nvim_get_current_tabpage() == st.tab then
    vim.notify('seam: here is for your own code; seam is open', vim.log.levels.INFO)
    return
  end
  local root = normal()
  local file = vim.fs.normalize(api.nvim_buf_get_name(0))
  local path = file ~= '' and file:sub(1, #root + 1) == root .. '/' and file:sub(#root + 2) or nil
  local word = vim.fn.expand '<cword>'
  local line = api.nvim_win_get_cursor(0)[1]
  M.start(root, {
    after = function()
      local m = index.model()
      if how == 'types' then
        screen.show(path)
        if not require('seam.screen_tree').show_type(word) then
          require('seam.screen_tree').search(word)
        end
        return
      end
      local r = require('seam.here').resolve(m, word, path, line, how)
      local function say(msg)
        vim.notify('seam: ' .. msg, vim.log.levels.INFO)
      end
      -- several, or nothing: the / picker holding the word
      local function pick()
        screen.show()
        require('seam.screen_tree').search(word)
      end
      -- a page is the row's Used by now, and so is called by
      local function used_by()
        if how == 'page' or how == 'called_by' then
          st.view = st.view or require('seam.views').new()
          st.view.aside = 'Used by'
        end
      end
      -- the tree on a function, and for calls its code screen over it
      local function fn(node)
        used_by()
        screen.show(node.id)
        if how == 'calls' then
          require('seam.screen_code').open { kind = 'fn', id = node.id }
        end
      end
      local c = r.contract
      if c then
        local node = m.graph and m.graph.nodes[c.id]
        if not vim.tbl_contains(m.contracts, c) then
          say('the lens hides ' .. c.name .. ' (' .. c.path .. '); L to see it')
          return pick()
        end
        if node then
          return fn(node)
        elseif how == 'calls' then
          say(c.name .. ' is not a function, component or class: its contract')
        end
        used_by()
        screen.show(c)
        -- a type has no row: it shows in the pane, its file's row under it
        if (how == 'page' or how == 'called_by') and m.flows and m.flows[c.name] then
          require('seam.screen_tree').show_type(c.name, 'Used by')
        end
      elseif r.node and not r.node.test then
        fn(r.node)
      elseif r.candidates then
        pick()
      else
        if word ~= '' and (how == 'calls' or how == 'called_by') then
          say('no function named ' .. word)
        end
        pick()
      end
    end,
  })
end

return M
