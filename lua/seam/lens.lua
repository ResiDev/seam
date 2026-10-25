-- What the explorer shows: a pin to some folders, and patterns that hide
-- files. Each says which columns it applies to.
--
-- A row is on in each column it has a mark in; no marks, it does nothing.
---@alias seam.Cols { contracts: boolean, built: boolean, used: boolean }
---@class seam.Pin
---@field dir string     -- 'packages/core/'
---@field cols seam.Cols -- show only what is inside it, in these columns
---@class seam.Hide
---@field pattern string
---@field cols seam.Cols -- hide what matches, in these columns
---@class seam.Lens
---@field pins seam.Pin[]
---@field hides seam.Hide[]
local M = {}

M.COLS = { 'contracts', 'built', 'used' }
M.COL_NAME = { contracts = 'contracts', built = 'built from', used = 'used by' }

--- Patterns worth offering when they match something in the repo. Per
--- language later; these cover TypeScript and JavaScript.
M.SUGGEST = {
  '*.test.*',
  '*.spec.*',
  '*.perf.*',
  '*.bench.*',
  '*.stories.*',
  'tests/',
  'test/',
  '__tests__/',
  '__mocks__/',
  'e2e/',
  'fixtures/',
  'examples/',
  'scripts/',
}

function M.new()
  return { pins = {}, hides = {} }
end

function M.none()
  return { contracts = false, built = false, used = false }
end

function M.everywhere()
  return { contracts = true, built = true, used = true }
end

--- `*.test.*` a file name; `tests/` a folder anywhere; `a/*/b/**` a path;
--- `/regex/` a regex on the path, very magic so `(test|spec)` means what it
--- says elsewhere; anything else, text in the path.
---@return (fun(path: string): boolean)|nil, string|nil
function M.compile(pattern)
  local p = vim.trim(pattern or '')
  if p == '' then
    return nil, 'type a pattern'
  end
  local re = p:match '^/(.+)/$'
  if re then
    local ok, rx = pcall(vim.regex, re:match '^\\[vmMV]' and re or ('\\v' .. re))
    if not ok then
      return nil, 'not a regex'
    end
    return function(path)
      return rx:match_str(path) ~= nil
    end
  end
  local globby = p:find '[%*%?%[{]' ~= nil
  local dir = p:match '^(.-)/$'
  if dir then
    local ok, lp = pcall(vim.glob.to_lpeg, dir:find '/' and dir or ('**/' .. dir))
    if not ok then
      return nil, 'not a pattern'
    end
    return function(path)
      local prefix = ''
      for seg in path:gmatch '([^/]+)/' do
        prefix = prefix .. seg
        if lp:match(prefix) or lp:match(seg) then
          return true
        end
        prefix = prefix .. '/'
      end
      return false
    end
  end
  if globby then
    local full = p:find '/' ~= nil
    local ok, lp = pcall(vim.glob.to_lpeg, p)
    if not ok then
      return nil, 'not a pattern'
    end
    return function(path)
      return lp:match(full and path or (path:match '[^/]+$' or path)) ~= nil
    end
  end
  return function(path)
    return path:find(p, 1, true) ~= nil
  end
end

--- What kind of pattern it is, in words, for the preview.
function M.describe(pattern)
  local p = vim.trim(pattern or '')
  if p:match '^/.+/$' then
    return 'a regex on the whole path'
  elseif p:match '/$' then
    return 'a folder of that name, anywhere'
  elseif p:find '[%*%?%[{]' then
    return p:find '/' and 'a path' or 'a file name'
  elseif p ~= '' then
    return 'any path containing it'
  end
  return ''
end

