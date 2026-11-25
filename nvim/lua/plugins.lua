local config_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.o.packlockfile = config_dir .. '/nvim-pack-lock.json'
vim.cmd.packadd('nvim.undotree')
vim.api.nvim_create_autocmd('FileType', {
	group = vim.api.nvim_create_augroup('aqsnow_treesitter', { clear = true }),
	callback = function(event)
		if vim.bo[event.buf].buftype ~= '' then return end
		local language = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
		if language and vim.treesitter.language.add(language) then
			vim.treesitter.start(event.buf, language)
		end
	end,
})
vim.pack.add({
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'refresh-partial-accept-preview' },
	{ src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
}, { confirm = false })
