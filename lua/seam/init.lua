-- seam: the contracts of a TypeScript repo, from its treesitter index.
-- :Seam starts here; the screens are in seam.screen.
local api = vim.api
local index = require 'seam.index'
local screen = require 'seam.screen'
local st = require 'seam.state'
local M = {}

M.st = st
M.index = index.index
M.open_calls = screen.open_calls
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
--- 'page' (the same, its Used by in the pane), 'calls' or 'called_by' (the
--- call tree anchored on that function, down or up), or 'types' (the Types
--- view of the type it names, in the tree's pane). Several by that name, or
--- nothing, the `/` picker holding the word: the tree's or the call tree's.
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
      local dir = how == 'called_by' and 'up' or 'down'
      local calls = how == 'calls' or how == 'called_by'
      local function say(msg)
        vim.notify('seam: ' .. msg, vim.log.levels.INFO)
      end
      -- several, or nothing: the / picker holding the word
      local function pick()
        screen.show()
        if calls and m.graph then
          screen.open_calls(nil)
          screen.calls_pick(word, dir)
        else
          require('seam.screen_tree').search(word)
        end
      end
      local function anchor(node)
        screen.open_calls(node.id, dir)
      end
      -- a page is the row's Used by now
      local function used_by()
        if how == 'page' then
          st.view = st.view or require('seam.views').new()
          st.view.at = 'Used by'
        end
      end
      local c = r.contract
      if c then
        local node = m.graph and m.graph.nodes[c.id]
        if calls and node then
          return anchor(node)
        elseif calls then
          say(c.name .. ' is not a function, component or class: its contract')
        end
        if not vim.tbl_contains(m.contracts, c) then
          say('the lens hides ' .. c.name .. ' (' .. c.path .. '); L to see it')
          return pick()
        end
        used_by()
        screen.show(c)
        -- a type has no row: it shows in the pane, its file's row under it
        if how == 'page' and not node and m.flows and m.flows[c.name] then
          require('seam.screen_tree').show_type(c.name, 'Used by')
        end
      elseif r.node then
        if (how == 'overview' or how == 'page') and not r.node.test then
          used_by()
          return screen.show(r.node.id)
        end
        if not calls then
          say(r.node.name .. ' is not a contract: its calls')
        end
        anchor(r.node)
      elseif r.candidates then
        pick()
      else
        if word ~= '' and calls then
          say('no function named ' .. word)
        end
        pick()
      end
    end,
  })
end

--- Seam on the repo, the call tree from where the code starts.
function M.from_top()
  M.start(nil, {
    after = function()
      screen.open_calls(nil)
    end,
  })
end

return M
