-- seam: the contracts of a TypeScript repo, from its treesitter index.
local api = vim.api
local code = require 'seam.code'
local diagram = require 'seam.diagram'
local lens = require 'seam.lens'
local M = {}

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local LAB = ROOT .. '/lab'
-- Where a repo's index lives: the lab's own three sources for its excalidraw
-- copy, else the cache, one directory a repo.
local OUT, HUEFILE
local function data_dir(root)
  if root == LAB .. '/excalidraw' then
    return LAB .. '/out'
  end
  return vim.fn.stdpath 'cache' .. '/seam/' .. root:gsub('^/', ''):gsub('/', '%%')
end
local ns = api.nvim_create_namespace 'seam'
local aug = api.nvim_create_augroup('seam', { clear = true })

local st = {
  models = {},
  names = {},
  order = 1,
  filter = '',
  code = {},
  view = 'trees',
  sides = 'both',
  panes = { built = 'both', used = 'seam' },
}
M.st = st
M.stats = { move = {}, diag = {}, open_ms = nil }

local function hr()
  return vim.uv.hrtime()
end
local function since(t)
  return (vim.uv.hrtime() - t) / 1e6
end

---------------------------------------------------------------- colours

local HUES = { '#7aa2f7', '#9ece6a', '#ff9e64', '#bb9af7', '#1abc9c', '#7dcfff', '#e0af68', '#f7768e' }

local function highlights()
  local function s(n, o)
    api.nvim_set_hl(0, n, o)
  end
  s('SeamTitle', { fg = '#7aa2f7', bold = true })
  s('SeamSection', { fg = '#b4bdf0', bold = true })
  s('SeamName', { fg = '#c0caf5' })
  s('SeamBold', { fg = '#c0caf5', bold = true })
  s('SeamText', { fg = '#a9b1d6' })
  s('SeamPath', { fg = '#737aa2' })
  s('SeamLabel', { fg = '#565f89' })
  s('SeamDim', { fg = '#414868' })
  s('SeamCodeDim', { fg = '#4a5274' })
  s('SeamLit', { bg = '#2b3a63' })
  s('SeamUse', { underline = true, sp = '#c0caf5' })
  s('SeamTab', { fg = '#c0caf5', bg = '#3b4261', bold = true })
  s('SeamTest', { fg = '#565f89', italic = true })
  s('SeamOwn', { fg = '#737aa2' })
  s('SeamGutter', { fg = '#4f5679' })
  s('SeamUnread', { fg = '#f7768e' })
  s('SeamMode', { fg = '#1a1b26', bg = '#7aa2f7', bold = true })
  s('SeamStatus', { fg = '#a9b1d6', bg = '#16161e' })
  s('SeamStatusDim', { fg = '#565f89', bg = '#16161e' })
  s('SeamSep', { fg = '#3b4261' })
  for i, h in ipairs(HUES) do
    s('SeamHue' .. i, { fg = h, bold = true })
    s('SeamBar' .. i, { fg = h })
  end
  s('SeamHueGrey', { fg = '#737aa2', bold = true })
  s('SeamBarGrey', { fg = '#414868' })
  s('SeamHueNeutral', { fg = '#c0caf5', bold = true })
  s('SeamBarNeutral', { fg = '#a9b1d6' })
end

---------------------------------------------------------------- data

local function pkg_of(m, path)
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

