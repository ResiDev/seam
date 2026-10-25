-- The highlight groups, and each package's hue: assigned once, stored with the
-- repo's index, so a package keeps its colour between sessions.
local api = vim.api
local st = require 'seam.state'
local M = {}

local HUES = { '#7aa2f7', '#9ece6a', '#ff9e64', '#bb9af7', '#1abc9c', '#7dcfff', '#e0af68', '#f7768e' }
local GREY = { name = 'SeamHueGrey', bar = 'SeamBarGrey' }

function M.setup()
  local function s(n, o)
    api.nvim_set_hl(0, n, o)
  end
  s('SeamTitle', { fg = '#7aa2f7', bold = true })
  s('SeamSection', { fg = '#b4bdf0', bold = true })
  s('SeamName', { fg = '#c0caf5' })
  s('SeamBold', { fg = '#c0caf5', bold = true })
  s('SeamText', { fg = '#a9b1d6' })
  s('SeamPath', { fg = '#737aa2' })
  s('SeamLabel', { fg = '#565f89' })
  s('SeamDim', { fg = '#414868' })
  s('SeamCodeDim', { fg = '#4a5274' })
  s('SeamLit', { bg = '#2b3a63' })
  s('SeamUse', { underline = true, sp = '#c0caf5' })
  s('SeamTab', { fg = '#c0caf5', bg = '#3b4261', bold = true })
  s('SeamTest', { fg = '#565f89', italic = true })
  s('SeamOwn', { fg = '#737aa2' })
  s('SeamGutter', { fg = '#4f5679' })
  s('SeamUnread', { fg = '#f7768e' })
  s('SeamMode', { fg = '#1a1b26', bg = '#7aa2f7', bold = true })
  s('SeamStatus', { fg = '#a9b1d6', bg = '#16161e' })
  s('SeamStatusDim', { fg = '#565f89', bg = '#16161e' })
  s('SeamSep', { fg = '#3b4261' })
  for i, h in ipairs(HUES) do
    s('SeamHue' .. i, { fg = h, bold = true })
    s('SeamBar' .. i, { fg = h })
  end
  s('SeamHueGrey', { fg = '#737aa2', bold = true })
  s('SeamBarGrey', { fg = '#414868' })
  s('SeamHueNeutral', { fg = '#c0caf5', bold = true })
  s('SeamBarNeutral', { fg = '#a9b1d6' })
  -- the diagram is drawn by thread's renderer, whose setup has not run here
  s('ThreadDiagramBox', { fg = '#737aa2' })
  s('ThreadDiagramEdge', { fg = '#565f89' })
  s('ThreadDiagramNode', { fg = '#c0caf5' })
  s('ThreadDiagramText', { fg = '#a9b1d6' })
  s('ThreadDiagramLabel', { fg = '#737aa2', italic = true })
  s('ThreadDiagramHint', { fg = '#565f89' })
  s('ThreadDiagramHere', { fg = '#c0caf5', bold = true })
  s('ThreadBroken', { fg = '#f7768e' })
  s('SeamDiagDim', { fg = '#3b4261' })
  s('SeamDiagDimText', { fg = '#545c7e' })
  s('SeamEdgeLabel', { fg = '#9aa5ce', italic = true })
end

--- Give each package of `m` its hue, from `file` when it was stored there,
--- else most contracts first, then stored.
---@param m table
---@param file string
function M.assign(m, file)
  if st.hues then
    return
  end
  local ok, saved = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(file), '\n'))
  end)
  local order
  if ok and type(saved) == 'table' then
    order = saved
  else
    local count = {}
    for _, e in ipairs(m.contracts) do
      count[e.pkg] = (count[e.pkg] or 0) + 1
    end
    order = {}
    for _, p in ipairs(m.packages) do
      if p ~= '.' then
        order[#order + 1] = p
      end
    end
    table.sort(order, function(a, b)
      if (count[a] or 0) ~= (count[b] or 0) then
        return (count[a] or 0) > (count[b] or 0)
      end
      return a < b
    end)
    pcall(vim.fn.writefile, { vim.json.encode(order) }, file)
  end
  st.hues = {}
  for i, p in ipairs(order) do
    st.hues[p] = i <= #HUES and { name = 'SeamHue' .. i, bar = 'SeamBar' .. i } or GREY
  end
end

--- A package's groups: `name` for its name, `bar` for its bars.
---@param pkg string
---@return { name: string, bar: string }
function M.hue(pkg)
  return st.hues[pkg] or GREY
end

return M
