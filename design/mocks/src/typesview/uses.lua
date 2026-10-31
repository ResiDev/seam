-- throwaway: where names are used in files, with the line and the top-level
-- declaration around each use, from treesitter.
-- nvim --headless --clean -l uses.lua <src dir> <want.json {file: [names]}> <out.json>
local src, want, out = arg[1], arg[2], arg[3]
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/site')
want = vim.json.decode(table.concat(vim.fn.readfile(want), '\n'))
local IDS = { identifier = true, type_identifier = true, shorthand_property_identifier = true, property_identifier = false }
local res = {}
for file, names in pairs(want) do
  local set = {}
  for _, n in ipairs(names) do set[n] = true end
  local lines = vim.fn.readfile(src .. '/' .. file)
  local s = table.concat(lines, '\n')
  local root = vim.treesitter.get_string_parser(s, 'typescript'):parse()[1]:root()
  local function top_name(n)
    local p = n
    while p:parent() and p:parent():type() ~= 'program' do p = p:parent() end
    local d = p:type() == 'export_statement' and p:field('declaration')[1] or p
    if not d then return nil end
    local nm = d:field('name')[1]
    if not nm and d:type() == 'lexical_declaration' then
      for v in d:iter_children() do if v:type() == 'variable_declarator' then nm = v:field('name')[1] break end end
    end
    return nm and vim.treesitter.get_node_text(nm, s), d:type()
  end
  local function walk(n)
    if n:type() == 'import_statement' then return end
    if IDS[n:type()] then
      local t = vim.treesitter.get_node_text(n, s)
      if set[t] then
        local r = n:start()
        local name, kind = top_name(n)
        res[#res + 1] = { file = file, name = t, line = r + 1, text = vim.trim(lines[r + 1]), top = name, kind = kind }
      end
    end
    for c in n:iter_children() do walk(c) end
  end
  walk(root)
end
vim.fn.writefile({ vim.json.encode(res) }, out)
print(#res .. ' uses')
