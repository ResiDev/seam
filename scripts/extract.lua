-- nvim --headless --clean -l extract.lua <repo> <out.json>
-- The treesitter index of a TypeScript repo: every export, the files that
-- use it and the names it is built from, resolved through relative paths,
-- every tsconfig's `paths` and workspace packages by name.
local repo, out = arg[1], arg[2]
local site = vim.fn.stdpath 'data' .. '/site/parser/'
local function add_lang(lang)
  local ok, found = pcall(vim.treesitter.language.add, lang)
  if not (ok and found) then
    vim.treesitter.language.add(lang, { path = site .. lang .. '.so' })
  end
end
add_lang 'typescript'
add_lang 'tsx'

local function now()
  return vim.uv.hrtime()
end
local function ms(t)
  return math.floor((now() - t) / 1e6)
end
local T0 = now()
local timing = {}
local function sh(cmd)
  return vim.fn.systemlist { 'sh', '-c', 'cd ' .. vim.fn.shellescape(repo) .. ' && ' .. cmd }
end

local files = vim.fn.systemlist { 'git', '-C', repo, 'ls-files', '--cached', '--others', '--exclude-standard', '*.ts', '*.tsx', '*.mts', '*.cts' }
if vim.v.shell_error ~= 0 then
  files =
    sh "find . \\( -name '*.ts' -o -name '*.tsx' -o -name '*.mts' -o -name '*.cts' \\) -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/.git/*' | sed 's|^./||'"
end
files = vim.tbl_filter(function(f)
  return not f:match '%.d%.[mc]?ts$' and vim.fn.filereadable(repo .. '/' .. f) == 1
end, files)
local is_file = {}
for _, f in ipairs(files) do
  is_file[f] = true
end

