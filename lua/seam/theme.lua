-- The highlight groups, and each package's hue: assigned once, stored with the
-- repo's index, so a package keeps its colour between sessions.
local api = vim.api
local st = require 'seam.state'
local M = {}

local HUES = { '#7aa2f7', '#9ece6a', '#ff9e64', '#bb9af7', '#1abc9c', '#7dcfff', '#e0af68', '#f7768e' }
local GREY = { name = 'SeamHueGrey', bar = 'SeamBarGrey', under = 'SeamUnderGrey' }

function M.setup()
  local function s(n, o)
    api.nvim_set_hl(0, n, o)
  end
  s('SeamTitle', { fg = '#7aa2f7', bold = true })
  s('SeamSection', { fg = '#b4bdf0', bold = true })
  s('SeamName', { fg = '#c0caf5' })
  s('SeamBold', { fg = '#c0caf5', bold = true })
  s('SeamText', { fg = '#a9b1d6' })
  s('SeamPunct', { fg = '#89ddff' })
  s('SeamPath', { fg = '#737aa2' })
  s('SeamLabel', { fg = '#565f89' })
  s('SeamDim', { fg = '#414868' })
  s('SeamLit', { bg = '#2b3a63' })
  s('SeamUse', { underline = true, sp = '#c0caf5' })
  s('SeamRef', { underline = true, sp = '#7aa2f7' })
  s('SeamTab', { fg = '#c0caf5', bg = '#3b4261', bold = true })
  -- the keys: lit, their word dim, a dim bar between groups; the status line's own on its background
  s('SeamKey', { fg = '#7aa2f7', bold = true })
  s('SeamKeyWord', { fg = '#737aa2' })
  s('SeamStatusKey', { fg = '#7aa2f7', bg = '#16161e', bold = true })
  s('SeamStatusKeyWord', { fg = '#737aa2', bg = '#16161e' })
  s('SeamStatusSep', { fg = '#3b4261', bg = '#16161e' })
  -- where a name lives: another file underlined in the text's colour, another package in its hue
  s('SeamUnder', { underline = true })
  s('SeamTest', { fg = '#565f89', italic = true })
  s('SeamOwn', { fg = '#737aa2' })
  s('SeamGutter', { fg = '#4f5679' })
  s('SeamUnread', { fg = '#f7768e' })
  s('SeamMode', { fg = '#1a1b26', bg = '#7aa2f7', bold = true })
  s('SeamStatus', { fg = '#a9b1d6', bg = '#16161e' })
  s('SeamStatusDim', { fg = '#565f89', bg = '#16161e' })
  s('SeamSep', { fg = '#3b4261' })
  -- the lens: what it hides in a muted red, apart from the pink package hue
  s('SeamLensHidden', { fg = '#c45c5c' })
  s('SeamStatusLens', { fg = '#c45c5c', bg = '#16161e' })
  -- a repo type in a signature, coloured as types are in code; lit where it is the one followed
  s('SeamType', { link = '@type' })
  local ty = api.nvim_get_hl(0, { name = '@type', link = false }).fg
  s('SeamTypeBold', { fg = ty, bold = true })
  s('SeamTypeLit', { fg = ty, bold = true, underline = true })
  for i, h in ipairs(HUES) do
    s('SeamHue' .. i, { fg = h, bold = true })
    s('SeamBar' .. i, { fg = h })
    s('SeamUnder' .. i, { underline = true, sp = h })
  end
  s('SeamHueGrey', { fg = '#737aa2', bold = true })
  s('SeamBarGrey', { fg = '#414868' })
  s('SeamUnderGrey', { underline = true, sp = '#737aa2' })
  s('SeamHueNeutral', { fg = '#c0caf5', bold = true })
  s('SeamBarNeutral', { fg = '#a9b1d6' })
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
    st.hues[p] = i <= #HUES and { name = 'SeamHue' .. i, bar = 'SeamBar' .. i, under = 'SeamUnder' .. i } or GREY
  end
end

--- A package's groups: `name` for its name, `bar` for its bars, `under`
--- for a name from it underlined.
---@param pkg string
---@return { name: string, bar: string, under: string }
function M.hue(pkg)
  return st.hues and st.hues[pkg] or GREY
end

return M
