-- What the explorer shows: rules, each a folder or file picked or a
-- pattern typed, that in each column show only the files they hold, hide
-- them, or leave the column be.
---@alias seam.Col 'contracts'|'built'|'used'
---@alias seam.Way 'only'|'hide'
---@class seam.Rule
---@field path? string    -- a folder picked, 'packages/core/', or a file
---@field pattern? string -- or what was typed, '**checklist**'
---@field cols table<seam.Col, seam.Way> -- a column missing, left be
---@class seam.Lens
---@field rules seam.Rule[]
local M = {}

M.COLS = { 'contracts', 'built', 'used' }
M.COL_NAME = { contracts = 'contracts', built = 'built from', used = 'used by' }

function M.new()
  return { rules = {} }
end

--- The same way in every column.
---@param way? seam.Way
function M.all(way)
  return { contracts = way, built = way, used = way }
end

local SPECIAL = {}
for c in ([[.^$~[]*+?=@{}()|<>%&\]]):gmatch '.' do
  SPECIAL[c] = true
end

--- A glob as a very magic regex: `**` anything, slashes too; `*` and `?`
--- within a name; `{a,b}` either; `[...]` a class; `\x` x itself.
local function glob_rx(g)
  local out, i, brace = {}, 1, false
  while i <= #g do
    local c = g:sub(i, i)
    if g:sub(i, i + 2) == '**/' then
      out[#out + 1], i = '(.*/)?', i + 3
    elseif g:sub(i, i + 1) == '**' then
      out[#out + 1], i = '.*', i + 2
    else
      if c == '*' then
        out[#out + 1] = '[^/]*'
      elseif c == '?' then
        out[#out + 1] = '[^/]'
      elseif c == '{' then
        out[#out + 1], brace = '(', true
      elseif c == '}' and brace then
        out[#out + 1], brace = ')', false
      elseif c == ',' and brace then
        out[#out + 1] = '|'
      elseif c == '[' and g:find(']', i + 1, true) then
        local close = g:find(']', i + 1, true)
        out[#out + 1] = '[' .. g:sub(i + 1, close - 1):gsub('^!', '^') .. ']'
        i = close
      elseif c == '\\' and i < #g then
        i = i + 1
        local n = g:sub(i, i)
        out[#out + 1] = SPECIAL[n] and '\\' .. n or n
      else
        out[#out + 1] = SPECIAL[c] and '\\' .. c or c
      end
      i = i + 1
    end
  end
  return table.concat(out)
end

--- `*.test.*` a file name; `tests/` a folder anywhere; `a/*/b/**` or
--- `**checklist**` a path; `/regex/` a regex on the path, very magic so
--- `(test|spec)` means what it says elsewhere; anything else, text in the
--- path. All but a regex ignore case unless they have a capital.
---@return (fun(path: string): boolean)|nil, string|nil
function M.compile(pattern)
  local p = vim.trim(pattern or '')
  if p == '' then
    return nil, 'type a pattern'
  end
  local function regex(body)
    local ok, rx = pcall(vim.regex, body)
    if ok then
      return rx
    end
  end
  local re = p:match '^/(.+)/$'
  if re then
    local rx = regex(re:match '^\\[vmMV]' and re or ('\\v' .. re))
    if not rx then
      return nil, 'not a regex'
    end
    return function(path)
      return rx:match_str(path) ~= nil
    end
  end
  local case = p:find '%u' and '' or '\\c'
  local dir = p:match '^(.-)/$'
  if dir then
    local rx = regex('\\v' .. case .. '^' .. glob_rx(dir) .. '$')
    if not rx then
      return nil, 'not a pattern'
    end
    -- with a slash, a folder from the root; without, a folder of that name anywhere
    local whole = dir:find '/' ~= nil
    return function(path)
      local prefix = ''
      for seg in path:gmatch '([^/]+)/' do
        prefix = prefix .. seg
        if rx:match_str(whole and prefix or seg) then
          return true
        end
        prefix = prefix .. '/'
      end
      return false
    end
  end
  if p:find '[%*%?%[{]' then
    local rx = regex('\\v' .. case .. '^' .. glob_rx(p) .. '$')
    if not rx then
      return nil, 'not a pattern'
    end
    local whole = p:find '/' or p:find('**', 1, true)
    return function(path)
      return rx:match_str(whole and path or (path:match '[^/]+$' or path)) ~= nil
    end
  end
  local needle = case == '' and p or p:lower()
  return function(path)
    return (case == '' and path or path:lower()):find(needle, 1, true) ~= nil
  end
end

--- What kind of pattern it is, in words, for the preview.
function M.describe(pattern)
  local p = vim.trim(pattern or '')
  if p:match '^/.+/$' then
    return 'a regex on the whole path'
  elseif p:match '/$' then
    return p:sub(1, -2):find '/' and 'that folder, from the repo root' or 'a folder of that name, anywhere'
  elseif p:find '[%*%?%[{]' then
    return (p:find '/' or p:find('**', 1, true)) and 'a path' or 'a file name'
  elseif p ~= '' then
    return 'any path containing it'
  end
  return ''
end

--- A rule's test of a path: inside the folder picked, that file, or a
--- match for what was typed.
---@param rule seam.Rule
---@return fun(path: string): boolean
function M.test(rule)
  if rule.pattern then
    return M.compile(rule.pattern) or function()
      return false
    end
  end
  local d = rule.path
  if d:sub(-1) == '/' then
    return function(path)
      return path:sub(1, #d) == d
    end
  end
  return function(path)
    return path == d
  end
end

--- What a rule shows in the panel and is found by.
function M.label(rule)
  return rule.path or rule.pattern
end

--- A function telling whether a path shows in a column: under one of the
--- column's `only` rules when it has any, and under none of its `hide` ones.
function M.visibility(lens)
  local only, hide = { contracts = {}, built = {}, used = {} }, { contracts = {}, built = {}, used = {} }
  for _, r in ipairs(lens.rules) do
    local test = M.test(r)
    for _, col in ipairs(M.COLS) do
      local way = r.cols[col]
      if way then
        table.insert(way == 'only' and only[col] or hide[col], test)
      end
    end
  end
  local cache = { contracts = {}, built = {}, used = {} }
  return function(path, col)
    local hit = cache[col][path]
    if hit ~= nil then
      return hit
    end
    local show = #only[col] == 0
    for _, test in ipairs(only[col]) do
      if test(path) then
        show = true
        break
      end
    end
    if show then
      for _, fn in ipairs(hide[col]) do
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
  -- the call tree asks as it draws; its counts were for the lens before
  m.visible = visible
  if m.graph then
    m.graph.memo = {}
  end
  local id_path = function(id)
    return id and id:match '^(.-):%d+:'
  end
  m.contracts = {}
  local hidden_files = {}
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
    if #e.all_uses > 0 then
      if visible(e.path, 'contracts') then
        m.contracts[#m.contracts + 1] = e
      else
        hidden_files[e.path] = true
      end
    end
  end
  -- the files whose contracts the contracts column leaves out
  m.hidden_files = vim.tbl_count(hidden_files)
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

--- The files a rule holds.
function M.rule_files(m, rule)
  local test, out = M.test(rule), {}
  for _, p in ipairs(M.files(m)) do
    if test(p) then
      out[#out + 1] = p
    end
  end
  return out
end

--- Where a repository keeps its lens, beside its code.
function M.file(root)
  return root .. '/.seams/lens.json'
end

---@return seam.Lens
function M.load(root)
  local ok, lines = pcall(vim.fn.readfile, M.file(root))
  local ok2, d = pcall(vim.json.decode, ok and table.concat(lines, '\n') or '')
  local lens = M.new()
  if not ok2 or type(d) ~= 'table' then
    return lens
  end
  for _, r in ipairs(type(d.rules) == 'table' and d.rules or {}) do
    local rule = { cols = {} }
    if type(r.path) == 'string' and r.path ~= '' then
      rule.path = r.path
    elseif type(r.pattern) == 'string' and M.compile(r.pattern) then
      rule.pattern = r.pattern
    end
    if rule.path or rule.pattern then
      for _, way in ipairs { 'only', 'hide' } do
        for _, c in ipairs(type(r[way]) == 'table' and r[way] or {}) do
          if M.COL_NAME[c] then
            rule.cols[c] = way
          end
        end
      end
      table.insert(lens.rules, rule)
    end
  end
  return lens
end

--- One rule a line, so it reads and diffs well. An empty lens is no file.
function M.save(lens, root)
  local file = M.file(root)
  if #lens.rules == 0 then
    vim.fn.delete(file)
    vim.fn.delete(vim.fs.dirname(file), 'd')
    return
  end
  local out = { '{', '  "rules": [' }
  for i, r in ipairs(lens.rules) do
    local parts = { ('%s: %s'):format(r.path and '"path"' or '"pattern"', vim.json.encode(M.label(r))) }
    for _, way in ipairs { 'only', 'hide' } do
      local cols = vim.tbl_filter(function(c)
        return r.cols[c] == way
      end, M.COLS)
      if #cols > 0 then
        parts[#parts + 1] = ('"%s": %s'):format(way, vim.json.encode(cols))
      end
    end
    out[#out + 1] = '    { ' .. table.concat(parts, ', ') .. ' }' .. (i < #lens.rules and ',' or '')
  end
  out[#out + 1] = '  ]'
  out[#out + 1] = '}'
  vim.fn.mkdir(vim.fs.dirname(file), 'p')
  vim.fn.writefile(out, file)
end

function M.any(cols)
  return cols.contracts or cols.built or cols.used
end

return M
