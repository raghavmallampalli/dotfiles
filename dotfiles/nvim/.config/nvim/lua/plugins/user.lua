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
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false,
    -- Removed the build property. Avante will now download the pre-built binary automatically.
    opts = {
      mode = "legacy",
      provider = "gemini-cli",
      auto_suggestions_provider = "gemini-cli",
      acp_providers = {
        ["gemini-cli"] = {
          command = "gemini",
          args = { "--experimental-acp" },
          env = {
            NODE_NO_WARNINGS = "1",
            HOME = os.getenv("HOME"), -- Ensures the subprocess finds ~/.gemini/
            -- Ensure these are NOT set to avoid the ADC error
            GEMINI_API_KEY = nil,
            GOOGLE_CLOUD_PROJECT = nil,
            GOOGLE_CLOUD_PROJECT_ID = nil,
            GOOGLE_APPLICATION_CREDENTIALS = nil,
          },
          auth_method = "oauth-personal",
        },
      },

      mappings = {
        submit = {
          normal = "<CR>",
          insert = "<CR>",
        },
      },
      instructions_file = "avante.md",
    },
    dependencies = {
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "hrsh7th/nvim-cmp",
      "nvim-tree/nvim-web-devicons",
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = { insert_mode = true },
            use_absolute_path = true,
          },
        },
      },
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = { file_types = { "markdown", "Avante" } },
        ft = { "markdown", "Avante" },
      },
    },
  },
  -- Import LazyVim extras (optional but recommended for your workflow)
}
