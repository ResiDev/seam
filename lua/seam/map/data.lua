-- What the Map draws from, read off the model: a function's calls and
-- callers through the lens, how much it goes on to reach, what crosses a
-- folder's or a file's edge, a type's makers and takers, and the names the
-- Map writes folders and files by. Pure, so the specs drive it on a graph
-- written by hand.
local graph = require 'seam.graph'
local index = require 'seam.index'
local M = {}

-- the most functions a reach counts before it stops: a size past it says `999+`
M.REACH_MAX = 999

--- A node's name as the Map writes it; a file's top level says so.
---@param n seam.Node
---@return string
function M.label(n)
  return (n.name and n.name ~= '') and n.name or '(top level)'
end

local function memo(m)
  local c = m.mapmemo
  if not (c and c.visible == m.visible) then
    c = { visible = m.visible, reach = {}, calls = {} }
    -- every node by path then line, once
    local g = m.graph
    c.ids = vim.tbl_keys(g.nodes)
    table.sort(c.ids, function(a, b)
      local na, nb = g.nodes[a], g.nodes[b]
      return na.path < nb.path or (na.path == nb.path and na.line < nb.line)
    end)
    m.mapmemo = c
  end
  return c
end

--- The distinct functions `id` calls, in the order first written.
---@param m table
---@param id string
---@return string[]
function M.calls(m, id)
  local c = memo(m).calls
  if not c[id] then
    local out = {}
    for _, k in ipairs((graph.kids(m.graph, id, 'down', graph.visible(m, 'down')))) do
      out[#out + 1] = k.id
    end
    c[id] = out
  end
  return c[id]
end

--- Who calls `id`, by path then line: the callers outside tests, and those in tests.
---@param m table
---@param id string
---@return string[] callers, string[] tests
function M.callers(m, id)
  local kids, tests = graph.kids(m.graph, id, 'up', graph.visible(m, 'up'))
  local function ids(list)
    return vim.tbl_map(function(k)
      return k.id
    end, list)
  end
  return ids(kids), ids(tests)
end

--- How many functions the ones in `from` go on to reach, those `skip`
--- says aside, up to REACH_MAX.
---@param m table
---@param from string[]
---@param skip? fun(n: seam.Node): boolean
---@return integer
function M.reach_of(m, from, skip)
  local seen, stack, n = {}, {}, 0
  for _, id in ipairs(from) do
    seen[id] = true
    stack[#stack + 1] = id
  end
  while #stack > 0 do
    local id = table.remove(stack)
    for _, k in ipairs(M.calls(m, id)) do
      if not seen[k] then
        seen[k] = true
        stack[#stack + 1] = k
        if not (skip and skip(m.graph.nodes[k])) then
          n = n + 1
          if n >= M.REACH_MAX then
            return n
          end
        end
      end
    end
  end
  return n
end

--- How many functions `id` goes on to reach, itself not counted.
---@param m table
---@param id string
---@return integer
function M.reach(m, id)
  local c = memo(m).reach
  if not c[id] then
    c[id] = M.reach_of(m, { id }, function(n)
      return n.id == id
    end)
  end
  return c[id]
end

--- A size as written: `999+` past the most counted.
---@param n integer
---@return string
function M.count(n)
  return n >= M.REACH_MAX and (M.REACH_MAX .. '+') or tostring(n)
end

-- a path inside its package, its `src/` left out, and the package's last
-- name: `run/run.ts`, 'core'
local function inside(m, path)
  local pkg = index.pkg_of(m, path)
  if pkg == '.' then
    return path, nil, ''
  end
  local rest = path:sub(#pkg + 2)
  local src = rest:match '^src/' and 'src/' or ''
  return rest:sub(#src + 1), pkg, src
end

--- The folder a path is in, as the Map writes it: inside the package of
--- `home` from its `src/`, `storage/`, its top `core/src/ files`; in
--- another package from the package's name, `react/src/`.
---@param m table
---@param path string
---@param home string a path in the package the Map is drawn from
---@return string
function M.where(m, path, home)
  local rest, pkg, src = inside(m, path)
  local dir = rest:match '^(.*)/[^/]*$'
  local leaf = pkg and pkg:match '[^/]+$' or ''
  if pkg and pkg == index.pkg_of(m, home) then
    return dir and (dir .. '/') or (leaf .. '/' .. src .. ' files')
  elseif pkg then
    return leaf .. '/' .. src .. (dir and (dir .. '/') or '')
  end
  return dir and (dir .. '/') or './'
end

--- A file as the Map writes it: inside the package of `home` from its
--- `src/`, `run/run.ts`; in another from the package's name.
---@param m table
---@param path string
---@param home string
---@return string
function M.short(m, path, home)
  local rest, pkg, src = inside(m, path)
  if pkg and pkg ~= index.pkg_of(m, home) then
    return pkg:match '[^/]+$' .. '/' .. src .. rest
  end
  return rest
end

--- Is `path` in folder `dir`, or is it the file `dir`?
---@param dir string
---@return fun(path: string): boolean
function M.within(dir)
  return function(path)
    return path == dir or path:sub(1, #dir + 1) == dir .. '/'
  end
end

--- The calls across the edge of what `inside` holds, tests left out:
--- `into` each call from outside to a function inside, `out` each call
--- from inside to a function outside, as `{ from, to }` node ids in the
--- order written, each pair once.
---@param m table
---@param inside fun(path: string): boolean
---@return { from: string, to: string }[] into, { from: string, to: string }[] out
function M.crossing(m, inside)
  local g = m.graph
  local into, out = {}, {}
  local top = graph.visible(m, 'top')
  for _, id in ipairs(memo(m).ids) do
    local n = g.nodes[id]
    if not n.test and top(n.path) then
      local a = inside(n.path)
      for _, k in ipairs(M.calls(m, id)) do
        local c = g.nodes[k]
        if not c.test then
          local b = inside(c.path)
          if a and not b then
            out[#out + 1] = { from = id, to = k }
          elseif b and not a then
            into[#into + 1] = { from = id, to = k }
          end
        end
      end
    end
  end
  return into, out
end

--- The functions in a file, its top left out, in its order.
---@param m table
---@param path string
---@return string[]
function M.fns_in(m, path)
  local out = {}
  for _, n in ipairs(require('seam.outline').functions(m, path)) do
    out[#out + 1] = n.id
  end
  return out
end

---------------------------------------------------------------- types

--- The repo types a type's text names, each once, in order.
---@param m table
---@param text string|nil
---@param own? table<string, true> the function's own type parameters
---@return string[]
function M.repo_types(m, text, own)
  local out, seen = {}, {}
  for _, name in ipairs(require('seam.types').names(text or '')) do
    if m.flows[name] and not (own and own[name]) and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

--- What a function gives, in a word: the first repo type its return
--- names, else its return as written, `void` when it says nothing.
---@param m table
---@param id string
---@return string name, boolean repo
function M.gives(m, id)
  local sig = m.sigs and m.sigs[id]
  local ret = sig and (sig.ret or sig.value)
  local named = M.repo_types(m, ret, sig and sig.generics)
  if named[1] then
    return named[1], true
  end
  ret = vim.trim((ret or 'void'):gsub('%s+', ' '))
  if #ret > 24 or ret:find '[{(]' then
    ret = ret:sub(1, 1) == '{' and '{ … }' or (vim.fn.strcharpart(ret, 0, 20) .. '…')
  end
  return ret, false
end

--- The repo types a function takes, each once, in order.
---@param m table
---@param id string
---@return string[]
function M.takes(m, id)
  local sig = m.sigs and m.sigs[id]
  local out, seen = {}, {}
  for _, p in ipairs(sig and sig.params or {}) do
    for _, name in ipairs(M.repo_types(m, p.type, sig.generics)) do
      if not seen[name] then
        seen[name] = true
        out[#out + 1] = name
      end
    end
  end
  return out
end

--- The functions that make type `name`, and those that take it, tests left
--- out, each by path then line.
---@param m table
---@param name string
---@return string[] makers, string[] takers
function M.flow(m, name)
  local f = m.flows and m.flows[name]
  if not f then
    return {}, {}
  end
  local g = m.graph
  local function keep(list)
    list = vim.tbl_filter(function(id)
      local n = g.nodes[id]
      return n ~= nil and not n.test
    end, list)
    table.sort(list, function(a, b)
      local na, nb = g.nodes[a], g.nodes[b]
      return na.path < nb.path or (na.path == nb.path and na.line < nb.line)
    end)
    return list
  end
  return keep(f.gives), keep(require('seam.types').takers(f))
end

return M
