local function shell_quote(path)
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function refresh()
	local files = vim.fn.systemlist({
		'env', 'LC_COLLATE=C', 'gls', '-1A', '-v', '--group-directories-first', '-r', '--', vim.b.vidir_dir,
	})
	if vim.v.shell_error ~= 0 then error(table.concat(files, '\n')) end
	local commands = { '#!/bin/sh', 'set -eu', 'cd -- ' .. shell_quote(vim.b.vidir_dir) }
	for _, path in ipairs(files) do
		local quoted = shell_quote(path)
		commands[#commands + 1] = 'mv -v -- ' .. quoted .. ' ' .. quoted
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, commands)
	vim.bo.modified = false
end

local function run()
	vim.cmd('write !sh')
	if vim.v.shell_error == 0 then refresh() end
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
	refresh()
	vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = 0, command = "lua require('vidir').run()" })
	vim.keymap.set({ 'n', 'i' }, '<M-CR>', "<Cmd>lua require('vidir').run()<CR>", { buffer = true })
	vim.bo.buftype = 'acwrite'
	vim.bo.filetype = 'sh'
end

return { open = open, run = run }
