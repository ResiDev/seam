-- Which TypeScript server seam asks: $SEAM_TS, else the first native
-- TypeScript (7+) server found: the repo's own Effect or tsgo build, then
-- tsc 7 or tsgo from Mason or the PATH. Shared by the types pass, the
-- lookups made while seam is open, and :checkhealth.
local M = {}

local function native_tsc(bin)
  local v = vim.system({ bin, '--version' }, { text = true }):wait()
  return v.code == 0 and tonumber((v.stdout or ''):match 'Version (%d+)') or 0
end

--- The command that starts the server for `repo` in LSP mode, and where it
--- came from; nil and why when there is none.
---@param repo string
---@return string[]|nil cmd, string from
function M.command(repo)
  local env = os.getenv 'SEAM_TS'
  if env and env ~= '' then
    return vim.split(env, ' ', { trimempty = true }), '$SEAM_TS'
  end
  local effect = repo .. '/node_modules/.bin/effect-tsgo'
  if vim.fn.executable(effect) == 1 then
    local exe = vim.trim(vim.system({ effect, 'get-exe-path' }, { cwd = repo, text = true }):wait().stdout or '')
    if exe ~= '' and vim.fn.executable(exe) == 1 then
      return { exe, '--lsp', '--stdio' }, 'the repo’s effect-tsgo'
    end
  end
  local mason = vim.fn.stdpath 'data' .. '/mason/bin/'
  for _, bin in ipairs { repo .. '/node_modules/.bin/tsgo', mason .. 'tsc', vim.fn.exepath 'tsc', mason .. 'tsgo', vim.fn.exepath 'tsgo' } do
    if bin ~= '' and vim.fn.executable(bin) == 1 and (bin:match 'tsgo$' or native_tsc(bin) >= 7) then
      return { bin, '--lsp', '--stdio' }, bin
    end
  end
  return nil, 'no TypeScript 7 server: tsc 7 or tsgo, from the repo, Mason or the PATH; or say which in $SEAM_TS'
end

return M
