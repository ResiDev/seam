-- Source files, their treesitter trees, highlight captures copied onto
-- copied lines, enclosing functions. Throwaway lab code.
local api = vim.api
local M = {}

local site = vim.fn.expand '~/.local/share/nvim/site'
pcall(vim.treesitter.language.add, 'tsx', { path = site .. '/parser/tsx.so' })
pcall(vim.treesitter.language.add, 'typescript', { path = site .. '/parser/typescript.so' })
-- the queries live beside the parsers; --clean leaves site off the rtp
if not vim.o.runtimepath:find(site, 1, true) then
  vim.opt.runtimepath:append(site)
end

M.root = nil
M.ns = api.nvim_create_namespace 'seam_code'
local files = {}
M.stats = { parses = 0, parse_ms = 0, cap_ms = 0 }

function M.reset()
  files = {}
end

local function lang_of(path)
  if path:match '%.tsx$' or path:match '%.jsx?$' then
    return 'tsx'
  elseif path:match '%.[mc]?ts$' then
    return 'typescript'
  end
end

---@return { lines: string[], lang: string|nil, caps: table, text: string|nil, root: any }
function M.file(path)
  local P = files[path]
  if P then
    return P
  end
  local ok, lines = pcall(vim.fn.readfile, M.root .. '/' .. path)
  P = { lines = ok and lines or {}, lang = lang_of(path), caps = {} }
  files[path] = P
  return P
end

function M.tree(P)
  if P.root == nil then
    P.root = false
    if P.lang then
      local t0 = vim.uv.hrtime()
      P.text = table.concat(P.lines, '\n')
      local ok, parser = pcall(vim.treesitter.get_string_parser, P.text, P.lang)
      if ok then
        local okp, trees = pcall(parser.parse, parser)
        if okp and trees[1] then
          P.root = trees[1]:root()
          P.query = vim.treesitter.query.get(P.lang, 'highlights')
        end
      end
      M.stats.parses = M.stats.parses + 1
      M.stats.parse_ms = M.stats.parse_ms + (vim.uv.hrtime() - t0) / 1e6
    end
  end
  return P.root or nil
end

-- the captures of rows r0..r1 (0-based), cached per row
local function captures(P, r0, r1)
  local root = M.tree(P)
  if not root or not P.query then
    return
  end
  local s, e
  for r = r0, r1 do
    if not P.caps[r] then
      s = s or r
      e = r
    end
  end
  if not s then
    return
  end
  local t0 = vim.uv.hrtime()
  for r = s, e do
    P.caps[r] = {}
  end
  local q = P.query
  for id, node, meta in q:iter_captures(root, P.text, s, e + 1) do
    local name = q.captures[id]
    if name ~= 'spell' and name ~= 'nospell' and name:sub(1, 1) ~= '_' and name ~= 'conceal' then
      local sr, sc, er, ec = node:range()
      local prio = tonumber(meta and (meta.priority or (meta[id] and meta[id].priority))) or 100
      for r = math.max(sr, s), math.min(er, e) do
        local a = r == sr and sc or 0
        local b = r == er and ec or #(P.lines[r + 1] or '')
        if b > a then
          local list = P.caps[r]
          list[#list + 1] = { a, b, '@' .. name .. '.' .. P.lang, prio }
        end
      end
    end
  end
  M.stats.cap_ms = M.stats.cap_ms + (vim.uv.hrtime() - t0) / 1e6
end

--- Copy the captures of source line `lnum` (1-based) from byte `from` onto
--- buffer row `row` at byte column `dst`.
function M.paint(buf, row, path, lnum, from, dst, len)
  local P = M.file(path)
  captures(P, lnum - 1, lnum - 1)
  local list = P.caps[lnum - 1]
  if not list then
    return
  end
  for _, c in ipairs(list) do
    local a, b = math.max(c[1], from), math.min(c[2], from + len)
    if b > a then
      pcall(api.nvim_buf_set_extmark, buf, M.ns, row, dst + a - from, { end_col = dst + b - from, hl_group = c[3], priority = c[4] })
    end
  end
end

--- Warm the capture cache for a range in one query run.
function M.warm(path, l0, l1)
  local P = M.file(path)
  captures(P, l0 - 1, l1 - 1)
end

local FN = {
  function_declaration = true,
  generator_function_declaration = true,
  method_definition = true,
  class_declaration = false,
}

--- The function a position sits in: nearest function, method, or arrow /
--- function expression assigned to a name; else the top-level statement.
--- Returns 1-based start and end lines.
function M.enclosing(path, line, col)
  local P = M.file(path)
  local root = M.tree(P)
  if not root then
    return line, line
  end
  local node = root:named_descendant_for_range(line - 1, math.max(col - 1, 0), line - 1, math.max(col - 1, 0))
  local top
  while node do
    local t = node:type()
    if FN[t] then
      break
    end
    if t == 'arrow_function' or t == 'function_expression' or t == 'function' then
      local p = node:parent()
      if p and (p:type() == 'variable_declarator' or p:type() == 'public_field_definition' or p:type() == 'pair') then
        if p:type() == 'variable_declarator' and p:parent() then
          node = p:parent()
          if node:parent() and node:parent():type() == 'export_statement' then
            node = node:parent()
          end
        else
          node = p
        end
        break
      end
    end
    local parent = node:parent()
    if parent and parent:type() == 'program' then
      top = node
      break
    end
    node = parent
  end
  node = node or top
  if not node then
    return line, line
  end
  local sr, _, er, ec = node:range()
  if ec == 0 and er > sr then
    er = er - 1
  end
  return sr + 1, er + 1
end

--- The import statement in `path` that names `name`: its 1-based lines.
function M.import_of(path, name)
  local P = M.file(path)
  local root = M.tree(P)
  if not root then
    return nil
  end
  for child in root:iter_children() do
    if child:type() == 'import_statement' then
      local sr, _, er = child:range()
      for r = sr, er do
        local l = P.lines[r + 1] or ''
        if l:find('%f[%w_$]' .. vim.pesc(name) .. '%f[^%w_$]') then
          return sr + 1, er + 1, r + 1
        end
      end
    end
  end
end

--- The top-level statement containing a line (for a declaration that is
--- not an export of the data).
function M.statement_at(path, line)
  local P = M.file(path)
  local root = M.tree(P)
  if not root then
    return line, line
  end
  for child in root:iter_children() do
    local sr, _, er = child:range()
    if sr + 1 <= line and er + 1 >= line then
      return sr + 1, er + 1
    end
  end
  return line, line
end

--- Where a doc comment above `line` starts.
function M.doc_start(path, line)
  local P = M.file(path)
  local l = line
  local prev = P.lines[l - 1]
  if prev and prev:match '%*/%s*$' then
    local k = l - 1
    while k >= 1 and not P.lines[k]:match '^%s*/%*' do
      k = k - 1
    end
    if k >= 1 and l - k < 40 then
      return k
    end
  end
  return line
end

return M
