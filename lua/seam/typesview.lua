-- The Types view as data: a function's line, what it takes, its name and
-- what it gives, from its written signature (else the server's hover);
-- the names on a line that are types; and the types opened in place, a set
-- of keys, laid out as the rows under the lines that name them.
local types = require 'seam.types'
local M = {}

---@class seam.TParam
---@field name string
---@field bound string|nil what it extends
---@field text string as written: `const T extends Step = Step`

---@class seam.TSig
---@field tparams seam.TParam[]
---@field params { name: string, type: string|nil, optional: boolean }[]
---@field ret string|nil

--- `Readonly<X>` as X, wherever it is: raf wraps every type in it.
---@param t string
---@return string
function M.unwrap(t)
  while true do
    local i = t:find '%f[%w_$]Readonly<'
    if not i then
      return t
    end
    local o = i + #'Readonly'
    local c = types.closing(t, o)
    if not c then
      return t
    end
    t = t:sub(1, i - 1) .. t:sub(o + 1, c - 1) .. t:sub(c + 1)
  end
end

--- A type's text on one line: comments gone, `import("…").` dropped,
--- `Readonly<…>` left out, the members of an object between commas.
---@param t string
---@return string
function M.simple(t)
  t = t:gsub('/%*.-%*/', ''):gsub('//[^\n]*', ''):gsub('import%b()%.', '')
  t = M.unwrap(t):gsub('%s+', ' ')
  t = t:gsub(';%s*}', ' }'):gsub(';%s*$', ''):gsub(';%s*', ', ')
  return vim.trim(t)
end

--- The parts of an object or a list, `{ a: A, b: B }` or `(A, B)`, at its
--- top level.
---@param t string
---@return string[]
function M.parts(t)
  t = vim.trim(t)
  return types.split((t:gsub(';', ','):sub(2, -2)))
end

--- Each type parameter in `t` as what it extends, `unknown` when nothing.
---@param t string
---@param tparams seam.TParam[]
---@return string
function M.bound(t, tparams)
  for _, p in ipairs(tparams or {}) do
    local b = M.simple(p.bound or 'unknown')
    t = t:gsub('%f[%w_$]' .. vim.pesc(p.name) .. '%f[^%w_$]', (b:gsub('%%', '%%%%')))
  end
  return t
end

--- What a function takes, as its line writes it: one object parameter
--- bare, `{ a: A, b: B }`; else `(A, B)`; type parameters as their bounds.
---@param sig seam.TSig
---@return string
function M.takes(sig)
  local ps = sig.params
  if #ps == 1 and ps[1].type and M.simple(ps[1].type):sub(1, 1) == '{' then
    return M.bound(M.simple(ps[1].type), sig.tparams)
  end
  local out = {}
  for i, p in ipairs(ps) do
    out[i] = p.type and M.bound(M.simple(p.type), sig.tparams) or p.name
  end
  return '(' .. table.concat(out, ', ') .. ')'
end

--- What a function gives, as its line writes it.
---@param sig seam.TSig
---@return string
function M.gives(sig)
  return M.bound(M.simple(sig.ret or 'void'), sig.tparams)
end

--- A function opened as written: its type parameters as written, then
--- each part of what it takes, one a line, between its brackets.
---@param sig seam.TSig
---@return string open, string[] parts, string close
function M.opened(sig)
  local ps = sig.params
  local parts = {}
  if #sig.tparams > 0 then
    parts[1] = '<' .. table.concat(
      vim.tbl_map(function(p)
        return p.text
      end, sig.tparams),
      ', '
    ) .. '>'
  end
  if #ps == 1 and ps[1].type and M.simple(ps[1].type):sub(1, 1) == '{' then
    for _, p in ipairs(M.parts(M.simple(ps[1].type))) do
      parts[#parts + 1] = p .. ','
    end
    return '{', parts, '}'
  end
  for _, p in ipairs(ps) do
    parts[#parts + 1] = (p.type and M.simple(p.type) or p.name) .. ','
  end
  return '(', parts, ')'
end

--- `text` cut to `w` columns, ending in `…` when cut.
---@param text string
---@param w integer
---@return string
function M.cut(text, w)
  if vim.api.nvim_strwidth(text) <= w then
    return text
  end
  return vim.fn.strcharpart(text, 0, w - 1) .. '…'
end

--- What a function takes and gives: the written signature where it says,
--- else the server's hover; a parameter written without a type takes the
--- hover's.
---@param written seam.TSig|nil
---@param hover seam.Sig|nil
---@return seam.TSig|nil
function M.sig(written, hover)
  local hp = hover and hover.params
  if not written and not hp then
    return nil
  end
  local s = { tparams = {}, params = {} }
  if written then
    s.tparams = written.tparams
    for i, p in ipairs(written.params) do
      local h = hp and hp[i]
      s.params[i] = { name = p.name, type = p.type or (h and h.type), optional = p.optional }
    end
    s.ret = written.ret
  else
    for i, p in ipairs(hp) do
      s.params[i] = { name = p.name, type = p.type, optional = p.optional }
    end
    s.tparams = M.tparams(hover.text)
  end
  s.ret = s.ret or (hover and hover.ret)
  return s
end

--- The type parameters a hover writes, `<T extends Step = Step>(…`.
---@param text string
---@return seam.TParam[]
function M.tparams(text)
  local s = text:gsub('%s+', ' ')
  local i = s:find '[<(]'
  if not i or s:sub(i, i) ~= '<' then
    return {}
  end
  local c = types.closing(s, i)
  if not c then
    return {}
  end
  local out = {}
  for _, g in ipairs(types.split(s:sub(i + 1, c - 1))) do
    out[#out + 1] = M.tparam(g)
  end
  return out
end

--- One type parameter from its text.
---@param g string
---@return seam.TParam
function M.tparam(g)
  g = vim.trim(g)
  local name, rest = g:gsub('^const%s+', ''):match '^([%a_$][%w_$]*)(.*)$'
  local ext = (rest or ''):match '^%s+extends%s+(.*)$'
  if ext then
    -- the default after a `=` of its own level, not an arrow's
    local depth = 0
    for i = 1, #ext do
      local c = ext:sub(i, i)
      if c:match '[<({%[]' then
        depth = depth + 1
      elseif c:match '[)}%]]' or (c == '>' and ext:sub(i - 1, i - 1) ~= '=') then
        depth = depth - 1
      elseif c == '=' and depth == 0 and ext:sub(i + 1, i + 1) ~= '>' then
        ext = ext:sub(1, i - 1)
        break
      end
    end
    ext = vim.trim(ext)
  end
  return { name = name or g, bound = ext, text = g }
end

--- A source line's code with its comments blanked, `inside` a block
--- comment when it starts; and whether the next line starts inside one.
---@param line string
---@param inside boolean
---@return string code, boolean inside
function M.code_part(line, inside)
  local out, i = {}, 1
  while i <= #line do
    if inside then
      local e = line:find('*/', i, true)
      if not e then
        out[#out + 1] = string.rep(' ', #line - i + 1)
        return table.concat(out), true
      end
      out[#out + 1] = string.rep(' ', e + 2 - i)
      i, inside = e + 2, false
    else
      local b = line:find('/*', i, true)
      local l = line:find('//', i, true)
      if l and (not b or l < b) then
        out[#out + 1] = line:sub(i, l - 1) .. string.rep(' ', #line - l + 1)
        return table.concat(out), false
      end
      if not b then
        out[#out + 1] = line:sub(i)
        return table.concat(out), false
      end
      out[#out + 1] = line:sub(i, b - 1)
      i, inside = b, true
    end
  end
  return table.concat(out), inside
end

---@class seam.TName
---@field s integer the byte it starts at, 1-based
---@field e integer the byte past it
---@field name string

--- The names in `text` that `is_type` says are types: not in a string,
--- not a member after `.`, not a key before `:`; each where it is.
---@param text string
---@param is_type fun(name: string): boolean
---@return seam.TName[]
function M.names(text, is_type)
  local t = text:gsub('(["\'`])(.-)%1', function(q, body)
    return q .. string.rep(' ', #body) .. q
  end)
  local out = {}
  for pre, name, post in t:gmatch '()([%a_$][%w_$]*)()' do
    local before = t:sub(pre - 1, pre - 1)
    local after = t:sub(post):match '^%s*(%??:?)'
    if before ~= '.' and after ~= ':' and after ~= '?:' and is_type(name) then
      out[#out + 1] = { s = pre, e = post, name = name }
    end
  end
  return out
end

--- The name holding byte `col` (0-based) of a row, from names placed at
--- 0-based `[s, e)`.
---@param names { s: integer, e: integer, name: string }[]
---@param col integer
---@return { s: integer, e: integer, name: string }|nil
function M.at(names, col)
  for _, n in ipairs(names or {}) do
    if col >= n.s and col < n.e then
      return n
    end
  end
end

---------------------------------------------------------------- opened

--- The key of the type `name` opened under line `line` of the block `key`.
---@param key string
---@param line string|integer
---@param name string
---@return string
function M.child(key, line, name)
  return key .. '|' .. line .. ':' .. name
end

--- Is the block `key` open: its own say in `open`, else `defaults`.
---@param open table<string, boolean>
---@param defaults table<string, boolean>|nil
---@param key string
---@return boolean
function M.is_open(open, defaults, key)
  local v = open[key]
  if v == nil then
    return (defaults and defaults[key]) == true
  end
  return v
end

--- Close the block `key` and forget what was opened inside it.
---@param open table<string, boolean>
---@param key string
function M.close(open, key)
  local under = key .. '|'
  for k in pairs(open) do
    if k:sub(1, #under) == under then
      open[k] = nil
    end
  end
  open[key] = false
end

---@class seam.TLine
---@field id string|integer the line's place in its block: a source line, or a part
---@field names string[] the types it names, in order

---@class seam.TItem
---@field line seam.TLine|nil a line of the block `key`
---@field head table|nil a block opened: what `resolve` gave for `name`
---@field name string|nil
---@field key string the block the line is in, or the block opened
---@field depth integer
---@field chain string[] the blocks open around it, the innermost last

--- The rows of `lines`, the lines of block `key`, each followed by the
--- types opened under it, one block a type, nested as they were opened.
--- `ctx.resolve(name, line, key)` gives a block `{ lines = seam.TLine[] }` or nil; a
--- type already open around a line does not open again under it.
---@param lines seam.TLine[]
---@param key string
---@param ctx { open: table<string, boolean>, defaults: table<string, boolean>|nil, resolve: fun(name: string): table|nil }
---@param depth? integer
---@param chain? string[]
---@param seen? table<string, true>
---@param out? seam.TItem[]
---@return seam.TItem[]
function M.layout(lines, key, ctx, depth, chain, seen, out)
  depth, chain, seen, out = depth or 0, chain or {}, seen or {}, out or {}
  for _, l in ipairs(lines) do
    out[#out + 1] = { line = l, key = key, depth = depth, chain = chain }
    local done = {}
    for _, name in ipairs(l.names) do
      local k = M.child(key, l.id, name)
      if not done[name] and not seen[name] and M.is_open(ctx.open, ctx.defaults, k) then
        done[name] = true
        local b = ctx.resolve(name, l, k)
        if b then
          local inner = vim.list_extend(vim.list_slice(chain), { k })
          out[#out + 1] = { head = b, name = name, key = k, depth = depth + 1, chain = inner }
          seen[name] = true
          M.layout(b.lines, k, ctx, depth + 1, inner, seen, out)
          seen[name] = nil
        end
      end
    end
  end
  return out
end

return M
