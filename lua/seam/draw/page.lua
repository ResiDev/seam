-- A contract's page: its head and tabs, the list of the tab shown (the files
-- it is built from, or the files that use it), the contract as code, and the
-- seam under the list's cursor: a dependency's declaration, or a user's code.
local api = vim.api
local code = require 'seam.code'
local draw = require 'seam.draw'
local index = require 'seam.index'
local st = require 'seam.state'
local tree = require 'seam.tree'
local M = {}

local row, plural, trunc, shape = draw.row, draw.plural, draw.trunc, draw.shape

--- A declaration's lines, its doc comment included.
---@param c table
---@return integer first, integer last
function M.decl_range(c)
  local s = code.doc_start(c.path, c.line)
  local e = c.end_line or c.line
  if e < c.line then
    e = c.line
  end
  return s, e
end

-- the declaration as code rows: opts.lit lines lit, else dimmed when opts.dim
-- and not in opts.keep
local function decl_rows(c, opts)
  opts = opts or {}
  local s, e = M.decl_range(c)
  local gw = math.max(3, #tostring(e))
  local rows = {}
  for l = s, e do
    local r = row { kind = 'code', lnum = l }
    r:add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
    code.add(r, c.path, l)
    if opts.lit and opts.lit[l] then
      r.line_hl = 'SeamLit'
    elseif opts.dim and not (opts.keep and opts.keep[l]) and l ~= c.line and l ~= e then
      r.dim = true
    end
    rows[#rows + 1] = r
  end
  return rows, s, e
end

--- The trail of pages, the contract, and the two tabs.
---@param p table the page
function M.head(p)
  local c = p.c
  local rows = {}
  local r = row()
  r:add(' Seams', 'SeamLabel')
  for _, prev in ipairs(st.stack) do
    r:add(' › ', 'SeamLabel'):add(draw.trail(prev), 'SeamLabel')
  end
  r:add(' › ', 'SeamLabel'):add(shape(c), 'SeamBold'):add('   ' .. c.kind .. ' in ', 'SeamLabel')
  draw.path(r, c.path, c.line)
  local lab = row()
  draw.source(lab)
  r:to(vim.o.columns - 2 - lab.w)
  draw.source(r)
  rows[1] = r
  local entries_n = select(4, index.deps_by_file(c))
  local labels = {
    { 'Built from', ' ' .. entries_n, 'built' },
    { 'Used by', ' ' .. plural(c.nusers, 'file'), 'used' },
  }
  r = row():add '  '
  for _, l in ipairs(labels) do
    if l[3] == p.tab then
      r:add(' ' .. l[1] .. l[2] .. ' ', 'SeamTab')
    else
      r:add(' ' .. l[1], 'SeamText'):add(l[2] .. ' ', 'SeamLabel')
    end
    r:add '    '
  end
  rows[2] = r
  rows[3] = row():add(string.rep('─', vim.o.columns), 'SeamSep')
  draw.put(p.buf.head, rows)
end

-- Built from tab --------------------------------------------------------

local function built_list(p)
  local c = p.c
  local entries, unresolved, nfiles, nnames = index.deps_by_file(c)
  local rows = { row(), draw.title('built from', plural(nfiles, 'file') .. ' · ' .. plural(nnames, 'name')), row() }
  vim.list_extend(
    rows,
    tree.rows(index.model(), entries, {
      own = c.pkg,
      width = 40,
      after = function(out, _, e, depth, pkg)
        for _, d in ipairs(e.list) do
          local r = row { kind = 'leaf', dep = d, select = true }
          tree.bar(r, pkg)
          r:add(string.rep(' ', depth * 2))
          code.add_name(r, index.id_path(d.target), index.id_line(d.target), d.name, 'SeamName', 38 - r.w)
          out[#out + 1] = r
        end
      end,
    })
  )
  if #unresolved > 0 then
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' not resolved', 'SeamLabel')
    for _, d in ipairs(unresolved) do
      local r = row { kind = 'leaf', dep = d, select = true }
      r:add('   ' .. trunc(d.name, 35), 'SeamText')
      rows[#rows + 1] = r
    end
  end
  return rows
end

-- the contract pane: its declaration, `lit` lines lit, the rest dimmed when
-- `dim`, and the members in `unders` underlined
local function contract(p, lit, dim, unders, note)
  if not p.win.mid then
    return
  end
  local c = p.c
  local head = row():add(' ' .. shape(c), 'SeamBold'):add('  ' .. vim.fn.fnamemodify(c.path, ':t') .. ':' .. c.line, 'SeamLabel')
  if note then
    head:add('   ' .. note, 'SeamLabel')
  end
  local rows = { row(), head, row() }
  local drows, s = decl_rows(c, { lit = lit, dim = dim, keep = unders and unders.lines })
  if unders then
    for _, r in ipairs(drows) do
      local names = unders.by_line[r.meta.lnum]
      if names then
        local src = code.file(c.path).lines[r.meta.lnum] or ''
        for name in pairs(names) do
          code.underline(r, r.code[1][4], src, name)
        end
      end
    end
  end
  vim.list_extend(rows, drows)
  draw.put(p.buf.mid, rows)
  -- the first lit line in view
  local first
  for l in pairs(lit or {}) do
    first = first and math.min(first, l) or l
  end
  if first then
    local at = 3 + first - s + 1
    local h = api.nvim_win_is_valid(p.win.mid) and api.nvim_win_get_height(p.win.mid) or 40
    code.scroll_to(p.win.mid, at, at < h - 2 and 1 or math.max(1, at - math.floor(h / 2)))
  else
    code.scroll_to(p.win.mid, 1, 1)
  end
end

--- A dependency's declaration in the right pane: where it lives, its code,
--- and who else uses it. Without the contract beside it, the lines naming it
--- come first.
---@param p table the page
---@param d table|nil a dependency, as index.deps_by_file groups it
function M.declaration(p, d)
  local m = index.model()
  local rows = { row() }
  local c = p.c
  p.enter = nil
  if not d then
    draw.put(p.buf.right, rows)
    return
  end
  if not d.target then
    rows[#rows + 1] = row():add(' ' .. d.name, 'SeamBold'):add('   ' .. st.cur .. ' could not resolve it', 'SeamLabel')
    draw.put(p.buf.right, rows)
    return
  end
  local t = m.byid[d.target]
  local path, line = index.id_path(d.target), index.id_line(d.target)
  local r = row():add ' '
  local s, e
  if t then
    r:add(shape(t), 'SeamBold'):add('   ' .. t.kind .. ' in ', 'SeamLabel')
    s, e = M.decl_range(t)
    p.enter = t.nusers > 0 and shape(t) or nil
  else
    r:add(d.name, 'SeamBold'):add('   not an export, in ', 'SeamLabel')
    s, e = code.statement_at(path, line)
    s = code.doc_start(path, s)
  end
  draw.path(r, path, line)
  rows[#rows + 1] = r
  rows[#rows + 1] = row()
  local width = p.win.right and api.nvim_win_get_width(p.win.right) or 100
  if not p.win.mid then
    local ls = vim.tbl_keys(d.lines)
    table.sort(ls)
    for i, l in ipairs(ls) do
      local ar = row():add(i == 1 and (' ' .. shape(c) .. ' uses it as') or '', 'SeamLabel')
      ar:to(#shape(c) + 14):add(string.format('%4d  ', l), 'SeamGutter')
      code.add(ar, c.path, l, true, width - ar.w - 1)
      rows[#rows + 1] = ar
    end
    rows[#rows + 1] = row()
  end
  rows[#rows + 1] = row()
  local gw = math.max(3, #tostring(e))
  local cut = false
  if e - s > 400 then
    e, cut = s + 400, true
  end
  for l = s, e do
    local cr = row():add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
    code.add(cr, path, l)
    rows[#rows + 1] = cr
  end
  if cut then
    rows[#rows + 1] = row():add('   ⋯', 'SeamLabel')
  end
  rows[#rows + 1] = row()
  if t then
    local rr = row():add(' used by ', 'SeamLabel'):add(plural(t.nusers, 'file'), 'SeamName')
    local names = {}
    for _, dd in ipairs(t.deps) do
      if not vim.tbl_contains(names, dd.name) then
        names[#names + 1] = dd.name
      end
    end
    if #names > 0 then
      rr:add('   built from ', 'SeamLabel'):add(trunc(table.concat(names, ', '), 80), 'SeamName')
    end
    rows[#rows + 1] = rr
  end
  draw.put(p.buf.right, rows)
  code.scroll_to(p.win.right, 1, 1)
end

-- a dependency on the list: the contract with the lines naming it lit, and
-- its declaration above, as short as it is so the contract keeps the rest
local function dependency(p, d)
  if d then
    local lit = {}
    for l in pairs(d.lines) do
      lit[l] = true
    end
    contract(p, lit, true, nil, 'uses ' .. d.name)
  end
  M.declaration(p, d)
  if d and p.win.mid and p.win.right then
    local total = api.nvim_win_get_height(p.win.right) + api.nvim_win_get_height(p.win.mid)
    local cs, ce = M.decl_range(p.c)
    local need = math.min(ce - cs + 1 + 4, math.floor(total * 0.45))
    api.nvim_win_set_height(p.win.right, math.min(api.nvim_buf_line_count(p.buf.right) + 1, total - need))
  end
end

--- Built from, read as code: the contract down the left, each name it is
--- built from marked where it stands. Leaves the names in `p.refs`, in reading
--- order, each `{ row, s, e, dep }` with `row` 1-based and `s`..`e` its bytes.
---@param p table the page
function M.code(p)
  local c = p.c
  local entries, unresolved, nfiles, nnames = index.deps_by_file(c)
  local rows = { row(), draw.title('built from', plural(nfiles, 'file') .. ' · ' .. plural(nnames, 'name')), row() }
  local drows, s = decl_rows(c)
  local P = code.file(c.path)
  local refs = {}
  for _, d in ipairs(c.deps) do
    local path = index.id_path(d.target)
    local dep = path and entries[path].names[d.name] or unresolved[d.name]
    local r = drows[d.line - s + 1]
    local src = P.lines[d.line] or ''
    -- a source without columns names each once: its first match on the line
    local at = d.col and src:sub(d.col, d.col + #d.name - 1) == d.name and d.col or src:find('%f[%w_$]' .. vim.pesc(d.name) .. '%f[^%w_$]')
    if r and at then
      local b = r.code[1][4] + at - 1
      r.h[#r.h + 1] = { b, b + #d.name, dep.target and 'SeamRef' or 'SeamRefLost', 310 }
      refs[#refs + 1] = { row = #rows + d.line - s + 1, s = b, e = b + #d.name, dep = dep }
    end
  end
  table.sort(refs, function(a, b)
    return a.row < b.row or (a.row == b.row and a.s < b.s)
  end)
  vim.list_extend(rows, drows)
  draw.put(p.buf.mid, rows)
  p.refs = refs
  local width = 0
  for _, r in ipairs(rows) do
    width = math.max(width, r.w)
  end
  return width
end

-- Used by tab --------------------------------------------------------

local function used_list(p)
  local c = p.c
  local entries, nfiles = index.uses_by_file(c)
  local rows = { row(), draw.title('used by', plural(nfiles, 'file') .. ' · ' .. plural(#c.uses, 'reference')), row() }
  vim.list_extend(
    rows,
    tree.rows(index.model(), entries, {
      own = c.pkg,
      width = 34,
      select = 'file',
      reserve = 1,
      file = function(r, _, us)
        local n = tostring(#us)
        r:to(38 - #n)
        r:add(n, 'SeamText')
      end,
    })
  )
  return rows
end

-- a user: the members it reads, and its uses in the functions they sit in
local function user(p, path)
  local c = p.c
  local us = index.uses_by_file(c)[path] or {}
  local P = code.file(path)
  local rows = { row() }
  local r = row():add(' ' .. vim.fn.fnamemodify(path, ':t'), 'SeamBold'):add '   '
  local dir = vim.fn.fnamemodify(path, ':h') .. '/'
  draw.path(r, dir)
  rows[#rows + 1] = r
  rows[#rows + 1] = row()
  -- members read, when the data says
  local unders
  local memat = {} -- line -> { {name, col} }
  local has_member_data = type(c.member_uses) == 'table' and next(c.member_uses) ~= nil
  if has_member_data then
    unders = { by_line = {}, lines = {}, readset = {}, reads = {} }
    for _, mem in ipairs(c.members) do
      for _, mu in ipairs(c.member_uses[mem.name] or {}) do
        if mu.path == path then
          if not unders.readset[mem.name] then
            unders.readset[mem.name] = true
            unders.reads[#unders.reads + 1] = mem.name
          end
          memat[mu.line] = memat[mu.line] or {}
          table.insert(memat[mu.line], { mem.name, mu.col })
        end
      end
    end
    if #unders.reads == 0 then
      unders.reads = { '(no member of it, by property access)' }
    end
  end
  for _, u in ipairs(us) do
    if u.member then
      unders = unders or { by_line = {}, lines = {}, readset = {}, reads = {} }
      if not unders.readset[u.member] then
        unders.readset[u.member] = true
        unders.reads[#unders.reads + 1] = u.member
      end
    end
  end
  if unders then
    for _, mem in ipairs(c.members) do
      if unders.readset[mem.name] then
        unders.by_line[mem.line] = unders.by_line[mem.line] or {}
        unders.by_line[mem.line][mem.name] = true
        unders.lines[mem.line] = true
      end
    end
  end
  contract(p, nil, unders ~= nil, unders, 'used in ' .. vim.fn.fnamemodify(path, ':t'))
  if unders and unders.reads then
    local rr = row():add(' reads', 'SeamLabel')
    for _, n in ipairs(unders.reads) do
      rr:add('  ' .. n, 'SeamName')
    end
    rows[#rows + 1] = rr
    rows[#rows + 1] = row()
  end
  -- pieces
  local show, lit, cols = {}, {}, {}
  local groups = {}
  for _, u in ipairs(us) do
    lit[u.line] = true
    cols[u.line] = cols[u.line] or u.col
    local s, e = code.enclosing(path, u.line, u.col or 1)
    local key = s .. ':' .. e
    local g = groups[key]
    if not g then
      g = { s = s, e = e, lines = {} }
      groups[key] = g
    end
    g.lines[u.line] = true
  end
  for ml in pairs(memat) do
    for _, g in pairs(groups) do
      if ml >= g.s and ml <= g.e then
        g.lines[ml] = true
      end
    end
  end
  for _, g in pairs(groups) do
    for l in pairs(code.pick_rows(g.s, g.e, g.lines)) do
      show[l] = true
    end
  end
  local lines = vim.tbl_keys(show)
  table.sort(lines)
  local last = lines[#lines] or 1
  local gw = math.max(3, #tostring(last))
  local function gap()
    rows[#rows + 1] = row():add(string.rep(' ', gw) .. '⋯', 'SeamLabel')
  end
  local function coderow(l, is_lit)
    local cr = row { kind = 'code', lnum = l }
    cr:add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
    local start = cr.b
    code.add(cr, path, l)
    if is_lit then
      cr.line_hl = 'SeamLit'
      code.underline(cr, start, P.lines[l] or '', c.name, cols[l])
    end
    for _, mu in ipairs(memat[l] or {}) do
      code.underline(cr, start, P.lines[l] or '', mu[1], mu[2])
    end
    rows[#rows + 1] = cr
    return cr
  end
  local is, ie, nl = code.import_of(path, c.name)
  if is and not show[is] then
    if ie - is > 3 then
      -- a long import: its first line, the line naming the contract, its last
      local prev
      for _, l in ipairs { is, nl, ie } do
        if l and l ~= prev then
          if prev and l > prev + 1 then
            gap()
          end
          coderow(l)
          prev = l
        end
      end
    else
      for l = is, ie do
        coderow(l)
      end
    end
    if lines[1] and lines[1] > ie + 1 then
      gap()
    end
  end
  p.lit_rows = {}
  local prev
  for _, l in ipairs(lines) do
    if prev and l > prev + 1 then
      gap()
    end
    coderow(l, lit[l])
    if lit[l] then
      p.lit_rows[#p.lit_rows + 1] = #rows
    end
    prev = l
  end
  draw.put(p.buf.right, rows)
  code.scroll_to(p.win.right, 1, 1)
end

-- the page --------------------------------------------------------

--- The list of the tab shown. Leaves its rows in `p.rows`, and the rows that
--- can be selected in `p.sel_rows`.
---@param p table the page
function M.list(p)
  local rows = p.tab == 'built' and built_list(p) or used_list(p)
  p.sel_rows = {}
  for i, r in ipairs(rows) do
    if r.meta.select then
      p.sel_rows[#p.sel_rows + 1] = i
    end
  end
  p.rows = rows
  p.count = #p.sel_rows
  draw.put(p.buf.list, rows)
end

--- The seam a list row stands for, beside the contract.
---@param p table the page
---@param meta table the row's meta
function M.seam(p, meta)
  if p.tab == 'built' then
    dependency(p, meta.dep)
  elseif meta.path then
    user(p, meta.path)
  end
end

--- A tab with nothing in it: the contract alone, unless it is already shown
--- as code.
---@param p table the page
function M.empty(p)
  if not p.refs then
    contract(p)
  end
  draw.put(p.buf.right, { row(), row():add(p.tab == 'built' and ' built from nothing in the repo' or ' no users', 'SeamLabel') })
end

return M
