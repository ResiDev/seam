-- The call graph read through the lens: which paths each way of reading it
-- shows, and what a function calls or what calls it, one level on. Pure, so
-- the specs drive it on a graph written by hand.
local M = {}

---@class seam.Node
---@field id string 'path:line:name'; a file's top is 'path:0:'
---@field name string
---@field kind 'function'|'component'|'class'|'value'|'module'
---@field path string
---@field line integer
---@field end_line integer
---@field exported boolean
---@field test boolean

---@class seam.Graph
---@field nodes table<string, seam.Node>
---@field down table<string, { to: string, line: integer, col: integer }[]> what each calls, as written
---@field up table<string, { from: string, line: integer, col: integer }[]> who calls each, by path then line

---@alias seam.Dir 'down'|'up'

local function all()
  return true
end

--- The lens column each way of reading the graph follows: what a function
--- calls is what it is built from, what calls it is what uses it, and the
--- starts from the top are the contracts.
M.LENS = { down = 'built', up = 'used', top = 'contracts' }

--- Whether a path shows, read `way`, under the model's lens.
---@param m table|nil the model, its lens in m.visible
---@param way seam.Dir|'top'
---@return fun(path: string): boolean
function M.visible(m, way)
  local v, col = m and m.visible, M.LENS[way]
  return v and function(path)
    return v(path, col)
  end or all
end

--- A node's calls one level on: the distinct functions it calls, in the
--- order first written, or that call it, by path then line; tests apart,
--- going up, and those `visible` hides left out.
---@param g seam.Graph
---@param id string
---@param dir seam.Dir
---@param visible? fun(path: string): boolean
---@return { id: string, n: integer, lines: integer[], col: integer }[] kids, table[] tests
function M.kids(g, id, dir, visible)
  visible = visible or all
  local kids, tests, at = {}, {}, {}
  local edges, field = g.down[id] or {}, 'to'
  if dir == 'up' then
    edges, field = g.up[id] or {}, 'from'
  end
  for _, e in ipairs(edges) do
    local to = e[field]
    local node = g.nodes[to]
    if node and visible(node.path) then
      local k = at[to]
      if k then
        k.n = k.n + 1
        if k.lines[#k.lines] ~= e.line then
          k.lines[#k.lines + 1] = e.line
        end
      else
        k = { id = to, n = 1, lines = { e.line }, col = e.col }
        at[to] = k
        local list = (dir == 'up' and node.test) and tests or kids
        list[#list + 1] = k
      end
    end
  end
  return kids, tests
end

return M
