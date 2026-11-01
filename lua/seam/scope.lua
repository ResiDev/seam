-- Scope in one file, from treesitter: what each block, function, loop and
-- catch binds (locals, parameters, names destructured, imports), the
-- binding a reference resolves to, and every reference to a binding.
local code = require 'seam.code'
local M = {}

local FN = {
  function_declaration = true,
  generator_function_declaration = true,
  arrow_function = true,
  function_expression = true,
  ['function'] = true,
  method_definition = true,
}

local SCOPE = { statement_block = true, program = true, for_in_statement = true, for_statement = true, catch_clause = true }
for k in pairs(FN) do
  SCOPE[k] = true
end

local REF = { identifier = true, shorthand_property_identifier = true }
M.FN, M.REF = FN, REF

---@class seam.Binding
---@field name string
---@field node any the identifier that binds it
---@field kind 'value'|'param'|'fn'|'import'|'class'|'loop'|'catch'
---@field decl any the declarator, parameter, function, loop or import
---@field field string|nil destructured: the field of what it came from
---@field scope any the node it is bound in

local function text(n, src)
  return vim.treesitter.get_node_text(n, src)
end

local function field(n, f)
  return n and n:field(f)[1]
end

local function annotation(n, src)
  return n and vim.trim((text(n, src):gsub('^:%s*', ''))) or nil
end

-- the file's tree and its caches, made again when the file is read again
local cache = setmetatable({}, { __mode = 'k' })
local function file(path)
  local root, src = code.tree(path)
  if not root then
    return nil
  end
  local C = cache[root]
  if not C then
    C = { root = root, src = src, path = path, binds = {} }
    cache[root] = C
  end
  return C
end

---------------------------------------------------------------- bindings

