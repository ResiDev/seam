-- Rows: a line of text built from pieces with their highlights, put into a
-- scratch buffer as lines and marks; and the pieces both screens draw.
local api = vim.api
local code = require 'seam.code'
local index = require 'seam.index'
local st = require 'seam.state'
local theme = require 'seam.theme'
local M = {}

M.ns = api.nvim_create_namespace 'seam'
local ns_cursor = api.nvim_create_namespace 'seam.cursor'

local function width(s)
  if s:find '[\128-\255]' then
    return api.nvim_strwidth(s)
  end
  return #s
end

local Row = {}
Row.__index = Row

--- A row; `meta` says what it stands for, to the code that moves over it.
---@param meta? table
---@return table
function M.row(meta)
  return setmetatable({ t = {}, h = {}, b = 0, w = 0, meta = meta or {} }, Row)
end

function Row:add(s, hl, prio)
  if not s or s == '' then
    return self
  end
  self.t[#self.t + 1] = s
  if hl then
    self.h[#self.h + 1] = { self.b, self.b + #s, hl, prio }
  end
  self.b = self.b + #s
  self.w = self.w + width(s)
  return self
end

--- Pad to display column `col`.
function Row:to(col)
  if self.w < col then
    self:add(string.rep(' ', col - self.w))
  end
  return self
end

function Row:text()
  return table.concat(self.t)
end

---@param n integer
---@param word string
---@return string
function M.plural(n, word)
  return n .. ' ' .. word .. (n == 1 and '' or 's')
end

--- `s` cut to `w` display columns, ending in … when cut.
---@param s string
---@param w integer
---@return string
function M.trunc(s, w)
  if w <= 1 then
    return ''
  end
  if width(s) <= w then
    return s
  end
  return vim.fn.strcharpart(s, 0, w - 1) .. '…'
end

--- A contract's name in the shape of its kind: `fn()`, `<Component>`, `Type`.
---@param c table
---@return string
function M.shape(c)
  if c.kind == 'function' then
    return c.name .. '()'
  elseif c.kind == 'component' then
    return '<' .. c.name .. '>'
  end
  return c.name
end

---@param name string
---@return integer
function M.scratch(name)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'hide'
  vim.bo[b].buftype = 'nofile'
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  vim.bo[b].tabstop = 2
  pcall(api.nvim_buf_set_name, b, 'seam://' .. name .. '/' .. b)
  return b
end

--- Replace `buf`'s lines and marks with `rows`.
---@param buf integer
---@param rows table[]
function M.put(buf, rows)
  local lines = {}
  for i, r in ipairs(rows) do
    lines[i] = r:text()
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, code.ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, ns_cursor, 0, -1)
  local codes = {}
  for i, r in ipairs(rows) do
    local row0 = i - 1
    for _, h in ipairs(r.h) do
      local e = math.min(h[2], #lines[i])
      if e > h[1] then
        api.nvim_buf_set_extmark(buf, M.ns, row0, h[1], { end_col = e, hl_group = h[3], priority = h[4] or 150 })
      end
    end
    if r.line_hl then
      api.nvim_buf_set_extmark(buf, M.ns, row0, 0, { line_hl_group = r.line_hl, priority = 90 })
    end
    if r.code then
      codes[row0] = r.code
      if r.dim then
        api.nvim_buf_set_extmark(buf, M.ns, row0, r.code[4], { end_col = r.code[4] + r.code[5], hl_group = 'SeamCodeDim', priority = 300 })
      end
    end
  end
  code.track(buf, codes)
end

--- Light the line the cursor is on in `win`, every row it wraps to.
--- 'cursorline' leaves the indent of a wrapped row dark.
---@param win integer
function M.cursor_line(win)
  local buf = api.nvim_win_get_buf(win)
  api.nvim_buf_clear_namespace(buf, ns_cursor, 0, -1)
  local r = api.nvim_win_get_cursor(win)[1] - 1
  api.nvim_buf_set_extmark(buf, ns_cursor, r, 0, { line_hl_group = 'CursorLine', priority = 95 })
end

--- A path with its package in the package's hue, and `:line` when given.
---@param r table
---@param path string
---@param line? integer
function M.path(r, path, line)
  local pkg = index.pkg_of(index.model(), path)
  if pkg ~= '.' then
    local prefix = pkg:match '^(.*/)' or ''
    r:add(prefix, 'SeamPath')
    r:add(pkg:match '[^/]+$', theme.hue(pkg).name)
    r:add(path:sub(#pkg + 1) .. (line and (':' .. line) or ''), 'SeamPath')
  else
    r:add(path .. (line and (':' .. line) or ''), 'SeamPath')
  end
end

--- The source shown and how long it took to index.
---@param r table
function M.source(r)
  r:add(st.cur, 'SeamBold')
  r:add(string.format('  %s ms', tostring(index.model().ms.total or '?')), 'SeamLabel')
end

---@param text string
---@param rest string
---@return table
function M.title(text, rest)
  return M.row():add(text, 'SeamSection'):add('   ' .. rest, 'SeamLabel')
end

return M
