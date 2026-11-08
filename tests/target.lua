-- Targets, the places a link from outside opens seam on: the strings read,
-- then checked against a real repo's index (SEAM_REPO, the lab's excalidraw
-- copy by default; those checks skipped when it has no index).
--   nvim -l tests/target.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local seam = require 'seam'
local target = require 'seam.target'
local index = require 'seam.index'
local st = require 'seam.state'

local failures, checks = {}, 0
local function fail(msg)
  failures[#failures + 1] = msg
  io.stdout:write('FAIL ' .. msg .. '\n')
end
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    fail(what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')')
  end
end
-- `why` says each of `parts`
local function says(why, parts, what)
  checks = checks + 1
  if type(why) ~= 'string' then
    return fail(what .. ': no why (got ' .. vim.inspect(why) .. ')')
  end
  for _, p in ipairs(parts) do
    if not why:find(p, 1, true) then
      return fail(what .. ': ' .. vim.inspect(why) .. ' does not say ' .. vim.inspect(p))
    end
  end
end

local function parse(s)
  local t, why = target.parse(s)
  return t or why
end

eq(parse 'src/store.ts:save@Map', { what = { kind = 'name', path = 'src/store.ts', name = 'save' }, view = 'Map' }, 'a function, its Map')
eq(parse 'src/store.ts:save@Types', { what = { kind = 'name', path = 'src/store.ts', name = 'save' }, view = 'Types' }, 'a function, its Types')
eq(parse 'src/store.ts:save:42@Code', { what = { kind = 'name', path = 'src/store.ts', name = 'save', line = 42 }, view = 'Code' }, 'a line breaks ties')
eq(parse 'type:Card@Types', { what = { kind = 'type', name = 'Card' }, view = 'Types' }, 'a type, its Types')
eq(parse 'type:Card@Map/type', { what = { kind = 'type', name = 'Card' }, view = 'Map', display = 'type' }, 'a type, its Map by type')
eq(parse 'src/billing@Map/folder', { what = { kind = 'path', path = 'src/billing' }, view = 'Map', display = 'folder' }, 'a folder, its Map by folder')
eq(parse 'src/billing/@Map/library', { what = { kind = 'path', path = 'src/billing' }, view = 'Map', display = 'library' }, 'a folder written with its slash')
eq(parse 'src/store.ts', { what = { kind = 'path', path = 'src/store.ts' } }, 'a file, its view as seam picks it')
eq(parse './src/store.ts:$save', { what = { kind = 'name', path = 'src/store.ts', name = '$save' } }, 'a ./ and a $ in a name')
eq(parse 'packages/@scope/pkg.ts:save', { what = { kind = 'name', path = 'packages/@scope/pkg.ts', name = 'save' } }, "an @ in a path is the path's")

says(parse '', { 'empty' }, 'nothing')
says(parse '@Map', { 'empty' }, 'a view of nothing')
says(parse 'src/store.ts@Mapp', { "no view 'Mapp'", 'Code, Types or Map' }, 'a view seam has not')
says(parse 'src/store.ts@map', { "no view 'map'" }, 'a view is written as its tab is')
says(parse 'src/store.ts@Map/libs', { "Map has no display 'libs'", 'folder, type or library' }, 'a display the Map has not')
says(parse 'src/store.ts@Types/folder', { "Types has no display 'folder'" }, 'a display of another view')
says(parse 'type:', { 'type:Card' }, 'a type with no name')
says(parse 'type:my card', { "'my card' is no type's name" }, "a type's name with a space")
says(parse '/src/store.ts', { 'relative to the repo root' }, 'an absolute path')
says(parse 'src/store.ts:save()', { "'save()' is no function's or contract's name", 'src/store.ts:name' }, 'a name with its call')
says(parse 'src/store.ts:', { 'does not read' }, 'a path and a colon')
says(parse 'src/store.ts:save:12:3', { 'does not read' }, 'a line and a column')

-- check, against a real index
local repo = vim.fn.fnamemodify(os.getenv 'SEAM_REPO' or (root .. '/lab/excalidraw'), ':p'):gsub('/$', '')
local m = index.peek(repo)
if not (m and m.version >= index.VERSION and m.flows) then
  io.stdout:write('skipped the checks on ' .. repo .. ': no index of it with types\n')
else
  -- a function, a file, a folder and a type the index has, found in it
  local fn, file
  for _, n in pairs(m.graph.nodes) do
    if n.kind ~= 'module' and not n.test and require('seam.outline').files(m)[n.path] and (not fn or n.id < fn.id) then
      fn = n
    end
  end
  file = fn.path
  local dir = vim.fs.dirname(file)
  local ty = vim.tbl_keys(m.flows)
  table.sort(ty)
  ty = ty[1]
  local function check(s)
    return seam.check(s, repo)
  end
  eq(check(file .. ':' .. fn.name), nil, 'a function')
  eq(check(file .. ':' .. fn.name .. ':' .. fn.line .. '@Map/library'), nil, 'a function at its line, its Map by library')
  eq(check(file .. ':' .. fn.name .. '@Code'), nil, 'a function, its Code')
  eq(check(file), nil, 'a file')
  eq(check(dir .. '@Map/folder'), nil, 'a folder, its Map by folder')
  eq(check(dir .. '/@Types'), nil, 'a folder written with its slash, its Types')
  eq(check('type:' .. ty .. '@Types'), nil, 'a type, its Types')
  eq(check('type:' .. ty .. '@Map/type'), nil, 'a type, its Map by type')
  says(check(repo .. '/' .. file), { 'relative to the repo root' }, 'an absolute path says so')

  local typo = fn.name:sub(1, -2)
  says(check(file .. ':' .. typo), { file .. ' has no function, value or contract named ' .. typo, 'it has ' .. fn.name }, 'a name misspelt: the nearest first')
  says(check(file:sub(1, -2)), { 'no file or folder ' .. file:sub(1, -2), 'nearest: ' .. file }, 'a path misspelt: the nearest first')
  says(check(dir .. ':' .. fn.name), { dir .. ' is a folder' }, 'a name after a folder')
  says(check(dir .. '@Code'), { 'a folder has no Code view', 'Types or Map' }, "a folder's Code")
  says(check('type:' .. ty .. '@Map/library'), { "a type's Map has no display 'library'", 'folder or type' }, "a type's library")
  says(check('type:' .. ty .. 'Zz'), { 'no type ' .. ty .. 'Zz', 'nearest: ' .. ty }, 'a type misspelt')
  says(check 'src/foo.test.ts', { 'is a test' }, 'a test file')
  says(check 'x@Mapp', { "no view 'Mapp'" }, 'a target that does not read')

  says(seam.check('src/a.ts', '/nowhere/at/all'), { 'seam has no index of /nowhere/at/all', ':Seam once' }, 'a repo with no index')
  local old = '/tmp/seam-target-spec-' .. vim.uv.os_getpid()
  vim.fn.mkdir(index.dir(old), 'p')
  vim.fn.writefile({ '{"version":3,"exports":[],"nodes":[]}' }, index.dir(old) .. '/treesitter.json')
  says(seam.check('src/a.ts', old), { 'older than it reads', ':Seam once' }, 'a repo indexed by an older seam')
  vim.fn.delete(index.dir(old), 'rf')

  eq({ st.root, next(st.models), st.view, st.tab }, {}, "checking leaves seam's state alone")
  local t = vim.uv.hrtime()
  for _ = 1, 20 do
    check(file .. ':' .. fn.name)
  end
  local ms = (vim.uv.hrtime() - t) / 1e6 / 20
  checks = checks + 1
  if ms > 20 then
    fail(('a check again takes %.1f ms: the model is read each time'):format(ms))
  end
end

io.stdout:write(('target: %d checks, %d failures\n'):format(checks, #failures))
os.exit(#failures == 0 and 0 or 1)
