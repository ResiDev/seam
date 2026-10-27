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
M.open_calls = screen.open_calls
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

local WAYS = { overview = true, page = true, calls = true, called_by = true }
M.ways = { 'overview', 'page', 'calls', 'called_by' }

--- From your own code: seam on what the word under the cursor names. `how`:
--- 'overview' (the explorer on that contract), 'page' (its page), 'calls' or
--- 'called_by' (the call tree anchored on that function, down or up). A
--- function that is no contract opens its calls; several by that name, the
--- `/` picker holding the word; nothing, the explorer's search holding it.
---@param how? 'overview'|'page'|'calls'|'called_by'
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
      local r = require('seam.here').resolve(m, word, path, line, how)
      local dir = how == 'called_by' and 'up' or 'down'
      local calls = how == 'calls' or how == 'called_by'
      local function say(msg)
        vim.notify('seam: ' .. msg, vim.log.levels.INFO)
      end
      -- several, or nothing: the / picker holding the word
      local function pick(nodes)
        if (calls or nodes) and m.graph then
          screen.show()
          screen.open_calls(nil)
          screen.calls_pick(word, dir)
        elseif how == 'page' then
          screen.show()
          screen.page_pick(word)
        else
          screen.show()
          screen.search(word)
        end
      end
      local function anchor(node)
        st.stack, st.page = {}, nil
        screen.open_calls(node.id, dir)
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
          return pick(false)
        end
        screen.show(c)
        if how == 'page' then
          screen.open_page(c)
        end
      elseif r.node then
        if not calls then
          say(r.node.name .. ' is not a contract: its calls')
        end
        anchor(r.node)
      elseif r.candidates then
        pick(r.nodes)
      else
        if word ~= '' and calls then
          say('no function named ' .. word)
        end
        pick(false)
      end
    end,
  })
end

--- Seam on the repo, the call tree from where the code starts.
function M.from_top()
  M.start(nil, {
    after = function()
      st.stack, st.page = {}, nil
      screen.open_calls(nil)
    end,
  })
end

return M
