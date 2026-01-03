return {
  -- Theme
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = { flavour = "mocha", transparent_background = false },
  },

  -- Logic to ensure Catppuccin loads
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },

  -- Essential logic from your old setup not in LazyVim core
  {
    "christoomey/vim-tmux-navigator",
    event = "VeryLazy",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
    },
  },

  -- snacks config
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            follow = true, -- Crucial for symlinked dotfiles
            ignored = true,
            hidden = true, -- Ensure hidden files show up
          },
          files = {
            hidden = true,
            ignored = true,
            follow = true,
          },
        },
      },
    },
  },

  -- Import LazyVim extras (optional but recommended for your workflow)
}