local function jsonc(path)
  local fh = io.open(repo .. '/' .. path, 'r')
  if not fh then
    return nil
  end
  local s = fh:read '*a'
  fh:close()
  local out, i, n, instr = {}, 1, #s, false
  while i <= n do
    local c = s:sub(i, i)
    if instr then
      out[#out + 1] = c
      if c == '\\' then
        out[#out + 1] = s:sub(i + 1, i + 1)
        i = i + 1
      elseif c == '"' then
        instr = false
      end
    elseif c == '"' then
      instr = true
      out[#out + 1] = c
    elseif s:sub(i, i + 1) == '//' then
      while i <= n and s:sub(i, i) ~= '\n' do
        i = i + 1
      end
      out[#out + 1] = '\n'
    elseif s:sub(i, i + 1) == '/*' then
      local e = s:find('*/', i + 2, true) or n
      i = e + 1
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  local text = table.concat(out):gsub(',(%s*[}%]])', '%1')
  local ok, j = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  return ok and type(j) == 'table' and j or nil
end

local function norm(p)
  local parts = {}
  for seg in p:gmatch '[^/]+' do
    if seg == '..' then
      table.remove(parts)
    elseif seg ~= '.' then
      parts[#parts + 1] = seg
    end
  end
  return table.concat(parts, '/')
end
local function dir_of(p)
  local d = vim.fs.dirname(p)
  return (d == '.' or d == '') and '' or d
end
local function join(d, p)
  return norm(d == '' and p or (d .. '/' .. p))
end
local function try(p)
  p = norm(p)
  local base = p:gsub('%.[mc]?js$', ''):gsub('%.jsx$', '')
  for _, c in ipairs { p, base .. '.ts', base .. '.tsx', base .. '.mts', base .. '.cts', base .. '/index.ts', base .. '/index.tsx' } do
    if is_file[c] then
      return c
    end
  end
end

-- workspace packages: a directory with a package.json is a package
local workspace, pkgdirs = {}, {}
for _, pj in ipairs(sh "find . -name package.json -not -path '*/node_modules/*' -not -path '*/.git/*' | sed 's|^./||'") do
  local j = jsonc(pj)
  local dir = dir_of(pj)
  if j and dir ~= '' then
    pkgdirs[#pkgdirs + 1] = dir
  end
  if j and j.name then
    local entries = {}
    local function add(e)
      if type(e) == 'string' then
        entries[#entries + 1] = e
      end
    end
    add(j.source)
    add(j.types)
    add(j.typings)
    add(j.module)
    add(j.main)
    if type(j.exports) == 'table' then
      local dot = j.exports['.'] or j.exports
      if type(dot) == 'string' then
        add(dot)
      elseif type(dot) == 'table' then
        add(dot.source)
        add(dot.types)
        add(dot.import)
        add(dot.default)
      end
    end
    workspace[j.name] = { dir = dir, entries = entries }
  end
end
table.sort(pkgdirs, function(a, b)
  return #a > #b
end)
local function package_of(p)
  for _, d in ipairs(pkgdirs) do
    if p:sub(1, #d + 1) == d .. '/' then
      return d
    end
  end
  return p:match '^([^/]+)/' or '.'
end
local function in_workspace(w, rest)
  if rest then
    return try(join(w.dir, 'src/' .. rest)) or try(join(w.dir, rest))
  end
  for _, e in ipairs(w.entries) do
    local hit = try(join(w.dir, e))
      or try(join(w.dir, (e:gsub('^%./', ''):gsub('^dist/', 'src/'):gsub('^lib/', 'src/'):gsub('^build/', 'src/'):gsub('%.d%.ts$', ''))))
    if hit then
      return hit
    end
  end
  return try(join(w.dir, 'src/index')) or try(join(w.dir, 'index'))
end

-- every tsconfig's paths, following `extends`; a file uses the nearest one that has any
local configs = {}
local function load_config(path, depth)
  local j = jsonc(path)
  if not j then
    return {}
  end
  local co = j.compilerOptions or {}
  local res = {}
  if type(j.extends) == 'string' and (depth or 0) < 5 then
    local ext = j.extends:sub(1, 1) == '.' and join(dir_of(path), j.extends) or nil
    if ext and not ext:match '%.json$' then
      ext = ext .. '.json'
    end
    if ext then
      res = load_config(ext, (depth or 0) + 1)
    end
  end
  if co.paths then
    local base = co.baseUrl and join(dir_of(path), co.baseUrl) or dir_of(path)
    res = { base = base, paths = co.paths }
  elseif co.baseUrl and res.paths then
    res = { base = join(dir_of(path), co.baseUrl), paths = res.paths }
  end
  return res
end
for _, tc in ipairs(sh "find . -name 'tsconfig*.json' -not -path '*/node_modules/*' -not -path '*/.git/*' | sed 's|^./||'") do
  local c = load_config(tc)
  if c.paths then
    local list = {}
    for k, v in pairs(c.paths) do
      if type(v) == 'table' and type(v[1]) == 'string' then
        list[#list + 1] = { pat = k, to = join(c.base, v[1]) }
      end
    end
    table.sort(list, function(a, b)
      return #a.pat > #b.pat
    end)
    local d = dir_of(tc)
    if not configs[d] or tc:match '/tsconfig%.json$' or tc == 'tsconfig.json' then
      configs[d] = list
    end
  end
end
local function paths_for(file)
  local d = dir_of(file)
  while true do
    if configs[d] then
      return configs[d]
    end
    if d == '' then
      return {}
    end
    d = dir_of(d)
  end
end

local function resolve_spec(from, spec)
  if spec:sub(1, 1) == '.' then
    return try(join(dir_of(from), spec))
  end
  for _, m in ipairs(paths_for(from)) do
    if m.pat:sub(-1) == '*' then
      local pre = m.pat:sub(1, -2)
      if spec:sub(1, #pre) == pre then
        local hit = try((m.to:gsub('%*', (spec:sub(#pre + 1):gsub('%%', '%%%%')))))
        if hit then
          return hit
        end
      end
    elseif spec == m.pat then
      local hit = try(m.to)
      if hit then
        return hit
      end
    end
  end
  for name, w in pairs(workspace) do
    if spec == name then
      return in_workspace(w)
    elseif spec:sub(1, #name + 1) == name .. '/' then
      return in_workspace(w, spec:sub(#name + 2))
    end
  end
end

local function text_of(node, src)
  return vim.treesitter.get_node_text(node, src)
end
local function line_of(node)
  return (node:start()) + 1
end

local KIND = {
  function_declaration = 'function',
  generator_function_declaration = 'function',
  class_declaration = 'class',
  abstract_class_declaration = 'class',
  interface_declaration = 'interface',
  type_alias_declaration = 'type',
  enum_declaration = 'enum',
}

local function members_of(decl, src)
  local out = {}
  local body = decl:field('body')[1] or decl:field('value')[1]
  if not body then
    return out
  end
  for child in body:iter_children() do
    local t = child:type()
    local name
    if t == 'property_signature' or t == 'method_signature' or t == 'public_field_definition' or t == 'method_definition' then
      local acc = false
      for c in child:iter_children() do
        if c:type() == 'accessibility_modifier' and text_of(c, src) ~= 'public' then
          acc = true
        end
      end
      local n = child:field('name')[1]
      if n and not acc then
        name = text_of(n, src)
      end
    elseif t == 'enum_assignment' then
      local n = child:field('name')[1]
      name = n and text_of(n, src)
    elseif t == 'property_identifier' and body:type() == 'enum_body' then
      name = text_of(child, src)
    end
    if name and name:sub(1, 1) ~= '#' then
      out[#out + 1] = { name = name, line = line_of(child) }
    end
  end
  return out
end

-- pass 1: parse, exports, imports, re-exports
local F = {} -- path -> { src, root, lang, exports = {name -> exp}, imports = {local -> {spec, name}}, reexports = {}, top = {name -> node} }
local EXPORTS = {} -- id -> export record
local LIST = {}
local t = now()
for _, path in ipairs(files) do
  local src = table.concat(vim.fn.readfile(repo .. '/' .. path), '\n')
  local lang = path:match '%.tsx$' and 'tsx' or 'typescript'
  local root = vim.treesitter.get_string_parser(src, lang):parse()[1]:root()
  local f = { src = src, root = root, lang = lang, exports = {}, imports = {}, reexports = {}, top = {}, local_exports = {} }
  F[path] = f

  local function add_export(name_node, decl, kind)
    local name = text_of(name_node, src)
    if kind == 'function' and lang == 'tsx' and name:match '^%u' then
      kind = 'component'
    end
    local e = {
      id = path .. ':' .. line_of(name_node) .. ':' .. name,
      name = name,
      kind = kind,
      path = path,
      line = line_of(name_node),
      end_line = (select(1, decl:end_())) + 1,
      members = members_of(decl, src),
      uses = {},
      deps = {},
      _decl = decl,
      _range = { decl:range() },
    }
    f.exports[name] = e
    EXPORTS[e.id] = e
    LIST[#LIST + 1] = e
  end

  local function declare(decl, exported)
    if decl:type() == 'ambient_declaration' then
      decl = decl:named_child(0) or decl
    end
    local kind = KIND[decl:type()]
    if kind then
      local n = decl:field('name')[1]
      if n then
        f.top[text_of(n, src)] = { node = n, decl = decl, kind = kind }
        if exported then
          add_export(n, decl, kind)
        end
      end
    elseif decl:type() == 'lexical_declaration' or decl:type() == 'variable_declaration' then
      for d in decl:iter_children() do
        if d:type() == 'variable_declarator' then
          local n, v = d:field('name')[1], d:field('value')[1]
          if n and n:type() == 'identifier' then
            local k = (v and (v:type() == 'arrow_function' or v:type() == 'function_expression' or v:type() == 'function')) and 'function' or 'const'
            f.top[text_of(n, src)] = { node = n, decl = decl, kind = k }
            if exported then
              add_export(n, decl, k)
            end
          end
        end
      end
    end
  end

  for node in root:iter_children() do
    local ty = node:type()
    if ty == 'import_statement' then
      local s = node:field('source')[1]
      local spec = s and text_of(s, src):sub(2, -2)
      for clause in node:iter_children() do
        if clause:type() == 'import_clause' then
          for c in clause:iter_children() do
            if c:type() == 'identifier' then
              f.imports[text_of(c, src)] = { spec = spec, name = 'default' }
            elseif c:type() == 'namespace_import' then
              local id = c:named_child(0)
              if id then
                f.imports[text_of(id, src)] = { spec = spec, name = '*' }
              end
            elseif c:type() == 'named_imports' then
              for sp in c:iter_children() do
                if sp:type() == 'import_specifier' then
                  local n, a = sp:field('name')[1], sp:field('alias')[1]
                  f.imports[text_of(a or n, src)] = { spec = spec, name = text_of(n, src) }
                end
              end
            end
          end
        end
      end
    elseif ty == 'export_statement' then
      local s = node:field('source')[1]
      local decl = node:field('declaration')[1]
      local is_default = false
      for c in node:iter_children() do
        if c:type() == 'default' then
          is_default = true
        end
      end
      if s then
        local spec = text_of(s, src):sub(2, -2)
        local clause
        for c in node:iter_children() do
          if c:type() == 'export_clause' then
            clause = c
          end
        end
        if clause then
          for sp in clause:iter_children() do
            if sp:type() == 'export_specifier' then
              local n, a = sp:field('name')[1], sp:field('alias')[1]
              f.reexports[#f.reexports + 1] = { spec = spec, as = text_of(a or n, src), name = text_of(n, src) }
            end
          end
        else
          f.reexports[#f.reexports + 1] = { spec = spec, star = true }
        end
      elseif decl and not is_default then
        declare(decl, true)
      elseif not is_default then
        for c in node:iter_children() do
          if c:type() == 'export_clause' then
            for sp in c:iter_children() do
              if sp:type() == 'export_specifier' then
                local n, a = sp:field('name')[1], sp:field('alias')[1]
                f.local_exports[#f.local_exports + 1] = { name = text_of(n, src), as = text_of(a or n, src) }
              end
            end
          end
        end
      end
    else
      declare(node, false)
    end
  end
  for _, le in ipairs(f.local_exports) do
    local top = f.top[le.name]
    if top and not f.exports[le.as] then
      local kind = top.kind
      local name = le.name
      local e = {
        id = path .. ':' .. line_of(top.node) .. ':' .. name,
        name = name,
        kind = kind,
        path = path,
        line = line_of(top.node),
        end_line = (select(1, top.decl:end_())) + 1,
        members = members_of(top.decl, src),
        uses = {},
        deps = {},
        _decl = top.decl,
        _range = { top.decl:range() },
      }
      if not EXPORTS[e.id] then
        EXPORTS[e.id] = e
        LIST[#LIST + 1] = e
      end
      f.exports[le.as] = EXPORTS[e.id]
    elseif f.imports[le.name] then
      local im = f.imports[le.name]
      f.reexports[#f.reexports + 1] = { spec = im.spec, as = le.as, name = im.name }
    end
  end
  f.root = nil
  for k, v in pairs(f.top) do
    f.top[k] = line_of(v.node)
  end
  for _, e in pairs(f.exports) do
    e._decl = nil
  end
  if #LIST % 400 == 0 then
    collectgarbage()
  end
end
for _, e in ipairs(LIST) do
  e._decl = nil
end
collectgarbage()
timing.parse = ms(t)

-- resolve (file, exported name) to an export, through barrels
local memo = {}
local function find(path, name, depth)
  depth = depth or 0
  if not path or depth > 12 then
    return nil
  end
  local key = path .. '\0' .. name
  if memo[key] ~= nil then
    return memo[key] or nil
  end
  memo[key] = false
  local f = F[path]
  local hit = f and f.exports[name]
  if not hit and f then
    for _, r in ipairs(f.reexports) do
      if r.star then
        hit = find(resolve_spec(path, r.spec), name, depth + 1)
      elseif r.as == name and r.name ~= '*' and r.name ~= 'default' then
        hit = find(resolve_spec(path, r.spec), r.name, depth + 1)
      end
      if hit then
        break
      end
    end
  end
  memo[key] = hit or false
  return hit
end

-- pass 2: uses and deps
t = now()
local Q = {}
for _, lang in ipairs { 'typescript', 'tsx' } do
  Q[lang] = vim.treesitter.query.parse(
    lang,
    [[
    [(identifier) (type_identifier) (shorthand_property_identifier)] @id
    (member_expression object: (identifier) @ns property: (property_identifier) @prop)
    (nested_type_identifier module: (identifier) @ns name: (type_identifier) @prop)
  ]]
  )
end
local function excluded(node)
  local p = node:parent()
  while p do
    local ty = p:type()
    if ty == 'import_statement' or ty == 'export_clause' or (ty == 'export_statement' and p:field('source')[1]) then
      return true
    end
    if ty == 'program' then
      return false
    end
    p = p:parent()
  end
end
local function role(node)
  if node:type() == 'type_identifier' then
    return 'type'
  end
  local p = node:parent()
  if not p then
    return 'read'
  end
  local pt = p:type()
  if pt == 'member_expression' and p:field('property')[1] and p:field('property')[1]:id() == node:id() then
    node = p
    p = p:parent()
    pt = p and p:type() or ''
  elseif pt == 'nested_type_identifier' then
    return 'type'
  end
  if
    (pt == 'call_expression' and p:field('function')[1] and p:field('function')[1]:id() == node:id())
    or pt == 'new_expression'
    or pt == 'jsx_opening_element'
    or pt == 'jsx_self_closing_element'
  then
    return 'call'
  end
  if pt == 'assignment_expression' and p:field('left')[1] and p:field('left')[1]:id() == node:id() then
    return 'set'
  end
  if pt == 'member_expression' then
    return 'read'
  end
  if pt == 'arguments' or pt == 'jsx_expression' then
    return 'pass'
  end
  return 'read'
end

local nuses = 0
local done = 0
for path, f in pairs(F) do
  f.root = vim.treesitter.get_string_parser(f.src, f.lang):parse()[1]:root()
  local bound = {} -- local name -> export
  local ns = {} -- local namespace -> target path
  for localname, im in pairs(f.imports) do
    if im.spec then
      local target = resolve_spec(path, im.spec)
      if target then
        if im.name == '*' then
          ns[localname] = target
        elseif im.name ~= 'default' then
          bound[localname] = find(target, im.name)
        end
      end
    end
  end
  local own = {} -- same-file top-level names -> the export, or where it is declared
  for name, line in pairs(f.top) do
    own[name] = f.exports[name] or { id = path .. ':' .. line .. ':' .. name }
  end

  local q = Q[f.lang]
  local ns_node
  for cid, node in q:iter_captures(f.root, f.src) do
    local cap = q.captures[cid]
    local txt = text_of(node, f.src)
    local hit
    if cap == 'id' then
      hit = bound[txt]
    elseif cap == 'ns' then
      ns_node = ns[txt] and txt or nil
    elseif cap == 'prop' and ns_node then
      hit = find(ns[ns_node], txt)
      ns_node = nil
    end
    if hit and hit.path ~= path and not excluded(node) then
      local r, c = node:start()
      hit.uses[#hit.uses + 1] = { path = path, line = r + 1, col = c + 1, role = role(node) }
      nuses = nuses + 1
    end
  end

  -- deps: names inside each exported declaration, every place each is named
  for _, e in pairs(f.exports) do
    if e.path == path and not e._deps_done then
      e._deps_done = true
      local r = e._range
      local decl = f.root:named_descendant_for_range(r[1], r[2], r[3], r[4])
      for cid, node in q:iter_captures(decl, f.src, r[1], r[3] + 1) do
        if q.captures[cid] == 'id' then
          local txt = text_of(node, f.src)
          if txt ~= e.name then
            local target = bound[txt]
            if target == nil and own[txt] ~= nil then
              target = own[txt]
            end
            if target ~= nil then
              local l, c = node:start()
              e.deps[#e.deps + 1] = { name = txt, line = l + 1, col = c + 1, target = target and target.id or vim.NIL }
            end
          end
        end
      end
    end
  end
  f.root, f.src = nil, nil
  done = done + 1
  if done % 400 == 0 then
    collectgarbage()
  end
end
timing.uses = ms(t)
timing.total = ms(T0)

local pkgs, seen = {}, {}
for _, p in ipairs(files) do
  local k = package_of(p)
  if not seen[k] then
    seen[k] = true
    pkgs[#pkgs + 1] = k
  end
end
table.sort(pkgs)
local exports = {}
for _, e in ipairs(LIST) do
  e._decl, e._deps_done, e._range = nil, nil, nil
  exports[#exports + 1] = e
end
table.sort(exports, function(a, b)
  return a.id < b.id
end)
local fh = assert(io.open(out, 'w'))
fh:write(vim.json.encode {
  source = 'treesitter',
  version = 2,
  repo = repo,
  ms = timing,
  packages = pkgs,
  exports = exports,
  notes = { 'imports resolved by relative path and tsconfig paths only; a local that shadows an imported name still counts; default exports skipped' },
})
fh:close()
local used = 0
for _, e in ipairs(exports) do
  if #e.uses > 0 then
    used = used + 1
  end
end
io.stderr:write(
  ('treesitter: %d files, %d exports, %d used outside their file, %d uses; %s\n'):format(#files, #exports, used, nuses, vim.inspect(timing):gsub('%s+', ' '))
)
