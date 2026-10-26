-- The explorer: the contracts in the order chosen, and for the one under the
-- cursor its head, then what it is built from and who uses it, as trees or
-- as a diagram.
local api = vim.api
local code = require 'seam.code'
local diagram = require 'seam.diagram'
local draw = require 'seam.draw'
local index = require 'seam.index'
local lens = require 'seam.lens'
local st = require 'seam.state'
local theme = require 'seam.theme'
local tree = require 'seam.tree'
local M = {}

local row, plural, trunc, shape = draw.row, draw.plural, draw.trunc, draw.shape

M.ORDERS = {
  { key = 'folder', label = 'by folder', short = 'by folder' },
  { key = 'used', label = 'most used first', short = 'most used' },
  { key = 'built', label = 'most built from first', short = 'most built from' },
  { key = 'name', label = 'by name', short = 'by name' },
}
-- the widths of the contracts and built-from columns
M.LW, M.MW = 46, 60
-- where the list's two counts end
local USED_END, BUILT_END = 34, 45

local function counts(r, c)
  local u, b = tostring(c.nusers), tostring(c.nbuilt)
  r:to(USED_END - #u)
  r:add(u, c.nusers == 0 and 'SeamLabel' or 'SeamText')
  r:to(BUILT_END - #b)
  r:add(b, 'SeamText')
end

local function contract_row(c, depth, flat)
  local r = row { kind = 'c', c = c }
  tree.bar(r, c.pkg)
  r:add(string.rep(' ', flat and 1 or depth * 2))
  local s, room = shape(c), USED_END - 5 - r.w
  local pre, post = s:match('^(.-)' .. vim.pesc(c.name) .. '(.*)$')
  if api.nvim_strwidth(s) > room or not pre then
    r:add(trunc(s, room), 'SeamName')
  else
    r:add(pre, 'SeamName')
    code.add_name(r, c.path, c.line, c.name, 'SeamName', room)
    r:add(post, 'SeamName')
  end
  counts(r, c)
  return r
end

local function head()
  local order = M.ORDERS[st.order]
  local rows = {}
  local r = row()
  r:add('Contracts', 'SeamTitle'):add('  ' .. order.label, 'SeamText')
  rows[1] = r
  r = row()
  if st.filter ~= '' then
    r:add('/ ', 'SeamLabel'):add(st.filter, 'SeamBold'):add('  ' .. #st.crows .. ' found', 'SeamLabel')
  else
    r:add('/ search', 'SeamLabel')
  end
  local sum = lens.summary(st.lens)
  r:add('   L ', 'SeamLabel'):add(sum ~= '' and sum or 'lens', sum ~= '' and 'SeamText' or 'SeamLabel')
  rows[2] = r
  r = row()
  draw.source(r)
  r:to(USED_END - 7)
  r:add('used by', order.key == 'used' and 'SeamTitle' or 'SeamLabel')
  r:add ' '
  r:add('built from', order.key == 'built' and 'SeamTitle' or 'SeamLabel')
  rows[3] = r
  draw.put(st.buf.lhead, rows)
end

--- The contracts matching the search, in the order chosen, and their head.
--- Leaves which row holds which contract in `st.rowc` and `st.crows`.
function M.list()
  local m = index.model()
  local f = st.filter:lower()
  local list = {}
  for _, c in ipairs(m.contracts) do
    if f == '' or c.name:lower():find(f, 1, true) then
      list[#list + 1] = c
    end
  end
  local key = M.ORDERS[st.order].key
  local rows
  if key == 'folder' then
    local entries = {}
    for _, c in ipairs(list) do
      local e = entries[c.path]
      if not e then
        e = {}
        entries[c.path] = e
      end
      e[#e + 1] = c
    end
    rows = tree.rows(m, entries, {
      file_hl = 'SeamPath',
      width = USED_END - 2,
      after = function(out, _, cs, depth)
        table.sort(cs, function(a, b)
          return a.line < b.line
        end)
        for _, c in ipairs(cs) do
          out[#out + 1] = contract_row(c, depth)
        end
      end,
    })
  else
    table.sort(list, function(a, b)
      if key == 'used' and a.nusers ~= b.nusers then
        return a.nusers > b.nusers
      elseif key == 'built' and a.nbuilt ~= b.nbuilt then
        return a.nbuilt > b.nbuilt
      end
      if a.name:lower() ~= b.name:lower() then
        return a.name:lower() < b.name:lower()
      end
      return a.id < b.id
    end)
    rows = {}
    for _, c in ipairs(list) do
      rows[#rows + 1] = contract_row(c, 0, true)
    end
  end
  st.rowc, st.crows = {}, {}
  for i, r in ipairs(rows) do
    if r.meta.kind == 'c' then
      st.rowc[i] = r.meta.c
      st.crows[#st.crows + 1] = i
    end
  end
  if #rows == 0 then
    rows = { row():add('  nothing matches', 'SeamLabel') }
  end
  draw.put(st.buf.list, rows)
  head()
end

-- what each other source says of `c`, when more than one is loaded
local function compare(c)
  if #st.names < 2 then
    return nil
  end
  local r = row()
  local differ = false
  local function one(name, e, first)
    if not first then
      r:add(' · ', 'SeamLabel')
    end
    r:add(name .. ': ', 'SeamLabel')
    if e and e.nusers > 0 then
      r:add(plural(e.nusers, 'file'), 'SeamText')
      if e == c or e.nbuilt ~= c.nbuilt then
        r:add(', built from ' .. e.nbuilt, 'SeamLabel')
      end
    elseif e then
      r:add('no users', 'SeamText')
    else
      r:add('not an export', 'SeamText')
    end
  end
  local first = true
  for _, nm in ipairs(st.names) do
    if nm ~= st.cur then
      local om = st.models[nm]
      local e = om.byid[c.id] or om.bykey[c.path .. ':' .. c.name]
      if not e or e.nusers ~= c.nusers or e.nbuilt ~= c.nbuilt then
        differ = true
      end
      one(nm, e, first)
      first = false
    end
  end
  one(st.cur, c, false)
  if not differ then
    r = row():add('every source agrees: ', 'SeamLabel'):add(plural(c.nusers, 'file'), 'SeamText'):add(', built from ' .. c.nbuilt, 'SeamLabel')
  end
  return r
end

--- The head over the trees: the contract, its first line, the sources.
---@param c table
function M.contract_head(c)
  local rows = {}
  local r = row()
  r:add(shape(c), 'SeamBold'):add('   ' .. c.kind .. ' in ', 'SeamLabel')
  draw.path(r, c.path, c.line)
  rows[1] = r
  r = row()
  if c.kind == 'function' or c.kind == 'component' or c.kind == 'const' then
    local l = vim.trim(code.file(c.path).lines[c.line] or ''):gsub('^export%s+', '')
    r:add(trunc(l, 120), 'SeamText')
  end
  rows[2] = r
  rows[3] = compare(c) or row()
  draw.put(st.buf.rhead, rows)
end

local function draw_diagram(c)
  local w = st.win.diag and api.nvim_win_is_valid(st.win.diag) and api.nvim_win_get_width(st.win.diag) or 120
  local rows
  if st.view == 'map' then
    rows = diagram.map(c, w - 2)
  else
    rows = diagram.contract(c, w - 2, st.sides)
  end
  draw.put(st.buf.diag, rows)
  if st.win.diag and api.nvim_win_is_valid(st.win.diag) then
    api.nvim_win_set_cursor(st.win.diag, { 1, 0 })
  end
end

--- The contract under the cursor: its head, then its trees or its diagram.
---@param c table
function M.contract(c)
  local m = index.model()
  M.contract_head(c)
  if st.view ~= 'trees' then
    return draw_diagram(c)
  end
  -- built from
  local entries, unresolved, nfiles, nnames = index.deps_by_file(c)
  local rows = { draw.title('built from', plural(nfiles, 'file') .. ' · ' .. plural(nnames, 'name')), row() }
  local NAMECOL = 30
  vim.list_extend(
    rows,
    tree.rows(m, entries, {
      own = c.pkg,
      width = NAMECOL,
      reserve = 1,
      file = function(r, _, e)
        r:to(NAMECOL)
        local names = {}
        for _, d in ipairs(e.list) do
          names[#names + 1] = d.name
        end
        r:add(trunc(table.concat(names, '  '), M.MW - NAMECOL - 1), 'SeamName')
      end,
    })
  )
  if #unresolved > 0 then
    local names = {}
    for _, d in ipairs(unresolved) do
      names[#names + 1] = d.name
    end
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' not resolved  ', 'SeamLabel'):add(trunc(table.concat(names, '  '), M.MW - 17), 'SeamText')
  end
  if (c.hidden_dep_files or 0) > 0 then
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' ' .. plural(c.hidden_dep_files, 'file') .. ' hidden by the lens', 'SeamLabel')
  end
  draw.put(st.buf.mid, rows)
  -- used by
  local uentries, nu = index.uses_by_file(c)
  local width = st.win.right and api.nvim_win_is_valid(st.win.right) and api.nvim_win_get_width(st.win.right) or 70
  local BARCOL = width - 12
  local max = 1
  for _, us in pairs(uentries) do
    max = math.max(max, #us)
  end
  rows = { draw.title('used by', plural(nu, 'file') .. ' · ' .. plural(#c.uses, 'reference')), row() }
  vim.list_extend(
    rows,
    tree.rows(m, uentries, {
      own = c.pkg,
      dimown = true,
      width = BARCOL,
      reserve = 1,
      file = function(r, path, us, pkg)
        r:to(BARCOL)
        local n = #us
        local w = math.max(1, math.min(6, math.ceil(6 * math.sqrt(n / max))))
        local own = pkg == c.pkg or index.is_test(path)
        r:add(string.rep('━', w), own and 'SeamBarGrey' or (pkg ~= '.' and theme.hue(pkg).bar or 'SeamPath'))
        r:add(' ' .. n, 'SeamText')
      end,
    })
  )
  if (c.hidden_users or 0) > 0 then
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' ' .. plural(c.hidden_users, 'file') .. ' hidden by the lens', 'SeamLabel')
  end
  draw.put(st.buf.right, rows)
  for _, w in ipairs { st.win.mid, st.win.right } do
    if w and api.nvim_win_is_valid(w) then
      api.nvim_win_set_cursor(w, { 1, 0 })
    end
  end
end

return M
