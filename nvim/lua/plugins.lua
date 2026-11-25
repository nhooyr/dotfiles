local plugins, update_parsers, load_copilot

vim.api.nvim_create_user_command('Plug', function()
	vim.pack.add(plugins, { confirm = false })
	vim.pack.update(nil, { force = true })
	vim.loader.reset()
	update_parsers()
end, {})

local copilot_group = vim.api.nvim_create_augroup('aqsnow_copilot', { clear = true })
if not vim.g.loaded_copilot then
	vim.api.nvim_create_autocmd('InsertEnter', {
		group = copilot_group,
		callback = function()
			load_copilot()
			vim.fn['copilot#util#Defer']('copilot#OnInsertEnter')
		end,
	})
	vim.api.nvim_create_autocmd('CmdUndefined', {
		group = copilot_group,
		pattern = 'Copilot',
		callback = function() load_copilot() end,
	})
end

if vim.fn.exists(':Undotree') == 0 then
	vim.api.nvim_create_user_command('Undotree', function()
		vim.cmd.packadd('nvim.undotree')
		vim.cmd.Undotree()
	end, {})
end

plugins = {
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'refresh-partial-accept-preview' },
	{ src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
}

local config_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.o.packlockfile = config_dir .. '/pack-lock.json'
update_parsers = dofile(config_dir .. '/lua/treesitter.lua')

load_copilot = function()
	vim.api.nvim_clear_autocmds({ group = copilot_group })
	vim.cmd.packadd('copilot.vim')
	vim.fn['copilot#OnFileType']()
end

if arg and arg[1] == 'install' then vim.cmd.Plug() end
