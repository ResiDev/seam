-- What a file has written, asked of its treesitter tree: a function's
-- signature as written, and the types the file declares.
local code = require 'seam.code'
local tv = require 'seam.typesview'
local M = {}

local FN = {
  function_declaration = true,
  generator_function_declaration = true,
  arrow_function = true,
  function_expression = true,
  ['function'] = true,
  method_definition = true,
}

local TYPE = {
  type_alias_declaration = 'type',
  interface_declaration = 'interface',
  class_declaration = 'class',
  abstract_class_declaration = 'class',
  enum_declaration = 'enum',
}

local function text(n, src)
  return vim.treesitter.get_node_text(n, src)
end

local function field(n, f)
  return n and n:field(f)[1]
end

-- the first function at or under `n`, depth first
local function first_fn(n)
  if FN[n:type()] then
    return n
  end
  for c in n:iter_children() do
    if c:named() then
      local f = first_fn(c)
      if f then
        return f
      end
    end
  end
end

-- a type annotation's text without its colon
local function annotation(n, src)
  return n and vim.trim((text(n, src):gsub('^:%s*', ''))) or nil
end

--- The signature written for the function declared on `line` of `path`:
--- its type parameters, its parameters with their types where written,
--- and its return where written. Nil when no function starts there.
---@param path string
---@param line integer
---@return seam.TSig|nil
function M.fn(path, line)
  local root, src = code.tree(path)
  local l = code.file(path).lines[line]
  if not root or not l then
    return nil
  end
  local c = #l:match '^%s*'
  local n = root:named_descendant_for_range(line - 1, c, line - 1, c)
  while n and n:parent() and n:parent():type() ~= 'program' and n:parent():start() == line - 1 do
    n = n:parent()
  end
  local f = n and first_fn(n)
  if not f then
    return nil
  end
  local sig = { tparams = {}, params = {} }
  local tps = field(f, 'type_parameters')
  for p in tps and tps:iter_children() or function() end do
    if p:type() == 'type_parameter' then
      sig.tparams[#sig.tparams + 1] = tv.tparam(text(p, src))
    end
  end
  local ps = field(f, 'parameters')
  if ps then
    for p in ps:iter_children() do
      local t = p:type()
      if t == 'required_parameter' or t == 'optional_parameter' then
        local pat = field(p, 'pattern')
        sig.params[#sig.params + 1] = {
          name = pat and text(pat, src):gsub('%s+', ' ') or '?',
          type = annotation(field(p, 'type'), src),
          optional = t == 'optional_parameter' or field(p, 'value') ~= nil,
        }
      end
    end
  elseif field(f, 'parameter') then
    sig.params[1] = { name = text(field(f, 'parameter'), src), optional = false }
  end
  sig.ret = annotation(field(f, 'return_type'), src)
  return sig
end

---@class seam.WType
---@field name string
---@field kind string type, interface, class or enum
---@field path string
---@field line integer where it is declared, `export` and all
---@field end_line integer
---@field exported boolean

--- The types declared at the top of `path`, in its order.
---@param path string
---@return seam.WType[]
function M.types(path)
  local P = code.file(path)
  if P.wtypes then
    return P.wtypes
  end
  local out = {}
  P.wtypes = out
  local root, src = code.tree(path)
  if not root then
    return out
  end
  for c in root:iter_children() do
    local d = c:type() == 'export_statement' and field(c, 'declaration') or c
    local kind = d and TYPE[d:type()]
    local name = kind and field(d, 'name')
    if name then
      local sr, _, er, ec = c:range()
      out[#out + 1] = {
        name = text(name, src),
        kind = kind,
        path = path,
        line = sr + 1,
        end_line = (ec == 0 and er > sr) and er or er + 1,
        exported = d ~= c,
      }
    end
  end
  return out
end

--- The type `name` declared at the top of `path`.
---@param path string
---@param name string
---@return seam.WType|nil
function M.type_in(path, name)
  for _, t in ipairs(M.types(path)) do
    if t.name == name then
      return t
    end
  end
end

return M
