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
  local r = row():add('Seams', 'SeamTitle')
  local on = #vim.tbl_filter(function(rule)
    return lens.any(rule.cols)
  end, st.lens.rules)
  if on > 0 then
    r:add('   ' .. on .. (on == 1 and ' filter applied' or ' filters applied'), 'SeamFilter')
  end
  rows[1] = r
  r = row()
  if st.filter ~= '' then
    r:add('/ ', 'SeamLabel'):add(st.filter, 'SeamBold'):add('  ' .. #st.crows .. ' found', 'SeamLabel')
  end
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

-- the declaration from its first line, `export` dropped, wrapped at spaces
-- to `w` columns and cut to `max` rows
local function signature(c, w, max)
  local P = code.file(c.path)
  local last = math.max(c.end_line or c.line, c.line)
  local rows = {}
  for l = c.line, last do
    local src = P.lines[l] or ''
    local from = l == c.line and #(src:match '^%s*export%s+' or src:match '^%s*') or 0
    local cont = false
    while true do
      local r = row()
      if cont then
        r:add '  '
        from = from + #(src:sub(from + 1):match '^%s*')
      end
      local room = w - r.w
      local rest = #src - from
      if #rows == max - 1 and (rest > room or l < last) then
        code.add(r, c.path, l, from, math.min(rest, room - 1))
        rows[#rows + 1] = r:add('…', 'SeamLabel')
        return rows
      end
      local n = rest
      if rest > room then
        n = (src:sub(from + 1, from + room):match '^.*()%s') or room
        if n <= room / 2 then
          n = room
        end
      end
      rows[#rows + 1] = code.add(r, c.path, l, from, n)
      from, cont = from + n, true
      if from >= #src then
        break
      end
    end
  end
  return rows
end

--- The head over the trees: the contract, its declaration, the sources.
--- Its declaration takes two rows, or five beside one tree alone.
---@param c table
function M.contract_head(c)
  local win = st.win.rhead
  local w = win and api.nvim_win_is_valid(win) and api.nvim_win_get_width(win) or 120
  local r = row()
  r:add(shape(c), 'SeamBold'):add('   ' .. c.kind .. ' in ', 'SeamLabel')
  draw.path(r, c.path, c.line)
  local rows = { r }
  vim.list_extend(rows, signature(c, w - 1, st.sides == 'both' and 2 or 5))
  rows[#rows + 1] = compare(c)
  draw.put(st.buf.rhead, rows)
  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_set_height(win, #rows)
  end
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

-- the names of `list` from the `i`th on, after one another to column `w`; the
-- index of the first left over, or nil once all are on or, when `last`, the
-- one that does not fit is cut or, with no room for it, an ellipsis
local function put_names(r, list, i, w, last)
  local start = r.w
  for j = i, #list do
    local d = list[j]
    local gap = r.w > start and 2 or 0
    local nw = api.nvim_strwidth(d.name)
    local fits = r.w + gap + nw <= w
    if not fits and gap > 0 and not last then
      return j
    end
    if not fits and r.w + gap + 2 > w then
      r:add(r.w + 2 <= w and ' …' or '', 'SeamLabel')
      return nil
    end
    r:add(string.rep(' ', gap))
    code.add_name(r, index.id_path(d.target), index.id_line(d.target), d.name, 'SeamName', w - r.w)
    if not fits then
      return nil
    end
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
  local mw = st.win.mid and api.nvim_win_is_valid(st.win.mid) and api.nvim_win_get_width(st.win.mid) or M.MW
  local rows_of_names = st.sides == 'both' and 2 or 5
  local rest
  vim.list_extend(
    rows,
    tree.rows(m, entries, {
      own = c.pkg,
      width = NAMECOL,
      reserve = 1,
      file = function(r, _, e)
        r:to(NAMECOL)
        rest = put_names(r, e.list, 1, mw - 1, false)
      end,
      after = function(out, _, e, _, pkg)
        local n = 1
        while rest do
          n = n + 1
          local r = row()
          tree.bar(r, pkg)
          r:to(NAMECOL)
          rest = put_names(r, e.list, rest, mw - 1, n == rows_of_names)
          out[#out + 1] = r
        end
      end,
    })
  )
  if #unresolved > 0 then
    local names = {}
    for _, d in ipairs(unresolved) do
      names[#names + 1] = d.name
    end
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' not resolved  ', 'SeamLabel'):add(trunc(table.concat(names, '  '), mw - 17), 'SeamText')
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
