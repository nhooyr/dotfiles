local plugins, update_parsers

vim.api.nvim_create_user_command('Plug', function()
	vim.pack.add(plugins, { confirm = false })
	vim.pack.update(nil, { force = true })
	update_parsers()
end, {})

plugins = {
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'refresh-partial-accept-preview' },
	{ src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
}

local config_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.o.packlockfile = config_dir .. '/pack-lock.json'
vim.cmd.packadd('nvim.undotree')
for _, plugin in ipairs(plugins) do
	vim.cmd('silent! packadd! ' .. vim.fs.basename(plugin.src):gsub('%.git$', ''))
end
update_parsers = dofile(config_dir .. '/lua/treesitter.lua')

if arg and arg[1] == 'install' then vim.cmd.Plug() end
