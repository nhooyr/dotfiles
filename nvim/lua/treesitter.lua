local parsers = {
	go = function(event)
		vim.treesitter.start(event.buf)
		vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
		vim.wo[0][0].foldmethod = 'expr'
		vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
}

vim.api.nvim_create_autocmd('FileType', {
	group = vim.api.nvim_create_augroup('aqsnow_treesitter', { clear = true }),
	pattern = vim.tbl_keys(parsers),
	callback = function(event)
		if not vim.g.loaded_nvim_treesitter then vim.cmd.packadd('nvim-treesitter') end
		if vim.treesitter.language.add(event.match) then parsers[event.match](event) end
	end,
})

local function install()
	local treesitter = require('nvim-treesitter')
	local languages = vim.tbl_keys(parsers)
	assert(treesitter.install(languages):wait(300000), 'Parser installation failed')
	assert(treesitter.update(languages):wait(300000), 'Parser update failed')
	-- A first install can create a runtime directory that was cached as absent.
	vim.o.runtimepath = vim.o.runtimepath
end

return install
