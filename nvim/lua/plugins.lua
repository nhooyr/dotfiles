local plugins, update_parsers
local installing = arg and arg[1] == 'install'

vim.api.nvim_create_user_command('Plug', function()
	vim.pack.add(plugins, { confirm = false })
	vim.pack.update(nil, { force = true })
	vim.loader.reset()
	update_parsers()
end, {})

if vim.fn.exists(':Undotree') == 0 then
	vim.api.nvim_create_user_command('Undotree', function()
		vim.cmd.packadd('nvim.undotree')
		vim.cmd.Undotree()
	end, {})
end

local copilot_group = vim.api.nvim_create_augroup('aqsnow_copilot', { clear = true })
vim.fn.timer_stop(vim.g.aqsnow_copilot_timer or -1)
vim.g.aqsnow_copilot_timer = nil
local function load_copilot(event)
	vim.fn.timer_stop(vim.g.aqsnow_copilot_timer or -1)
	vim.g.aqsnow_copilot_timer = nil
	vim.api.nvim_clear_autocmds({ group = copilot_group })
	vim.cmd.packadd('copilot.vim')
	vim.fn['copilot#Init']()
	vim.fn['copilot#OnFileType']()
	if event and event.event == 'InsertEnter' then vim.fn['copilot#util#Defer']('copilot#OnInsertEnter') end
end
if not vim.g.loaded_copilot and not installing then
	for event, pattern in pairs({ InsertEnter = '*', CmdUndefined = 'Copilot' }) do
		vim.api.nvim_create_autocmd(event, { group = copilot_group, pattern = pattern, callback = load_copilot })
	end
	local function warm_copilot()
		vim.g.aqsnow_copilot_timer = vim.fn.timer_start(100, function() load_copilot() end)
	end
	if vim.v.vim_did_enter == 0 then
		vim.api.nvim_create_autocmd('VimEnter', { group = copilot_group, once = true, callback = warm_copilot })
	else
		warm_copilot()
	end
end

plugins = {
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'refresh-partial-accept-preview' },
	{ src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
}

local config_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
if vim.api.nvim_list_runtime_paths()[1] ~= config_dir then
	vim.opt.runtimepath:prepend({ vim.fn.escape(config_dir, ',') })
end
vim.o.packlockfile = config_dir .. '/pack-lock.json'
update_parsers = require('treesitter')

if installing then vim.cmd.Plug() end
