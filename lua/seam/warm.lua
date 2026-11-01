-- The range's changes worked out ahead while you are idle: once git has
-- said what changed, each changed file is parsed, its declarations compared
-- and its diffs made, one small piece every tick and only when no key has
-- been pressed for a moment, so the pane on a changed row draws from what
-- is kept rather than making it while you wait. Lua here has no threads:
-- a piece runs whole, so each is kept small (one diff), and a key pressed
-- puts the rest off until you rest again.
local changes = require 'seam.changes'
local code = require 'seam.code'
local diff = require 'seam.diff'
local M = {}

-- pieces run when no key came for IDLE ms, looked at every TICK ms, as many
-- as fit in BUDGET ms of each tick
M.IDLE, M.TICK, M.BUDGET = 250, 50, 25

local last = vim.uv.now()
local ns = vim.api.nvim_create_namespace 'seam.warm'
vim.on_key(function()
  last = vim.uv.now()
end, ns)

local timer, queue

local function slice(lines, d)
  return d and vim.list_slice(lines, d.s, d.e) or {}
end

-- the pieces for `path`: parse it, compare its declarations, then the whole
-- file's diff and each changed declaration's own, one piece each
local function pieces(C, path, out)
  out[#out + 1] = function()
    if C.files[path] ~= 'gone' then
      code.tree(path)
    end
  end
  out[#out + 1] = function()
    local A = changes.lines(changes.key(C, path, 'from'))
    local B = changes.lines(changes.key(C, path, 'to'))
    diff.hunks(A, B)
    local f = changes.file(C, path)
    for _, d in ipairs(f and f.list or {}) do
      if d.state then
        table.insert(out, 1, function()
          diff.hunks(slice(A, d.from), slice(B, d.to))
        end)
      end
    end
  end
end

local function stop()
  if timer then
    timer:stop()
  end
  queue = nil
end

local function tick(C)
  if changes.get() ~= C or not queue or #queue == 0 then
    return stop()
  end
  if vim.uv.now() - last < M.IDLE then
    return
  end
  local t0 = vim.uv.hrtime()
  repeat
    pcall(table.remove(queue, 1))
  until #queue == 0 or (vim.uv.hrtime() - t0) / 1e6 >= M.BUDGET
end

--- Work out what `C` changed ahead, a piece at a time while idle; a later
--- range replaces it.
---@param C seam.Changes|nil
function M.changes(C)
  stop()
  if not C or C.err or #C.list == 0 then
    return
  end
  queue = {}
  for _, path in ipairs(C.list) do
    pieces(C, path, queue)
  end
  timer = timer or vim.uv.new_timer()
  timer:start(
    M.TICK,
    M.TICK,
    vim.schedule_wrap(function()
      tick(C)
    end)
  )
end

--- Pieces still to do, for the checks.
---@return integer
function M.left()
  return queue and #queue or 0
end

return M
