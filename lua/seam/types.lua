-- Types as data: what each function takes and gives, read from the hover the
-- TypeScript server wrote for it (scripts/types.lua), and each type of the
-- repo with the functions that take it and the ones that give it.
local M = {}

---@class seam.Param
---@field name string   -- as written: `cart`, `{ x, y }`, `...rest`
---@field type string
---@field optional boolean

---@class seam.Sig
---@field text string            -- the hover
---@field params seam.Param[]|nil -- nil when the server gave a value, not a call (a class, `React.FC<P>`)
---@field ret string|nil
---@field value string|nil       -- the type of a callable written as a value
---@field generics table<string, true>|nil -- its own type parameters: a `Point` there is not the repo's

---@class seam.Flow
---@field name string
---@field decls table[]    -- the exports of that name that declare a type: interface, type, class or enum
---@field takes { id: string, param: string }[]  -- a function per parameter whose type names it
---@field gives string[]   -- functions whose return type names it, and for a class, those that `new` it
---@field new table<string, true>|nil -- of those, the ones that `new` it
---@field n integer        -- functions it flows through, either way

local OPEN = { ['('] = ')', ['['] = ']', ['{'] = '}', ['<'] = '>' }
local CLOSE = { [')'] = true, [']'] = true, ['}'] = true, ['>'] = true }

--- Walk `s` from `i`, calling `at(j, c)` for each character outside brackets
--- and strings, until it returns true or a closing bracket of the level `i`
--- starts in. `=>` is an arrow, not a closing angle.
---@return integer|nil j where it stopped
local function scan(s, i, at)
  local depth, n = 0, #s
  local j = i
  while j <= n do
    local c = s:sub(j, j)
    if c == '"' or c == "'" or c == '`' then
      local k = j + 1
      while k <= n and s:sub(k, k) ~= c do
        k = k + (s:sub(k, k) == '\\' and 2 or 1)
      end
      j = k
    elseif OPEN[c] then
      if depth == 0 and at(j, c) then
        return j
      end
      depth = depth + 1
    elseif CLOSE[c] and not (c == '>' and s:sub(j - 1, j - 1) == '=') then
      if depth == 0 then
        return j
      end
      depth = depth - 1
    elseif depth == 0 and at(j, c) then
      return j
    end
    j = j + 1
  end
end

