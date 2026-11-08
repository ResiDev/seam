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

--- The view you came from holds `buf`, a buffer seam shows itself in its
--- pane, beside its own views; nil lets go of it.
---@param buf integer|nil
function M.hold(buf)
  require('seam.views.held').hold(buf)
  if require('seam.pane').wins() then
    require('seam.pane').redraw()
  end
end

-- the buffer you are arriving from: the current one, outside seam's tab,
-- in a window of its own, unless an empty one
local function arriving()
  local buf = api.nvim_get_current_buf()
  if (st.tab and api.nvim_get_current_tabpage() == st.tab) or api.nvim_win_get_config(0).relative ~= '' then
    return nil
  end
  local bt = vim.bo[buf].buftype
  if bt == 'quickfix' or bt == 'prompt' then
    return nil
  end
  local empty = api.nvim_buf_get_name(buf) == '' and api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
  return not empty and buf or nil
end

--- Open seam on a repo (the current one by default), indexing it first when
--- it has no index yet, an older one, or when asked to; on seam's tab as it
--- was when it is open on that repo already. `after` runs once it is open.
--- The view you came from holds `from`; with `hold`, or `vim.g.seam_hold`
--- set, the buffer you arrive from. Arriving from outside seam's tab any
--- other way lets go of what it held: the tab is there while you asked.
---@param root? string
---@param opts? { reindex?: boolean, after?: fun(), from?: integer, hold?: boolean }
function M.start(root, opts)
  root = normal(root)
  opts = opts or {}
  local outside = not (st.tab and api.nvim_get_current_tabpage() == st.tab)
  local buf = opts.from or ((opts.hold or vim.g.seam_hold == true) and arriving() or nil)
  if buf or outside then
    -- you land on what you asked for, not on where you came from
    if st.view and st.view.at == require('seam.views.held').NAME then
      st.view.at = 'Code'
    end
    M.hold(buf)
  end
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
--- 'page' (the same, its Map in the pane), 'calls' (the code screen on
--- that function, K back to its row in the tree), 'called_by' (the tree on
--- it, its Map in the pane), or 'types' (the Types view of the type it
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
      -- a page is the row's Map now, its callers under it, and so is called by
      local function used_by()
        if how == 'page' or how == 'called_by' then
          st.view = st.view or require('seam.views').new()
          st.view.aside = 'Map'
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
          require('seam.screen_tree').show_type(c.name, 'Map')
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

--- Why `target` is nothing seam can show in the repo at `root`, for the
--- agent who wrote it; nil when it is. Reads the repo's index on disk and
--- leaves seam's open state alone, so it runs headless and while seam shows
--- another repo. A contract the lens hides still counts: the lens is the
--- reader's, not the link's.
---@param target string   e.g. "src/store.ts:save@Map/library"
---@param root string     the repo's root, absolute
---@return string|nil why
function M.check(target, root)
  local t, why = require('seam.target').parse(target)
  if not t then
    return why
  end
  root = normal(root)
  local where = vim.fn.fnamemodify(root, ':~')
  local ok, m = pcall(index.peek, root)
  if not ok then
    return ('seam could not read its index of %s: open it with :Seam! to make it again (%s)'):format(where, m)
  elseif not m then
    return ('seam has no index of %s: open it with :Seam once'):format(where)
  elseif m.version < index.VERSION then
    return ('seam has an index of %s older than it reads: open it with :Seam once to make it again'):format(where)
  end
  local _, no = require('seam.target').resolve(m, t)
  return no
end

--- Open seam on `target` in the repo at `opts.root` (default: the current
--- repo, as `start` finds it), its row in the view and display it names,
--- the view you came from holding `opts.from`, or with `opts.hold` the
--- buffer you arrive from (as `start`). One that does not resolve says why
--- and leaves the tree's `/` picker holding its name.
---@param target string
---@param opts? { root?: string, from?: integer, hold?: boolean }
function M.show(target, opts)
  opts = opts or {}
  local tg = require 'seam.target'
  local t, why = tg.parse(target)
  if not t then
    vim.notify('seam: ' .. why, vim.log.levels.WARN)
    return
  end
  M.start(opts.root, {
    from = opts.from,
    hold = opts.hold,
    after = function()
      local m = index.model()
      local tree = require 'seam.screen_tree'
      local function pick(msg)
        vim.notify('seam: ' .. msg, vim.log.levels.WARN)
        screen.show()
        tree.search(tg.query(t))
      end
      local at, no = tg.resolve(m, t)
      if not at then
        return pick(no)
      end
      local c = at.contract
      if c and not vim.tbl_contains(m.contracts, c) then
        return pick('the lens hides ' .. c.name .. ' (' .. c.path .. '); L to see it')
      end
      st.view = st.view or require('seam.views').new()
      if t.view == 'Map' then
        st.view.aside = 'Map'
      elseif t.view then
        st.view.at, st.view.aside = t.view, nil
      end
      -- a view named without a display opens on its first, not the last one used
      if t.view then
        st.view.display[t.view] = t.display
      end
      screen.show()
      -- a type has no row: it shows in the pane, its file's row under it
      local shown = tree.reveal(at.id or at.path)
      if at.kind == 'type' then
        tree.show_type(at.name, t.view)
      elseif not shown then
        return pick('the lens hides ' .. at.path .. '; L to see it')
      end
      -- drawn now, not once the cursor rests: no key follows to wake it
      require('seam.pane').flush()
    end,
  })
end

return M
