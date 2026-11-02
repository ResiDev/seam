-- Package types on demand: the declaration of a name that is no repo type,
-- one from a package in node_modules or TypeScript's own lib, asked of the
-- TypeScript server only when the cursor rests on it; never indexed, never
-- a contract. One server for the session, started on the first lookup and
-- stopped when seam closes; textDocument/definition at a position where the
-- name is written, never waited on, and the declaration read out of the
-- file it points at with treesitter. No server, no lookup.
local code = require 'seam.code'
local st = require 'seam.state'
local M = {}

-- the declarations a definition can land in
M.DECL = {
  interface_declaration = true,
  type_alias_declaration = true,
  class_declaration = true,
  abstract_class_declaration = true,
  enum_declaration = true,
  function_signature = true,
  function_declaration = true,
}
-- what a declaration is written inside of, `export` and `declare`
local WRAP = { export_statement = true, ambient_declaration = true }
-- the times a session starts the server before it gives up on it
local STARTS = 3

-- the session: its client, what it was asked and what it said, the files read
local S = { got = {}, asking = {}, opened = {}, starts = 0 }

---------------------------------------------------------------- pure

--- Where a declaration's file is, as the foot says it: TypeScript's lib
--- file by its name, else the package after the last `node_modules/`, a
--- scoped one `@scope/name`; nil for a file in no package.
---@param path string
---@return string|nil
function M.package(path)
  local rest = path:match '.*/node_modules/(.*)$'
  local pkg = rest and (rest:match '^(@[^/]+/[^/]+)' or rest:match '^([^/]+)')
  local lib = path:match '[^/]+$'
  if lib:match '^lib[%w.]*%.d%.ts$' and (pkg == 'typescript' or (pkg or ''):match '^@typescript/' or (not pkg and path:find('typescript', 1, true))) then
    return 'TypeScript’s ' .. lib
  end
  return pkg
end

--- The declaration holding 0-based `row`, `col` of a file's tree: the
--- innermost interface, type alias, class, enum or function signature
--- around it, with the `export` or `declare` it is written in; its first
--- and last rows, 0-based. Nil when the position is in none.
---@param root TSNode
---@param row integer
---@param col integer
---@return integer|nil first, integer|nil last
function M.decl(root, row, col)
  local n = root:named_descendant_for_range(row, col, row, col)
  while n and not M.DECL[n:type()] do
    n = n:parent()
  end
  if not n then
    return nil
  end
  while n:parent() and WRAP[n:parent():type()] do
    n = n:parent()
  end
  local sr, _, er, ec = n:range()
  if ec == 0 and er > sr then
    er = er - 1
  end
  return sr, er
end

---------------------------------------------------------------- the server

--- The session's server stopped, and all it said forgotten.
function M.stop()
  local c = S.id and vim.lsp.get_client_by_id(S.id)
  if c then
    -- asked to shut down, not killed: killed, Neovim reports it quit
    c:stop()
  end
  S = { got = {}, asking = {}, opened = {}, starts = 0 }
end

-- the client, started on the first lookup; requests wait in `S.queue`
-- until it has said hello
local function client()
  if S.root ~= st.root then
    M.stop()
    S.root = st.root
  end
  local c = S.id and vim.lsp.get_client_by_id(S.id)
  if c and not c:is_stopped() then
    return c
  end
  if S.starts >= STARTS then
    return nil
  end
  local cmd = require('seam.tsserver').command(st.root)
  if not cmd then
    S.starts = STARTS
    return nil
  end
  -- tsgo leaves with 1 even when asked to, and Neovim reports any client
  -- that does; a shell between them leaves with 0
  if vim.fn.executable 'sh' == 1 then
    cmd = vim.list_extend({ 'sh', '-c', '"$@"; exit 0', 'seam-lookup' }, cmd)
  end
  S.starts, S.ready, S.queue, S.opened = S.starts + 1, false, {}, {}
  S.id = vim.lsp.start({
    name = 'seam-lookup',
    cmd = cmd,
    root_dir = st.root,
    on_init = function()
      S.ready = true
      local q = S.queue or {}
      S.queue = {}
      for _, f in ipairs(q) do
        f()
      end
    end,
  }, { attach = false, silent = true })
  return S.id and vim.lsp.get_client_by_id(S.id) or nil
end

-- the file the server is to read `path` (relative to the root) from, opened once
local function open(c, path)
  local uri = vim.uri_from_fname(st.root .. '/' .. path)
  if not S.opened[uri] then
    S.opened[uri] = true
    c:notify('textDocument/didOpen', {
      textDocument = {
        uri = uri,
        languageId = path:match '%.[jt]sx$' and 'typescriptreact' or 'typescript',
        version = 0,
        text = table.concat(code.file(path).lines, '\n'),
      },
    })
  end
  return uri
end

-- a declaration out of what the definition gave: the first location in one
local function read(locs)
  if type(locs) ~= 'table' then
    return nil
  end
  if locs.uri or locs.targetUri then
    locs = { locs }
  end
  for _, loc in ipairs(locs) do
    local fname = vim.uri_to_fname(loc.targetUri or loc.uri)
    local r = loc.targetSelectionRange or loc.range
    local key = 'lookup:' .. fname
    if not code.has(key) then
      local ok, lines = pcall(vim.fn.readfile, fname)
      code.virtual(key, fname, ok and lines or {})
    end
    local root = code.tree(key)
    if root and r then
      local src = code.file(key).lines[r.start.line + 1] or ''
      local ok, col = pcall(vim.str_byteindex, src, 'utf-16', r.start.character, false)
      local s, e = M.decl(root, r.start.line, ok and col or r.start.character)
      if s then
        return { key = key, path = fname, s = s + 1, e = e + 1, pkg = M.package(fname) }
      end
    end
  end
end

--- The declaration of `name`, written in `path` (relative to the root) at
--- `at` (`line` 1-based, `col` a byte, 0-based), else where `path` first
--- writes it: `{ key, path, s, e, pkg }`, its lines s..e read as `key` is
--- (seam.code). Cached for the session per name and file; the first time
--- nil, the server asked, and `done` called once it has answered.
---@param name string
---@param path string
---@param at { line: integer, col: integer }|nil
---@param done fun()
---@return table|nil
function M.get(name, path, at, done)
  local k = name .. '\0' .. path
  local got = S.root == st.root and S.got[k]
  if got ~= nil and got ~= false and not code.has(got.key) then
    -- seam opened again: the files read are read again
    code.virtual(got.key, got.path, vim.fn.readfile(got.path))
  end
  if got ~= nil and S.root == st.root then
    return got or nil
  end
  if S.root == st.root and S.asking[k] then
    return nil
  end
  local lines = code.file(path).lines
  local line, col = at and at.line, at and at.col
  if not line then
    for l, s in ipairs(lines) do
      local a = s:find('%f[%w_$]' .. vim.pesc(name) .. '%f[^%w_$]')
      if a then
        line, col = l, a - 1
        break
      end
    end
  end
  local c = line and client()
  if not c then
    return nil
  end
  S.asking[k] = true
  local function ask()
    local ok, ch = pcall(vim.str_utfindex, lines[line] or '', 'utf-16', col, false)
    c:request('textDocument/definition', {
      textDocument = { uri = open(c, path) },
      position = { line = line - 1, character = ok and ch or col },
    }, function(err, result)
      vim.schedule(function()
        S.asking[k] = nil
        S.got[k] = not err and read(result) or false
        done()
      end)
    end)
  end
  if S.ready then
    ask()
  else
    S.queue[#S.queue + 1] = ask
  end
  return nil
end

return M
