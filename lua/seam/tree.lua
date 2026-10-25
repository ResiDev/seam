-- Paths to rows: directories before files, a chain of lone directories on one
-- row, every package shown, and the package bar down the left.
local draw = require 'seam.draw'
local index = require 'seam.index'
local theme = require 'seam.theme'
local M = {}

--- The package bar, or a space outside every package.
---@param r table
---@param pkg string|nil
---@param dim? boolean
function M.bar(r, pkg, dim)
  if pkg and pkg ~= '.' then
    r:add('▎', dim and 'SeamBarGrey' or theme.hue(pkg).bar)
  else
    r:add ' '
  end
end

---@class seam.TreeOpts
---@field file? fun(r: table, path: string, payload: any, pkg: string|nil) fill a file row after its name
---@field after? fun(rows: table[], path: string, payload: any, depth: integer, pkg: string|nil) rows under a file
---@field file_hl? string the file name's group
---@field own? string the contract's package
---@field dimown? boolean grey bars in the contract's own package
---@field select? 'file' file rows can be selected
---@field width? integer the columns a name may take
---@field reserve? integer columns kept free after a name

--- The rows of a tree of `entries`, path -> payload.
---@param m table the model
---@param entries table<string, any>
---@param o seam.TreeOpts
---@return table[]
function M.rows(m, entries, o)
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
      local r = draw.row { kind = 'dir', path = c.path }
      if c.touched then
        M.bar(r, cpkg, own and o.dimown)
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
            r:add(sg, theme.hue(c.pkg).name)
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
      local r = draw.row { kind = 'file', path = f.path, payload = f.payload, select = o.select == 'file' }
      M.bar(r, pkg, own and o.dimown)
      r:add(string.rep(' ', depth * 2))
      local hl = index.is_test(f.path) and 'SeamTest' or o.file_hl or 'SeamName'
      r:add(draw.trunc(fname, (o.width or 60) - r.w - (o.reserve or 0)), hl)
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

return M
