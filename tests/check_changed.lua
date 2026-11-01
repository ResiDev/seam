-- What changed, driven through its keys, from tests/check.lua: a throwaway
-- git directory in /tmp whose last commit is the repo's with one file
-- edited (a function given a first parameter, a function added, one taken
-- out), git asked with it as the repo's own, so the range from HEAD to the
-- working tree undoes that edit: the file's function changed in its
-- signature, one gone and one new. Nothing is written in the repo.
-- The signs in the tree, gc, ]c [c, D's diff in Code and its displays and
-- in Types, ]c in the pane, a row the range left alone plain, Used by now
-- and at HEAD on gu, the lens's range, a range picked, ]c on the code
-- screen, its code and its types with the diff.
local api = vim.api
local changes = require 'seam.changes'
local outline = require 'seam.outline'
local screen = require 'seam.screen'
local tree_screen = require 'seam.screen_tree'
local views = require 'seam.views'

---@param t { key: fun(k: string), fail: fun(msg: string), where: fun(w: string), st: table, repo: string }
return function(t)
  local key, fail, st, repo = t.key, t.fail, t.st, t.repo
  local m = st.models[st.cur]
  local g = m.graph
  t.where 'changed setup'
  -- a file with two exported functions declared `function name(` and taking something
  local by = {}
  for _, n in pairs(g and g.nodes or {}) do
    local src = n.kind == 'function' and not n.test and require('seam.code').file(n.path).lines[n.line] or ''
    if src:find('function ' .. n.name .. '(', 1, true) and not src:find('function ' .. n.name .. '()', 1, true) then
      by[n.path] = by[n.path] or {}
      table.insert(by[n.path], n)
    end
  end
  local path, n1, n2
  for p, list in pairs(by) do
    if #list >= 2 and outline.files(m)[p] and (not path or p < path) then
      table.sort(list, function(a, b)
        return a.line < b.line
      end)
      path, n1, n2 = p, list[1], list[2]
    end
  end
  if not path then
    return fail 'no file with two functions to change'
  end
  local tmp = vim.fn.tempname() .. '-seam-git'
  local function git(args, stdin)
    local cmd = vim.list_extend({ 'git', '-c', 'user.name=seam', '-c', 'user.email=seam@localhost', '--git-dir=' .. tmp .. '/.git' }, args)
    local r = vim.system(cmd, { text = true, stdin = stdin, cwd = repo }):wait()
    return vim.trim(r.stdout or ''), r.code
  end
  -- a git directory of its own that reads the repo's objects, its HEAD the repo's
  local own = vim.trim(vim.system({ 'git', '-C', repo, 'rev-parse', '--absolute-git-dir' }, { text = true }):wait().stdout or '')
  local head = vim.trim(vim.system({ 'git', '-C', repo, 'rev-parse', 'HEAD' }, { text = true }):wait().stdout or '')
  if own == '' or head == '' or vim.system({ 'git', 'init', '--quiet', tmp }):wait().code ~= 0 then
    return fail 'the repo is not in git, or git init did not run'
  end
  vim.fn.writefile({ own .. '/objects' }, tmp .. '/.git/objects/info/alternates')
  if vim.uv.fs_stat(own .. '/shallow') then
    vim.uv.fs_copyfile(own .. '/shallow', tmp .. '/.git/shallow')
  end
  git { 'update-ref', 'HEAD', head }
  local lines = vim.deepcopy(require('seam.code').file(path).lines)
  lines[n1.line] = lines[n1.line]:gsub('function ' .. vim.pesc(n1.name) .. '%(', 'function ' .. n1.name:gsub('%%', '%%%%') .. '(seamWas: number, ', 1)
  -- n2 out of the commit, so the working tree has it new
  local s2, e2 = require('seam.code').doc_start(path, n2.line), n2.end_line or n2.line
  for l = e2, s2, -1 do
    table.remove(lines, l)
  end
  -- a function only the commit has, gone in the working tree
  vim.list_extend(lines, { '', 'export function seamCheckGone(a: number): number {', '  return a;', '}' })
  local blob = git({ 'hash-object', '-w', '--stdin' }, table.concat(lines, '\n') .. '\n')
  git { 'read-tree', 'HEAD' }
  git { 'update-index', '--add', '--cacheinfo', '100644,' .. blob .. ',' .. path }
  local tree = git { 'write-tree' }
  local commit = git({ 'commit-tree', tree, '-p', 'HEAD' }, 'seam check\n')
  local _, code = git { 'update-ref', 'HEAD', commit }
  if code ~= 0 or commit == '' then
    vim.fn.delete(tmp, 'rf')
    return fail 'could not make the throwaway commit'
  end
  changes.env = { GIT_DIR = tmp .. '/.git', GIT_WORK_TREE = repo }
  local function ask()
    screen.ask_changes()
    vim.wait(20000, function()
      return changes.get() ~= nil
    end, 20)
  end
  ask()

  t.where 'changed range'
  local C = changes.get()
  io.stdout:write(('changed: %s, %s() given a parameter, %s() new, seamCheckGone() gone\n'):format(path, n1.name, n2.name))
  if not C then
    fail 'git did not say what changed'
  elseif C.err then
    fail('git: ' .. C.err)
  elseif not (C.files[path] == 'changed' and #C.list == 1) then
    fail('the range is not the one file changed: ' .. vim.inspect(C.files, { newline = ' ', indent = '' }))
  else
    -- worked out ahead while nothing is pressed: the file's pieces all done
    local warm = require 'seam.warm'
    if warm.left() == 0 and not changes.file(C, path) then
      fail 'nothing was worked out ahead'
    end
    vim.wait(5000, function()
      return warm.left() == 0
    end, 20)
    if warm.left() > 0 then
      fail(('the changes were not worked out ahead while idle: %d pieces left'):format(warm.left()))
    end
    local f = changes.file(C, path)
    local function state(name)
      return f.by[name] and f.by[name].state
    end
    if state(n1.name) ~= 'signature' or state(n2.name) ~= 'new' or state 'seamCheckGone' ~= 'gone' then
      fail(
        ('the declarations: %s %s, %s %s, seamCheckGone %s'):format(
          n1.name,
          tostring(state(n1.name)),
          n2.name,
          tostring(state(n2.name)),
          tostring(state 'seamCheckGone')
        )
      )
    end
  end

  -- the signs: the file's folders and the file ~, its functions + ~ _, the gone one where it was
  t.where 'changed signs'
  screen.show(n1.id)
  api.nvim_set_current_win(st.owin.tree)
  local function row(pred)
    for i, r in ipairs(st.orows) do
      if pred(r) then
        return r, i
      end
    end
  end
  local fr = row(function(r)
    return r.kind == 'file' and r.path == path
  end)
  local r1 = row(function(r)
    return r.id == n1.id and r.depth == (fr and fr.depth + 1)
  end)
  local r2 = row(function(r)
    return r.id == n2.id and r.depth == (fr and fr.depth + 1)
  end)
  local rg, gi = row(function(r)
    return r.kind == 'gone' and r.name == 'seamCheckGone'
  end)
  if not (fr and fr.sign == '~') then
    fail 'the file is not ~'
  end
  if not (r1 and r1.sign == '~' and r2 and r2.sign == '+' and rg and rg.sign == '_') then
    fail(("the functions' signs: %s %s %s"):format(tostring(r1 and r1.sign), tostring(r2 and r2.sign), tostring(rg and rg.sign)))
  end
  for _, r in ipairs(st.orows) do
    if r.kind == 'dir' and path:sub(1, #outline.full(r.item) + 1) == outline.full(r.item) .. '/' and r.sign ~= '~' then
      fail('the folder ' .. r.path .. ' above it is not ~')
    end
  end
  if gi then
    local text = api.nvim_buf_get_lines(st.obuf.tree, gi - 1, gi, false)[1] or ''
    if text:sub(1, 1) ~= '_' or not text:find('seamCheckGone()', 1, true) then
      fail('the gone row reads ' .. text)
    end
  end
  local signed = 0
  for _, r in ipairs(st.orows) do
    signed = signed + (r.sign and 1 or 0)
  end

  -- gc: only the rows with a sign, then all again; ]c [c from row to row
  t.where 'changed gc'
  local all = #st.orows
  key 'gc'
  if #st.orows ~= signed then
    fail(('gc kept %d rows, not the %d that changed'):format(#st.orows, signed))
  end
  key 'gc'
  if #st.orows ~= all then
    fail 'gc again did not show every row'
  end
  t.where 'changed ]c'
  key '1G'
  key ']c'
  local at = tree_screen.at()
  if not (at and at.sign) then
    fail ']c did not go to a row that changed'
  end
  local first = at and at.key
  key ']c'
  key '[c'
  if (tree_screen.at() or {}).key ~= first then
    fail '[c did not come back'
  end

  -- D: the diff on; Code on the function its lines, removed then added, on <C-Tab> the whole file
  t.where 'changed D'
  local pane_ = require 'seam.pane'
  local draw = require 'seam.draw'
  screen.show(n1.id)
  api.nvim_set_current_win(st.owin.tree)
  st.view.at, st.view.aside = 'Code', nil
  tree_screen.redraw(true)
  if st.diff then
    fail 'the diff is on before D'
  end
  if not pane_.can_diff() then
    fail 'D is not hinted on a range with changes'
  end
  key 'D'
  local v, d = views.shown(tree_screen.at(), st.view)
  if not st.diff or not tree_screen.status():find('diff on', 1, true) then
    fail 'D did not turn the diff on, said in the status line'
  elseif not (v and v.name == 'Code' and d == 'changes only') then
    fail(('with the diff on the function shows %s %s, not Code changes only'):format(tostring(v and v.name), tostring(d)))
  else
    local pane = api.nvim_buf_get_lines(st.obuf.pane, 0, -1, false)
    local del, add
    for i, l in ipairs(pane) do
      local meta = draw.meta(st.obuf.pane, i)
      if l:find('seamWas: number', 1, true) and meta.change and not meta.lnum then
        del = i
      end
      if del and not add and meta.lnum == n1.line then
        add = i
      end
    end
    if not (del and add) then
      fail 'the removed line and the line now are not there'
    end
    local head = table.concat(api.nvim_buf_get_lines(st.obuf.phead, 0, -1, false), ' ')
    if not head:find('signature changed', 1, true) or not head:find('Map    changes only', 1, true) then
      fail('the head does not say the signature changed, or name the display: ' .. head)
    end
    -- ]c in the pane: the change
    api.nvim_set_current_win(st.owin.pane)
    key '1G'
    key ']c'
    if not draw.meta(st.obuf.pane, api.nvim_win_get_cursor(st.owin.pane)[1]).change then
      fail ']c in the pane is not on a change'
    end
    api.nvim_set_current_win(st.owin.tree)
    local short = api.nvim_buf_line_count(st.obuf.pane)
    key '<C-Tab>'
    if select(2, views.shown(tree_screen.at(), st.view)) ~= 'whole file' or api.nvim_buf_line_count(st.obuf.pane) < short then
      fail 'the whole file is not shown, or is shorter than the changes only'
    end
    key '<C-S-Tab>'
    -- Types with the diff: its line as it was, then as it is
    t.where 'changed D types'
    key '<Tab>'
    if (views.shown(tree_screen.at(), st.view) or {}).name ~= 'Types' then
      fail '<Tab> did not show Types'
    elseif m.sigs then
      local tl = api.nvim_buf_get_lines(st.obuf.pane, 0, -1, false)
      local was
      for i, l in ipairs(tl) do
        if not was and l:sub(1, 2) == '- ' and l:find(n1.name, 1, true) and draw.meta(st.obuf.pane, i).change then
          was = i
        end
      end
      if not was or (tl[was + 1] or ''):sub(1, 2) ~= '+ ' or not tl[was + 1]:find(n1.name, 1, true) then
        fail('Types with the diff does not have its line as it was over its line: ' .. tostring(tl[1]) .. ' / ' .. tostring(tl[2]))
      end
    end
    key '<S-Tab>'
  end
  -- a function in another file, which the range left alone: Code as it is
  t.where 'changed D plain'
  for id, n in pairs(g.nodes) do
    if n.kind == 'function' and n.path ~= path and outline.files(m)[n.path] and not n.test then
      screen.show(id)
      api.nvim_set_current_win(st.owin.tree)
      local x = tree_screen.at()
      if x and x.id == id then
        local v2 = views.shown(x, st.view)
        if not (v2 and v2.name == 'Code') or #views.displays(v2, x) ~= 1 or #pane_.stops 'change' > 0 then
          fail(n.name .. ', which did not change, does not show its code as it is with the diff on')
        end
        break
      end
    end
  end
  -- on the gone row, its lines removed
  if rg then
    screen.show(n1.id)
    local _, i = row(function(r)
      return r.kind == 'gone' and r.name == 'seamCheckGone'
    end)
    key(i .. 'G')
    local pane = api.nvim_buf_get_lines(st.obuf.pane, 0, -1, false)
    if not (pane[1] and pane[1]:find('seamCheckGone', 1, true)) then
      fail('the gone function does not show its lines: ' .. tostring(pane[1]))
    end
  end

  -- Used by on the function: now, then at HEAD
  t.where 'changed used by'
  screen.show(n1.id)
  api.nvim_set_current_win(st.owin.tree)
  key 'gu'
  local pane = table.concat(api.nvim_buf_get_lines(st.obuf.pane, 0, -1, false), '\n')
  if not (pane:find('\n now', 1, true) and pane:find('\n at HEAD', 1, true) and pane:find('was  (', 1, true)) then
    fail 'Used by does not say who uses it now and at HEAD'
  end
  key 'gu'
  if st.view.aside then
    fail 'gu again did not come back'
  end

  -- the code screen: ]c to the line that changed
  t.where 'changed code screen'
  screen.show(n1.id)
  api.nvim_set_current_win(st.owin.tree)
  key 'J'
  if st.screen == 'code' then
    key 'gg'
    key ']c'
    local meta = require('seam.draw').meta(st.cbuf.code, api.nvim_win_get_cursor(st.cwin.code)[1])
    if st.diff then
      -- with the diff: the removed line before the line now, ]c on it
      local i = api.nvim_win_get_cursor(st.cwin.code)[1]
      local text = api.nvim_buf_get_lines(st.cbuf.code, i - 1, i, false)[1] or ''
      if meta.lnum or not text:find('seamWas: number', 1, true) or require('seam.draw').meta(st.cbuf.code, i + 1).lnum ~= n1.line then
        fail(']c on the code screen with the diff is not on the removed line before ' .. n1.line .. ': ' .. text)
      end
      -- the lines removed are the function's own, as the pane's Code has them, not the file's laid inside it
      local C = changes.get()
      local items, ka, _, a0 = require('seam.views.changed').decl_items(C, path, n1.name, false)
      local want, got = {}, {}
      for _, it in ipairs(items or {}) do
        if it.kind == 'del' then
          want[#want + 1] = vim.trim(changes.lines(ka)[it.a + a0] or '')
        end
      end
      for r = 1, api.nvim_buf_line_count(st.cbuf.code) do
        local rm = require('seam.draw').meta(st.cbuf.code, r)
        if rm.at and not rm.lnum then
          got[#got + 1] = vim.trim(api.nvim_buf_get_lines(st.cbuf.code, r - 1, r, false)[1] or '')
        end
      end
      if not vim.deep_equal(got, want) then
        fail(('the code screen removed %d lines, the function its own %d'):format(#got, #want))
      end
      -- its types: the function's line as it was over it
      key '<S-Tab>'
      local tl = api.nvim_buf_get_lines(st.cbuf.code, 0, 2, false)
      if not ((tl[1] or ''):sub(1, 1) == '-' and (tl[1] or ''):find('seamWas', 1, true) and (tl[2] or ''):sub(1, 1) == '+') then
        fail('the types display with the diff does not start with the line as it was: ' .. tostring(tl[1]))
      end
      key '<S-Tab>'
      key 'D'
      if st.diff then
        fail 'D on the code screen did not turn the diff off'
      end
      key 'gg'
      key ']c'
      meta = require('seam.draw').meta(st.cbuf.code, api.nvim_win_get_cursor(st.cwin.code)[1])
    end
    if meta.lnum ~= n1.line then
      fail(']c on the code screen went to ' .. tostring(meta.lnum) .. ', not ' .. n1.line)
    end
    key 'K'
  else
    fail 'J did not open the code screen'
  end

  -- the lens: the range on its first row; a range picked, the head naming it, no signs
  t.where 'changed lens'
  api.nvim_set_current_win(st.owin.tree)
  key 'L'
  local lens = api.nvim_buf_get_lines(api.nvim_get_current_buf(), 0, 3, false)
  if not (lens[2] or ''):find('changes   from  HEAD   to  the working tree', 1, true) then
    fail('the lens does not start with the range: ' .. tostring(lens[2]))
  end
  local refs = require 'seam.refs'
  if (refs.list(repo)[1] or {}).id ~= 'HEAD' then
    fail 'the picker does not start with HEAD'
  end
  key 'q'
  -- from the repo's own commit, which the working tree is: nothing changed
  st.range = { from = head }
  ask()
  tree_screen.redraw(true)
  local hl = api.nvim_buf_get_lines(st.obuf.head, 0, 1, false)[1] or ''
  if not hl:find('changes ' .. head .. ' → now', 1, true) then
    fail('the head does not name the range: ' .. hl)
  end
  for _, r in ipairs(st.orows) do
    if r.sign then
      fail 'an empty range still has signs'
      break
    end
  end
  key 'L'
  key 'x'
  key 'q'
  if not changes.is_default(changes.range()) then
    fail 'x did not put the range back'
  end

  st.diff = nil
  changes.env = nil
  vim.fn.delete(tmp, 'rf')
  ask()
  tree_screen.redraw(true)
end
