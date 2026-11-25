local languages = { 'go' }

vim.api.nvim_create_autocmd('FileType', {
	group = vim.api.nvim_create_augroup('aqsnow_treesitter', { clear = true }),
	pattern = languages,
	callback = function(event)
		if not vim.g.loaded_nvim_treesitter then vim.cmd.packadd('nvim-treesitter') end
		if not vim.treesitter.language.add(event.match) then return end
		vim.treesitter.start(event.buf)
		vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
		vim.wo[0][0].foldmethod = 'expr'
		vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})

local function install()
	local treesitter = require('nvim-treesitter')
	assert(treesitter.install(languages):wait(300000), 'Parser installation failed')
	assert(treesitter.update(languages):wait(300000), 'Parser update failed')
	-- A first install can create a runtime directory that was cached as absent.
	vim.o.runtimepath = vim.o.runtimepath
end

return install
