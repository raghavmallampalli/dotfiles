-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Escape inserts
map("i", "jk", "<Esc>")
map("i", "kj", "<Esc>")

-- Movement & Utility
map("n", "gm", "m")
map("n", "k", "gk")
map("n", "j", "gj")
map("n", "<C-t>", ":tabnew<CR>")
map("n", "<leader>nr", ":set relativenumber!<CR>")
map("n", "<esc>", ":noh<return><esc>", { silent = true })

-- Moving lines (Alt+j/k)
-- Note: LazyVim has built-in <A-j>/<A-k> for moving lines, but we replicate user's here to be safe/consistent
map("n", "<A-j>", ":m .+1<CR>==")
map("n", "<A-k>", ":m .-2<CR>==")
map("i", "<A-j>", "<Esc>:m .+1<CR>==gi")
map("i", "<A-k>", "<Esc>:m .-2<CR>==gi")
map("v", "<A-j>", ":m '>+1<CR>gv=gv")
map("v", "<A-k>", ":m '<-2<CR>gv=gv")

-- Twiddle Case (Visual Mode ~)
local function twiddle_case()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return end

  local function transform(str)
    if str == str:upper() then return str:lower()
    elseif str == str:lower() then return str:gsub("(%a)([%w_]*)", function(f, r) return f:upper() .. r:lower() end)
    else return str:upper() end
  end

  for i, line in ipairs(lines) do
    lines[i] = transform(line)
  end
  vim.api.nvim_buf_set_lines(0, start_pos[2] - 1, end_pos[2], false, lines)
end

map("v", "~", function() twiddle_case() vim.cmd("normal! gv") end, { silent = true, desc = "Twiddle Case" })

-- Diff helpers
map("n", "dT", ":diffthis<CR><C-w>w:diffthis<CR><C-w>w")
map("n", "dO", ":diffoff!<CR>")
