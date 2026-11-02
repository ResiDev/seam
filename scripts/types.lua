-- nvim --headless --clean -l types.lua <repo> <treesitter.json> <out.json>
-- What the TypeScript server says each callable of the call graph is: its
-- hover, one request a function, component or class, written as it came;
-- and for each class, the callables that make one with `new`.
-- The server is $SEAM_TS, else the first TypeScript 7 server found.
local repo, index, out = arg[1], arg[2], arg[3]
local T0 = vim.uv.hrtime()

local fh = assert(io.open(index, 'r'))
local nodes = vim.json.decode(fh:read '*a').nodes
fh:close()

local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
package.path = here .. '/lua/?.lua;' .. package.path
local cmd, why = require('seam.tsserver').command(repo)
if not cmd then
  io.stderr:write('types: ' .. why .. '\n')
  os.exit(1)
end

local id = vim.lsp.start({
  name = 'seam-types',
  cmd = cmd,
  root_dir = repo,
  init_options = { maximumHoverLength = 100000 },
  settings = { typescript = { unstable = { maximumHoverLength = 100000 } } },
}, { attach = false })
local client
vim.wait(30000, function()
  client = id and vim.lsp.get_client_by_id(id)
  return client and client.initialized
end, 20)
if not (client and client.initialized) then
  io.stderr:write('types: no TypeScript server started from ' .. table.concat(cmd, ' ') .. '\n')
  os.exit(1)
end

local byfile = {}
for _, n in ipairs(nodes) do
  if n.kind ~= 'module' then
    byfile[n.path] = byfile[n.path] or {}
    table.insert(byfile[n.path], n)
  end
end

local sigs, asked, answered = {}, 0, 0
for path, list in pairs(byfile) do
  local buf = vim.fn.bufadd(repo .. '/' .. path)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = path:match '%.tsx$' and 'typescriptreact' or 'typescript'
  vim.lsp.buf_attach_client(buf, id)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, n in ipairs(list) do
    local pat = '%f[%w_$]' .. vim.pesc(n.name) .. '%f[^%w_$]'
    for l = n.line, math.min(n.line + 3, #lines) do
      local c = lines[l]:find(pat)
      if c then
        asked = asked + 1
        local res = client:request_sync('textDocument/hover', {
          textDocument = { uri = vim.uri_from_bufnr(buf) },
          position = { line = l - 1, character = c - 1 },
        }, 20000, buf)
        local v = res and res.result and res.result.contents
        local s = type(v) == 'table' and (v.value or v[1] and (v[1].value or v[1])) or v
        if type(s) == 'string' and s ~= '' then
          sigs[n.id] = vim.trim((s:match '```%w*\n(.-)\n```' or s))
          answered = answered + 1
        end
        break
      end
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- which calls of a class are `new`: the source just before the call says so
local classes, lines_of, news = {}, {}, {}
for _, n in ipairs(nodes) do
  if n.kind == 'class' then
    classes[n.id] = true
  end
end
for _, n in ipairs(nodes) do
  for _, c in ipairs(n.calls or {}) do
    if classes[c[1]] then
      lines_of[n.path] = lines_of[n.path] or vim.fn.readfile(repo .. '/' .. n.path)
      local l = lines_of[n.path][c[2]] or ''
      if l:sub(1, c[3] - 1):match 'new%s+$' then
        news[c[1]] = news[c[1]] or {}
        if not vim.tbl_contains(news[c[1]], n.id) then
          table.insert(news[c[1]], n.id)
        end
      end
    end
  end
end

local server = client.server_info and (client.server_info.name .. ' ' .. (client.server_info.version or '')) or cmd[1]
client:stop(true)
local o = assert(io.open(out, 'w'))
o:write(vim.json.encode {
  version = 1,
  server = server,
  ms = math.floor((vim.uv.hrtime() - T0) / 1e6),
  sigs = sigs,
  news = news,
})
o:close()
io.stderr:write(('types: %d of %d callables answered by %s in %.1f s\n'):format(answered, asked, server, (vim.uv.hrtime() - T0) / 1e9))
vim.cmd 'qa!'
