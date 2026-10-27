-- From your own code into seam: the word under the cursor, in a file of the
-- repo, to the contract or function it names. A model in, an answer out;
-- seam.here in init.lua opens what it says.
local M = {}

---@class seam.HereAnswer
---@field contract table|nil the contract it names
---@field node table|nil a function, component or class of the call graph
---@field candidates table[]|nil several by that name and none in this file
---@field nodes boolean|nil the candidates are functions, not contracts
---@field enclosing boolean|nil the word named nothing: the node is the one the cursor is in

local function holds(x, line)
  return line and x.line <= line and line <= (x.end_line or x.line)
end

local function by_id(a, b)
  return a.id < b.id
end

-- of several in one file, the one whose lines hold the cursor, else the first
local function nearest(list, line)
  table.sort(list, function(a, b)
    return a.line < b.line
  end)
  for _, x in ipairs(list) do
    if holds(x, line) then
      return x
    end
  end
  return list[1]
end

local function used_in(e, path)
  for _, u in ipairs(e.all_uses or e.uses or {}) do
    if u.path == path then
      return true
    end
  end
  return false
end

--- The contract `word` names from `path`: declared in this file, else the one
--- this file uses, else the only one of that name. Several and none of them
--- here or used here: nil and the several.
---@param m table the model
---@param word string
---@param path string|nil relative to the repo root
---@param line integer|nil the cursor's
---@return table|nil contract
---@return table[]|nil candidates
function M.contract(m, word, path, line)
  local named, mine, used = {}, {}, {}
  for _, e in ipairs(m.exports or {}) do
    if e.name == word and #(e.all_uses or e.uses or {}) > 0 then
      named[#named + 1] = e
      if e.path == path then
        mine[#mine + 1] = e
      elseif path and used_in(e, path) then
        used[#used + 1] = e
      end
    end
  end
  table.sort(named, by_id)
  table.sort(used, by_id)
  if #mine > 0 then
    return nearest(mine, line)
  elseif #used == 1 then
    return used[1]
  elseif #used > 1 then
    return nil, used
  elseif #named == 1 then
    return named[1]
  elseif #named > 1 then
    return nil, named
  end
end

--- The function, component or class `word` names from `path`, the same way:
--- declared in this file (the one holding the cursor if several), else the
--- one this file calls, else the only one of that name.
---@param g seam.Graph
---@param word string
---@param path string|nil
---@param line integer|nil
---@return table|nil node
---@return table[]|nil candidates
---@return boolean|nil here declared in this file
function M.node(g, word, path, line)
  local named, mine, called, seen = {}, {}, {}, {}
  for id, n in pairs(g.nodes) do
    if n.name == word and n.kind ~= 'module' then
      named[#named + 1] = n
      if n.path == path then
        mine[#mine + 1] = n
      end
    end
    if path and n.path == path then
      for _, e in ipairs(g.down[id] or {}) do
        local to = g.nodes[e.to]
        if to and to.name == word and to.path ~= path and not seen[e.to] then
          seen[e.to] = true
          called[#called + 1] = to
        end
      end
    end
  end
  table.sort(named, by_id)
  table.sort(called, by_id)
  if #mine > 0 then
    return nearest(mine, line), nil, true
  elseif #called == 1 then
    return called[1]
  elseif #called > 1 then
    return nil, called
  elseif #named == 1 then
    return named[1]
  elseif #named > 1 then
    return nil, named
  end
end

--- The function the cursor is in: the innermost node of the file holding it.
---@param g seam.Graph
---@param path string|nil
---@param line integer|nil
---@return table|nil
function M.enclosing(g, path, line)
  local best
  for _, n in pairs(g.nodes) do
    if n.path == path and n.kind ~= 'module' and holds(n, line) then
      if not best or (n.end_line - n.line) < (best.end_line - best.line) then
        best = n
      end
    end
  end
  return best
end

local CALLS = { calls = true, called_by = true }

--- What the word under the cursor names, for `how`: 'overview' and 'page'
--- look for a contract first, then a function; 'calls' and 'called_by' for a
--- function first, then a contract, then the function the cursor is in.
---@param m table the model
---@param word string
---@param path string|nil relative to the repo root
---@param line integer|nil
---@param how? 'overview'|'page'|'calls'|'called_by'
---@return seam.HereAnswer
function M.resolve(m, word, path, line, how)
  local g = m.graph
  word = vim.trim(word or '')
  if word:match '^[%a_$][%w_$]*$' then
    if CALLS[how] and g then
      local n, several = M.node(g, word, path, line)
      if n then
        return { node = n }
      end
      local c = M.contract(m, word, path, line)
      if c then
        return { contract = c }
      end
      if several then
        return { candidates = several, nodes = true }
      end
    else
      local c, several = M.contract(m, word, path, line)
      if c then
        return { contract = c }
      end
      local n, nodes, mine
      if g then
        n, nodes, mine = M.node(g, word, path, line)
      end
      if n and mine then
        return { node = n }
      elseif several then
        return { candidates = several }
      elseif n then
        return { node = n }
      elseif nodes then
        return { candidates = nodes, nodes = true }
      end
    end
  end
  if CALLS[how] and g then
    local n = M.enclosing(g, path, line)
    if n then
      return { node = n, enclosing = true }
    end
  end
  return {}
end

return M
