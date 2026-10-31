-- throwaway: written signatures of raf core, for the Types view mocks.
-- nvim --headless --clean -l extract.lua <src dir> <types.json> <out.json>
local src, tyjson, out = arg[1], arg[2], arg[3]
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/site')
local sigs = vim.json.decode(table.concat(vim.fn.readfile(tyjson), '\n')).sigs
local function T(n, s) return vim.treesitter.get_node_text(n, s) end
local function field(n, f) return n:field(f)[1] end
local files = vim.fs.find(function(name) return name:match('%.ts$') and not name:match('%.test%.ts$') and not name:match('%.perf%.ts$') end, { path = src, type = 'file', limit = math.huge })
local res = { files = {} }
local function flat(s) return (s:gsub('%s+', ' ')) end
local function params(n, s)
  local out = {}
  if not n then return out end
  for p in n:iter_children() do
    local t = p:type()
    if t == 'required_parameter' or t == 'optional_parameter' then
      local pat, ann = field(p, 'pattern'), field(p, 'type')
      out[#out + 1] = { name = pat and flat(T(pat, s)) or '?', type = ann and flat(T(ann, s):gsub('^:%s*', '')) or nil, optional = t == 'optional_parameter' or field(p, 'value') ~= nil }
    end
  end
  return out
end
for _, path in ipairs(files) do
  local rel = path:sub(#src + 2)
  local s = table.concat(vim.fn.readfile(path), '\n')
  local parser = vim.treesitter.get_string_parser(s, 'typescript')
  local root = parser:parse()[1]:root()
  local f = { path = rel, fns = {}, types = {}, imports = {} }
  local function sig_of(name)
    for k, v in pairs(sigs) do
      if k:find('src/' .. rel .. ':', 1, true) and k:match(':' .. name .. '$') then return v end
    end
  end
  local function add_fn(name, fnode, exported, line)
    local ret = field(fnode, 'return_type')
    local tp = field(fnode, 'type_parameters')
    f.fns[#f.fns + 1] = { name = name, line = line, exported = exported,
      params = params(field(fnode, 'parameters'), s),
      ret = ret and flat(T(ret, s):gsub('^:%s*', '')) or nil,
      tparams = tp and flat(T(tp, s)) or nil, hover = (not ret) and sig_of(name) or nil }
  end
  for c in root:iter_children() do
    local exported = c:type() == 'export_statement'
    local d = exported and field(c, 'declaration') or c
    if c:type() == 'import_statement' then
      local from = field(c, 'source')
      local names = {}
      for id in c:iter_children() do
        if id:type() == 'import_clause' then
          for x in vim.gsplit(T(id, s), '[^%w_]+') do if x ~= '' and x ~= 'type' and x ~= 'as' then names[#names + 1] = x end end
        end
      end
      f.imports[#f.imports + 1] = { from = T(from, s):sub(2, -2), names = names }
    end
    if d then
      local t = d:type()
      if t == 'function_declaration' then
        add_fn(T(field(d, 'name'), s), d, exported, d:start() + 1)
      elseif t == 'lexical_declaration' then
        for v in d:iter_children() do
          if v:type() == 'variable_declarator' then
            local val = field(v, 'value')
            if val and (val:type() == 'arrow_function' or val:type() == 'function_expression') then
              add_fn(T(field(v, 'name'), s), val, exported, v:start() + 1)
            end
          end
        end
      elseif t == 'type_alias_declaration' or t == 'interface_declaration' then
        local a = c:start()
        -- doc comment just above
        local prev = c:prev_sibling()
        local doc = (prev and prev:type() == 'comment' and prev:end_() == a - 0) and T(prev, s) or nil
        if prev and prev:type() == 'comment' and prev:end_() >= a - 1 then doc = T(prev, s) end
        f.types[#f.types + 1] = { name = T(field(d, 'name'), s), line = a + 1, exported = exported, text = T(c, s), doc = doc }
      end
    end
  end
  res.files[#res.files + 1] = f
end
vim.fn.writefile({ vim.json.encode(res) }, out)
print(#res.files .. ' files')
