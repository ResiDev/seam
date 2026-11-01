-- What changed from a commit, `from`, to the working tree, the files as
-- seam reads them: each file new, changed or gone, and its lines then,
-- asked of git in the background; each declaration of a file new, gone or
-- changed by its text under treesitter, a changed function's signature or
-- body by what it takes and gives as written. The range is `st.range`, what
-- git said `st.changes`.
local code = require 'seam.code'
local st = require 'seam.state'
local written = require 'seam.written'
local M = {}

-- the environment git runs in, for the check's own repository
M.env = nil

---@class seam.Range
---@field from string a ref; the range always ends at the working tree

---@class seam.Changes
---@field root string
---@field range seam.Range
---@field key string
---@field pending boolean git has not answered yet
---@field err string|nil what git said when it would not
---@field files table<string, 'new'|'changed'|'gone'> the TypeScript files that changed
---@field list string[] the same, sorted
---@field old table<string, string[]> a file's lines at `from`
---@field decls table<string, seam.FileDecls> what changed in each file, as asked

--- The range shown, from HEAD to the working tree until one is picked.
---@return seam.Range
function M.range()
  st.range = st.range or { from = 'HEAD' }
  return st.range
end

---@param r seam.Range
---@return boolean
function M.is_default(r)
  return r.from == 'HEAD'
end

local function key_of(r)
  return r.from
end

--- What git said of the range shown, once it has.
---@return seam.Changes|nil
function M.get()
  local C = st.changes
  if C and C.root == st.root and C.key == key_of(M.range()) and not C.pending then
    return C
  end
end

--- Did anything change in the range shown?
---@return boolean
function M.any()
  local C = M.get()
  return C ~= nil and #C.list > 0
end

--- The files the tree can hold: TypeScript, no declarations file.
---@param path string
---@return boolean
function M.is_ts(path)
  return path:match '%.[cm]?tsx?$' ~= nil and not path:match '%.d%.[cm]?tsx?$'
end

