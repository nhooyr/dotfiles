local function setup()
	vim.keymap.set('n', ']h', '/^@@<CR>', { buffer = true })
	vim.keymap.set('n', '[h', '?^@@<CR>', { buffer = true })
end

return { setup = setup }
