vim.opt.termguicolors = true
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.ruler = true
vim.opt.scrolloff = 5
vim.opt.list = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.colorcolumn = '111'
vim.opt.textwidth = 111
vim.opt.swapfile = false
vim.opt.backup = true
vim.opt.backupdir = vim.fn.expand('~/.vimbackup')
vim.opt.writebackup = true
vim.opt.wrap = false
vim.opt.wildmenu = true
vim.opt.wildignore:append({'*.o','*.so','*.swp','*.zip','*.class','*.pyc'})
vim.opt.autowriteall = true
vim.opt.updatetime = 4000
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  command = "%s/\\s\\+$//e"
})
