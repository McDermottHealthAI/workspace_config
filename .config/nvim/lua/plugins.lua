return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      bigfile = { enabled = true },
      dashboard = { enabled = true },
      explorer = { enabled = false },
      indent = { enabled = true },
      input = { enabled = true },
      picker = { enabled = false },
      notifier = { enabled = true },
      quickfile = { enabled = true },
      scope = { enabled = true },
      scroll = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
    },
  },
  {"lark-parser/vim-lark-syntax"},
  {"williamboman/mason.nvim"},
  {"nvim-tree/nvim-web-devicons"},
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = {"nvim-tree/nvim-web-devicons"},
    config = function()
      require("nvim-tree").setup({
        sort_by = "case_sensitive",
        renderer = { group_empty = true },
        filters = { dotfiles = true },
      })
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require('gitsigns').setup()
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require('lualine').setup()
    end,
  },
  {"jghauser/mkdir.nvim"},
  {
    -- Pin the `main` branch explicitly. Upstream switched its default branch
    -- from `master` to `main` as part of a ground-up rewrite; pinning keeps
    -- the spec stable against any future default-branch flips.
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install("all")
      -- The pre-migration config had `additional_vim_regex_highlighting = {'python'}`,
      -- which layered vim's regex syntax on top of treesitter for Python buffers.
      -- Dropped during the main-branch migration: treesitter's Python highlighting has
      -- matured substantially, and the replacement plumbing (re-enabling regex syntax
      -- after `vim.treesitter.start()`) wasn't verified on a live buffer. If a gap
      -- shows up, re-add via `vim.cmd('syntax enable')` inside the callback below.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if not pcall(vim.treesitter.start, args.buf) then return end
          vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo.foldmethod = "expr"
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
  {
    "marko-cerovac/material.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.material_style = "darker"
      vim.cmd.colorscheme("material")
    end,
  },
  {"github/copilot.vim"},
  {"lukas-reineke/indent-blankline.nvim"},
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = {"nvim-tree/nvim-web-devicons"},
    config = function()
      require("bufferline").setup{}
    end,
  },
  {
    "davidmh/mdx.nvim",
    config = true,
    dependencies = {"nvim-treesitter/nvim-treesitter"}
  }
}
