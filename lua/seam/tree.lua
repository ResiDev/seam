-- Paths to a tree: directories before files, a chain of lone directories
-- on one row, every package shown; and the package bar down the left.
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

---@class seam.TreeItem
---@field kind 'dir'|'file'
---@field path string
---@field depth integer
---@field pkg string|nil the package it is in
---@field ispkg? boolean a directory that is a package
---@field touched? boolean a directory with entries under it
---@field segs? string[] a directory's names, a chain of lone directories joined
---@field name? string a file's name
---@field payload? any a file's entry

--- The tree of `entries`, path -> payload, in the order it is drawn.
---@param m table the model
---@param entries table<string, any>
---@return seam.TreeItem[]
function M.walk(m, entries)
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
  local items = {}
  local function emit(n, depth, pkg)
    local names = vim.tbl_keys(n.dirs)
    table.sort(names)
    for _, nm in ipairs(names) do
      local c = n.dirs[nm]
      local cpkg = c.pkg or pkg
      local it = { kind = 'dir', path = c.path, depth = depth, pkg = cpkg, ispkg = c.pkg ~= nil, touched = c.touched, segs = { nm } }
      items[#items + 1] = it
      if c.touched then
        local cur = c
        while true do
          local ks = vim.tbl_keys(cur.dirs)
          if #ks == 1 and next(cur.files) == nil and not cur.dirs[ks[1]].pkg and cur.dirs[ks[1]].touched then
            cur = cur.dirs[ks[1]]
            it.segs[#it.segs + 1] = ks[1]
          else
            break
          end
        end
        emit(cur, depth + 1, cpkg)
      end
    end
    local fnames = vim.tbl_keys(n.files)
    table.sort(fnames)
    for _, fname in ipairs(fnames) do
      local f = n.files[fname]
      items[#items + 1] = { kind = 'file', path = f.path, depth = depth, pkg = pkg, name = fname, payload = f.payload }
    end
  end
  emit(rootn, 0, nil)
  return items
end

return M