local function lines_of(text)
  local out = vim.split((text:gsub('\r\n', '\n')), '\n', { plain = true })
  if out[#out] == '' then
    out[#out] = nil
  end
  return out
end

-- the blobs `git cat-file --batch` gave, in the order asked; false for one missing
local function blobs(out, n)
  local res, i = {}, 1
  for k = 1, n do
    local nl = out:find('\n', i, true)
    if not nl then
      break
    end
    local size = tonumber(out:sub(i, nl - 1):match '^%x+ blob (%d+)$')
    if size then
      res[k] = out:sub(nl + 1, nl + size)
      i = nl + size + 2
    else
      res[k] = false
      i = nl + 1
    end
  end
  return res
end

local function git(root, args, stdin, cb)
  local cmd = vim.list_extend({ 'git', '-C', root }, args)
  vim.system(cmd, { stdin = stdin, env = M.env, text = false }, function(r)
    vim.schedule(function()
      cb(r)
    end)
  end)
end

--- Ask git what changed in the range shown, in the background; `done`
--- once it has said, unless the range changed meanwhile.
---@param root string
---@param done? fun()
function M.ask(root, done)
  local r = vim.deepcopy(M.range())
  ---@type seam.Changes
  local C = { root = root, range = r, key = key_of(r), pending = true, files = {}, list = {}, old = {}, decls = {} }
  st.changes = C
  local function finish(err)
    C.pending, C.err = false, err
    C.list = vim.tbl_keys(C.files)
    table.sort(C.list)
    if st.changes == C and done then
      done()
    end
  end
  local function said(res)
    return vim.trim(((res.stderr or ''):match '[^\n]+' or ''))
  end
  local function texts()
    local specs, at = {}, {}
    for path, s in pairs(C.files) do
      if s ~= 'new' then
        specs[#specs + 1] = r.from .. ':' .. path
        at[#at + 1] = { C.old, path }
      end
    end
    if #specs == 0 then
      return finish()
    end
    git(root, { 'cat-file', '--batch' }, table.concat(specs, '\n') .. '\n', function(res)
      if st.changes ~= C then
        return
      end
      for k, text in pairs(blobs(res.stdout or '', #specs)) do
        if text then
          at[k][1][at[k][2]] = lines_of(text)
        end
      end
      finish()
    end)
  end
  local args = { 'diff', '--name-status', '--no-renames', '-z', r.from, '--' }
  git(root, args, nil, function(res)
    if st.changes ~= C then
      return
    end
    if res.code ~= 0 then
      return finish(said(res))
    end
    local parts = vim.split(res.stdout or '', '\0', { plain = true })
    for i = 1, #parts - 1, 2 do
      local s, path = parts[i], parts[i + 1]
      if M.is_ts(path) then
        C.files[path] = s == 'A' and 'new' or s == 'D' and 'gone' or 'changed'
      end
    end
    git(root, { 'ls-files', '--others', '--exclude-standard', '-z' }, nil, function(u)
      if st.changes ~= C then
        return
      end
      for _, path in ipairs(vim.split(u.stdout or '', '\0', { plain = true, trimempty = true })) do
        if M.is_ts(path) then
          C.files[path] = 'new'
        end
      end
      texts()
    end)
  end)
end

--- The key code reads a file's version by, at `from` or at `to`, the
--- working tree: there the file itself; nil where it is not there.
---@param C seam.Changes
---@param path string
---@param side 'from'|'to'
---@return string|nil
function M.key(C, path, side)
  local s = C.files[path]
  if side == 'to' then
    return s ~= 'gone' and path or nil
  end
  if not s then
    -- unchanged: the same at both ends, so the working tree's
    return path
  end
  local lines = C.old[path]
  if not lines then
    return nil
  end
  local k = 'git:' .. C.range.from .. ':' .. path
  if not code.has(k) then
    code.virtual(k, path, lines)
  end
  return k
end

--- A version's lines: at `from` or at `to`, by its key; empty where it is not there.
---@param key string|nil
---@return string[]
function M.lines(key)
  return key and code.file(key).lines or {}
end

---------------------------------------------------------------- declarations

---@class seam.Decl
---@field name string
---@field kind 'fn'|'class'|'type'|'value'
---@field line integer where its statement starts
---@field s integer where it starts, its doc comment with it
---@field e integer
---@field text string lines s..e

local TYPE = { type_alias_declaration = 'type', interface_declaration = 'type', enum_declaration = 'type' }
local CLASS = { class_declaration = true, abstract_class_declaration = true }
local FN = { function_declaration = true, generator_function_declaration = true }
local FNV = { arrow_function = true, function_expression = true, ['function'] = true, generator_function = true }

--- The declarations at the top of a version of a file, read by `key`, in its order.
---@param key string
---@return seam.Decl[]
function M.decls_of(key)
  local root, src = code.tree(key)
  if not root then
    return {}
  end
  local P = code.file(key)
  local out, by = {}, {}
  local function add(name, kind, node)
    local sr, _, er, ec = node:range()
    local e = (ec == 0 and er > sr) and er or er + 1
    local old = by[name]
    if old then
      -- merged declarations and overloads: one, as long as all of them
      old.e = math.max(old.e, e)
      old.text = table.concat(P.lines, '\n', old.s, old.e)
      return
    end
    local s = code.doc_start(key, sr + 1)
    local d = { name = name, kind = kind, line = sr + 1, s = s, e = e, text = table.concat(P.lines, '\n', s, e) }
    by[name] = d
    out[#out + 1] = d
  end
  for c in root:iter_children() do
    local d = c:type() == 'export_statement' and c:field('declaration')[1] or c
    local t = d and d:type()
    local name = d and d:field('name')[1]
    if FN[t] and name then
      add(vim.treesitter.get_node_text(name, src), 'fn', c)
    elseif CLASS[t] and name then
      add(vim.treesitter.get_node_text(name, src), 'class', c)
    elseif TYPE[t] and name then
      add(vim.treesitter.get_node_text(name, src), 'type', c)
    elseif t == 'lexical_declaration' or t == 'variable_declaration' then
      for v in d:iter_children() do
        local n = v:type() == 'variable_declarator' and v:field('name')[1]
        if n and n:type() == 'identifier' then
          local val = v:field('value')[1]
          add(vim.treesitter.get_node_text(n, src), val and FNV[val:type()] and 'fn' or 'value', c)
        end
      end
    end
  end
  return out
end

-- what a function takes and gives as written, as one string to compare
local function sig_of(key, line)
  local s = written.fn(key, line)
  if not s then
    return ''
  end
  local parts = {}
  for _, p in ipairs(s.tparams) do
    parts[#parts + 1] = '<' .. p.text
  end
  for _, p in ipairs(s.params) do
    parts[#parts + 1] = p.name .. (p.optional and '?' or '') .. ':' .. (p.type or '')
  end
  return table.concat(parts, ',') .. '=>' .. (s.ret or '')
end

---@class seam.DeclChange
---@field name string
---@field kind string
---@field state 'new'|'gone'|'signature'|'body'|'changed'|nil nil when the same
---@field from seam.Decl|nil
---@field to seam.Decl|nil

---@class seam.FileDecls
---@field list seam.DeclChange[] in the order at `to`, then the gone in the order at `from`
---@field by table<string, seam.DeclChange>
---@field before seam.Decl[] the declarations at `from`, in its order

--- The declarations of two versions of a file compared by name: each new,
--- gone, or changed by its text; a changed function's signature when what
--- it takes or gives as written differs, else its body.
---@param ka string|nil the key of the version at `from`
---@param kb string|nil at `to`
---@return seam.FileDecls
function M.compare(ka, kb)
  local A = ka and M.decls_of(ka) or {}
  local B = kb and M.decls_of(kb) or {}
  local at = {}
  for _, d in ipairs(A) do
    at[d.name] = d
  end
  local res = { list = {}, by = {}, before = A }
  local function put(x)
    res.list[#res.list + 1] = x
    res.by[x.name] = x
  end
  for _, b in ipairs(B) do
    local a = at[b.name]
    local s
    if not a then
      s = 'new'
    elseif a.text ~= b.text then
      if b.kind == 'fn' and a.kind == 'fn' then
        s = sig_of(ka, a.line) == sig_of(kb, b.line) and 'body' or 'signature'
      else
        s = 'changed'
      end
    end
    put { name = b.name, kind = b.kind, state = s, from = a, to = b }
  end
  for _, a in ipairs(A) do
    if not res.by[a.name] then
      put { name = a.name, kind = a.kind, state = 'gone', from = a }
    end
  end
  return res
end

--- What changed in each declaration of `path`, nil when the file did not change.
---@param C seam.Changes
---@param path string
---@return seam.FileDecls|nil
function M.file(C, path)
  if not C.files[path] then
    return nil
  end
  local f = C.decls[path]
  if not f then
    f = M.compare(M.key(C, path, 'from'), M.key(C, path, 'to'))
    C.decls[path] = f
  end
  return f
end

--- How the declaration `name` of `path` changed, nil when it did not.
---@param C seam.Changes
---@param path string
---@param name string
---@return seam.DeclChange|nil
function M.decl(C, path, name)
  local f = M.file(C, path)
  local d = f and f.by[name]
  return d and d.state and d or nil
end

--- How many declarations of `path` changed.
---@param C seam.Changes
---@param path string
---@return integer
function M.count(C, path)
  local n = 0
  for _, d in ipairs((M.file(C, path) or { list = {} }).list) do
    n = n + (d.state and 1 or 0)
  end
  return n
end

---------------------------------------------------------------- uses at `from`

-- is `n` inside an import, or an export's list of names?
local function in_import(n)
  local p = n:parent()
  while p and p:type() ~= 'program' do
    if p:type() == 'import_statement' or p:type() == 'export_clause' then
      return true
    end
    p = p:parent()
  end
  return false
end

local DECL = { function_declaration = true, generator_function_declaration = true, variable_declarator = true, class_declaration = true }

-- is `n` the name of a declaration at the top of its file?
local function own(n)
  local p = n:parent()
  local nm = p and DECL[p:type()] and p:field('name')[1]
  if not (nm and nm:id() == n:id()) then
    return false
  end
  local q = p:parent()
  while q and q:type() ~= 'program' do
    if q:type() == 'statement_block' or q:type() == 'class_body' then
      return false
    end
    q = q:parent()
  end
  return true
end

--- Where `name` was named at `from` in `path`: each identifier of that name
--- outside the imports and its own declaration, in a file that imports it
--- or is `home`, its own. Each `{ line, col }`, 1-based.
---@param C seam.Changes
---@param path string
---@param name string
---@param home string
---@return { line: integer, col: integer }[]
function M.named_at_from(C, path, name, home)
  local key = M.key(C, path, 'from')
  local lines = M.lines(key)
  local text = table.concat(lines, '\n')
  if not key or not text:find(name, 1, true) then
    return {}
  end
  local root, src = code.tree(key)
  if not root then
    return {}
  end
  local found, imported = {}, path == home
  local stack = { root }
  while #stack > 0 do
    local n = table.remove(stack)
    local t = n:type()
    if (t == 'identifier' or t == 'shorthand_property_identifier') and vim.treesitter.get_node_text(n, src) == name then
      if in_import(n) then
        imported = imported or n:parent():type() == 'import_specifier'
      elseif not own(n) then
        local r, c = n:start()
        found[#found + 1] = { line = r + 1, col = c + 1 }
      end
    end
    for i = n:named_child_count() - 1, 0, -1 do
      stack[#stack + 1] = n:named_child(i)
    end
  end
  if not imported then
    return {}
  end
  table.sort(found, function(a, b)
    return a.line < b.line or (a.line == b.line and a.col < b.col)
  end)
  return found
end

return M