-- the names a pattern binds, each with the field it was destructured from
local function pattern(p, src, out, fld)
  local t = p:type()
  if t == 'identifier' or t == 'shorthand_property_identifier_pattern' then
    out[#out + 1] = { node = p, field = fld or (t ~= 'identifier' and text(p, src) or nil) }
  elseif t == 'object_pattern' then
    for c in p:iter_children() do
      local ct = c:type()
      if ct == 'shorthand_property_identifier_pattern' then
        out[#out + 1] = { node = c, field = text(c, src) }
      elseif ct == 'pair_pattern' then
        local k, v = field(c, 'key'), field(c, 'value')
        if k and v then
          pattern(v, src, out, text(k, src))
        end
      elseif ct == 'object_assignment_pattern' then
        local l = field(c, 'left')
        if l then
          pattern(l, src, out, l:type() == 'shorthand_property_identifier_pattern' and text(l, src) or nil)
        end
      elseif ct == 'rest_pattern' then
        local inner = c:named_child(0)
        if inner then
          pattern(inner, src, out)
        end
      end
    end
  elseif t == 'array_pattern' then
    for c in p:iter_children() do
      if c:named() then
        pattern(c, src, out)
      end
    end
  elseif t == 'assignment_pattern' then
    local l = field(p, 'left')
    if l then
      pattern(l, src, out, fld)
    end
  elseif t == 'rest_pattern' then
    local inner = p:named_child(0)
    if inner then
      pattern(inner, src, out)
    end
  end
  return out
end

local function bind(bs, scope, src, list, kind, decl)
  for _, x in ipairs(list) do
    local name = text(x.node, src)
    bs[name] = bs[name] or { name = name, node = x.node, kind = kind, decl = decl, field = x.field, scope = scope }
  end
end

local function declarations(bs, scope, src, d)
  for c in d:iter_children() do
    if c:type() == 'variable_declarator' and field(c, 'name') then
      bind(bs, scope, src, pattern(field(c, 'name'), src, {}), 'value', c)
    end
  end
end

-- the names a statement binds in the block it is in
local function statement(bs, scope, src, s)
  local t = s:type()
  if t == 'export_statement' then
    local d = field(s, 'declaration')
    if d then
      statement(bs, scope, src, d)
    end
  elseif t == 'lexical_declaration' or t == 'variable_declaration' then
    declarations(bs, scope, src, s)
  elseif t == 'function_declaration' or t == 'generator_function_declaration' then
    local n = field(s, 'name')
    if n then
      bind(bs, scope, src, { { node = n } }, 'fn', s)
    end
  elseif t == 'class_declaration' or t == 'abstract_class_declaration' then
    local n = field(s, 'name')
    if n then
      bind(bs, scope, src, { { node = n } }, 'class', s)
    end
  elseif t == 'import_statement' then
    for c in s:iter_children() do
      if c:type() == 'import_clause' then
        for x in c:iter_children() do
          if x:type() == 'identifier' then
            bind(bs, scope, src, { { node = x } }, 'import', s)
          elseif x:type() == 'namespace_import' then
            local id = x:named_child(0)
            if id then
              bind(bs, scope, src, { { node = id } }, 'import', s)
            end
          elseif x:type() == 'named_imports' then
            for sp in x:iter_children() do
              if sp:type() == 'import_specifier' then
                local n = field(sp, 'alias') or field(sp, 'name')
                if n then
                  bind(bs, scope, src, { { node = n } }, 'import', s)
                end
              end
            end
          end
        end
      end
    end
  end
end

-- what a scope binds, by name
local function bindings(C, scope)
  local id = scope:id()
  if C.binds[id] then
    return C.binds[id]
  end
  local bs, src, t = {}, C.src, scope:type()
  if FN[t] then
    local ps = field(scope, 'parameters')
    if ps then
      for p in ps:iter_children() do
        if (p:type() == 'required_parameter' or p:type() == 'optional_parameter') and field(p, 'pattern') then
          bind(bs, scope, src, pattern(field(p, 'pattern'), src, {}), 'param', p)
        end
      end
    elseif field(scope, 'parameter') then
      bind(bs, scope, src, { { node = field(scope, 'parameter') } }, 'param', field(scope, 'parameter'))
    end
  elseif t == 'for_in_statement' then
    local l = field(scope, 'left')
    if l then
      bind(bs, scope, src, pattern(l, src, {}), 'loop', scope)
    end
  elseif t == 'for_statement' then
    local i = field(scope, 'initializer')
    if i and (i:type() == 'lexical_declaration' or i:type() == 'variable_declaration') then
      declarations(bs, scope, src, i)
    end
  elseif t == 'catch_clause' then
    local p = field(scope, 'parameter')
    if p then
      bind(bs, scope, src, pattern(p, src, {}), 'catch', scope)
    end
  else
    for s in scope:iter_children() do
      statement(bs, scope, src, s)
    end
  end
  C.binds[id] = bs
  return bs
end

-- the binding a reference resolves to, the nearest scope out first
local function resolve(C, n)
  local name = text(n, C.src)
  local s = n:parent()
  while s do
    if SCOPE[s:type()] then
      local b = bindings(C, s)[name]
      if b then
        return b
      end
    end
    s = s:parent()
  end
end

-- the references to binding `b` in its scope, its own name left out
local function refs(C, b)
  local out, src = {}, C.src
  local function walk(n)
    for c in n:iter_children() do
      if REF[c:type()] then
        if c:id() ~= b.node:id() and text(c, src) == b.name then
          local r = resolve(C, c)
          if r and r.node:id() == b.node:id() then
            local l, s = c:start()
            local _, e = c:end_()
            out[#out + 1] = { line = l + 1, col = s, e = e }
          end
        end
      elseif c:named_child_count() > 0 then
        walk(c)
      end
    end
  end
  walk(b.scope)
  table.sort(out, function(a, x)
    return a.line < x.line or (a.line == x.line and a.col < x.col)
  end)
  return out
end

M.text, M.field, M.annotation, M.file, M.resolve, M.refs = text, field, annotation, file, resolve, refs

--- The names a pattern binds: `{ node, field }` each.
---@param p any
---@param src string
---@return table[]
function M.pattern(p, src)
  return pattern(p, src, {})
end

return M
