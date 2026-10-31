-- throwaway: each top-level declaration of every .ts file under a folder, with
-- its lines and text, for the Changed view mocks.
-- nvim --headless --clean -l decls.lua <src dir> <out.json>
local src, out = arg[1], arg[2]
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/site')
local files = vim.fs.find(function(n) return n:match('%.ts$') end, { path = src, type = 'file', limit = math.huge })
local res = {}
local KIND = { function_declaration = 'function', lexical_declaration = 'const', type_alias_declaration = 'type', interface_declaration = 'type' }
for _, path in ipairs(files) do
  local rel = path:sub(#src + 2)
  local s = table.concat(vim.fn.readfile(path), '\n')
  local root = vim.treesitter.get_string_parser(s, 'typescript'):parse()[1]:root()
  local f = { path = rel, decls = {} }
  for node in root:iter_children() do
    local exported = node:type() == 'export_statement'
    local d = exported and (node:field('declaration')[1]) or node
    if d and KIND[d:type()] then
      local name
      if d:type() == 'lexical_declaration' then
        local v = d:named_child(0)
        name = v and v:field('name')[1] and vim.treesitter.get_node_text(v:field('name')[1], s)
        local val = v and v:field('value')[1]
        if val and (val:type() == 'arrow_function' or val:type() == 'function_expression') then KIND_ = 'function' end
      else
        name = vim.treesitter.get_node_text(d:field('name')[1], s)
      end
      local sr, _, er = node:range()
      local kind = KIND[d:type()]
      if d:type() == 'lexical_declaration' then
        local v = d:named_child(0); local val = v and v:field('value')[1]
        if val and (val:type() == 'arrow_function' or val:type() == 'function_expression') then kind = 'function' end
      end
      if name then f.decls[#f.decls + 1] = { name = name, kind = kind, exported = exported, from = sr + 1, to = er + 1, text = vim.treesitter.get_node_text(node, s) } end
    end
  end
  res[#res + 1] = f
end
vim.fn.writefile({ vim.json.encode(res) }, out)
print(#res .. ' files')
