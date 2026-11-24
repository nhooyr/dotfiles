local function run()
	vim.cmd('write !cd -- ' .. vim.fn.shellescape(vim.b.vidir_dir, true) .. ' && sh')
	if vim.v.shell_error == 0 then vim.bo.modified = false end
end

local function shell_quote(path)
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function open()
	local directory = vim.fn.getcwd()
	for _, buffer in ipairs(vim.fn.getbufinfo()) do
		if buffer.variables.vidir_dir == directory then
			vim.cmd.buffer(buffer.bufnr)
			return
		end
	end
	vim.cmd.enew()
	vim.b.vidir_dir = directory
	vim.api.nvim_buf_set_name(0, 'vidir://' .. require('dirali').shorten(directory))
	vim.cmd.bcd(directory)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { '#!/bin/sh', 'set -eu' })
	vim.cmd('silent $read !LC_COLLATE=C gls -1A -v --group-directories-first -r')
	local commands = vim.api.nvim_buf_get_lines(0, 2, -1, false)
	for i, path in ipairs(commands) do
		local quoted = shell_quote(path)
		commands[i] = 'mv -v -- ' .. quoted .. ' ' .. quoted
	end
	vim.api.nvim_buf_set_lines(0, 2, -1, false, commands)
	vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = 0, command = "lua require('vidir').run()" })
	vim.keymap.set({ 'n', 'i' }, '<M-CR>', "<Cmd>lua require('vidir').run()<CR>", { buffer = true })
	vim.bo.modified = false
	vim.bo.buftype = 'acwrite'
	vim.bo.filetype = 'sh'
end

return { open = open, run = run }
