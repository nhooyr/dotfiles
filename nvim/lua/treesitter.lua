local function configure()
	local directory = vim.fn.stdpath('data') .. '/treesitter'
	vim.fn.mkdir(directory, 'p')
	vim.opt.runtimepath:remove(directory)
	require('nvim-treesitter').setup({ install_dir = directory })
end

local function start(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return end
	local filetype = vim.bo[buf].filetype
	local language = vim.treesitter.language.get_lang(filetype)
	local treesitter = require('nvim-treesitter')
	if not language or not vim.list_contains(treesitter.get_available(), language) then return end
	treesitter.install({ language }):await(vim.schedule_wrap(function(err, installed)
		if err then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		if installed and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == filetype
			and vim.treesitter.language.add(language) then
			vim.treesitter.start(buf, language)
		end
	end))
end

local function setup()
	local group = vim.api.nvim_create_augroup('aqsnow_treesitter', { clear = true })
	vim.api.nvim_create_autocmd('FileType', {
		group = group,
		callback = function(event) start(event.buf) end,
	})
	vim.api.nvim_create_autocmd('PackChanged', {
		group = group,
		callback = function(event)
			if event.data.spec.name == 'nvim-treesitter' and event.data.kind == 'update' then
				vim.cmd.packadd('nvim-treesitter')
				configure()
				require('nvim-treesitter').update()
			end
		end,
	})
end

return { setup = setup, configure = configure }
