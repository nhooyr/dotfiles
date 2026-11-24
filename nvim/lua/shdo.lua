local function run()
	local directory, listing = vim.b.shdo_directory, vim.b.shdo_listing
	vim.cmd.stopinsert()
	vim.cmd.write()
	vim.cmd('!cd -- ' .. vim.fn.shellescape(directory, true) .. ' && sh '
		.. vim.fn.shellescape(vim.api.nvim_buf_get_name(0), true))
	if vim.v.shell_error == 0 then vim.api.nvim_set_current_buf(listing) end
end

local function setup_script()
	local script, split = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local window = vim.fn.win_getid(vim.fn.winnr('#'))
	local listing, directory = vim.api.nvim_win_get_buf(window), vim.fn.getcwd()
	vim.bo.bufhidden = 'hide'
	vim.api.nvim_win_close(split, false)
	vim.api.nvim_set_current_win(window)
	vim.api.nvim_set_current_buf(script)
	vim.bo.bufhidden = 'wipe'
	vim.b.shdo_directory, vim.b.shdo_listing = directory, listing
	vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'set -eu' })
	vim.keymap.set({ 'n', 'i' }, '<M-CR>', run, { buffer = true })
	vim.keymap.set('n', 'Z!', run, { buffer = true })
end

local function generate(options)
	local paths = options.bang and vim.fn.argv() or vim.fn.getline(options.line1, options.line2)
	local shell = vim.o.shell
	vim.o.shell = 'sh'
	local ok, err = pcall(vim.fn['dirvish#shdo'], paths, options.args)
	vim.o.shell = shell
	if not ok then error(err) end
end

local function setup()
	vim.api.nvim_create_user_command('Shdo', generate,
		{ nargs = '*', range = true, bang = true, complete = 'file' })
	vim.api.nvim_create_autocmd('User', {
		group = vim.api.nvim_create_augroup('aqsnow.shdo', { clear = true }),
		pattern = 'DirvishShdo',
		callback = setup_script,
	})
end

return { setup = setup, run = run }
