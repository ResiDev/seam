-- The model: a repo's index read from its JSON, one model a source, with the
-- lens applied; where indexes live, and making one with treesitter.
local lens = require 'seam.lens'
local st = require 'seam.state'
local M = {}

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local LAB = ROOT .. '/lab'

--- Where a repo's index lives: the lab's own sources for its excalidraw copy,
--- else the cache, one directory a repo.
---@param root string
---@return string
function M.dir(root)
  if root == LAB .. '/excalidraw' then
    return LAB .. '/out'
  end
  return vim.fn.stdpath 'cache' .. '/seam/' .. root:gsub('^/', ''):gsub('/', '%%')
end

---@param m table
---@param path string
---@return string # the package, '.' outside every package
function M.pkg_of(m, path)
  local p = m.pkgcache[path]
  if p then
    return p
  end
  p = '.'
  for _, k in ipairs(m.pkgsorted) do
    if path:sub(1, #k + 1) == k .. '/' then
      p = k
      break
    end
  end
  m.pkgcache[path] = p
  return p
end

--- The extractor's format: 3 adds the call graph, `nodes` and their calls.
--- An index older than this is made again when seam opens.
M.VERSION = 3

--- The format of the repo's treesitter index, 0 when there is none.
---@param root string
---@return integer
function M.version(root)
  local fh = io.open(M.dir(root) .. '/treesitter.json', 'r')
  if not fh then
    return 0
  end
  local s = fh:read '*a'
  fh:close()
  return tonumber(s:match '"version":%s*(%d+)') or 1
end

--- The call graph from the JSON's nodes: what each calls as written, and who
--- calls each, by the caller's path then line.
---@param list table[]
---@return seam.Graph
function M.graph(list)
  local g = { nodes = {}, down = {}, up = {}, memo = {} }
  for _, n in ipairs(list) do
    n.test = M.is_test(n.path)
    g.nodes[n.id] = n
  end
  for _, n in ipairs(list) do
    local down = {}
    for _, c in ipairs(n.calls or {}) do
      if g.nodes[c[1]] then
        down[#down + 1] = { to = c[1], line = c[2], col = c[3] }
        local up = g.up[c[1]] or {}
        g.up[c[1]] = up
        up[#up + 1] = { from = n.id, line = c[2], col = c[3] }
      end
    end
    g.down[n.id] = down
    n.calls = nil
  end
  for _, up in pairs(g.up) do
    table.sort(up, function(a, b)
      local pa, pb = g.nodes[a.from].path, g.nodes[b.from].path
      if pa ~= pb then
        return pa < pb
      end
      return a.line < b.line or (a.line == b.line and a.col < b.col)
    end)
  end
  return g
end

local function build(file)
  local fh = assert(io.open(file, 'r'))
  local s = fh:read '*a'
  fh:close()
  local d = vim.json.decode(s, { luanil = { object = true, array = true } })
  local m = {
    ms = d.ms or {},
    packages = d.packages or {},
    exports = d.exports or {},
    byid = {},
    bykey = {},
    contracts = {},
    pkgcache = {},
    ispkg = {},
    pkgsorted = {},
    graph = d.nodes and M.graph(d.nodes) or nil,
  }
  for _, p in ipairs(m.packages) do
    if p ~= '.' and p ~= '' then
      m.pkgsorted[#m.pkgsorted + 1] = p
      m.ispkg[p] = true
    end
  end
  -- longest first, so a nested package wins over the one around it
  table.sort(m.pkgsorted, function(a, b)
    return #a > #b
  end)
  for _, e in ipairs(m.exports) do
    m.byid[e.id] = e
    local key = e.path .. ':' .. e.name
    m.bykey[key] = m.bykey[key] or e
    e.uses = e.uses or {}
    e.deps = e.deps or {}
    e.members = e.members or {}
    e.pkg = M.pkg_of(m, e.path)
    local seen, nf = {}, 0
    for _, u in ipairs(e.uses) do
      if not seen[u.path] then
        seen[u.path] = true
        nf = nf + 1
      end
    end
    e.nusers = nf
    local names, nn = {}, 0
    for _, dp in ipairs(e.deps) do
      if not names[dp.name] then
        names[dp.name] = true
        nn = nn + 1
      end
    end
    e.nbuilt = nn
    if nf > 0 then
      m.contracts[#m.contracts + 1] = e
    end
  end
  if st.lens then
    lens.apply(st.lens, m)
  end
  return m
end

--- Read the repo's indexes, each source's JSON, or only `only`; one that has
--- not changed on disk is kept as it is.
---@param only? string
function M.load(only)
  for _, f in ipairs(vim.fn.glob(M.dir(st.root) .. '/*.json', false, true)) do
    local name = vim.fn.fnamemodify(f, ':t:r')
    if name == 'hues' or (only and name ~= only) then
      goto continue
    end
    local stat = vim.uv.fs_stat(f)
    local mt = stat and (stat.mtime.sec .. ':' .. stat.size) or ''
    if not st.models[name] or st.models[name].mtime ~= mt then
      local ok, m = pcall(build, f)
      if ok then
        m.mtime = mt
        st.models[name] = m
      else
        vim.notify('seam: could not read ' .. f .. ': ' .. tostring(m), vim.log.levels.WARN)
      end
    end
    ::continue::
  end
  st.names = vim.tbl_keys(st.models)
  table.sort(st.names)
end

--- The model of the source shown.
---@return table
function M.model()
  return st.models[st.cur]
end

---@param path string
---@return boolean
function M.is_test(path)
  return (path:find '%.test%.' or path:find '%.spec%.' or path:find '/__tests__/' or ('/' .. path):find '/tests?/') ~= nil
end

--- The path and line of an id, 'path:line:name'.
---@param id string|nil
---@return string|nil
function M.id_path(id)
  return id and id:match '^(.*):%d+:[^:]*$'
end
---@param id string|nil
---@return integer|nil
function M.id_line(id)
  return id and tonumber(id:match ':(%d+):[^:]*$')
end

--- A contract's dependencies by the file they are declared in.
---@param c table
---@return table entries path -> { names, list }
---@return table unresolved
---@return integer files
---@return integer names
function M.deps_by_file(c)
  local entries, unresolved, names = {}, {}, {}
  local nfiles = 0
  for _, d in ipairs(c.deps) do
    local p = M.id_path(d.target)
    if p then
      local e = entries[p]
      if not e then
        e = { names = {}, list = {} }
        entries[p] = e
        nfiles = nfiles + 1
      end
      if not e.names[d.name] then
        e.names[d.name] = { name = d.name, target = d.target, lines = {} }
        e.list[#e.list + 1] = e.names[d.name]
      end
      e.names[d.name].lines[d.line] = true
    else
      if not unresolved[d.name] then
        unresolved[d.name] = { name = d.name, lines = {} }
        unresolved[#unresolved + 1] = unresolved[d.name]
      end
      unresolved[d.name].lines[d.line] = true
    end
    names[d.name] = true
  end
  for _, e in pairs(entries) do
    table.sort(e.list, function(a, b)
      return a.name < b.name
    end)
  end
  return entries, unresolved, nfiles, vim.tbl_count(names)
end

--- A contract's uses by the file they are in, each file's in order.
---@param c table
---@return table entries path -> uses
---@return integer files
function M.uses_by_file(c)
  local entries, n = {}, 0
  for _, u in ipairs(c.uses) do
    local e = entries[u.path]
    if not e then
      e = {}
      entries[u.path] = e
      n = n + 1
    end
    e[#e + 1] = u
  end
  for _, e in pairs(entries) do
    table.sort(e, function(a, b)
      if a.line ~= b.line then
        return a.line < b.line
      end
      return (a.col or 0) < (b.col or 0)
    end)
  end
  return entries, n
end

--- Index a repo with treesitter in a headless Neovim of its own, so the
--- editor stays free; `done` runs once the JSON is written.
---@param root string
---@param done? fun()
function M.index(root, done)
  local out = M.dir(root)
  vim.fn.mkdir(out, 'p')
  local script = ROOT .. '/scripts/extract.lua'
  local t = vim.uv.hrtime()
  vim.notify('seam: indexing ' .. vim.fn.fnamemodify(root, ':~') .. ' with treesitter…')
  vim.system({ vim.v.progpath, '--headless', '--clean', '-l', script, root, out .. '/treesitter.json' }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify('seam: indexing failed\n' .. (res.stderr or ''), vim.log.levels.ERROR)
        return
      end
      local line = vim.trim((res.stderr or ''):match '[^\n]*$' or '')
      vim.notify(('seam: indexed in %.1f s. %s'):format((vim.uv.hrtime() - t) / 1e9, line))
      if done then
        done()
      end
    end)
  end)
end

return M
