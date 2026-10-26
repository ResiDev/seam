-- Code panes: source files and their treesitter trees, lines copied into
-- rows with their highlight captures painted on as they come into view, and
-- the questions asked of a file's tree: enclosing function, import, statement.
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
-- buffer -> { rows = row0 -> code, painted = row0 -> true }, the rows of copied code
local shown = {}

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

local function tree(P)
  if P.root == nil then
    P.root = false
    if P.lang then
      P.text = table.concat(P.lines, '\n')
      local ok, parser = pcall(vim.treesitter.get_string_parser, P.text, P.lang, { injections = { [P.lang] = '' } })
      if ok then
        local okp, trees = pcall(parser.parse, parser)
        if okp and trees[1] then
          P.root = trees[1]:root()
          P.query = vim.treesitter.query.get(P.lang, 'highlights')
        end
      end
    end
  end
  return P.root or nil
end

-- the captures of rows r0..r1 (0-based), cached per row
local function captures(P, r0, r1)
  local root = tree(P)
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
  -- the later pattern wins a range, as in the highlighter; two marks of one
  -- priority on one range are drawn in no promised order
  for r = s, e do
    local list, seen, keep = P.caps[r], {}, {}
    for i = #list, 1, -1 do
      local c = list[i]
      local k = c[1] .. ':' .. c[2] .. ':' .. c[4]
      if not seen[k] then
        seen[k] = true
        table.insert(keep, 1, c)
      end
    end
    P.caps[r] = keep
  end
end

-- Copy the captures of source line `lnum` (1-based) from byte `from` onto
-- buffer row `row` at byte column `dst`.
local function paint(buf, row, path, lnum, from, dst, len)
  local P = M.file(path)
  if type(from) == 'string' then
    -- a name: where its line names it, looked for only once it is in view
    local at = (P.lines[lnum] or ''):find('%f[%w_$]' .. vim.pesc(from) .. '%f[^%w_$]')
    if not at then
      return
    end
    from = at - 1
  end
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

--- Append source line `lnum` of `path` to row `r`, from its first non-blank
--- when `trim`, or from byte `trim` when it is a number; its captures are
--- painted when it comes into view.
---@param r table a draw row
---@param path string
---@param lnum integer
---@param trim? boolean|integer
---@param maxw? integer
---@return table r
function M.add(r, path, lnum, trim, maxw)
  local src = M.file(path).lines[lnum] or ''
  local from = type(trim) == 'number' and trim or trim and #(src:match '^%s*') or 0
  local text = src:sub(from + 1)
  if maxw and #text > maxw then
    text = text:sub(1, maxw)
  end
  r.code = r.code or {}
  r.code[#r.code + 1] = { path, lnum, from, r.b, #text }
  r:add(text)
  return r
end

--- Add `name` to row `r` coloured as its declaration on line `lnum` of `path`
--- is, from that line's captures, once in view; as `hl` until then, and where
--- the line does not name it. Cut to `maxw` it is plain `hl`.
---@param r table a draw row
---@param path string|nil
---@param lnum integer|nil
---@param name string
---@param hl string
---@param maxw integer
---@return table r
function M.add_name(r, path, lnum, name, hl, maxw)
  local w = api.nvim_strwidth(name)
  if not (path and lnum) or w > maxw then
    return r:add(w <= maxw and name or vim.fn.strcharpart(name, 0, maxw - 1) .. '…', hl)
  end
  r.code = r.code or {}
  r.code[#r.code + 1] = { path, lnum, name, r.b, #name }
  -- under the captures, for what they leave uncoloured
  return r:add(name, hl, 90)
end

--- The spans of copied code now in `buf`, by 0-based row, none painted yet.
---@param buf integer
---@param rows table<integer, table>
function M.track(buf, rows)
  shown[buf] = { rows = rows, painted = {} }
end

--- Paint the code rows in view in `win`, and a screen above and below.
---@param win integer
function M.paint_win(win)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  local C = shown[buf]
  if not C or next(C.rows) == nil then
    return
  end
  local tb = api.nvim_win_call(win, function()
    return { vim.fn.line 'w0', vim.fn.line 'w$' }
  end)
  local top, bot = tb[1], tb[2]
  local h = api.nvim_win_get_height(win)
  -- warm each file's range in one query run
  local ranges = {}
  for r0 = math.max(top - 1 - h, 0), bot - 1 + h do
    if C.rows[r0] and not C.painted[r0] then
      for _, c in ipairs(C.rows[r0]) do
        local R = ranges[c[1]]
        if not R then
          ranges[c[1]] = { c[2], c[2] }
        else
          R[1], R[2] = math.min(R[1], c[2]), math.max(R[2], c[2])
        end
      end
    end
  end
  for path, R in pairs(ranges) do
    captures(M.file(path), R[1] - 1, R[2] - 1)
  end
  for r0 = math.max(top - 1 - h, 0), bot - 1 + h do
    if C.rows[r0] and not C.painted[r0] then
      C.painted[r0] = true
      for _, c in ipairs(C.rows[r0]) do
        paint(buf, r0, c[1], c[2], c[3], c[4], c[5])
      end
    end
  end
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
  local root = tree(P)
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
  local root = tree(P)
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
  local root = tree(P)
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
