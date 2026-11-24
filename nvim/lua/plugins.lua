local directory = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.o.packlockfile = directory .. '/nvim-pack-lock.json'
vim.pack.add({
	{ src = 'https://github.com/nhooyr/copilot.vim.git', version = 'fix-partial-accept-preview' },
	'https://github.com/justinmk/vim-dirvish.git',
}, { confirm = false })
