local function setup()
	vim.keymap.set('n', ']h', '/^@@<CR>', { buffer = true })
	vim.keymap.set('n', '[h', '?^@@<CR>', { buffer = true })
end

local function orig()
	vim.cmd([[
		noautocmd vert new
		set buftype=nofile
		read ++edit #
		0d_
		diffthis
		noautocmd wincmd p
		diffthis
	]])
end

local function strip(range)
	vim.cmd((range or '%') .. [[s/^\s*[+-]//]])
end

return { setup = setup, orig = orig, strip = strip }
