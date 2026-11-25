local config_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.o.packlockfile = config_dir .. '/nvim-pack-lock.json'
vim.cmd.packadd('nvim.undotree')
vim.pack.add({
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'refresh-partial-accept-preview' },
	{ src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
}, { confirm = false })
dofile(config_dir .. '/lua/treesitter.lua')
