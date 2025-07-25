vim.g.mapleader = "\\"

local map = vim.api.nvim_set_keymap
map('n', '<Leader>bn', ':bn<CR>', { noremap = true, silent = true })
map('n', '<Leader>bp', ':bp<CR>', { noremap = true, silent = true })
map('n', '<Leader>bd', ':bdelete<CR>', { noremap = true, silent = true })
map('i', 'jj', '<Esc>', { noremap = true })
map('n', '<F5>', ':let _s=@/<Bar>:%s/\\s\\+$//e<Bar>:let @/=_s<Bar><CR>', { noremap = true, silent = true })