--- A function telling whether a path shows in a column.
function M.visibility(lens)
  local hides, pins = { contracts = {}, built = {}, used = {} }, { contracts = {}, built = {}, used = {} }
  for _, h in ipairs(lens.hides) do
    local fn = M.compile(h.pattern)
    for _, col in ipairs(M.COLS) do
      if fn and h.cols[col] then
        table.insert(hides[col], fn)
      end
    end
  end
  for _, p in ipairs(lens.pins) do
    for _, col in ipairs(M.COLS) do
      if p.cols[col] then
        table.insert(pins[col], p.dir)
      end
    end
  end
  local cache = { contracts = {}, built = {}, used = {} }
  return function(path, col)
    local hit = cache[col][path]
    if hit ~= nil then
      return hit
    end
    local show = #pins[col] == 0
    for _, d in ipairs(pins[col]) do
      if path:sub(1, #d) == d then
        show = true
        break
      end
    end
    if show then
      for _, fn in ipairs(hides[col]) do
        if fn(path) then
          show = false
          break
        end
      end
    end
    cache[col][path] = show
    return show
  end
end

--- Point each export's uses and deps at what the lens lets through, keeping
--- the full lists beside them, so every screen follows the lens unchanged.
function M.apply(lens, m)
  local visible = M.visibility(lens)
  local id_path = function(id)
    return id and id:match '^(.-):%d+:'
  end
  m.contracts = {}
  for _, e in ipairs(m.exports) do
    e.all_uses = e.all_uses or e.uses
    e.all_deps = e.all_deps or e.deps
    local uses, files, hidden = {}, {}, {}
    for _, u in ipairs(e.all_uses) do
      if visible(u.path, 'used') then
        uses[#uses + 1] = u
        files[u.path] = true
      else
        hidden[u.path] = true
      end
    end
    local deps, names, hidden_deps = {}, {}, {}
    for _, d in ipairs(e.all_deps) do
      local p = id_path(d.target)
      if not p or visible(p, 'built') then
        deps[#deps + 1] = d
        names[d.name] = true
      else
        hidden_deps[p] = true
      end
    end
    e.uses, e.deps = uses, deps
    e.nusers, e.nbuilt = vim.tbl_count(files), vim.tbl_count(names)
    e.hidden_users, e.hidden_dep_files = vim.tbl_count(hidden), vim.tbl_count(hidden_deps)
    if #e.all_uses > 0 and visible(e.path, 'contracts') then
      m.contracts[#m.contracts + 1] = e
    end
  end
end

--- Every file the index knows: where contracts live and where they are used.
function M.files(m)
  if m.lens_files then
    return m.lens_files
  end
  local set = {}
  for _, e in ipairs(m.exports) do
    set[e.path] = true
    for _, u in ipairs(e.all_uses or e.uses) do
      set[u.path] = true
    end
  end
  local list = vim.tbl_keys(set)
  table.sort(list)
  m.lens_files = list
  return list
end

function M.matches(m, pattern)
  local fn, err = M.compile(pattern)
  if not fn then
    return {}, err
  end
  local out = {}
  for _, p in ipairs(M.files(m)) do
    if fn(p) then
      out[#out + 1] = p
    end
  end
  return out
end

--- The suggestions this repo has files for, and not already a rule.
function M.suggestions(lens, m)
  local have = {}
  for _, h in ipairs(lens.hides) do
    have[h.pattern] = true
  end
  local out = {}
  for _, p in ipairs(M.SUGGEST) do
    if not have[p] then
      local n = #M.matches(m, p)
      if n > 0 then
        out[#out + 1] = { pattern = p, n = n }
      end
    end
  end
  return out
end

--- Where a repository keeps its lens, beside its code.
function M.file(root)
  return root .. '/.seams/lens.json'
end

local function cols_of(list)
  local cols = M.none()
  for _, c in ipairs(type(list) == 'table' and list or {}) do
    if cols[c] ~= nil then
      cols[c] = true
    end
  end
  return cols
end

---@return seam.Lens
function M.load(root)
  local ok, lines = pcall(vim.fn.readfile, M.file(root))
  local ok2, d = pcall(vim.json.decode, ok and table.concat(lines, '\n') or '')
  local lens = M.new()
  if not ok2 or type(d) ~= 'table' then
    return lens
  end
  for _, p in ipairs(type(d.pins) == 'table' and d.pins or {}) do
    if type(p.dir) == 'string' and p.dir ~= '' then
      table.insert(lens.pins, { dir = p.dir:gsub('/*$', '') .. '/', cols = cols_of(p.columns) })
    end
  end
  for _, h in ipairs(type(d.hides) == 'table' and d.hides or {}) do
    if type(h.pattern) == 'string' and M.compile(h.pattern) then
      table.insert(lens.hides, { pattern = h.pattern, cols = cols_of(h.columns) })
    end
  end
  return lens
end

--- One rule a line, so it reads and diffs well. An empty lens is no file.
function M.save(lens, root)
  local file = M.file(root)
  if #lens.pins == 0 and #lens.hides == 0 then
    vim.fn.delete(file)
    vim.fn.delete(vim.fs.dirname(file), 'd')
    return
  end
  local function entry(key, value, cols)
    local on = vim.tbl_filter(function(c)
      return cols[c]
    end, M.COLS)
    return ('    { %s: %s, "columns": %s }'):format(vim.json.encode(key), vim.json.encode(value), #on == 0 and '[]' or vim.json.encode(on))
  end
  local pins, hides = {}, {}
  for _, p in ipairs(lens.pins) do
    pins[#pins + 1] = entry('dir', p.dir, p.cols)
  end
  for _, h in ipairs(lens.hides) do
    hides[#hides + 1] = entry('pattern', h.pattern, h.cols)
  end
  local out = { '{' }
  local function list(name, items, last)
    local close = last and ']' or '],'
    if #items == 0 then
      out[#out + 1] = ('  "%s": []%s'):format(name, last and '' or ',')
      return
    end
    out[#out + 1] = ('  "%s": ['):format(name)
    for i, item in ipairs(items) do
      out[#out + 1] = item .. (i < #items and ',' or '')
    end
    out[#out + 1] = '  ' .. close
  end
  list('pins', pins)
  list('hides', hides, true)
  out[#out + 1] = '}'
  vim.fn.mkdir(vim.fs.dirname(file), 'p')
  vim.fn.writefile(out, file)
end

function M.any(cols)
  return cols.contracts or cols.built or cols.used
end

--- `in run/ · 2 hiding` for the explorer's head.
function M.summary(lens)
  local parts, dirs, n = {}, {}, 0
  for _, p in ipairs(lens.pins) do
    if M.any(p.cols) then
      dirs[#dirs + 1] = (p.dir:gsub('/$', ''):match '[^/]+$' or p.dir) .. '/'
    end
  end
  if #dirs > 0 then
    parts[#parts + 1] = 'in ' .. table.concat(dirs, ' ')
  end
  for _, h in ipairs(lens.hides) do
    if M.any(h.cols) then
      n = n + 1
    end
  end
  if n > 0 then
    parts[#parts + 1] = n .. ' hiding'
  end
  return table.concat(parts, ' · ')
end

function M.cols_text(cols)
  if cols.contracts and cols.built and cols.used then
    return 'everywhere'
  end
  local out = {}
  for _, c in ipairs(M.COLS) do
    if cols[c] then
      out[#out + 1] = M.COL_NAME[c]
    end
  end
  return #out == 0 and 'nowhere' or table.concat(out, ', ')
end

return M
