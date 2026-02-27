-- ~/.config/nvim/colors/serenity.lua

vim.o.termguicolors = true
vim.g.colors_name = "serenity"

local colors = {
  panel = "NONE", -- Transparent
  fg = "#FFFFFF", -- Primary Text (Pure White)
  subtle_fg = "#BBBBBB", -- Secondary Text (Light Silver)
  dim_fg = "#888888", -- Tertiary/Comments (Medium Gray)

  -- Accents (Brightened for readability)
  blue = "#89B4FA",
  magenta = "#CBA6F7",
  green = "#A6E3A1",
  yellow = "#F9E2AF",
  cyan = "#94E2D5",
  red = "#F38BA8",
  border = "#444444",
}

local function set(g, o)
  vim.api.nvim_set_hl(0, g, o)
end

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") then
  vim.cmd("syntax reset")
end

-- Core UI (Using White/Silver)
set("Normal", { fg = colors.fg, bg = colors.panel })
set("NormalNC", { fg = colors.subtle_fg, bg = colors.panel })
set("SignColumn", { bg = colors.panel })
set("LineNr", { fg = colors.dim_fg, bg = colors.panel })
set("CursorLineNr", { fg = colors.yellow, bold = true })
set("NormalFloat", { fg = colors.fg, bg = colors.panel })
set("FloatBorder", { fg = colors.border, bg = colors.panel })

-- Syntax (Readable Bright Colors)
set("Comment", { fg = colors.dim_fg, italic = true })
set("String", { fg = colors.green })
set("Function", { fg = colors.blue, bold = true })
set("Keyword", { fg = colors.magenta, bold = true })
set("Statement", { fg = colors.magenta })
set("Type", { fg = colors.yellow })
set("Constant", { fg = colors.red })

-- Treesitter (Modern Highlights)
set("@variable", { fg = colors.fg })
set("@variable.builtin", { fg = colors.red, italic = true })
set("@property", { fg = colors.subtle_fg })
set("@parameter", { fg = colors.subtle_fg, italic = true })
set("@function", { link = "Function" })
set("@keyword", { link = "Keyword" })
