-- The types in a function's code, from seam.names: each value's type after
-- its name where none is written and it is known, a function's return after
-- its parameters; and the code's types display as data, the function's line,
-- each value it makes with its type in the order made, each function inside
-- under its own line. A file's: its declarations' lines.
local names = require 'seam.names'
local scope = require 'seam.scope'
local written = require 'seam.written'
local M = {}

local FN = scope.FN
local text, field = scope.text, scope.field

local function fn_value(v)
  return v and FN[v:type()]
end

---@class seam.Hint
---@field line integer
---@field col integer 0-based, the byte it goes before
---@field text string `: Queue`

--- The types to show in lines `s`..`e` of `path`: after a value's name,
--- the type of what made it, where none is written; after a function's
--- parameters, its return, where none is written and it is known.
---@param m table
---@param path string
---@param s integer
---@param e integer
---@return seam.Hint[]
function M.hints(m, path, s, e)
  local root = names.tree(path)
  if not root then
    return {}
  end
  local out = {}
  local function add(n, t)
    local l, c = n:end_()
    out[#out + 1] = { line = l + 1, col = c, text = ': ' .. t }
  end
  local function walk(n)
    for c in n:iter_children() do
      local cs, _, ce = c:range()
      if ce + 1 >= s and cs + 1 <= e then
        local t = c:type()
        if t == 'variable_declarator' then
          local nm, v = field(c, 'name'), field(c, 'value')
          if nm and nm:type() == 'identifier' and v and not field(c, 'type') and not fn_value(v) then
            local ty = names.type_of(m, path, v)
            if ty and not ty.written and ty.text then
              add(nm, ty.text)
            end
          end
        elseif FN[t] and t ~= 'method_definition' and not field(c, 'return_type') then
          local ps = field(c, 'parameters')
          local r = ps and names.fn_ret(m, path, c)
          if r then
            add(ps, r)
          end
        end
        walk(c)
      end
    end
  end
  walk(root)
  table.sort(out, function(a, b)
    return a.line < b.line or (a.line == b.line and a.col < b.col)
  end)
  return vim.tbl_filter(function(h)
    return h.line >= s and h.line <= e
  end, out)
end

---@class seam.TRow
---@field kind 'fn'|'value'|'blank'|'type'
---@field depth integer how far in: 0 the function shown, 1 a function inside it
---@field name string|nil
---@field params string|nil a function's, as written
---@field ret string|nil a function's return, written or known
---@field type string|nil a value's
---@field line integer|nil where it is made
---@field col integer|nil 0-based, its name

-- the types display of function node `f`, named `name`, at `depth`
local function fn_rows(m, path, out, f, name, depth)
  local src = select(2, names.tree(path))
  local fl = f:start()
  out[#out + 1] = { kind = 'fn', depth = depth, name = name, params = names.params_text(path, f), ret = (names.fn_ret(m, path, f)), line = fl + 1 }
  local inner = {}
  local function value(nd)
    local l, c = nd:start()
    local t = names.binding_type(m, path, l + 1, c)
    out[#out + 1] = { kind = 'value', depth = depth, name = text(nd, src), type = t and t.text, line = l + 1, col = c }
  end
  local function walk(n)
    for c in n:iter_children() do
      local t = c:type()
      if t == 'variable_declarator' and field(c, 'name') then
        local nm, v = field(c, 'name'), field(c, 'value')
        if nm:type() == 'identifier' and fn_value(v) and field(v, 'body'):type() == 'statement_block' and not field(c, 'type') then
          inner[#inner + 1] = { f = v, name = text(nm, src) }
        else
          for _, x in ipairs(scope.pattern(nm, src)) do
            value(x.node)
          end
          if v and not fn_value(v) then
            walk(v)
          end
        end
      elseif t == 'function_declaration' or t == 'generator_function_declaration' then
        inner[#inner + 1] = { f = c, name = field(c, 'name') and text(field(c, 'name'), src) or '' }
      elseif t == 'pair' and fn_value(field(c, 'value')) then
        inner[#inner + 1] = { f = field(c, 'value'), name = text(field(c, 'key'), src) }
      elseif t == 'for_in_statement' and field(c, 'left') then
        for _, x in ipairs(scope.pattern(field(c, 'left'), src)) do
          value(x.node)
        end
        walk(c)
      elseif FN[t] then
        -- a callback with no name: what it makes is the function's
        local b = field(c, 'body')
        if b then
          walk(b)
        end
      elseif c:named_child_count() > 0 then
        walk(c)
      end
    end
  end
  local body = field(f, 'body')
  if body then
    walk(body)
  end
  for _, x in ipairs(inner) do
    out[#out + 1] = { kind = 'blank', depth = depth + 1 }
    fn_rows(m, path, out, x.f, x.name, depth + 1)
  end
end

-- the function node declared on `line`
local function fn_at(path, line)
  local root, src = names.tree(path)
  local l = require('seam.code').file(path).lines[line]
  if not (root and l) then
    return nil
  end
  local c = #l:match '^%s*'
  local n = root:named_descendant_for_range(line - 1, c, line - 1, c)
  while n and n:parent() and n:parent():type() ~= 'program' and n:parent():start() == line - 1 do
    n = n:parent()
  end
  local function first(x)
    if FN[x:type()] then
      return x
    end
    -- a value is no function, whatever functions it holds, as in seam.written
    if x:type() == 'variable_declarator' then
      local v = field(x, 'value')
      return fn_value(v) and v or nil
    end
    for ch in x:iter_children() do
      if ch:named() then
        local f = first(ch)
        if f then
          return f
        end
      end
    end
  end
  return n and first(n), src
end

-- the declarator of value `name` on `line`
local function value_at(path, line, name)
  local root, src = names.tree(path)
  if not root then
    return nil
  end
  for c in root:iter_children() do
    local d = c:type() == 'export_statement' and field(c, 'declaration') or c
    if d and (d:type() == 'lexical_declaration' or d:type() == 'variable_declaration') then
      for v in d:iter_children() do
        local nm = v:type() == 'variable_declarator' and field(v, 'name')
        if nm and nm:start() + 1 == line and text(nm, src) == name then
          return v, src
        end
      end
    end
  end
end

-- a value's display: `name  Type`, then each function it holds by its key,
-- `perform` of `register({ perform() {} })`, the same way as inside a function
local function value_rows(m, path, out, d, src)
  local nm = field(d, 'name')
  local l, c = nm:start()
  local t = names.binding_type(m, path, l + 1, c)
  out[#out + 1] = { kind = 'value', depth = 0, name = text(nm, src), type = t and t.text, line = l + 1, col = c }
  local function walk(n)
    for ch in n:iter_children() do
      local v = ch:type() == 'pair' and field(ch, 'value')
      if v and fn_value(v) then
        out[#out + 1] = { kind = 'blank', depth = 1 }
        fn_rows(m, path, out, v, text(field(ch, 'key'), src), 1)
      elseif ch:type() == 'method_definition' and field(ch, 'name') then
        out[#out + 1] = { kind = 'blank', depth = 1 }
        fn_rows(m, path, out, ch, text(field(ch, 'name'), src), 1)
      elseif not FN[ch:type()] and ch:named_child_count() > 0 then
        walk(ch)
      end
    end
  end
  local v = field(d, 'value')
  if v then
    walk(v)
  end
end

--- The types display of the function declared on `line` of `path`: its
--- line, then each value it makes with its type in the order made, then
--- each function inside, a blank line before it, the same way. A value's:
--- its `name  Type`, then each function it holds.
---@param m table
---@param path string
---@param line integer
---@param name string
---@return seam.TRow[]
function M.fn(m, path, line, name)
  local f = fn_at(path, line)
  local out = {}
  if f then
    fn_rows(m, path, out, f, name, 0)
  else
    local d, src = value_at(path, line, name)
    if d then
      value_rows(m, path, out, d, src)
    end
  end
  return out
end

--- A file's types display: each function at its top as its line, each
--- value as `name  Type`, each type it declares, in the file's order.
---@param m table
---@param path string
---@return seam.TRow[]
function M.file(m, path)
  local root, src = names.tree(path)
  local out = {}
  if not root then
    return out
  end
  local decls = {}
  for _, t in ipairs(written.types(path)) do
    decls[t.line] = t
  end
  for c in root:iter_children() do
    local d = c:type() == 'export_statement' and field(c, 'declaration') or c
    local l = c:start() + 1
    local t = d and d:type()
    if decls[l] then
      out[#out + 1] = { kind = 'type', depth = 0, name = decls[l].name, type = decls[l].kind, line = l }
    elseif t == 'function_declaration' or t == 'generator_function_declaration' then
      out[#out + 1] =
        { kind = 'fn', depth = 0, name = text(field(d, 'name'), src), params = names.params_text(path, d), ret = (names.fn_ret(m, path, d)), line = l }
    elseif t == 'lexical_declaration' or t == 'variable_declaration' then
      for v in d:iter_children() do
        local nm, val = field(v, 'name'), field(v, 'value')
        if v:type() == 'variable_declarator' and nm and nm:type() == 'identifier' then
          local vl = v:start() + 1
          if fn_value(val) then
            out[#out + 1] =
              { kind = 'fn', depth = 0, name = text(nm, src), params = names.params_text(path, val), ret = (names.fn_ret(m, path, val)), line = vl }
          else
            local _, c0 = nm:start()
            local ty = names.binding_type(m, path, vl, c0)
            out[#out + 1] = { kind = 'value', depth = 0, name = text(nm, src), type = ty and ty.text, line = vl, col = c0 }
          end
        end
      end
    end
  end
  return out
end

return M
