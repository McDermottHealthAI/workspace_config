-- Set leader keys before anything else loads (lazy.nvim expects this)
vim.g.mapleader = "\\"
vim.g.maplocalleader = "\\"

-- Load general settings
require('settings')

-- Load key mappings
require('keymaps')

-- Load plugins (material.nvim applies the colorscheme in its own config)
require("config.lazy")
