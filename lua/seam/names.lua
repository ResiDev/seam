-- What a name in the code is, from treesitter and the index alone: the
-- binding it resolves to in its function (a local, a parameter, a name
-- destructured, a loop's), a repo function or type, an import; the type of
-- a value as written, else the declared return of the call that made it;
-- a field or method of a type, from the type's declaration; and the later
-- uses of a binding. No windows, so the specs drive it on source text.
local code = require 'seam.code'
local scope = require 'seam.scope'
local tv = require 'seam.typesview'
local written = require 'seam.written'
local M = {}

local FN, REF = scope.FN, scope.REF
local text, field, annotation, file, resolve, refs = scope.text, scope.field, scope.annotation, scope.file, scope.resolve, scope.refs

---@class seam.Name
---@field kind 'call'|'method'|'value'|'param'|'field'|'type'|'file'
---@field name string the name under the cursor
---@field line integer
---@field col integer 0-based, where the name starts
---@field e integer 0-based, past its end
---@field id string|nil a call: the repo function's node id
---@field path string|nil a file: the path of the import's file
---@field type string|nil a value's, a parameter's, a field's type, as written or declared
---@field decl table|nil the repo type: { name, kind, path, line, end_line } (a type; the type a field or method is of)
---@field object string|nil a field or method: what it is read from, as written
---@field member table|nil a field or method: { name, line, doc, end_line, type, ret }
---@field made_by { name: string, id: string|nil }|nil a value: the call that made it
---@field at { line: integer, col: integer }|nil a value or parameter: where it is bound
---@field fn string|nil a parameter: the function it is one of
---@field uses { line: integer, col: integer, e: integer }[]|nil its later uses, a value's or the value a call made
---@field declares boolean|nil a function's own name where it is declared, not a call

---------------------------------------------------------------- the index

-- the names this file imports from another, by the name written here: the
-- exports whose uses are in it
local function imports(m, C)
  m.name_imports = m.name_imports or {}
  local got = m.name_imports[C.path]
  if got then
    return got
  end
  got = {}
  local lines = code.file(C.path).lines
  for _, e in ipairs(m.exports or {}) do
    for _, u in ipairs(e.uses or {}) do
      if u.path == C.path and e.path ~= C.path then
        local w = (lines[u.line] or ''):match('^[%a_$][%w_$]*', u.col)
        if w then
          got[w] = got[w] or e
        end
      end
    end
  end
  m.name_imports[C.path] = got
  return got
end

-- the repo function a name in this file means: imported, or declared at
-- its top; its node
local function repo_fn(m, C, name)
  local g = m.graph
  if not g then
    return nil
  end
  local e = imports(m, C)[name]
  if e and g.nodes[e.id] and g.nodes[e.id].kind ~= 'module' then
    return g.nodes[e.id]
  end
  for _, n in ipairs(require('seam.outline').by_file(g)[C.path] or {}) do
    if n.name == name and n.kind ~= 'module' then
      return n
    end
  end
end

--- The repo type `name` means in `path`: declared there, else the repo's of
--- that name, the one in `path` first.
---@param m table
---@param name string
---@param path string
---@return table|nil { name, kind, path, line, end_line }
function M.type_decl(m, name, path)
  local t = written.type_in(path, name)
  if t then
    return t
  end
  local f = m.flows and m.flows[name]
  if not f then
    return nil
  end
  for _, e in ipairs(f.decls) do
    if e.path == path then
      return e
    end
  end
  return f.decls[1]
end

--- The written return of the repo function `id`, else the server's when it
--- names a type rather than writing a shape out; `Readonly<…>` left out.
---@param m table
---@param id string
---@return string|nil
function M.ret(m, id)
  local n = m.graph and m.graph.nodes[id]
  if not n then
    return nil
  end
  local w = written.fn(n.path, n.line)
  local r = w and w.ret
  if not r then
    local s = m.sigs and m.sigs[id]
    r = s and s.ret
    if r and (r:find '[{\n]' or #r > 60) then
      r = nil
    end
  end
  return r and vim.trim(tv.unwrap(r)) or nil
end

---------------------------------------------------------------- members

local MEMBER = { property_signature = true, method_signature = true, public_field_definition = true, method_definition = true }

-- the one type a type's text names: `X | undefined` is X, `Readonly<X>` X, `X<A>` X
local function base_name(t)
  t = vim.trim(tv.unwrap(t or ''))
  local parts = {}
  for p in (t .. '|'):gmatch '([^|]+)|' do
    p = vim.trim(p)
    if p ~= 'undefined' and p ~= 'null' and p ~= '' then
      parts[#parts + 1] = p
    end
  end
  if #parts ~= 1 then
    return nil
  end
  return parts[1]:match '^([%a_$][%w_$]*)%s*<' or parts[1]:match '^([%a_$][%w_$]*)$'
end
M.base_name = base_name

-- the statement declaring a type on `line` of its file
local function decl_node(C, line)
  local n = C.root:named_descendant_for_range(line - 1, 0, line - 1, 0)
  while n and n:parent() and n:parent():type() ~= 'program' do
    n = n:parent()
  end
  if n and n:type() == 'export_statement' then
    n = field(n, 'declaration') or n
  end
  return n
end

local function member_record(C, n, d)
  local src = C.src
  local name = text(field(n, 'name'), src)
  local sr, _, er = n:range()
  local ty, ret
  local tn = field(n, 'type')
  if tn then
    ty = annotation(tn, src)
    local f = tn:named_child(0)
    if f and f:type() == 'function_type' then
      ret = annotation(field(f, 'return_type'), src)
    end
  elseif n:type() == 'method_signature' or n:type() == 'method_definition' then
    local ps = field(n, 'parameters')
    ret = annotation(field(n, 'return_type'), src)
    ty = (ps and text(ps, src) or '()') .. ' => ' .. (ret or 'unknown')
  end
  return {
    name = name,
    line = sr + 1,
    end_line = er + 1,
    doc = code.doc_start(C.path, sr + 1),
    type = ty and ty:gsub('%s+', ' '),
    ret = ret,
    decl = d,
  }
end

--- The field or method `name` of the type a type's text names: its line
--- in the type's declaration, its doc comment's, its type and return. One
--- it extends or is made of is looked in too, three deep.
---@param m table
---@param type_text string
---@param name string
---@param path string where the type is named
---@param depth? integer
---@return table|nil
function M.member(m, type_text, name, path, depth)
  depth = depth or 0
  local tn = base_name(type_text)
  local d = tn and M.type_decl(m, tn, path)
  local C = d and file(d.path)
  if not C or depth > 3 then
    return nil
  end
  local top = decl_node(C, d.line)
  if not top then
    return nil
  end
  local queue, found = { top }, nil
  while #queue > 0 and not found do
    local n = table.remove(queue, 1)
    for c in n:iter_children() do
      if c:named() then
        if MEMBER[c:type()] and field(c, 'name') and text(field(c, 'name'), C.src) == name then
          found = c
          break
        end
        if not (c:type() == 'function_type' or c:type() == 'statement_block' or c:type() == 'formal_parameters') then
          queue[#queue + 1] = c
        end
      end
    end
  end
  if found then
    return member_record(C, found, d)
  end
  -- what it extends or is made of: each type named outside an object
  local seen = {}
  local function others(n)
    for c in n:iter_children() do
      if c:type() == 'type_identifier' and not seen[text(c, C.src)] then
        seen[text(c, C.src)] = true
        local r = text(c, C.src) ~= tn and M.member(m, text(c, C.src), name, d.path, depth + 1)
        if r then
          return r
        end
      elseif c:named() and c:type() ~= 'object_type' and c:type() ~= 'interface_body' and c:type() ~= 'type_parameters' then
        local r = others(c)
        if r then
          return r
        end
      end
    end
  end
  return others(top)
end

---------------------------------------------------------------- types

local type_of

-- an array's or a set's element type
local function element(t)
  t = vim.trim(tv.unwrap(t or ''):gsub('^readonly%s+', ''))
  return t:match '^([%w_$%.<>, ]+)%[%]$'
    or t:match '^%((.*)%)%[%]$'
    or t:match '^Array<(.*)>$'
    or t:match '^ReadonlyArray<(.*)>$'
    or t:match '^Set<(.*)>$'
    or t:match '^ReadonlySet<(.*)>$'
end

-- a function's parameters as written, `(a: A, b?: B)`, defaults left out
local function params_text(C, f)
  local ps = field(f, 'parameters')
  if not ps then
    local p = field(f, 'parameter')
    return '(' .. (p and text(p, C.src) or '') .. ')'
  end
  local out = {}
  for p in ps:iter_children() do
    local t = p:type()
    if (t == 'required_parameter' or t == 'optional_parameter') and field(p, 'pattern') then
      local s = text(field(p, 'pattern'), C.src) .. (t == 'optional_parameter' and '?' or '')
      local ty = annotation(field(p, 'type'), C.src)
      out[#out + 1] = (s .. (ty and (': ' .. ty) or '')):gsub('%s+', ' ')
    end
  end
  return '(' .. table.concat(out, ', ') .. ')'
end
M.params_text = function(path, f)
  return params_text(file(path), f)
end

-- what a function gives: its return as written, else its expression body's type
local function fn_ret(m, C, f)
  local r = annotation(field(f, 'return_type'), C.src)
  if r then
    return r, true
  end
  local b = field(f, 'body')
  if b and b:type() ~= 'statement_block' then
    local t = type_of(m, C, b)
    return t and t.text, false
  end
end

-- the type of a binding: written, else what made it
local function binding_type(m, C, b)
  local src = C.src
  if b.kind == 'param' then
    local t = annotation(field(b.decl, 'type'), src)
    if t and b.field then
      local mem = M.member(m, t, b.field, C.path)
      return mem and mem.type and { text = mem.type, from = t, written = true }
    end
    return t and { text = t, written = true }
  elseif b.kind == 'value' then
    local t = annotation(field(b.decl, 'type'), src)
    local v = field(b.decl, 'value')
    local got = t and { text = t, written = true } or (v and type_of(m, C, v))
    if got and b.field then
      local mem = M.member(m, got.text, b.field, C.path)
      return mem and mem.type and { text = mem.type, from = got.text, written = false }
    end
    return got
  elseif b.kind == 'loop' then
    local r = field(b.decl, 'right')
    local t = r and type_of(m, C, r)
    local e = t and element(t.text)
    return e and { text = e, written = false }
  elseif b.kind == 'fn' then
    local r = fn_ret(m, C, b.decl)
    return { text = params_text(C, b.decl) .. ' => ' .. (r or '…'), written = true, fn = true }
  end
end

-- the type of an expression, from what is written and what made it
type_of = function(m, C, n)
  local t, src = n:type(), C.src
  if REF[t] then
    local b = resolve(C, n)
    return b and binding_type(m, C, b)
  elseif t == 'parenthesized_expression' or t == 'non_null_expression' then
    local inner = n:named_child(0)
    return inner and type_of(m, C, inner)
  elseif t == 'await_expression' then
    local inner = n:named_child(0)
    local got = inner and type_of(m, C, inner)
    if got then
      got = vim.deepcopy(got)
      got.text = got.text:match '^Promise<(.*)>$' or got.text
    end
    return got
  elseif t == 'as_expression' or t == 'satisfies_expression' then
    local ty = n:named_child(1)
    return ty and { text = text(ty, src), written = true }
  elseif t == 'new_expression' then
    local c = field(n, 'constructor')
    local ta = field(n, 'type_arguments')
    return c and { text = text(c, src) .. (ta and text(ta, src) or ''), written = true }
  elseif t == 'member_expression' then
    local o, p = field(n, 'object'), field(n, 'property')
    local ot = o and type_of(m, C, o)
    local mem = ot and p and M.member(m, ot.text, text(p, src), C.path)
    return mem and mem.type and { text = mem.type, written = false }
  elseif t == 'call_expression' then
    local f = field(n, 'function')
    if not f then
      return nil
    end
    if f:type() == 'identifier' then
      local b = resolve(C, f)
      if b and b.kind == 'fn' then
        local r = fn_ret(m, C, b.decl)
        return r and { text = r, written = false, made_by = { name = b.name } }
      end
      local node = (not b or b.kind == 'import') and repo_fn(m, C, text(f, src))
      local r = node and M.ret(m, node.id)
      return r and { text = r, written = false, made_by = { name = node.name, id = node.id } }
    elseif f:type() == 'member_expression' then
      local o, p = field(f, 'object'), field(f, 'property')
      local ot = o and type_of(m, C, o)
      local mem = ot and p and M.member(m, ot.text, text(p, src), C.path)
      return mem and mem.ret and { text = mem.ret, written = false, made_by = { name = text(f, src) } }
    end
  elseif FN[t] then
    local r, w = fn_ret(m, C, n)
    return { text = params_text(C, n) .. ' => ' .. (r or '…'), written = w, fn = true, ret = r }
  end
end

---------------------------------------------------------------- at the cursor

-- the declarator a call makes the value of, through await and brackets
local function made(n)
  local p = n:parent()
  while p and (p:type() == 'await_expression' or p:type() == 'parenthesized_expression' or p:type() == 'non_null_expression') do
    n, p = p, p:parent()
  end
  if p and p:type() == 'variable_declarator' and field(p, 'value') and field(p, 'value'):id() == n:id() then
    local name = field(p, 'name')
    return name and name:type() == 'identifier' and name or nil
  end
end

local function later(list, line, col)
  return vim.tbl_filter(function(u)
    return u.line > line or (u.line == line and u.col > col)
  end, list)
end

--- What the name at `line` (1-based), byte `col` (0-based) of `path` is,
--- nil off a name or for one that is no repo function, type, file, value,
--- parameter or member.
---@param m table the model
---@param path string
---@param line integer
---@param col integer
---@return seam.Name|nil
function M.at(m, path, line, col)
  local C = file(path)
  if not C then
    return nil
  end
  local n = C.root:named_descendant_for_range(line - 1, col, line - 1, col)
  if not n then
    return nil
  end
  local t, src = n:type(), C.src
  local sr, sc = n:start()
  local _, ec = n:end_()
  local name = text(n, src)
  local base = { name = name, line = sr + 1, col = sc, e = ec }
  local function with(x)
    return vim.tbl_extend('force', base, x)
  end
  if t == 'type_identifier' then
    local d = M.type_decl(m, name, path)
    return d and with { kind = 'type', decl = d } or nil
  end
  if t == 'property_identifier' then
    local p = n:parent()
    if not (p and p:type() == 'member_expression' and field(p, 'property'):id() == n:id()) then
      return nil
    end
    local o = field(p, 'object')
    local ot = o and type_of(m, C, o)
    local mem = ot and M.member(m, ot.text, name, path)
    if not mem then
      return nil
    end
    local call = p:parent() and p:parent():type() == 'call_expression' and field(p:parent(), 'function'):id() == p:id()
    return with {
      kind = call and 'method' or 'field',
      object = text(o, src),
      member = mem,
      decl = mem.decl,
      type = mem.type,
    }
  end
  if not (REF[t] or t == 'shorthand_property_identifier_pattern') then
    return nil
  end
  local b = resolve(C, n)
  if b and (b.kind == 'value' or b.kind == 'param' or b.kind == 'loop') then
    local bt = binding_type(m, C, b)
    local bl, bc = b.node:start()
    local all = refs(C, b)
    local x = with {
      kind = b.kind == 'param' and 'param' or 'value',
      type = bt and bt.text,
      made_by = bt and bt.made_by,
      at = { line = bl + 1, col = bc },
      uses = later(all, bl + 1, bc),
      count = #all,
    }
    if b.field and bt and bt.from then
      x.kind, x.object = 'field', nil
      x.member = M.member(m, bt.from, b.field, path)
      x.decl = x.member and x.member.decl
    end
    if b.kind == 'param' then
      local f = b.decl:parent() and b.decl:parent():parent()
      local fname = f and (field(f, 'name') or (f:parent() and f:parent():type() == 'variable_declarator' and field(f:parent(), 'name')))
      x.fn = fname and text(fname, src) or nil
    end
    local d = x.type and base_name(x.type) and M.type_decl(m, base_name(x.type), path)
    x.decl = x.decl or d
    return x
  end
  if b and (b.kind == 'fn' or b.kind == 'class') and b.scope:type() ~= 'program' then
    -- a function inside this one: a value of its own
    local bt = binding_type(m, C, b)
    local bl, bc = b.node:start()
    local all = refs(C, b)
    return with { kind = 'value', type = bt and bt.text, at = { line = bl + 1, col = bc }, uses = later(all, bl + 1, bc), count = #all }
  end
  -- a name of the repo's: a function, a type, a file's export
  local e = imports(m, C)[name]
  local node = (not b or b.kind == 'import' or b.kind == 'fn') and repo_fn(m, C, name)
  if node then
    local call = n:parent()
    local v = call and call:type() == 'call_expression' and field(call, 'function'):id() == n:id() and made(call)
    local x = with { kind = 'call', id = node.id, declares = b ~= nil and b.node:id() == n:id() or nil }
    if v then
      local vb = resolve(C, v)
      if vb then
        local vl, vc = v:start()
        x.uses = later(refs(C, vb), vl + 1, vc)
      end
    end
    return x
  end
  local d = M.type_decl(m, name, path)
  if d and (not b or b.kind == 'import' or b.kind == 'class') then
    return with { kind = 'type', decl = d }
  end
  if e then
    return with { kind = 'file', path = e.path }
  end
end

--- The name at `col` on `line`, else the one on that line nearest it that
--- answers; nil on a line with none.
---@param m table the model
---@param path string
---@param line integer
---@param col integer
---@return seam.Name|nil
function M.near(m, path, line, col)
  local hit = col >= 0 and M.at(m, path, line, col)
  if hit then
    return hit
  end
  local C = file(path)
  if not C then
    return nil
  end
  local row, leaves = line - 1, {}
  local function walk(n)
    for c in n:iter_children() do
      local sr, _, er = c:range()
      if sr <= row and er >= row then
        if c:named_child_count() == 0 then
          if c:named() and sr == row then
            local _, sc, _, ec = c:range()
            leaves[#leaves + 1] = { sc, ec }
          end
        else
          walk(c)
        end
      end
    end
  end
  walk(C.root)
  local function dist(x)
    return col < x[1] and x[1] - col or col >= x[2] and col - x[2] + 1 or 0
  end
  table.sort(leaves, function(a, b)
    local da, db = dist(a), dist(b)
    return da < db or da == db and a[1] < b[1]
  end)
  for _, x in ipairs(leaves) do
    local n = M.at(m, path, line, x[1])
    if n then
      return n
    end
  end
end

--- The uses of the binding at `line`, `col` after it, in its scope.
---@param path string
---@param line integer
---@param col integer
---@return { line: integer, col: integer, e: integer }[]
function M.uses(path, line, col)
  local C = file(path)
  local n = C and C.root:named_descendant_for_range(line - 1, col, line - 1, col)
  local b = n and REF[n:type()] and resolve(C, n)
  return b and refs(C, b) or {}
end

--- The type of the expression node `n` in `path`, `{ text, written, made_by }`.
---@param m table
---@param path string
---@param n any
---@return table|nil
function M.type_of(m, path, n)
  local C = file(path)
  return C and type_of(m, C, n)
end

--- What a function gives, `ret, written`: its return as written, else its
--- expression body's type.
---@param m table
---@param path string
---@param f any
---@return string|nil, boolean|nil
function M.fn_ret(m, path, f)
  local C = file(path)
  if C then
    return fn_ret(m, C, f)
  end
end

--- The type of the binding the name at `line`, `col` resolves to,
--- `{ text, written, made_by }`.
---@param m table
---@param path string
---@param line integer
---@param col integer
---@return table|nil
function M.binding_type(m, path, line, col)
  local C = file(path)
  local n = C and C.root:named_descendant_for_range(line - 1, col, line - 1, col)
  local b = n and (REF[n:type()] or n:type() == 'shorthand_property_identifier_pattern') and resolve(C, n)
  return b and binding_type(m, C, b)
end

--- The names a pattern binds: `{ node, field }` each.
---@param path string
---@param p any
---@return table[]
function M.pattern(path, p)
  return scope.pattern(p, file(path).src)
end

--- The tree and source of `path`, for what walks it.
---@param path string
---@return any|nil root, string|nil src
function M.tree(path)
  local C = file(path)
  return C and C.root, C and C.src
end

return M
