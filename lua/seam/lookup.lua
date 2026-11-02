-- Package types on demand: the declaration of a name that is no repo type,
-- one from a package in node_modules or TypeScript's own lib, asked of the
-- TypeScript server only when the cursor rests on it; never indexed, never
-- a contract. One server for the session, started on the first lookup and
-- stopped when seam closes; textDocument/definition at a position where the
-- name is written, never waited on, and the declaration read out of the
-- file it points at with treesitter. A value no type is written for, the
-- same way: its hover and its type's definition where it is made. No
-- server, no lookup.
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
local S = { got = {}, vals = {}, asking = {}, opened = {}, starts = 0 }

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
---@return integer|nil first, integer|nil last, TSNode|nil name
function M.decl(root, row, col)
  local n = root:named_descendant_for_range(row, col, row, col)
  -- a location at the line's start is on its `export` or `declare`: the declaration inside
  while n and WRAP[n:type()] and n:named_child(0) and (M.DECL[n:named_child(0):type()] or WRAP[n:named_child(0):type()]) do
    n = n:named_child(0)
  end
  while n and not M.DECL[n:type()] do
    n = n:parent()
  end
  if not n then
    return nil
  end
  local nm = n:field('name')[1]
  while n:parent() and WRAP[n:parent():type()] do
    n = n:parent()
  end
  local sr, _, er, ec = n:range()
  if ec == 0 and er > sr then
    er = er - 1
  end
  return sr, er, nm
end

--- The code a hover answer leads with: its first fenced block, else its
--- text, with what kind of name it is, `(alias)` `(parameter)`, its
--- overloads' count and the `import` an alias adds left out; nil when it
--- has none.
---@param contents any MarkupContent, a MarkedString or a list of them
---@return string|nil
function M.hover_code(contents)
  if type(contents) == 'table' and not contents.value then
    contents = contents[1]
  end
  if type(contents) == 'table' then
    contents = contents.language and ('```\n' .. contents.value .. '\n```') or contents.value
  end
  if type(contents) ~= 'string' then
    return nil
  end
  local s = vim.trim(contents:match '```[%w]*\n(.-)\n?```' or contents)
  s = s:gsub('\nimport [^\n]*$', ''):gsub('^%([%w ]+%)%s*', ''):gsub('%s*%(%+%d+ overloads?%)', '')
  return s ~= '' and s or nil
end

--- The type a hover's code says: `T` of `const x: T`, a `let`'s, a
--- parameter's or a property's, on one line; a function's signature
--- whole, its name kept, `function` left out, and true with it.
---@param s string
---@return string, boolean fn
function M.hover_type(s)
  s = vim.trim(s:gsub('%s+', ' ')):gsub('^export ', ''):gsub('^declare ', '')
  local kw, rest = s:match '^(%a+)%s+(.*)$'
  if kw == 'function' then
    return rest, true
  elseif kw == 'const' or kw == 'let' or kw == 'var' or kw == 'readonly' then
    s = rest
  end
  local t = s:match '^[%w_$][%w_$%.]*%??%s*:%s*(.-)%s*;?$'
  if t then
    return t, false
  end
  return s, s:match '^[%w_$][%w_$%.]*%s*[<(]' ~= nil
end

-- the words a hover's code can start with and still be read as TypeScript
local LEADS = {
  const = true,
  let = true,
  var = true,
  ['function'] = true,
  class = true,
  interface = true,
  type = true,
  enum = true,
  namespace = true,
  module = true,
  export = true,
  declare = true,
}

--- The function a value is made by, `const x = f(…)` or `await a.f(…)`,
--- where its name is written, from the 0-based `row`, `col` of the value's
--- name in a file's tree: `{ line, col }`, the line 1-based; nil for a value
--- no call makes.
---@param root TSNode|nil
---@param row integer
---@param col integer
---@return { line: integer, col: integer }|nil
function M.maker(root, row, col)
  local n = root and root:named_descendant_for_range(row, col, row, col)
  local d = n and n:parent()
  local v = d and d:type() == 'variable_declarator' and d:field('value')[1]
  while v and (v:type() == 'await_expression' or v:type() == 'parenthesized_expression' or v:type() == 'non_null_expression') do
    v = v:named_child(0)
  end
  local f = v and v:type() == 'call_expression' and v:field('function')[1]
  f = f and f:type() == 'member_expression' and f:field('property')[1] or f
  if f and (f:type() == 'identifier' or f:type() == 'property_identifier') then
    local l, c = f:start()
    return { line = l + 1, col = c }
  end
end

---------------------------------------------------------------- the server

--- The session's server stopped, and all it said forgotten.
function M.stop()
  local c = S.id and vim.lsp.get_client_by_id(S.id)
  if c then
    -- asked to shut down, not killed: killed, Neovim reports it quit
    c:stop()
  end
  S = { got = {}, vals = {}, asking = {}, opened = {}, starts = 0 }
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
    -- gone before it answered: what was asked is asked again next time,
    -- not left asking
    on_exit = function()
      local session = S
      vim.schedule(function()
        if S == session then
          S.asking, S.queue = {}, {}
        end
      end)
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

