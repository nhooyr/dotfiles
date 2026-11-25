local function setup()
	vim.keymap.set('n', ']h', '/^@@<CR>', { buffer = true })
	vim.keymap.set('n', '[h', '?^@@<CR>', { buffer = true })
end

local function orig()
	vim.cmd('noautocmd vert new')
	local buffer = vim.api.nvim_get_current_buf()
	local ok, err = pcall(vim.cmd, [[
		setlocal buftype=nofile
		read ++edit #
		0d_
	]])
	if not ok then
		vim.cmd('noautocmd bwipeout! ' .. buffer)
		error(err, 0)
	end
	vim.cmd([[
		diffthis
		noautocmd wincmd p
		diffthis
	]])
end

local function strip(range)
	vim.cmd((range or '%') .. [[s/^\s*[+-]//]])
end

return { setup = setup, orig = orig, strip = strip }
