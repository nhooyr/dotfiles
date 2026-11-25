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
		local treesitter = require('nvim-treesitter')
		if not vim.list_contains(treesitter.get_installed('parsers'), event.match) then
			if not treesitter.install({ event.match }):wait(300000) then return end
			-- A first install can create a runtime directory that was cached as absent.
			vim.o.runtimepath = vim.o.runtimepath
		end
		if vim.api.nvim_get_current_buf() ~= event.buf
			or vim.bo[event.buf].filetype ~= event.match then return end
		parsers[event.match](event)
	end,
})
