return {
  -- Theme
  { 
    "catppuccin/nvim", 
    name = "catppuccin", 
    opts = { flavour = "mocha", transparent_background = false } 
  },

  -- Logic to ensure Catppuccin loads
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },

  -- Essential logic from your old setup not in LazyVim core
  { "christoomey/vim-tmux-navigator" },
  { "junegunn/vim-peekaboo" },

  -- Import LazyVim extras (optional but recommended for your workflow)
}