local function build_model(file)
  local t0 = hr()
  local fh = assert(io.open(file, 'r'))
  local s = fh:read '*a'
  fh:close()
  local d = vim.json.decode(s, { luanil = { object = true, array = true } })
  local m = {
    file = file,
    name = d.source or vim.fn.fnamemodify(file, ':t:r'),
    ms = d.ms or {},
    notes = d.notes or {},
    packages = d.packages or {},
    exports = d.exports or {},
    byid = {},
    bykey = {},
    contracts = {},
    pkgcache = {},
    ispkg = {},
  }
  m.pkgsorted = {}
  for _, p in ipairs(m.packages) do
    if p ~= '.' and p ~= '' then
      m.pkgsorted[#m.pkgsorted + 1] = p
      m.ispkg[p] = true
    end
  end
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
    e.pkg = pkg_of(m, e.path)
    local seen, nf = {}, 0
    for _, u in ipairs(e.uses) do
      if not seen[u.path] then
        seen[u.path] = true
        nf = nf + 1
      end
    end
    e.nusers, e.nrefs = nf, #e.uses
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
  m.load_ms = since(t0)
  return m
end

local function load_sources(only)
  for _, f in ipairs(vim.fn.glob(OUT .. '/*.json', false, true)) do
    local name = vim.fn.fnamemodify(f, ':t:r')
    if name == 'hues' or (only and name ~= only) then
      goto continue
    end
    local stat = vim.uv.fs_stat(f)
    local mt = stat and (stat.mtime.sec .. ':' .. stat.size) or ''
    if not st.models[name] or st.models[name].mtime ~= mt then
      local ok, m = pcall(build_model, f)
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

local function model()
  return st.models[st.cur]
end

local function assign_hues()
  if st.hues then
    return
  end
  local ok, saved = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(HUEFILE), '\n'))
  end)
  local order
  if ok and type(saved) == 'table' then
    order = saved
  else
    local m = model()
    local count = {}
    for _, e in ipairs(m.contracts) do
      count[e.pkg] = (count[e.pkg] or 0) + 1
    end
    order = {}
    for _, p in ipairs(m.packages) do
      if p ~= '.' then
        order[#order + 1] = p
      end
    end
    table.sort(order, function(a, b)
      if (count[a] or 0) ~= (count[b] or 0) then
        return (count[a] or 0) > (count[b] or 0)
      end
      return a < b
    end)
    pcall(vim.fn.writefile, { vim.json.encode(order) }, HUEFILE)
  end
  st.hues = {}
  for i, p in ipairs(order) do
    st.hues[p] = i <= 8 and { name = 'SeamHue' .. i, bar = 'SeamBar' .. i } or { name = 'SeamHueGrey', bar = 'SeamBarGrey' }
  end
end

local function hue(pkg)
  return st.hues[pkg] or { name = 'SeamHueGrey', bar = 'SeamBarGrey' }
end

local function is_test(path)
  return path:find '%.test%.' or path:find '%.spec%.' or path:find '/__tests__/' or path:find '/tests/' ~= nil
end

local function shape(c)
  if c.kind == 'function' then
    return c.name .. '()'
  elseif c.kind == 'component' then
    return '<' .. c.name .. '>'
  end
  return c.name
end

local function id_path(id)
  return id and id:match '^(.*):%d+:[^:]*$'
end
local function id_line(id)
  return id and tonumber(id:match ':(%d+):[^:]*$')
end

---------------------------------------------------------------- rows

local function W(s)
  if s:find '[\128-\255]' then
    return api.nvim_strwidth(s)
  end
  return #s
end

local Row = {}
Row.__index = Row
local function row(meta)
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
  self.w = self.w + W(s)
  return self
end
function Row:to(col)
  if self.w < col then
    self:add(string.rep(' ', col - self.w))
  end
  return self
end
function Row:text()
  return table.concat(self.t)
end

local function plural(n, word)
  return n .. ' ' .. word .. (n == 1 and '' or 's')
end

local function trunc(s, w)
  if w <= 1 then
    return ''
  end
  if W(s) <= w then
    return s
  end
  return vim.fn.strcharpart(s, 0, w - 1) .. '…'
end

--- append source line `lnum` of `path`, from its first non-blank when
--- `trim`, with its captures copied (lazily, when shown)
local function add_code(r, path, lnum, trim, maxw)
  local P = code.file(path)
  local src = P.lines[lnum] or ''
  local from = trim and #(src:match '^%s*') or 0
  local text = src:sub(from + 1)
  if maxw and #text > maxw then
    text = text:sub(1, maxw)
  end
  r.code = { path, lnum, from, r.b, #text }
  r:add(text)
  return r
end

local function scratch(name)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'hide'
  vim.bo[b].buftype = 'nofile'
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  vim.bo[b].tabstop = 2
  pcall(api.nvim_buf_set_name, b, 'seam://' .. name .. '/' .. b)
  return b
end

local function put(buf, rows)
  local lines = {}
  for i, r in ipairs(rows) do
    lines[i] = r:text()
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, code.ns, 0, -1)
  local codes = {}
  for i, r in ipairs(rows) do
    local row0 = i - 1
    for _, h in ipairs(r.h) do
      local e = math.min(h[2], #lines[i])
      if e > h[1] then
        api.nvim_buf_set_extmark(buf, ns, row0, h[1], { end_col = e, hl_group = h[3], priority = h[4] or 150 })
      end
    end
    if r.line_hl then
      api.nvim_buf_set_extmark(buf, ns, row0, 0, { line_hl_group = r.line_hl, priority = 90 })
    end
    if r.code then
      codes[row0] = r.code
      if r.dim then
        api.nvim_buf_set_extmark(buf, ns, row0, r.code[4], { end_col = r.code[4] + r.code[5], hl_group = 'SeamCodeDim', priority = 300 })
      end
    end
  end
  st.code[buf] = { rows = codes, painted = {} }
end

local function paint_win(win)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  local C = st.code[buf]
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
    local c = C.rows[r0]
    if c and not C.painted[r0] then
      local R = ranges[c[1]]
      if not R then
        ranges[c[1]] = { c[2], c[2] }
      else
        R[1], R[2] = math.min(R[1], c[2]), math.max(R[2], c[2])
      end
    end
  end
  for path, R in pairs(ranges) do
    code.warm(path, R[1], R[2])
  end
  for r0 = math.max(top - 1 - h, 0), bot - 1 + h do
    local c = C.rows[r0]
    if c and not C.painted[r0] then
      C.painted[r0] = true
      code.paint(buf, r0, c[1], c[2], c[3], c[4], c[5])
    end
  end
end

local function paint_all()
  if not st.tab or not api.nvim_tabpage_is_valid(st.tab) then
    return
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(st.tab)) do
    paint_win(w)
  end
end

---------------------------------------------------------------- trees

local function bar(r, pkg, dim)
  if pkg and pkg ~= '.' then
    r:add('▎', dim and 'SeamBarGrey' or hue(pkg).bar)
  else
    r:add ' '
  end
end

--- Paths to rows. entries: path -> payload.
--- o.file(r, path, payload, pkg): fill a file row after its name
--- o.after(rows, path, payload, depth, pkg): rows under a file
--- o.file_hl: the file name's colour; o.own: the contract's package
--- o.select: 'file' to make file rows selectable
local function tree(m, entries, o)
  local rootn = { dirs = {}, files = {}, path = '', touched = true }
  local function dir(parent, name)
    local n = parent.dirs[name]
    if not n then
      local p = parent.path == '' and name or (parent.path .. '/' .. name)
      n = { dirs = {}, files = {}, name = name, path = p, pkg = m.ispkg[p] and p or nil }
      parent.dirs[name] = n
    end
    return n
  end
  for path, payload in pairs(entries) do
    local n = rootn
    local parts = vim.split(path, '/', { plain = true })
    for i = 1, #parts - 1 do
      n = dir(n, parts[i])
      n.touched = true
    end
    n.files[parts[#parts]] = { path = path, payload = payload }
  end
  for _, p in ipairs(m.pkgsorted) do
    local n = rootn
    for _, seg in ipairs(vim.split(p, '/', { plain = true })) do
      n = dir(n, seg)
    end
  end
  local rows = {}
  local function emit(n, depth, pkg)
    local names = vim.tbl_keys(n.dirs)
    table.sort(names)
    for _, nm in ipairs(names) do
      local c = n.dirs[nm]
      local cpkg = c.pkg or pkg
      local own = o.own and cpkg == o.own
      local r = row { kind = 'dir', path = c.path }
      if c.touched then
        bar(r, cpkg, own and o.dimown)
      else
        r:add ' '
      end
      r:add(string.rep(' ', depth * 2))
      if not c.touched then
        r:add('▸ ' .. nm .. '/', 'SeamDim')
        rows[#rows + 1] = r
      else
        local cur, segs = c, { nm }
        while true do
          local ks = vim.tbl_keys(cur.dirs)
          if #ks == 1 and next(cur.files) == nil and not cur.dirs[ks[1]].pkg and cur.dirs[ks[1]].touched then
            cur = cur.dirs[ks[1]]
            segs[#segs + 1] = ks[1]
          else
            break
          end
        end
        local room = (o.width or 60) + (o.reserve or 0) + 8 - r.w
        local total = #table.concat(segs, '/') + 1
        if total > room and #segs > 1 then
          -- keep the head and the tail of a long chain
          while #segs > 2 and #table.concat(segs, '/') + 3 > room do
            table.remove(segs, 2)
            segs.cut = true
          end
          if segs.cut then
            table.insert(segs, 2, '…')
          end
        end
        for i, sg in ipairs(segs) do
          if i == 1 and c.pkg then
            r:add(sg, hue(c.pkg).name)
            r:add('/', 'SeamPath')
          else
            r:add(sg .. '/', 'SeamPath')
          end
        end
        if c.pkg and own then
          r:add('  its own folder', 'SeamLabel')
        end
        rows[#rows + 1] = r
        emit(cur, depth + 1, cpkg)
      end
    end
    local fnames = vim.tbl_keys(n.files)
    table.sort(fnames)
    for _, fname in ipairs(fnames) do
      local f = n.files[fname]
      local own = o.own and pkg == o.own
      local r = row { kind = 'file', path = f.path, payload = f.payload, select = o.select == 'file' }
      bar(r, pkg, own and o.dimown)
      r:add(string.rep(' ', depth * 2))
      local hl = is_test(f.path) and 'SeamTest' or (own and o.ownfile_hl) or o.file_hl or 'SeamName'
      r:add(trunc(fname, (o.width or 60) - r.w - (o.reserve or 0)), hl)
      if o.file then
        o.file(r, f.path, f.payload, pkg)
      end
      rows[#rows + 1] = r
      if o.after then
        o.after(rows, f.path, f.payload, depth + 1, pkg)
      end
    end
  end
  emit(rootn, 0, nil)
  return rows
end

---------------------------------------------------------------- layout

local function winopts(win, cursorline)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'
  wo.wrap = false
  wo.list = false
  wo.spell = false
  wo.cursorline = cursorline or false
  wo.winfixwidth = true
  wo.statuscolumn = ''
  wo.colorcolumn = ''
  wo.sidescrolloff = 0
  wo.fillchars = 'eob: ,vert:│,horiz: ,horizup:│,horizdown:│,vertleft:│,vertright:│,verthoriz:│'
  wo.winhighlight = 'WinSeparator:SeamSep'
  wo.statusline = '%!v:lua.SeamLabStatus()'
end

local function reset_tab()
  api.nvim_set_current_tabpage(st.tab)
  local wins = api.nvim_tabpage_list_wins(st.tab)
  local keep = wins[1]
  for _, w in ipairs(wins) do
    local pos = api.nvim_win_get_position(w)
    if pos[1] == 0 and pos[2] == 0 then
      keep = w
    end
  end
  api.nvim_set_current_win(keep)
  vim.cmd 'silent! only!'
  return keep
end

local function split(buf, win, dir, enter)
  return api.nvim_open_win(buf, enter or false, { split = dir, win = win })
end

---------------------------------------------------------------- status

local ORDERS = {
  { key = 'folder', label = 'by folder', short = 'by folder' },
  { key = 'used', label = 'most used first', short = 'most used' },
  { key = 'built', label = 'most built from first', short = 'most built from' },
  { key = 'name', label = 'by name', short = 'by name' },
}
local TABS = { built = 'built from', used = 'used by' }

function _G.SeamLabStatus()
  local left, right = '', ''
  local srcs = #st.names > 1 and ('S ' .. st.names[(vim.fn.index(st.names, st.cur) + 1) % #st.names + 1]) or ''
  if st.screen == 'page' and st.page then
    local p = st.page
    local pos = ''
    if p.count and p.count > 0 then
      pos = string.format('  %d of %d', p.index or 1, p.count)
    end
    left = shape(p.c) .. '  ' .. TABS[p.tab] .. pos
    local hints = {}
    local seam = p.tab == 'built' and 'dependency' or 'file'
    local panes = st.panes[p.tab]
    if p.tab == 'built' then
      hints[#hints + 1] = 'j/k next'
      if p.enter then
        hints[#hints + 1] = '<CR> enter ' .. p.enter
      end
    else
      hints[#hints + 1] = 'j/k next file'
      hints[#hints + 1] = ']] next use'
      hints[#hints + 1] = '<CR> open'
    end
    hints[#hints + 1] = panes == 'contract' and 'c both' or 'c contract'
    hints[#hints + 1] = panes == 'seam' and 's both' or ('s ' .. seam)
    hints[#hints + 1] = '<Tab> ' .. (p.tab == 'built' and 'used by' or 'built from')
    if #st.stack > 0 then
      hints[#hints + 1] = '<BS> ' .. shape(st.stack[#st.stack].c)
    end
    hints[#hints + 1] = (#st.stack > 0 and '- ' or '<BS> ') .. 'overview'
    right = table.concat(hints, '   ')
  else
    left = 'contracts  ' .. ORDERS[st.order].short
    local vw = st.view == 'diagram' and 'v trees   V map' or st.view == 'map' and 'v diagram   V trees' or 'v diagram   V map'
    local sd = st.sides == 'built' and 'b both   u used by' or st.sides == 'used' and 'b built from   u both' or 'b built from   u used by'
    right = '<Tab> ' .. ORDERS[st.order % #ORDERS + 1].short .. '   ' .. vw .. '   ' .. sd .. '   f lens   / search   <CR> open'
  end
  if srcs ~= '' then
    right = right .. '   ' .. srcs
  end
  return '%#SeamMode# NORMAL %#SeamStatus# ' .. left:gsub('%%', '%%%%') .. '%=' .. right:gsub('%%', '%%%%') .. ' '
end

---------------------------------------------------------------- explorer

local LW, MW = 46, 60
local USED_END, BUILT_END = 34, 45

local function source_label(r)
  local m = model()
  r:add(st.cur, 'SeamBold')
  r:add(string.format('  %s ms', tostring(m.ms.total or '?')), 'SeamLabel')
end

local function counts(r, c)
  local u, b = tostring(c.nusers), tostring(c.nbuilt)
  r:to(USED_END - #u)
  r:add(u, c.nusers == 0 and 'SeamLabel' or 'SeamText')
  r:to(BUILT_END - #b)
  r:add(b, 'SeamText')
end

local function contract_row(c, depth, flat)
  local r = row { kind = 'c', c = c }
  bar(r, c.pkg)
  r:add(string.rep(' ', flat and 1 or depth * 2))
  r:add(trunc(shape(c), USED_END - 5 - r.w), 'SeamName')
  counts(r, c)
  return r
end

local function draw_left_head()
  local m = model()
  local rows = {}
  local r = row()
  r:add('Contracts', 'SeamTitle'):add('  ' .. ORDERS[st.order].label, 'SeamText')
  rows[1] = r
  r = row()
  if st.filter ~= '' then
    r:add('/ ', 'SeamLabel'):add(st.filter, 'SeamBold'):add('  ' .. #st.crows .. ' found', 'SeamLabel')
  else
    r:add('/ search', 'SeamLabel')
  end
  local sum = lens.summary(st.lens)
  r:add('   f ', 'SeamLabel'):add(sum ~= '' and sum or 'lens', sum ~= '' and 'SeamText' or 'SeamLabel')
  rows[2] = r
  r = row()
  source_label(r)
  r:to(USED_END - 7)
  r:add('used by', ORDERS[st.order].key == 'used' and 'SeamTitle' or 'SeamLabel')
  r:add ' '
  r:add('built from', ORDERS[st.order].key == 'built' and 'SeamTitle' or 'SeamLabel')
  rows[3] = r
  put(st.buf.lhead, rows)
end

local function draw_list(keep)
  local t0 = hr()
  local m = model()
  local f = st.filter:lower()
  local list = {}
  for _, c in ipairs(m.contracts) do
    if f == '' or c.name:lower():find(f, 1, true) then
      list[#list + 1] = c
    end
  end
  local key = ORDERS[st.order].key
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
    rows = tree(m, entries, {
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
  put(st.buf.list, rows)
  draw_left_head()
  M.stats.list_ms = since(t0)
  M.stats.list_rows = #rows
  -- the cursor back on the contract it was on
  local want = keep or st.shown
  local target = st.crows[1] or 1
  if want then
    for _, i in ipairs(st.crows) do
      local c = st.rowc[i]
      if c == want or (c.path == want.path and c.name == want.name) then
        target = i
        break
      end
    end
  end
  if st.win.list and api.nvim_win_is_valid(st.win.list) then
    st.drawing = true
    api.nvim_win_set_cursor(st.win.list, { target, 0 })
    st.drawing = false
  end
  st.shown = nil
  M.on_move()
end

local function path_parts(r, c_path, line)
  local m = model()
  local pkg = pkg_of(m, c_path)
  if pkg ~= '.' then
    local prefix = pkg:match '^(.*/)' or ''
    r:add(prefix, 'SeamPath')
    r:add(pkg:match '[^/]+$', hue(pkg).name)
    r:add(c_path:sub(#pkg + 1) .. (line and (':' .. line) or ''), 'SeamPath')
  else
    r:add(c_path .. (line and (':' .. line) or ''), 'SeamPath')
  end
end

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

local function head_rows(c)
  local rows = {}
  local r = row()
  r:add(shape(c), 'SeamBold'):add('   ' .. c.kind .. ' in ', 'SeamLabel')
  path_parts(r, c.path, c.line)
  rows[1] = r
  r = row()
  if c.kind == 'function' or c.kind == 'component' or c.kind == 'const' then
    local P = code.file(c.path)
    local l = vim.trim(P.lines[c.line] or ''):gsub('^export%s+', '')
    r:add(trunc(l, 120), 'SeamText')
  end
  rows[2] = r
  rows[3] = compare(c) or row()
  return rows
end

local function deps_by_file(c)
  local m = model()
  local entries, unresolved, names = {}, {}, {}
  local nfiles = 0
  for _, d in ipairs(c.deps) do
    local p = id_path(d.target)
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
  local _ = m
  return entries, unresolved, nfiles, vim.tbl_count(names)
end

local function uses_by_file(c)
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

local function title(text, rest)
  return row():add(text, 'SeamSection'):add('   ' .. rest, 'SeamLabel')
end

local function draw_diagram(c)
  local t0 = hr()
  local w = st.win.diag and api.nvim_win_is_valid(st.win.diag) and api.nvim_win_get_width(st.win.diag) or 120
  local rows
  if st.view == 'map' then
    rows = diagram.map(c, w - 2, row)
  else
    rows = diagram.contract(c, w - 2, row, st.sides)
  end
  put(st.buf.diag, rows)
  local ms = since(t0)
  local dv = M.stats.diag
  dv[#dv + 1] = ms
  if #dv > 200 then
    table.remove(dv, 1)
  end
  M.stats.last_diag_ms = ms
  if st.win.diag and api.nvim_win_is_valid(st.win.diag) then
    api.nvim_win_set_cursor(st.win.diag, { 1, 0 })
  end
end

local function draw_trees(c)
  local m = model()
  put(st.buf.rhead, head_rows(c))
  if st.view ~= 'trees' then
    return draw_diagram(c)
  end
  -- built from
  local entries, unresolved, nfiles, nnames = deps_by_file(c)
  local rows = { title('built from', plural(nfiles, 'file') .. ' · ' .. plural(nnames, 'name')), row() }
  local NAMECOL = 30
  vim.list_extend(
    rows,
    tree(m, entries, {
      own = c.pkg,
      width = NAMECOL,
      reserve = 1,
      file = function(r, _, e)
        r:to(NAMECOL)
        local names = {}
        for _, d in ipairs(e.list) do
          names[#names + 1] = d.name
        end
        r:add(trunc(table.concat(names, '  '), MW - NAMECOL - 1), 'SeamName')
      end,
    })
  )
  if #unresolved > 0 then
    local names = {}
    for _, d in ipairs(unresolved) do
      names[#names + 1] = d.name
    end
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' not resolved  ', 'SeamLabel'):add(trunc(table.concat(names, '  '), MW - 17), 'SeamText')
  end
  if (c.hidden_dep_files or 0) > 0 then
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' ' .. plural(c.hidden_dep_files, 'file') .. ' hidden by the lens', 'SeamLabel')
  end
  put(st.buf.mid, rows)
  -- used by
  local uentries, nu = uses_by_file(c)
  local width = st.win.right and api.nvim_win_is_valid(st.win.right) and api.nvim_win_get_width(st.win.right) or 70
  local BARCOL = width - 12
  local max = 1
  for _, us in pairs(uentries) do
    max = math.max(max, #us)
  end
  rows = { title('used by', plural(nu, 'file') .. ' · ' .. plural(#c.uses, 'reference')), row() }
  vim.list_extend(
    rows,
    tree(m, uentries, {
      own = c.pkg,
      dimown = true,
      width = BARCOL,
      reserve = 1,
      file = function(r, path, us, pkg)
        r:to(BARCOL)
        local n = #us
        local w = math.max(1, math.min(6, math.ceil(6 * math.sqrt(n / max))))
        local own = pkg == c.pkg or is_test(path)
        r:add(string.rep('━', w), own and 'SeamBarGrey' or (pkg ~= '.' and hue(pkg).bar or 'SeamPath'))
        r:add(' ' .. n, 'SeamText')
      end,
    })
  )
  if (c.hidden_users or 0) > 0 then
    rows[#rows + 1] = row()
    rows[#rows + 1] = row():add(' ' .. plural(c.hidden_users, 'file') .. ' hidden by the lens', 'SeamLabel')
  end
  put(st.buf.right, rows)
  for _, w in ipairs { st.win.mid, st.win.right } do
    if w and api.nvim_win_is_valid(w) then
      api.nvim_win_set_cursor(w, { 1, 0 })
    end
  end
end

function M.on_move()
  if st.screen ~= 'explorer' or st.drawing then
    return
  end
  local t0 = hr()
  local r = api.nvim_win_get_cursor(st.win.list)[1]
  local c = st.rowc[r]
  if c and c ~= st.shown then
    st.shown = c
    draw_trees(c)
    local ms = since(t0)
    local mv = M.stats.move
    mv[#mv + 1] = ms
    if #mv > 200 then
      table.remove(mv, 1)
    end
    M.stats.last_move_ms = ms
  end
end

local function bisect_step(n)
  local cur = api.nvim_win_get_cursor(st.win.list)[1]
  local list = st.crows
  if #list == 0 then
    return
  end
  local idx
  if n > 0 then
    idx = #list
    for i, r in ipairs(list) do
      if r > cur then
        idx = math.min(#list, i + n - 1)
        break
      end
    end
  else
    idx = 1
    for i = #list, 1, -1 do
      if list[i] < cur then
        idx = math.max(1, i + n + 1)
        break
      end
    end
  end
  api.nvim_win_set_cursor(st.win.list, { list[idx], 0 })
end

local function layout_explorer()
  st.screen = 'explorer'
  local keep = reset_tab()
  local lh = keep
  api.nvim_win_set_buf(lh, st.buf.lhead)
  local rh = split(st.buf.rhead, lh, 'right')
  local list = split(st.buf.list, lh, 'below', true)
  if st.view ~= 'trees' then
    local dg = split(st.buf.diag, rh, 'below')
    api.nvim_win_set_width(lh, LW)
    api.nvim_win_set_height(lh, 3)
    api.nvim_win_set_height(rh, 3)
    for _, w in ipairs { lh, rh, dg } do
      winopts(w)
    end
    vim.wo[dg].winfixwidth = false
    winopts(list, true)
    vim.wo[lh].winfixheight = true
    vim.wo[rh].winfixheight = true
    st.win = { lhead = lh, rhead = rh, list = list, diag = dg }
    api.nvim_set_current_win(list)
    return
  end
  local mid, right
  if st.sides == 'built' then
    mid = split(st.buf.mid, rh, 'below')
  elseif st.sides == 'used' then
    right = split(st.buf.right, rh, 'below')
  else
    mid = split(st.buf.mid, rh, 'below')
    right = split(st.buf.right, mid, 'right')
  end
  api.nvim_win_set_width(lh, LW)
  api.nvim_win_set_height(lh, 3)
  api.nvim_win_set_height(rh, 3)
  if mid and right then
    api.nvim_win_set_width(mid, MW)
  end
  for _, w in ipairs { lh, rh, mid, right } do
    winopts(w)
  end
  winopts(list, true)
  vim.wo[lh].winfixheight = true
  vim.wo[rh].winfixheight = true
  st.win = { lhead = lh, rhead = rh, list = list, mid = mid, right = right }
  api.nvim_set_current_win(list)
end

---------------------------------------------------------------- page

local function decl_range(c)
  local s = code.doc_start(c.path, c.line)
  local e = c.end_line or c.line
  if e < c.line then
    e = c.line
  end
  return s, e
end

--- the declaration as code rows; opts.lit/dim/under per line
local function decl_rows(c, opts)
  opts = opts or {}
  local s, e = decl_range(c)
  local gw = math.max(3, #tostring(e))
  local rows = {}
  for l = s, e do
    local r = row { kind = 'code', lnum = l }
    r:add(string.format(' %' .. gw .. 'd  ', l), 'SeamGutter')
    add_code(r, c.path, l, false, opts.maxw)
    if opts.lit and opts.lit[l] then
      r.line_hl = 'SeamLit'
    elseif opts.dim and not (opts.keep and opts.keep[l]) and l ~= c.line and l ~= e then
      r.dim = true
    end
    if opts.beside then
      opts.beside(r, l)
    end
    rows[#rows + 1] = r
  end
  return rows, s, e
end

--- underline the name at a use's column, or the first match on the line
local function mark_name(r, text_start, src, name, col)
  local at
  if col then
    local a = col
    if src:sub(a, a + #name - 1) == name then
      at = a
    elseif src:sub(a + 1, a + #name) == name then
      at = a + 1
    end
  end
  if not at then
    at = src:find('%f[%w_$]' .. vim.pesc(name) .. '%f[^%w_$]')
  end
  if at then
    r.h[#r.h + 1] = { text_start + at - 1, text_start + at - 1 + #name, 'SeamUse', 320 }
  end
end

local function page_head(p)
  local c = p.c
  local rows = {}
  local r = row()
  r:add(' Contracts', 'SeamLabel')
  for _, prev in ipairs(st.stack) do
    r:add(' › ', 'SeamLabel'):add(shape(prev.c), 'SeamLabel')
  end
  r:add(' › ', 'SeamLabel'):add(shape(c), 'SeamBold'):add('   ' .. c.kind .. ' in ', 'SeamLabel')
  path_parts(r, c.path, c.line)
  local lab = row()
  source_label(lab)
  r:to(vim.o.columns - 2 - lab.w)
  source_label(r)
  rows[1] = r
  local entries_n = select(4, deps_by_file(c))
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
  return rows
end

local function first_row_of(rows, pred)
  for i, r in ipairs(rows) do
    if pred(r) then
      return i
    end
  end
end

local function scroll_to(win, lnum, top)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local n = api.nvim_buf_line_count(api.nvim_win_get_buf(win))
  lnum = math.max(1, math.min(lnum, n))
  api.nvim_win_call(win, function()
    vim.fn.winrestview { topline = math.max(1, top or lnum), lnum = lnum }
  end)
end

-- Built from tab --------------------------------------------------------

local function draw_built_tab(p)
  local c = p.c
  local m = model()
  local entries, unresolved, nfiles, nnames = deps_by_file(c)
  local rows = { row(), title('built from', plural(nfiles, 'file') .. ' · ' .. plural(nnames, 'name')), row() }
  vim.list_extend(
    rows,
    tree(m, entries, {
      own = c.pkg,
      width = 40,
      after = function(out, _, e, depth, pkg)
        for _, d in ipairs(e.list) do
          local r = row { kind = 'leaf', dep = d, select = true }
          bar(r, pkg)
          r:add(string.rep(' ', depth * 2))
          r:add(trunc(d.name, 38 - r.w), 'SeamName')
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
  p.sel_rows = {}
  for i, r in ipairs(rows) do
    if r.meta.select then
      p.sel_rows[#p.sel_rows + 1] = i
    end
  end
  p.rows = rows
  p.count = #p.sel_rows
  put(p.buf.list, rows)
end

local function draw_mid(p, lit, dim, unders, note)
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
          mark_name(r, r.code[4], src, name)
        end
      end
    end
  end
  vim.list_extend(rows, drows)
  put(p.buf.mid, rows)
  -- the first lit line in view
  local first
  for l in pairs(lit or {}) do
    first = first and math.min(first, l) or l
  end
  if first then
    local at = 3 + first - s + 1
    local h = api.nvim_win_is_valid(p.win.mid) and api.nvim_win_get_height(p.win.mid) or 40
    scroll_to(p.win.mid, at, at < h - 2 and 1 or math.max(1, at - math.floor(h / 2)))
  else
    scroll_to(p.win.mid, 1, 1)
  end
end

local function draw_dep(p, d)
  local m = model()
  local rows = { row() }
  local c = p.c
  p.enter = nil
  if not d then
    put(p.buf.right, rows)
    return
  end
  local lit = {}
  for l in pairs(d.lines) do
    lit[l] = true
  end
  draw_mid(p, lit, true, nil, 'uses ' .. d.name)
  if not d.target then
    rows[#rows + 1] = row():add(' ' .. d.name, 'SeamBold'):add('   ' .. st.cur .. ' could not resolve it', 'SeamLabel')
    put(p.buf.right, rows)
    return
  end
  local t = m.byid[d.target]
  local path, line = id_path(d.target), id_line(d.target)
  local r = row():add ' '
  local s, e
  if t then
    r:add(shape(t), 'SeamBold'):add('   ' .. t.kind .. ' in ', 'SeamLabel')
    s, e = decl_range(t)
    p.enter = t.nusers > 0 and shape(t) or nil
  else
    r:add(d.name, 'SeamBold'):add('   not an export, in ', 'SeamLabel')
    s, e = code.statement_at(path, line)
    s = code.doc_start(path, s)
  end
  path_parts(r, path, line)
  rows[#rows + 1] = r
  rows[#rows + 1] = row()
  local width = p.win.right and api.nvim_win_get_width(p.win.right) or 100
  if not p.win.mid then
    local ls = vim.tbl_keys(d.lines)
    table.sort(ls)
    for i, l in ipairs(ls) do
      local ar = row():add(i == 1 and (' ' .. shape(c) .. ' uses it as') or '', 'SeamLabel')
      ar:to(#shape(c) + 14):add(string.format('%4d  ', l), 'SeamGutter')
      add_code(ar, c.path, l, true, width - ar.w - 1)
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
    add_code(cr, path, l)
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
  put(p.buf.right, rows)
  scroll_to(p.win.right, 1, 1)
  -- a short dependency keeps the contract just under it
  if p.win.mid and p.win.right then
    local total = api.nvim_win_get_height(p.win.right) + api.nvim_win_get_height(p.win.mid)
    local cs, ce = decl_range(c)
    local need = math.min(ce - cs + 1 + 4, math.floor(total * 0.45))
    api.nvim_win_set_height(p.win.right, math.min(#rows + 1, total - need))
  end
end

-- Used by tab --------------------------------------------------------

local function draw_used_tab(p)
  local c = p.c
  local m = model()
  local entries, nfiles = uses_by_file(c)
  local rows = { row(), title('used by', plural(nfiles, 'file') .. ' · ' .. plural(#c.uses, 'reference')), row() }
  vim.list_extend(
    rows,
    tree(m, entries, {
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
  p.sel_rows = {}
  for i, r in ipairs(rows) do
    if r.meta.select then
      p.sel_rows[#p.sel_rows + 1] = i
    end
  end
  p.rows = rows
  p.count = #p.sel_rows
  put(p.buf.list, rows)
end

local function pick_rows(s, e, uselines)
  local set = {}
  if e - s + 1 <= 20 then
    for l = s, e do
      set[l] = true
    end
    return set
  end
  local ls = vim.tbl_keys(uselines)
  table.sort(ls)
  for radius = 4, 0, -1 do
    set = { [s] = true }
    local n = 1
    for _, ul in ipairs(ls) do
      for l = math.max(s, ul - radius), math.min(e, ul + radius) do
        if not set[l] then
          set[l] = true
          n = n + 1
        end
      end
    end
    if n <= 20 then
      return set
    end
  end
  set = { [s] = true }
  for i = 1, math.min(19, #ls) do
    set[ls[i]] = true
  end
  return set
end

local function draw_user(p, path)
  local c = p.c
  local m = model()
  local us = uses_by_file(c)[path] or {}
  local P = code.file(path)
  local rows = { row() }
  local r = row():add(' ' .. vim.fn.fnamemodify(path, ':t'), 'SeamBold'):add '   '
  local dir = vim.fn.fnamemodify(path, ':h') .. '/'
  path_parts(r, dir)
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
  draw_mid(p, nil, unders ~= nil, unders, 'used in ' .. vim.fn.fnamemodify(path, ':t'))
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
    for l in pairs(pick_rows(g.s, g.e, g.lines)) do
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
    add_code(cr, path, l)
    if is_lit then
      cr.line_hl = 'SeamLit'
      mark_name(cr, start, P.lines[l] or '', c.name, cols[l])
    end
    for _, mu in ipairs(memat[l] or {}) do
      mark_name(cr, start, P.lines[l] or '', mu[1], mu[2])
    end
    rows[#rows + 1] = cr
    return cr
  end
  local is, ie = code.import_of(path, c.name)
  if is and not show[is] then
    if ie - is > 3 then
      local _, _, nl = code.import_of(path, c.name)
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
  put(p.buf.right, rows)
  if p.win.right then
    vim.wo[p.win.right].cursorline = false
  end
  scroll_to(p.win.right, 1, 1)
  local _ = m
end

-- the page --------------------------------------------------------

local function page_selected(p)
  if not (p.win.list and api.nvim_win_is_valid(p.win.list)) then
    return
  end
  local cur = api.nvim_win_get_cursor(p.win.list)[1]
  local r = p.rows and p.rows[cur]
  if not r or not r.meta.select then
    return
  end
  for i, sr in ipairs(p.sel_rows) do
    if sr == cur then
      p.index = i
    end
  end
  local t0 = hr()
  if p.tab == 'built' then
    draw_dep(p, r.meta.dep)
  elseif r.meta.path then
    draw_user(p, r.meta.path)
  end
  p.sel[p.tab] = cur
  M.stats.seam_ms = since(t0)
  paint_all()
  vim.cmd 'redrawstatus'
end

local draw_page

local function page_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  local function other()
    st.page.tab = st.page.tab == 'built' and 'used' or 'built'
    draw_page()
  end
  vim.keymap.set('n', '<Tab>', other, o)
  vim.keymap.set('n', '<S-Tab>', other, o)
  for key, only in pairs { c = 'contract', s = 'seam' } do
    vim.keymap.set('n', key, function()
      local t = st.page.tab
      st.panes[t] = st.panes[t] == only and 'both' or only
      draw_page()
    end, o)
  end
  vim.keymap.set('n', '<BS>', M.back, o)
  vim.keymap.set('n', '-', M.overview, o)
  vim.keymap.set('n', 'f', M.open_lens, o)
  vim.keymap.set('n', 'q', M.close, o)
  vim.keymap.set('n', 'S', M.switch, o)
  vim.keymap.set('n', 'gd', function()
    M.goto_decl(st.page.c)
  end, o)
  vim.keymap.set('n', 'R', function()
    load_sources()
    draw_page()
  end, o)
end

local function step_rows(win, list, n)
  if not list or #list == 0 then
    return
  end
  local cur = api.nvim_win_get_cursor(win)[1]
  local idx
  if n > 0 then
    idx = #list
    for i, r in ipairs(list) do
      if r > cur then
        idx = math.min(#list, i + n - 1)
        break
      end
    end
  else
    idx = 1
    for i = #list, 1, -1 do
      if list[i] < cur then
        idx = math.max(1, i + n + 1)
        break
      end
    end
  end
  api.nvim_win_set_cursor(win, { list[idx], 0 })
end

draw_page = function()
  local p = st.page
  st.screen = 'page'
  local keep = reset_tab()
  local old = p.buf or {}
  p.buf = { head = scratch 'head' }
  api.nvim_win_set_buf(keep, p.buf.head)
  -- fresh buffers each time; the old ones wiped
  for _, b in pairs(old) do
    if api.nvim_buf_is_valid(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  put(p.buf.head, page_head(p))
  winopts(keep)
  vim.wo[keep].winfixheight = true
  p.win = { head = keep }
  p.buf.list, p.buf.mid, p.buf.right = scratch 'list', scratch 'contract', scratch 'seam'
  local list = split(p.buf.list, keep, 'below', true)
  api.nvim_win_set_height(keep, 3)
  -- the contract sits where the flow puts it: below what it is built
  -- from, above what uses it
  local panes = st.panes[p.tab]
  local right, mid
  if panes == 'contract' then
    mid = split(p.buf.mid, list, 'right')
  else
    right = split(p.buf.right, list, 'right')
    if panes == 'both' then
      mid = split(p.buf.mid, right, p.tab == 'built' and 'below' or 'above')
      local s, e = decl_range(p.c)
      local h = api.nvim_win_get_height(right) + api.nvim_win_get_height(mid)
      api.nvim_win_set_height(mid, math.min(e - s + 1 + 4, math.floor(h * 0.45)))
    end
  end
  api.nvim_win_set_width(list, 40)
  winopts(list, true)
  for _, w in pairs { right = right, mid = mid } do
    winopts(w)
  end
  if right and mid then
    local upper = p.tab == 'built' and right or mid
    vim.wo[upper].fillchars = vim.wo[upper].fillchars:gsub('horiz: ', 'horiz:─'):gsub('vertright:│', 'vertright:├')
  end
  p.win.list, p.win.mid, p.win.right = list, mid, right
  for _, b in ipairs { p.buf.list, p.buf.mid, p.buf.right } do
    page_keys(b)
  end
  local o = { buffer = p.buf.list, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function()
    step_rows(list, p.sel_rows, vim.v.count1)
  end, o)
  vim.keymap.set('n', 'k', function()
    step_rows(list, p.sel_rows, -vim.v.count1)
  end, o)
  vim.keymap.set('n', '<Down>', function()
    step_rows(list, p.sel_rows, 1)
  end, o)
  vim.keymap.set('n', '<Up>', function()
    step_rows(list, p.sel_rows, -1)
  end, o)
  vim.keymap.set('n', ']]', function()
    M.next_use(1)
  end, o)
  vim.keymap.set('n', '[[', function()
    M.next_use(-1)
  end, o)
  vim.keymap.set('n', '<CR>', M.page_enter, o)
  api.nvim_create_autocmd('CursorMoved', {
    group = aug,
    buffer = p.buf.list,
    callback = function(ev)
      if st.page and st.page.buf.list == ev.buf then
        page_selected(st.page)
      end
    end,
  })
  if p.tab == 'built' then
    draw_built_tab(p)
  else
    draw_used_tab(p)
  end
  local want = p.sel[p.tab] or p.sel_rows[1]
  if want then
    api.nvim_win_set_cursor(list, { want, 0 })
    page_selected(p)
  else
    draw_mid(p)
    put(p.buf.right, { row(), row():add(p.tab == 'built' and ' built from nothing in the repo' or ' no users', 'SeamLabel') })
  end
  paint_all()
  vim.cmd 'redrawstatus'
end

function M.next_use(n)
  local p = st.page
  if not p or p.tab ~= 'used' or not p.win.right or not p.lit_rows or #p.lit_rows == 0 then
    return
  end
  local w = p.win.right
  vim.wo[w].cursorline = true
  p.use_i = ((p.use_i or 0) + n - 1) % #p.lit_rows + 1
  local r = p.lit_rows[p.use_i]
  api.nvim_win_set_cursor(w, { r, 0 })
  api.nvim_win_call(w, function()
    vim.cmd 'normal! zz'
  end)
  paint_win(w)
end

function M.page_enter()
  local p = st.page
  local cur = api.nvim_win_get_cursor(p.win.list)[1]
  local r = p.rows[cur]
  if not r then
    return
  end
  if p.tab == 'built' and r.meta.dep and r.meta.dep.target then
    local t = model().byid[r.meta.dep.target]
    if t and t.nusers > 0 then
      M.open_page(t)
    end
  elseif r.meta.path then
    local us = uses_by_file(p.c)[r.meta.path]
    local u = us and us[p.use_i or 1] or (us and us[1])
    vim.cmd('tabnew +' .. (u and u.line or 1) .. ' ' .. vim.fn.fnameescape(st.root .. '/' .. r.meta.path))
  end
end

function M.open_page(c)
  if st.page then
    st.stack[#st.stack + 1] = st.page
  else
    st.explorer_at = st.shown
  end
  local tab = (st.sides == 'used' or #c.deps == 0) and c.nusers > 0 and 'used' or 'built'
  st.page = { c = c, tab = tab, sel = {} }
  draw_page()
end

function M.back()
  if #st.stack > 0 then
    st.page = table.remove(st.stack)
    draw_page()
  else
    st.page = nil
    layout_explorer()
    draw_list(st.explorer_at)
    paint_all()
  end
end

--- straight to the overview from any depth, on the contract you were reading
function M.overview()
  local c = st.page and st.page.c
  st.stack, st.page = {}, nil
  layout_explorer()
  draw_list(c or st.explorer_at)
  paint_all()
end

function M.goto_decl(c)
  if c then
    vim.cmd('tabnew +' .. c.line .. ' ' .. vim.fn.fnameescape(st.root .. '/' .. c.path))
  end
end

---------------------------------------------------------------- switch

function M.switch()
  load_sources()
  if #st.names < 2 then
    vim.notify('seam: only ' .. (st.cur or '?') .. ' is loaded', vim.log.levels.INFO)
    return
  end
  local i = vim.fn.index(st.names, st.cur)
  st.cur = st.names[(i + 1) % #st.names + 1]
  local m = model()
  if st.screen == 'page' and st.page then
    local function find(c)
      return m.byid[c.id] or m.bykey[c.path .. ':' .. c.name]
    end
    local nc = find(st.page.c)
    if not nc then
      vim.notify('seam: ' .. st.page.c.name .. ' is not an export in ' .. st.cur, vim.log.levels.WARN)
      st.stack, st.page = {}, nil
      layout_explorer()
      draw_list()
      return
    end
    for _, sp in ipairs(st.stack) do
      sp.c = find(sp.c) or sp.c
    end
    if st.explorer_at then
      st.explorer_at = find(st.explorer_at) or st.explorer_at
    end
    st.page.c = nc
    st.page.sel = {}
    draw_page()
  else
    local keep = st.shown
    draw_list(keep)
    paint_all()
  end
end

---------------------------------------------------------------- open

function M.search()
  local au = api.nvim_create_autocmd('CmdlineChanged', {
    group = aug,
    callback = function()
      st.filter = vim.fn.getcmdline()
      pcall(draw_list)
      vim.cmd 'redraw'
    end,
  })
  local before = st.filter
  local ok, q = pcall(vim.fn.input, { prompt = '/', default = before, cancelreturn = '\0' })
  api.nvim_del_autocmd(au)
  if not ok or q == '\0' then
    q = ''
  end
  st.filter = q
  draw_list()
end

local function explorer_keys(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function()
    bisect_step(vim.v.count1)
  end, o)
  vim.keymap.set('n', 'k', function()
    bisect_step(-vim.v.count1)
  end, o)
  vim.keymap.set('n', '<Down>', function()
    bisect_step(1)
  end, o)
  vim.keymap.set('n', '<Up>', function()
    bisect_step(-1)
  end, o)
  vim.keymap.set('n', '<Tab>', function()
    st.order = st.order % #ORDERS + 1
    draw_list()
    paint_all()
  end, o)
  vim.keymap.set('n', '<S-Tab>', function()
    st.order = (st.order - 2) % #ORDERS + 1
    draw_list()
    paint_all()
  end, o)
  vim.keymap.set('n', '/', M.search, o)
  vim.keymap.set('n', 'v', function()
    M.set_view(st.view == 'diagram' and 'trees' or 'diagram')
  end, o)
  vim.keymap.set('n', 'V', function()
    M.set_view(st.view == 'map' and 'trees' or 'map')
  end, o)
  -- b: built from alone, u: used by alone; again for both
  vim.keymap.set('n', 'b', function()
    st.sides = st.sides == 'built' and 'both' or 'built'
    M.set_view(st.view)
  end, o)
  vim.keymap.set('n', 'u', function()
    st.sides = st.sides == 'used' and 'both' or 'used'
    M.set_view(st.view)
  end, o)
  vim.keymap.set('n', '<CR>', function()
    if st.shown then
      M.open_page(st.shown)
    end
  end, o)
  vim.keymap.set('n', 'gd', function()
    M.goto_decl(st.shown)
  end, o)
  vim.keymap.set('n', 'S', M.switch, o)
  vim.keymap.set('n', 'f', M.open_lens, o)
  vim.keymap.set('n', 'q', M.close, o)
  vim.keymap.set('n', 'R', function()
    load_sources()
    draw_list()
  end, o)
end

--- put the list's cursor on a contract by name (and path fragment), for view steps
--- the lens changed: save it, filter every source, redraw what is shown. A
--- page redraws when the panel closes: drawing it closes every window.
function M.lens_changed()
  lens.save(st.lens, st.root)
  for _, m in pairs(st.models) do
    lens.apply(st.lens, m)
  end
  if st.screen == 'page' and st.page then
    if require('seam.lens_panel').is_open() then
      st.page_stale = true
    else
      draw_page()
    end
  elseif st.win and st.win.list and api.nvim_win_is_valid(st.win.list) then
    local keep = st.shown
    draw_list(keep)
    st.shown = nil
    M.on_move()
    paint_all()
  end
end

function M.open_lens()
  require('seam.lens_panel').open {
    lens = function()
      return st.lens
    end,
    model = model,
    changed = M.lens_changed,
    closed = function()
      if st.page_stale and st.screen == 'page' and st.page then
        st.page_stale = false
        draw_page()
      end
    end,
  }
end

function M.find(name, inpath)
  for i, c in pairs(st.rowc) do
    if c.name == name and (not inpath or c.path:find(inpath, 1, true)) then
      api.nvim_win_set_cursor(st.win.list, { i, 0 })
      api.nvim_win_call(st.win.list, function()
        vim.cmd 'normal! zz'
      end)
      M.on_move()
      return i
    end
  end
end

function M.set_view(v)
  st.view = v
  local cur = api.nvim_win_get_cursor(st.win.list)
  local top = api.nvim_win_call(st.win.list, function()
    return vim.fn.line 'w0'
  end)
  st.drawing = true
  layout_explorer()
  api.nvim_win_call(st.win.list, function()
    vim.fn.winrestview { topline = top, lnum = cur[1], col = cur[2] }
  end)
  st.drawing = false
  st.shown = nil
  M.on_move()
  paint_all()
  vim.cmd 'redrawstatus'
end

function M.close()
  if st.tab and api.nvim_tabpage_is_valid(st.tab) then
    if #api.nvim_list_tabpages() > 1 then
      api.nvim_set_current_tabpage(st.tab)
      vim.cmd 'tabclose'
    end
  end
  if st.laststatus then
    vim.o.laststatus = st.laststatus
    vim.o.showtabline = st.showtabline
  end
end

--- Index a repo with treesitter in a headless Neovim of its own, so the
--- editor stays free; `done` runs once the JSON is written.
function M.index(root, done)
  local out = data_dir(root)
  vim.fn.mkdir(out, 'p')
  local script = ROOT .. '/scripts/extract.lua'
  local t = hr()
  vim.notify('seam: indexing ' .. vim.fn.fnamemodify(root, ':~') .. ' with treesitter…')
  vim.system({ vim.v.progpath, '--headless', '--clean', '-l', script, root, out .. '/treesitter.json' }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify('seam: indexing failed\n' .. (res.stderr or ''), vim.log.levels.ERROR)
        return
      end
      local line = vim.trim((res.stderr or ''):match '[^\n]*$' or '')
      vim.notify(('seam: indexed in %.1f s. %s'):format(since(t) / 1000, line))
      if done then
        done()
      end
    end)
  end)
end

local function repo_root()
  local buf = vim.api.nvim_buf_get_name(0)
  return vim.fs.root(buf ~= '' and buf or vim.fn.getcwd(), { '.git', 'package.json' }) or vim.fn.getcwd()
end

--- Open seam on a repo (the current one by default), indexing it first when
--- it has no index yet or when asked to.
function M.start(root, opts)
  root = vim.fn.fnamemodify(root or repo_root(), ':p'):gsub('/$', '')
  opts = opts or {}
  if opts.reindex or not vim.uv.fs_stat(data_dir(root) .. '/treesitter.json') then
    if st.tab and api.nvim_tabpage_is_valid(st.tab) then
      M.close()
    end
    M.index(root, function()
      st.loaded_root = nil
      M.open(root)
    end)
  else
    M.open(root)
  end
end

function M.open(root)
  local t0 = hr()
  st.root = vim.fn.fnamemodify(root or repo_root(), ':p'):gsub('/$', '')
  OUT = data_dir(st.root)
  HUEFILE = OUT .. '/hues.json'
  st.lens = lens.load(st.root)
  if st.loaded_root ~= st.root then
    st.models, st.names, st.hues, st.cur, st.filter, st.order = {}, {}, nil, nil, '', 1
    st.loaded_root = st.root
  end
  code.root = st.root
  code.reset()
  highlights()
  diagram.setup { model = model, hue = hue, pkg_of = pkg_of, is_test = is_test, shape = shape, plural = plural }
  local tl = hr()
  -- the one shown first, now; the rest once the screen is up
  local first = st.cur or 'treesitter'
  if vim.uv.fs_stat(OUT .. '/' .. first .. '.json') then
    load_sources(first)
  else
    load_sources()
  end
  M.stats.load_ms = since(tl)
  if #st.names == 0 then
    vim.notify('seam: no JSON in ' .. OUT, vim.log.levels.ERROR)
    return
  end
  st.cur = st.cur and st.models[st.cur] and st.cur or (vim.tbl_contains(st.names, 'treesitter') and 'treesitter' or st.names[1])
  assign_hues()
  st.stack, st.page, st.shown = {}, nil, nil
  vim.cmd 'tabnew'
  st.tab = api.nvim_get_current_tabpage()
  local blank = api.nvim_get_current_buf()
  vim.bo[blank].bufhidden = 'wipe'
  st.buf = {
    lhead = scratch 'contracts-head',
    rhead = scratch 'head',
    list = scratch 'contracts',
    mid = scratch 'built-from',
    right = scratch 'used-by',
    diag = scratch 'diagram',
  }
  explorer_keys(st.buf.list)
  for _, b in ipairs { st.buf.lhead, st.buf.rhead, st.buf.mid, st.buf.right, st.buf.diag } do
    local o = { buffer = b, nowait = true, silent = true }
    vim.keymap.set('n', 'q', M.close, o)
    vim.keymap.set('n', 'S', M.switch, o)
  end
  api.nvim_create_autocmd('CursorMoved', { group = aug, buffer = st.buf.list, callback = M.on_move })
  api.nvim_create_autocmd('WinScrolled', {
    group = aug,
    callback = function()
      if api.nvim_get_current_tabpage() == st.tab then
        paint_all()
      end
    end,
  })
  api.nvim_create_autocmd('TabEnter', {
    group = aug,
    callback = function()
      if api.nvim_get_current_tabpage() == st.tab then
        st.laststatus = vim.o.laststatus
        st.showtabline = vim.o.showtabline
        vim.o.laststatus = 3
        vim.o.showtabline = 0
      end
    end,
  })
  api.nvim_create_autocmd('TabLeave', {
    group = aug,
    callback = function()
      if api.nvim_get_current_tabpage() == st.tab and st.laststatus then
        vim.o.laststatus = st.laststatus
        vim.o.showtabline = st.showtabline
      end
    end,
  })
  st.laststatus = vim.o.laststatus
  st.showtabline = vim.o.showtabline
  vim.o.laststatus = 3
  vim.o.showtabline = 0
  layout_explorer()
  draw_list()
  paint_all()
  M.stats.open_ms = since(t0)
  vim.defer_fn(function()
    local t1 = hr()
    load_sources()
    M.stats.load_rest_ms = since(t1)
    if st.screen == 'explorer' and st.shown then
      put(st.buf.rhead, head_rows(st.shown))
    end
    vim.cmd 'redrawstatus'
  end, 30)
end

--- a summary of how fast things were, for `=` steps
function M.timing()
  local mv = M.stats.move
  local sum, max = 0, 0
  for _, v in ipairs(mv) do
    sum = sum + v
    max = math.max(max, v)
  end
  return {
    open_ms = M.stats.open_ms and math.floor(M.stats.open_ms),
    load_json_ms = M.stats.load_ms and math.floor(M.stats.load_ms),
    load_other_sources_ms = M.stats.load_rest_ms and math.floor(M.stats.load_rest_ms),
    list_ms = M.stats.list_ms and math.floor(M.stats.list_ms * 10) / 10,
    list_rows = M.stats.list_rows,
    moves = #mv,
    move_avg_ms = #mv > 0 and math.floor(sum / #mv * 100) / 100 or nil,
    move_max_ms = math.floor(max * 100) / 100,
    diag_last_ms = M.stats.last_diag_ms and math.floor(M.stats.last_diag_ms * 100) / 100,
    diag_n = #M.stats.diag,
    diag_avg_ms = #M.stats.diag > 0 and math.floor(vim.iter(M.stats.diag):fold(0, function(a, b)
      return a + b
    end) / #M.stats.diag * 100) / 100 or nil,
    diag_max_ms = #M.stats.diag > 0 and math.floor(math.max(unpack(M.stats.diag)) * 100) / 100 or nil,
    seam_ms = M.stats.seam_ms and math.floor(M.stats.seam_ms * 10) / 10,
    parses = code.stats.parses,
    parse_ms = math.floor(code.stats.parse_ms),
    capture_ms = math.floor(code.stats.cap_ms),
    sources = st.names,
    showing = st.cur,
  }
end

return M