-- seam opened again: the files read are read again
local function reread(got)
  if got.key and not code.has(got.key) then
    code.virtual(got.key, got.path, vim.fn.readfile(got.path))
  end
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
      local s, e, nm = M.decl(root, r.start.line, ok and col or r.start.character)
      if s then
        -- the declaration's own name: a location may start at the line, not the name
        local nr, nc, _, ne = (nm or root):range()
        local name = nm and (code.file(key).lines[nr + 1] or ''):sub(nc + 1, ne)
        return { key = key, path = fname, s = s + 1, e = e + 1, pkg = M.package(fname), name = name }
      end
    end
  end
end

--- The declaration of `name`, written in `path` (relative to the root) at
--- `at` (`line` 1-based, `col` a byte, 0-based), else where `path` first
--- writes it: `{ key, path, s, e, pkg, name }`, its lines s..e read as `key` is
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
  if got then
    reread(got)
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

-- the position the server is asked at: `at`'s byte as UTF-16
local function position(path, at)
  local ok, ch = pcall(vim.str_utfindex, code.file(path).lines[at.line] or '', 'utf-16', at.col, false)
  return { line = at.line - 1, character = ok and ch or at.col }
end

-- the package a definition's first location is in
local function where(locs)
  if type(locs) ~= 'table' then
    return nil
  end
  local loc = (locs.uri or locs.targetUri) and locs or locs[1]
  return loc and M.package(vim.uri_to_fname(loc.targetUri or loc.uri)) or nil
end

--- What the server says of the value made at `at` in `path` (`line`
--- 1-based, `col` a byte, 0-based), no type being written for it:
--- `{ code, type, fn, key, pre, pkg, def }`, its hover's code read as `key`
--- is (seam.code) from byte `pre` of its first line, the type it says, a
--- function's or not, the package its type is in, and that type's
--- declaration as `get` gives one, a value's only. Cached for the session
--- per place; the first time nil and true, the server asked, and `done`
--- called once it has answered; nil alone with no server, or when it said
--- nothing.
---@param path string
---@param at { line: integer, col: integer }
---@param done fun()
---@return table|nil, boolean|nil asking
function M.value(path, at, done)
  local k = path .. ':' .. at.line .. ':' .. at.col
  local got
  if S.root == st.root then
    got = S.vals[k]
  end
  if got then
    if not code.has(got.key) then
      code.virtual(got.key, 'hover.ts', got.lines)
    end
    if got.def then
      reread(got.def)
    end
    return got
  end
  if got == false then
    return nil
  end
  if S.root == st.root and S.asking[k] then
    return nil, true
  end
  local c = client()
  if not c then
    return nil
  end
  S.asking[k] = true
  local function ask()
    local params = { textDocument = { uri = open(c, path) }, position = position(path, at) }
    local hov, def, left, session = nil, nil, 2, S
    local function land()
      left = left - 1
      if left > 0 then
        return
      end
      local function said(v)
        if S ~= session then
          return
        end
        S.asking[k] = nil
        S.vals[k] = v
        done()
      end
      local text = hov and M.hover_code(hov.contents)
      if not text then
        return said(false)
      end
      local t, fn = M.hover_type(text)
      local lines = vim.split(text, '\n')
      -- a parameter's or a property's `x: T` read as a declaration
      local pre = LEADS[lines[1]:match '^%a+' or ''] and '' or 'let '
      lines[1] = pre .. lines[1]
      local v = { code = text, type = t, fn = fn, key = 'lookup-hover:' .. k, lines = lines, pre = #pre, pkg = where(def) }
      v.def = not fn and read(def) or nil
      code.virtual(v.key, 'hover.ts', lines)
      -- the server gives no definition for an intersection's type, `A & B`:
      -- A where the function that made the value writes it
      local first = not (fn or v.def) and t:match '^([%a_$][%w_$]*)'
      local maker = first and M.maker(code.tree(path), at.line - 1, at.col)
      if not maker then
        return said(v)
      end
      c:request('textDocument/definition', { textDocument = params.textDocument, position = position(path, maker) }, function(err, result)
        vim.schedule(function()
          local loc = not err and type(result) == 'table' and (result[1] or result)
          local fname = loc and (loc.targetUri or loc.uri) and vim.uri_to_fname(loc.targetUri or loc.uri)
          local rel = fname and fname:sub(1, #st.root + 1) == st.root .. '/' and fname:sub(#st.root + 2)
          if not rel then
            return said(v)
          end
          local k2 = first .. '\0' .. rel
          v.def = M.get(first, rel, nil, function()
            v.def = S.got[k2] or nil
            said(v)
          end)
          if v.def or not S.asking[k2] then
            said(v)
          end
        end)
      end)
    end
    for _, method in ipairs { 'textDocument/hover', 'textDocument/typeDefinition' } do
      c:request(method, params, function(err, result)
        vim.schedule(function()
          if method == 'textDocument/hover' then
            hov = not err and result or nil
          else
            def = not err and result or nil
          end
          land()
        end)
      end)
    end
  end
  if S.ready then
    ask()
  else
    S.queue[#S.queue + 1] = ask
  end
  return nil, true
end

return M
