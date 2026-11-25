local config_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local treesitter = dofile(config_dir .. '/lua/treesitter.lua')
vim.o.packlockfile = config_dir .. '/nvim-pack-lock.json'
vim.cmd.packadd('nvim.undotree')
treesitter.setup()
vim.pack.add({
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'refresh-partial-accept-preview' },
	{ src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
}, { confirm = false })
treesitter.configure()
