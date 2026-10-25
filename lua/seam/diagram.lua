-- The explorer's diagram views, drawn by thread.nvim's flow renderer (read
-- only, on the runtimepath) and recoloured here from its hits.
--   contract  deps grouped by folder -> the contract -> users grouped by folder
--   map       packages, provider -> user, the cursor's package lit
local draw = require 'seam.draw'
local index = require 'seam.index'
local theme = require 'seam.theme'
local M = {}

local THREAD = vim.fn.expand '~/.config/nvim/thread.nvim'
if not vim.tbl_contains(vim.opt.runtimepath:get(), THREAD) then
  vim.opt.runtimepath:append(THREAD)
end
local layout = require 'thread.ui.diagram'
local validate = require('thread.model.diagram').validate

local Row, plural = draw.row, draw.plural

---------------------------------------------------------------- groups

local function short(p)
  return (p:gsub('^packages/', ''))
end

--- the group a file falls in, seen from contract c: its package, or inside
--- c's own package the next folder down (past `src/`)
local function group_of(m, c, path)
  local pkg = index.pkg_of(m, path)
  if pkg == '.' then
    return '.', './', pkg
  end
  if pkg ~= c.pkg then
    return pkg, short(pkg) .. '/', pkg
  end
  local segs = vim.split(path:sub(#pkg + 2), '/', { plain = true })
  local i = (segs[1] == 'src' and #segs > 1) and 2 or 1
  local key
  if #segs > i then
    key = pkg .. '/' .. table.concat(segs, '/', 1, i)
  elseif i == 2 then
    key = pkg .. '/src'
  else
    key = pkg
  end
  return key, short(key) .. '/', pkg
end

local MAXBOX = 7

local function rank_groups(list)
  table.sort(list, function(a, b)
    if a.nfiles ~= b.nfiles then
      return a.nfiles > b.nfiles
    end
    if a.n ~= b.n then
      return a.n > b.n
    end
    return a.key < b.key
  end)
  if #list <= MAXBOX then
    return list
  end
  local out = {}
  for i = 1, MAXBOX - 1 do
    out[i] = list[i]
  end
  local rest = { key = '+rest', label = '+' .. (#list - MAXBOX + 1) .. ' folders', nfiles = 0, n = 0, rest = true, alltest = true }
  for i = MAXBOX, #list do
    rest.nfiles = rest.nfiles + list[i].nfiles
    rest.n = rest.n + list[i].n
    rest.alltest = rest.alltest and list[i].alltest
  end
  out[#out + 1] = rest
  return out
end

local function collect(m, c, items, path_of, count_key)
  local by, list = {}, {}
  for _, it in ipairs(items) do
    local path = path_of(it)
    if path then
      local key, label, pkg = group_of(m, c, path)
      local g = by[key]
      if not g then
        g = { key = key, label = label, pkg = pkg, files = {}, nfiles = 0, n = 0, names = {}, alltest = true }
        by[key] = g
        list[#list + 1] = g
      end
      if not g.files[path] then
        g.files[path] = true
        g.nfiles = g.nfiles + 1
        g.alltest = g.alltest and index.is_test(path)
      end
      local k = count_key(it)
      if k == true then
        g.n = g.n + 1
      elseif not g.names[k] then
        g.names[k] = true
        g.n = g.n + 1
      end
    end
  end
  return list
end

---------------------------------------------------------------- grid

local MASK = {
  ['│'] = 5,
  ['─'] = 10,
  ['╭'] = 6,
  ['╮'] = 12,
  ['╰'] = 3,
  ['╯'] = 9,
  ['├'] = 7,
  ['┤'] = 13,
  ['┬'] = 14,
  ['┴'] = 11,
  ['┼'] = 15,
  ['╎'] = 5,
  ['╌'] = 10,
  ['▶'] = 10,
}
local DELTA = { [1] = { -1, 0 }, [2] = { 0, 1 }, [4] = { 1, 0 }, [8] = { 0, -1 } }
local OPP = { [1] = 4, [2] = 8, [4] = 1, [8] = 2 }

local function to_grid(rows)
  local g = {}
  for r, chunks in ipairs(rows) do
    local line, col = {}, 0
    for _, ch in ipairs(chunks) do
      for _, x in ipairs(vim.fn.split(ch[1], '\\zs')) do
        line[col] = { ch = x, hl = ch[2] }
        col = col + 1
      end
    end
    line.n = col
    g[r - 1] = line
  end
  g.h = #rows
  return g
end

local function cell(g, r, c)
  return g[r] and g[r][c]
end

local function popcount(x)
  local n = 0
  while x > 0 do
    n = n + (x % 2)
    x = math.floor(x / 2)
  end
  return n
end

--- colour an edge from a port, walking dir, up to the first junction
local function walk(g, r, c, dir, hl)
  local guard = 0
  while guard < 2000 do
    guard = guard + 1
    r, c = r + DELTA[dir][1], c + DELTA[dir][2]
    local x = cell(g, r, c)
    if not x or (x.hl ~= 'ThreadDiagramEdge' and x.ch ~= '┼') then
      return
    end
    local mask = MASK[x.ch]
    if x.ch == '┼' then
      x.hl = hl
      mask = dir + OPP[dir]
    elseif not mask or popcount(mask) > 2 then
      return
    end
    x.hl = hl
    local rest = mask - (bit.band(mask, OPP[dir]) ~= 0 and OPP[dir] or 0)
    if rest == 0 or popcount(rest) ~= 1 then
      return
    end
    dir = rest
  end
end

--- recolour a box: border, then each label line
local function paint_box(g, h, border, lines)
  for r = h.row, h.row + h.height - 1 do
    for c = h.col, h.col + h.width - 1 do
      local x = cell(g, r, c)
      if x then
        local edge = r == h.row or r == h.row + h.height - 1 or c == h.col or c == h.col + h.width - 1
        if edge then
          if x.ch ~= '▶' then
            x.hl = border
          end
        elseif x.ch ~= ' ' then
          x.hl = lines[r - h.row] or lines.default or x.hl
        end
      end
    end
  end
end

--- every edge from the box's right-hand ports, and into its left side
local function paint_ports(g, h, out_hl, in_hl)
  local right, left = h.col + h.width - 1, h.col
  for r = h.row, h.row + h.height - 1 do
    local x = cell(g, r, right)
    if out_hl and x and x.ch == '├' then
      walk(g, r, right, 2, out_hl)
    end
    if in_hl then
      local a = cell(g, r, left - 1)
      if a and a.ch == '▶' then
        a.hl = in_hl
        walk(g, r, left - 1, 8, in_hl)
      elseif cell(g, r, left) and cell(g, r, left).ch == '▶' then
        cell(g, r, left).hl = in_hl
        walk(g, r, left, 8, in_hl)
      end
    end
  end
end

--- the grid as rows, offset by `pad` columns
local function grid_rows(g, pad)
  local out = {}
  for r = 0, g.h - 1 do
    local row = Row()
    row:add(string.rep(' ', pad))
    local line = g[r]
    local run, hl = {}, nil
    local function flush()
      if #run > 0 then
        row:add(table.concat(run), hl ~= 'Normal' and hl or nil)
      end
      run = {}
    end
    for c = 0, line.n - 1 do
      local x = line[c]
      if x.hl ~= hl then
        flush()
        hl = x.hl
      end
      run[#run + 1] = x.ch
    end
    flush()
    -- labels thread leaves muted: brighter here, beside the coloured edges
    out[#out + 1] = row
  end
  return out
end

local function brighten_labels(g)
  for r = 0, g.h - 1 do
    for c = 0, g[r].n - 1 do
      if g[r][c].hl == 'ThreadDiagramLabel' then
        g[r][c].hl = 'SeamEdgeLabel'
      end
    end
  end
end

local function render(raw, width)
  local d, err = validate(raw, function()
    return nil
  end)
  if not d then
    return nil, err
  end
  local drawn = layout.render(d, { max_width = width })
  return drawn
end

--- text as rows, wrapped at `width`, starting at column `pad`
local function para(rows, pad, text, hl, width)
  local line = ''
  local function flush()
    rows[#rows + 1] = Row():add(string.rep(' ', pad)):add(line, hl)
    line = ''
  end
  for word in text:gmatch '%S+' do
    if line ~= '' and vim.api.nvim_strwidth(line .. ' ' .. word) > width - pad then
      flush()
    end
    line = line == '' and word or (line .. ' ' .. word)
  end
  if line ~= '' then
    flush()
  end
end

---------------------------------------------------------------- contract

local function pad_label(lines, inner)
  local out = {}
  local top = math.max(0, math.floor((inner - #lines) / 2))
  for _ = 1, top do
    out[#out + 1] = ''
  end
  vim.list_extend(out, lines)
  while #out < inner do
    out[#out + 1] = ''
  end
  return table.concat(out, '\n'), top
end

local function and_list(names)
  if #names <= 1 then
    return names[1] or ''
  end
  return table.concat(names, ', ', 1, #names - 1) .. ' and ' .. names[#names]
end

local function summary(m, c, deps, users)
  local upk, dpk = {}, {}
  for _, u in ipairs(c.uses) do
    upk[index.pkg_of(m, u.path)] = true
  end
  for _, dp in ipairs(c.deps) do
    local p = dp.target and dp.target:match '^(.*):%d+:[^:]*$'
    if p then
      dpk[index.pkg_of(m, p)] = true
    end
  end
  local others = {}
  for p in pairs(upk) do
    if p ~= c.pkg then
      others[#others + 1] = p == '.' and 'the root' or short(p)
    end
  end
  table.sort(others)
  local who
  if #others == 0 then
    who = 'only its own package uses it'
  elseif #others <= 4 then
    local l = vim.list_extend({}, others)
    if upk[c.pkg] then
      l[#l + 1] = 'its own package'
    end
    who = and_list(l) .. ' use it'
  else
    who = plural(#others, 'other package') .. (upk[c.pkg] and ' and its own use it' or ' use it')
  end
  local nd = vim.tbl_count(dpk)
  local built
  if #c.deps == 0 then
    built = 'it is built from nothing in the repo'
  elseif nd == 1 and dpk[c.pkg] then
    built = 'it draws only on its own package'
  else
    built = 'it draws on ' .. plural(nd, 'package')
  end
  return string.format('%s; %s.', who, built),
    string.format('%s in %s; built from %s.', plural(#c.uses, 'use'), plural(c.nusers, 'file'), plural(c.nbuilt, 'name'))
end

--- rows for contract c's diagram, `width` columns
function M.contract(c, width, sides)
  local m = index.model()
  local deps = sides == 'used' and {}
    or rank_groups(collect(m, c, c.deps, function(dp)
      return dp.target and dp.target:match '^(.*):%d+:[^:]*$'
    end, function(dp)
      return dp.name
    end))
  local users = sides == 'built' and {} or rank_groups(collect(m, c, c.uses, function(u)
    return u.path
  end, function()
    return true
  end))
  local nodes, edges, info = {}, {}, {}
  local function group_hl(g)
    if g.alltest then
      return 'SeamDiagDim', 'SeamDiagDimText', 'SeamDiagDim'
    elseif g.rest or not g.pkg or g.pkg == '.' then
      return 'SeamBarGrey', 'SeamHueGrey', 'SeamBarGrey'
    end
    local hu = theme.hue(g.pkg)
    return hu.bar, hu.name, hu.bar
  end
  for i, g in ipairs(deps) do
    local id = 'd' .. i
    nodes[#nodes + 1] = { id = id, label = g.label .. '\n' .. plural(g.nfiles, 'file') .. ' · ' .. plural(g.n, 'name') }
    edges[#edges + 1] = { from = id, to = 'c' }
    info[id] = { g = g, side = 'dep' }
  end
  local inner = math.max(2, #deps, #users)
  local label, top = pad_label({ draw.shape(c), c.path }, inner)
  nodes[#nodes + 1] = { id = 'c', label = label }
  info.c = { top = top }
  for i, g in ipairs(users) do
    local id = 'u' .. i
    nodes[#nodes + 1] = { id = id, label = g.label .. '\n' .. plural(g.nfiles, 'file') .. ' · ' .. plural(g.n, 'use') }
    edges[#edges + 1] = { from = 'c', to = id }
    info[id] = { g = g, side = 'use' }
  end
  local drawn, err = render({ kind = 'flow', direction = 'right', nodes = nodes, edges = edges }, width)
  if not drawn then
    return { Row():add('  could not draw: ' .. tostring(err), 'SeamLabel') }
  end
  local g = to_grid(drawn.rows)
  brighten_labels(g)
  for _, h in ipairs(drawn.hits) do
    local inf = info[h.node.id]
    if h.node.id == 'c' then
      paint_box(g, h, 'SeamBold', { [inf.top + 1] = 'SeamBold', [inf.top + 2] = 'SeamPath' })
    else
      local border, name, edge = group_hl(inf.g)
      local second = inf.g.alltest and 'SeamDiagDim' or 'SeamLabel'
      paint_box(g, h, border, { [1] = name, [2] = second })
      if inf.side == 'dep' then
        paint_ports(g, h, edge, nil)
      else
        paint_ports(g, h, nil, edge)
      end
    end
  end
  local pad = math.max(1, math.floor((width - drawn.width) / 2))
  local rows = { Row(), Row() }
  local hdr = Row()
  -- column heads over each side, so the direction reads before the arrows
  local left_end, right_start
  for _, h in ipairs(drawn.hits) do
    if h.node.id:sub(1, 1) == 'd' then
      left_end = math.max(left_end or 0, h.col)
    elseif h.node.id:sub(1, 1) == 'u' then
      right_start = math.min(right_start or 1e9, h.col)
    end
  end
  hdr:add(string.rep(' ', pad))
  if left_end then
    hdr:add('built from', 'SeamSection')
  end
  if right_start then
    hdr:to(pad + right_start)
    hdr:add('used by', 'SeamSection')
  end
  rows[#rows + 1] = hdr
  vim.list_extend(rows, grid_rows(g, pad))
  rows[#rows + 1] = Row()
  local s1, s2 = summary(m, c, deps, users)
  para(rows, pad, s1, 'SeamText', width)
  para(rows, pad, s2, 'SeamLabel', width)
  if drawn.degraded then
    rows[#rows + 1] = Row():add(string.rep(' ', pad)):add('(' .. drawn.degraded .. ')', 'SeamLabel')
  end
  return rows
end

---------------------------------------------------------------- map

local map_cache = {}
local MIN_LINK = 10

local function map_data(m)
  if map_cache[m] then
    return map_cache[m]
  end
  local count, ncon, pk = {}, {}, {}
  for _, c in ipairs(m.contracts) do
    ncon[c.pkg] = (ncon[c.pkg] or 0) + 1
    pk[c.pkg] = true
    for _, u in ipairs(c.uses) do
      local a = index.pkg_of(m, u.path)
      if a ~= c.pkg then
        local k = c.pkg .. '\0' .. a
        count[k] = (count[k] or 0) + 1
        pk[a] = true
      end
    end
  end
  -- one arrow per pair, its stronger way; the weaker way and small links
  -- are said under the picture, as arrows both ways only tangle
  local list, back, small = {}, {}, {}
  for k, n in pairs(count) do
    local b, a = k:match '^(.-)%z(.*)$'
    local rev = count[a .. '\0' .. b] or 0
    if n > rev or (n == rev and b < a) then
      if n >= MIN_LINK then
        list[#list + 1] = { from = b, to = a, n = n, rev = rev }
        if rev > 0 then
          back[#back + 1] = { from = a, to = b, n = rev }
        end
      else
        small[#small + 1] = { from = b, to = a, n = n }
        if rev > 0 then
          small[#small + 1] = { from = a, to = b, n = rev }
        end
      end
    end
  end
  table.sort(list, function(x, y)
    return x.n > y.n
  end)
  pk = {}
  for _, e in ipairs(list) do
    pk[e.from], pk[e.to] = true, true
  end
  local pkgs = vim.tbl_keys(pk)
  table.sort(pkgs, function(a, b)
    if (ncon[a] or 0) ~= (ncon[b] or 0) then
      return (ncon[a] or 0) > (ncon[b] or 0)
    end
    return a < b
  end)
  map_cache[m] = { edges = list, pkgs = pkgs, ncon = ncon, back = back, small = small, count = count }
  return map_cache[m]
end

local function fmt_n(n)
  if n >= 1000 then
    return string.format('%.1fk', n / 1000)
  end
  return tostring(n)
end

function M.map(c, width)
  local m = index.model()
  local D = map_data(m)
  local deg = {}
  for _, e in ipairs(D.edges) do
    deg[e.from] = deg[e.from] or { i = 0, o = 0 }
    deg[e.to] = deg[e.to] or { i = 0, o = 0 }
    deg[e.from].o = deg[e.from].o + 1
    deg[e.to].i = deg[e.to].i + 1
  end
  local id_of, nodes, info = {}, {}, {}
  for i, p in ipairs(D.pkgs) do
    local id = 'p' .. i
    id_of[p] = id
    local dg = deg[p] or { i = 0, o = 0 }
    local inner = math.max(2, dg.i, dg.o)
    local name = p == '.' and './' or short(p)
    local lab, top = pad_label({ name }, inner)
    nodes[#nodes + 1] = { id = id, label = lab }
    info[id] = { pkg = p, top = top }
  end
  local edges = {}
  for _, e in ipairs(D.edges) do
    edges[#edges + 1] = { from = id_of[e.from], to = id_of[e.to], label = fmt_n(e.n) }
  end
  -- the picture is the same for every contract: laid out once a width
  D.drawn = D.drawn or {}
  local drawn, err = D.drawn[width], nil
  if not drawn then
    drawn, err = render({ kind = 'flow', direction = 'right', nodes = nodes, edges = edges }, width)
    D.drawn[width] = drawn
  end
  if not drawn then
    return { Row():add('  could not draw: ' .. tostring(err), 'SeamLabel') }
  end
  local g = to_grid(drawn.rows)
  local function inbox(rr, cc)
    for _, h in ipairs(drawn.hits) do
      if rr >= h.row and rr < h.row + h.height and cc >= h.col and cc < h.col + h.width then
        return true
      end
    end
  end
  local mine
  for _, h in ipairs(drawn.hits) do
    if info[h.node.id].pkg == c.pkg then
      mine = h
    end
  end
  local lit_hl, near = {}, {}
  for _, e in ipairs(D.edges) do
    if e.from == c.pkg then
      near[e.to] = true
    elseif e.to == c.pkg then
      near[e.from] = true
    end
  end
  if mine then
    local hu = theme.hue(c.pkg)
    lit_hl[hu.bar], lit_hl.SeamText = true, true
    -- its arrows: out to its users in its hue, in from its providers plain
    paint_ports(g, mine, hu.bar, 'SeamText')
    -- a label beside a lit edge is lit
    for r = 0, g.h - 1 do
      local col = 0
      while col < g[r].n do
        if g[r][col].hl == 'ThreadDiagramLabel' then
          local s, e = col, col
          while g[r][e + 1] and g[r][e + 1].hl == 'ThreadDiagramLabel' do
            e = e + 1
          end
          local lit = false
          for rr = r - 1, r + 1 do
            for cc = s - 1, e + 1 do
              local y = cell(g, rr, cc)
              if y and MASK[y.ch] and lit_hl[y.hl] and not inbox(rr, cc) then
                lit = true
              end
            end
          end
          if lit then
            for cc = s, e do
              g[r][cc].hl = 'SeamEdgeLabel'
            end
          end
          col = e + 1
        else
          col = col + 1
        end
      end
    end
  end
  for r = 0, g.h - 1 do
    for col = 0, g[r].n - 1 do
      local x = g[r][col]
      if x.hl == 'ThreadDiagramEdge' or x.hl == 'ThreadDiagramLabel' then
        x.hl = 'SeamDiagDim'
      end
    end
  end
  for _, h in ipairs(drawn.hits) do
    local inf = info[h.node.id]
    if h == mine then
      local hu = theme.hue(c.pkg)
      paint_box(g, h, hu.bar, { [inf.top + 1] = hu.name })
    elseif near[inf.pkg] then
      paint_box(g, h, 'SeamBarGrey', { [inf.top + 1] = 'SeamText' })
    else
      paint_box(g, h, 'SeamDiagDim', { [inf.top + 1] = 'SeamDiagDimText', [inf.top + 2] = 'SeamDiagDim' })
    end
  end
  local pad = math.max(1, math.floor((width - drawn.width) / 2))
  local rows = { Row(), Row() }
  vim.list_extend(rows, grid_rows(g, pad))
  rows[#rows + 1] = Row()
  local into, outof, rev = {}, {}, {}
  local function nm(p)
    return p == '.' and 'the root' or short(p)
  end
  for k, n in pairs(D.count) do
    local b, a = k:match '^(.-)%z(.*)$'
    if b == c.pkg then
      outof[#outof + 1] = { nm(a), n }
    elseif a == c.pkg then
      into[#into + 1] = { nm(b), n }
    end
  end
  local function fmt(l)
    table.sort(l, function(x, y)
      return x[2] > y[2]
    end)
    local o = {}
    for _, x in ipairs(l) do
      o[#o + 1] = x[1] .. ' ' .. fmt_n(x[2])
    end
    return #o > 0 and and_list(o) or 'none'
  end
  for _, e in ipairs(D.back) do
    if e.from == c.pkg or e.to == c.pkg then
      rev[#rev + 1] = nm(e.from) .. ' → ' .. nm(e.to) .. ' ' .. fmt_n(e.n)
    end
  end
  local name = nm(c.pkg)
  local line = string.format('%s: its contracts are used by %s', name, fmt(outof))
  rows[#rows + 1] = Row():add(string.rep(' ', pad)):add(name, theme.hue(c.pkg).name):add(line:sub(#name + 1), 'SeamText')
  para(rows, pad, string.format('it uses the contracts of %s', fmt(into)), 'SeamText', width)
  rows[#rows + 1] = Row()
  local notes = 'Arrows run from a package to those that use its contracts, labelled with uses. One arrow per pair, the stronger way'
  if #rev > 0 then
    notes = notes .. '; the other way here: ' .. table.concat(rev, ', ')
  end
  para(rows, pad, notes .. '.', 'SeamLabel', width)
  line = string.format('Links under %d uses not drawn: %d.', MIN_LINK, #D.small)
  rows[#rows + 1] = Row():add(string.rep(' ', pad)):add(line, 'SeamLabel')
  if drawn.degraded then
    rows[#rows + 1] = Row():add(string.rep(' ', pad)):add('(' .. drawn.degraded .. ')', 'SeamLabel')
  end
  return rows
end

return M
