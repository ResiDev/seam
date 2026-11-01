-- The refs a range of changes can start from, git's say: HEAD first, then
-- the branches, the tags and the recent commits; and the picker over them,
-- a ref typed narrowing it, or taken as it is when git knows it. The range
-- always ends at the working tree: to see another branch, check it out.
local api = vim.api
local draw = require 'seam.draw'
local picker = require 'seam.picker'
local M = {}

local function git(root, args)
  local r = vim.system(vim.list_extend({ 'git', '-C', root }, args), { text = true, env = require('seam.changes').env }):wait(3000)
  return r.code == 0 and r.stdout or ''
end

--- Does git know `ref` as a commit?
---@param root string
---@param ref string
---@return boolean
function M.known(root, ref)
  return vim.trim(git(root, { 'rev-parse', '--verify', '--quiet', ref .. '^{commit}' })) ~= ''
end

---@class seam.Ref: seam.Pick
---@field what string a branch, a tag, a commit
---@field note string its subject

--- What `from` can be: HEAD first, then the branches, the tags and the 40
--- last commits.
---@param root string
---@return seam.Ref[]
function M.list(root)
  local out, seen = {}, {}
  local function add(id, name, what, note)
    if not seen[id] then
      seen[id] = true
      out[#out + 1] = { id = id, name = name, used_by = 0, what = what, note = note or '' }
    end
  end
  add('HEAD', 'HEAD', 'the last commit', vim.trim(git(root, { 'log', '-1', '--format=%s' })))
  local refs = git(
    root,
    { 'for-each-ref', '--sort=-committerdate', '--format=%(refname)%09%(refname:short)%09%(contents:subject)', 'refs/heads', 'refs/remotes', 'refs/tags' }
  )
  for line in refs:gmatch '[^\n]+' do
    local full, short, subject = line:match '^(.-)\t(.-)\t(.*)$'
    if full and not full:match '/HEAD$' then
      add(short, short, full:match '^refs/tags/' and 'tag' or 'branch', subject)
    end
  end
  for line in git(root, { 'log', '-n', '40', '--format=%h%x09%cr%x09%s' }):gmatch '[^\n]+' do
    local h, when, subject = line:match '^(.-)\t(.-)\t(.*)$'
    if h then
      add(h, h .. ' ' .. subject, 'commit, ' .. when, subject)
    end
  end
  return out
end

-- a ref's row: its name, what it is, its subject
local function ref_row(p, W)
  local r = draw.row():add '  '
  local name = p.what:match '^commit' and p.id or p.name
  r:add(draw.trunc(name, 24), 'SeamRange')
  r:to(28):add(draw.trunc(p.what, 24), 'SeamLabel')
  r:to(54):add(draw.trunc(p.note, math.max(1, W - 56)), 'SeamText')
  return r
end

--- The picker of what `from` can be, over window `over`; `done(ref)` with
--- the ref picked; not called when nothing is.
---@param root string
---@param over integer
---@param done fun(ref: string)
---@param closed fun()
function M.pick(root, over, done, closed)
  picker.open {
    title = 'from',
    noun = 'refs',
    keys = '<CR> pick it, or the ref typed   <C-n>/<C-p> next   <Esc> back',
    over = over,
    col = 0,
    width = api.nvim_win_get_width(over) - 2,
    rows = math.min(20, vim.o.lines - 8),
    items = M.list(root),
    node = function()
      return {}
    end,
    row = ref_row,
    zindex = 55,
    pick = function(p, query)
      local q = vim.trim(query or '')
      -- a ref typed that git knows, unless what is picked is that ref
      if q ~= '' and not (p and (p.id == q or p.id:sub(1, #q) == q)) and M.known(root, q) then
        return done(q)
      end
      if p then
        done(p.id)
      end
    end,
    closed = closed,
  }
end

--- `f` in the lens: the picker of what the range's `from` can be, over its
--- window, the range set to what is picked; `x`, the range back to HEAD.
--- `after` once it is done.
---@param host seam.LensHost
---@param which 'from'|'reset'
---@param win integer
---@param after fun()
function M.lens(host, which, win, after)
  if which == 'reset' then
    host.set_range { from = 'HEAD' }
    return after()
  end
  M.pick(host.root(), win, function(ref)
    host.set_range { from = ref }
  end, after)
end

return M