--- Split at commas outside brackets and strings.
local function split(s)
  local out, from = {}, 1
  local i = 1
  while true do
    local j = scan(s, i, function(_, c)
      return c == ','
    end)
    if not j or s:sub(j, j) ~= ',' then
      out[#out + 1] = s:sub(from)
      break
    end
    out[#out + 1] = s:sub(from, j - 1)
    from, i = j + 1, j + 1
  end
  return vim.tbl_filter(function(x)
    return x ~= ''
  end, vim.tbl_map(vim.trim, out))
end

--- The index of the bracket closing the one opening at `i`.
local function closing(s, i)
  return scan(s, i + 1, function()
    return false
  end)
end

local function param(p)
  local colon = scan(p, 1, function(_, c)
    return c == ':'
  end)
  if not colon or p:sub(colon, colon) ~= ':' then
    return { name = p, type = 'any', optional = false }
  end
  local name = vim.trim(p:sub(1, colon - 1))
  local optional = name:sub(-1) == '?'
  return { name = optional and name:sub(1, -2) or name, type = vim.trim(p:sub(colon + 1)), optional = optional }
end

--- A call signature from its text, starting at its generics or its `(`:
--- `<T>(a: A) => R` with `arrow`, `<T>(a: A): R` without. Its parameters,
--- its return and the names of its type parameters.
local function call(s, arrow)
  s = vim.trim(s)
  local i = 1
  local generics
  if s:sub(1, 1) == '<' then
    local c = closing(s, 1) or #s
    for _, g in ipairs(split(s:sub(2, c - 1))) do
      local name = g:gsub('^const%s+', ''):match '^[%a_$][%w_$]*'
      if name then
        generics = generics or {}
        generics[name] = true
      end
    end
    i = c + 1
    while s:sub(i, i) == ' ' do
      i = i + 1
    end
  end
  if s:sub(i, i) ~= '(' then
    return nil
  end
  local j = closing(s, i)
  if not j then
    return nil
  end
  local rest = vim.trim(s:sub(j + 1))
  local sep = arrow and '=>' or ':'
  if rest:sub(1, #sep) ~= sep then
    return nil
  end
  local ret = vim.trim(rest:sub(#sep + 1)):gsub('%s*%(%+%d+ overloads?%)$', '')
  local semi = scan(ret, 1, function(_, c)
    return c == ';'
  end)
  if semi then
    ret = vim.trim(ret:sub(1, semi - 1))
  end
  return vim.tbl_map(param, split(s:sub(i + 1, j - 1))), ret, generics
end

--- Parse a hover into what the function takes and gives.
---@param text string
---@return seam.Sig
function M.parse(text)
  local sig = { text = text }
  local s = text:gsub('%s+', ' '):gsub('^%(%w+%) ', '')
  local fn_rest = s:match '^function [%w_$]+(.*)$' or s:match '^async function [%w_$]+(.*)$'
  if fn_rest then
    sig.params, sig.ret, sig.generics = call(fn_rest, false)
    return sig
  end
  local ty = s:match '^const [%w_$]+: (.*)$' or s:match '^let [%w_$]+: (.*)$' or s:match '^var [%w_$]+: (.*)$'
  if ty then
    sig.params, sig.ret, sig.generics = call(ty, true)
    if not sig.params and ty:match '^{ [(<]' then
      -- a call signature with properties, as a component with displayName
      sig.params, sig.ret, sig.generics = call(ty:sub(3), false)
    end
    if not sig.params then
      sig.value = ty
    end
  end
  return sig
end

--- The names a type's text mentions as types: identifiers outside strings,
--- not a member after `.` and not a key before `:`.
---@param t string
---@return string[]
function M.names(t)
  t = t:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub('`[^`]*`', '``')
  local out, seen = {}, {}
  for pre, name, post in t:gmatch '()([%a_$][%w_$]*)()' do
    local before = t:sub(pre - 1, pre - 1)
    local after = t:sub(post):match '^%s*(%??:?)'
    if before ~= '.' and after ~= ':' and after ~= '?:' and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

local TYPE_KIND = { interface = true, type = true, class = true, enum = true }

--- Hang the signatures on a model and build its flows: `m.sigs` by node id,
--- `m.flows` by type name, `m.flowlist` the most travelled first.
---@param m table a model, with `exports` and `graph`
---@param hovers table<string, string> node id -> hover
---@param news? table<string, string[]> class node id -> the callables that `new` it
function M.attach(m, hovers, news)
  m.sigs, m.flows, m.flowlist = {}, {}, {}
  for _, e in ipairs(m.exports) do
    if TYPE_KIND[e.kind] then
      local f = m.flows[e.name]
      if not f then
        f = { name = e.name, decls = {}, takes = {}, gives = {}, n = 0 }
        m.flows[e.name] = f
      end
      f.decls[#f.decls + 1] = e
    end
  end
  local through = {}
  for id, text in pairs(hovers) do
    if m.graph and m.graph.nodes[id] then
      local sig = M.parse(text)
      m.sigs[id] = sig
      local own = sig.generics or {}
      for _, p in ipairs(sig.params or {}) do
        for _, name in ipairs(M.names(p.type)) do
          local f = not own[name] and m.flows[name]
          if f then
            f.takes[#f.takes + 1] = { id = id, param = p.name }
            through[name] = through[name] or {}
            through[name][id] = true
          end
        end
      end
      for _, name in ipairs(M.names(sig.ret or sig.value or '')) do
        local f = not own[name] and m.flows[name]
        if f then
          f.gives[#f.gives + 1] = id
          through[name] = through[name] or {}
          through[name][id] = true
        end
      end
    end
  end
  -- a class is also made by whatever says `new Scene(…)`
  for name, f in pairs(m.flows) do
    for _, e in ipairs(f.decls) do
      for _, from in ipairs(news and news[e.id] or {}) do
        if m.graph.nodes[from] and not vim.tbl_contains(f.gives, from) then
          f.gives[#f.gives + 1] = from
          f.new = f.new or {}
          f.new[from] = true
          through[name] = through[name] or {}
          through[name][from] = true
        end
      end
    end
  end
  local function by_place(a, b)
    return a < b
  end
  for name, f in pairs(m.flows) do
    f.n = vim.tbl_count(through[name] or {})
    table.sort(f.gives, by_place)
    table.sort(f.takes, function(a, b)
      return a.id < b.id or (a.id == b.id and a.param < b.param)
    end)
    if f.n > 0 then
      m.flowlist[#m.flowlist + 1] = f
    end
  end
  table.sort(m.flowlist, function(a, b)
    return a.n > b.n or (a.n == b.n and a.name < b.name)
  end)
end

--- The functions that take a type, each once, in the order of its `takes`:
--- one taking it in two parameters is one function.
---@param f seam.Flow
---@return string[]
function M.takers(f)
  local out, seen = {}, {}
  for _, t in ipairs(f.takes) do
    if not seen[t.id] then
      seen[t.id] = true
      out[#out + 1] = t.id
    end
  end
  return out
end

--- The repo types a signature names, each once, in the order it names them.
---@param sig seam.Sig
---@param flows table<string, seam.Flow>
---@return string[]
function M.named(sig, flows)
  local out, seen = {}, {}
  for _, p in ipairs(M.pieces(sig, flows)) do
    if p.flow and not seen[p.flow] then
      seen[p.flow] = true
      out[#out + 1] = p.flow
    end
  end
  return out
end

--- Read the types JSON beside a model's index, when there is one.
---@param file string
---@return table<string, string>|nil hovers, table<string, string[]>|nil news, string|nil server
function M.read(file)
  local fh = io.open(file, 'r')
  if not fh then
    return nil
  end
  local ok, d = pcall(vim.json.decode, fh:read '*a')
  fh:close()
  if not ok or type(d) ~= 'table' then
    return nil
  end
  return d.sigs, d.news, d.server
end

--- A type's text made short for a row: spaces collapsed, `readonly` and
--- `import("…").` dropped, and each object type written inline as the repo
--- types it names, `{ AppState, Scene }`, or `{…}` naming none.
---@param t string
---@param flows table<string, seam.Flow>
---@return string
function M.short(t, flows)
  t = vim.trim(t:gsub('%s+', ' '):gsub('import%b()%.', ''):gsub('readonly ', ''))
  local out, i = {}, 1
  while true do
    local o = t:find('{', i, true)
    local c = o and closing(t, o)
    if not c then
      out[#out + 1] = t:sub(i)
      break
    end
    local named = vim.tbl_filter(function(n)
      return flows[n] ~= nil
    end, M.names(t:sub(o, c)))
    out[#out + 1] = t:sub(i, o - 1) .. (#named > 0 and '{ ' .. table.concat(named, ', ') .. ' }' or '{…}')
    i = c + 1
  end
  return table.concat(out)
end

--- The pieces of a signature as a row writes them, before and after:
--- `{ text, flow? }` where `flow` names the repo type the text is; a
--- type parameter of its own is not one, whatever its name.
---@param sig seam.Sig
---@param flows table<string, seam.Flow>
---@return { text: string, flow: string|nil }[]
function M.pieces(sig, flows)
  local own, all = sig.generics, flows
  if own then
    flows = setmetatable({}, {
      __index = function(_, k)
        return not own[k] and all[k] or nil
      end,
    })
  end
  local out = {}
  local function put(text, flow)
    out[#out + 1] = { text = text, flow = flow }
  end
  local function typ(t)
    local s = M.short(t, flows)
    local from = 1
    for pre, name, post in s:gmatch '()([%a_$][%w_$]*)()' do
      if flows[name] and s:sub(pre - 1, pre - 1) ~= '.' then
        if pre > from then
          put(s:sub(from, pre - 1))
        end
        put(name, name)
        from = post
      end
    end
    if from <= #s then
      put(s:sub(from))
    end
  end
  if not sig.params then
    typ(sig.value or sig.text)
    return out
  end
  put '('
  for i, p in ipairs(sig.params) do
    if i > 1 then
      put ', '
    end
    typ(p.type)
  end
  put ') → '
  typ(sig.ret or 'void')
  return out
end

--- Pieces fitted to `room` columns, the return kept whole as long as it can
--- be: what a function takes is cut first, `(A, B, …) → R`.
---@param pieces { text: string, flow: string|nil }[]
---@param room integer
---@return { text: string, flow: string|nil }[]
function M.fit(pieces, room)
  local function w(list)
    local n = 0
    for _, p in ipairs(list) do
      n = n + vim.api.nvim_strwidth(p.text)
    end
    return n
  end
  local function cut(list, n)
    local out, at = {}, 0
    for _, p in ipairs(list) do
      local pw = vim.api.nvim_strwidth(p.text)
      if at + pw > n then
        local keep = vim.fn.strcharpart(p.text, 0, math.max(0, n - at))
        if keep ~= '' then
          out[#out + 1] = { text = keep, flow = p.flow }
        end
        out[#out + 1] = { text = '…' }
        return out
      end
      out[#out + 1] = p
      at = at + pw
    end
    return out
  end
  if w(pieces) <= room then
    return pieces
  end
  local sep
  for i, p in ipairs(pieces) do
    if p.text == ') → ' then
      sep = i
    end
  end
  if not sep then
    return cut(pieces, room - 1)
  end
  local before, after = vim.list_slice(pieces, 1, sep - 1), vim.list_slice(pieces, sep)
  local left = room - w(after) - 1
  if left < 6 then
    return cut(pieces, room - 1)
  end
  return vim.list_extend(cut(before, left), after)
end

return M
