local function shell_safe(path)
	return path:match('^[%w_./-]+$') ~= nil
end

local function shell_quote(path)
	if shell_safe(path) then return path end
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function refresh()
	local files = vim.fn.systemlist({
		'env', 'LC_COLLATE=C', 'gls', '-1A', '-v', '--group-directories-first', '-r', '--', vim.b.vidir_dir,
	})
	if vim.v.shell_error ~= 0 then error(table.concat(files, '\n')) end
	local commands = { '#!/bin/sh', 'set -eu' }
	for _, path in ipairs(files) do
		local quoted = shell_quote(path)
		commands[#commands + 1] = 'mv -v -- ' .. quoted .. ' ' .. quoted
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, commands)
	vim.bo.modified = false
end

local function run()
	vim.cmd('write !cd -- ' .. vim.fn.shellescape(vim.b.vidir_dir, true) .. ' && sh')
	if vim.v.shell_error == 0 then refresh() end
end

local function open(path)
	if not path or path == '' then
		path = vim.b.vidir_dir or vim.b.netrw_curdir or vim.api.nvim_buf_get_name(0)
		if path == '' or (vim.bo.buftype ~= '' and vim.fn.isdirectory(path) == 0) then
			path = vim.fn.getcwd()
		elseif vim.fn.isdirectory(path) == 0 then
			path = vim.fs.dirname(path)
		end
	end
	local directory = vim.uv.fs_realpath(path)
	if not directory or vim.fn.isdirectory(directory) == 0 then
		vim.notify('Not a directory: ' .. path, vim.log.levels.ERROR)
		return
	end
	for _, buffer in ipairs(vim.fn.getbufinfo()) do
		if buffer.variables.vidir_dir == directory then
			vim.cmd.buffer(buffer.bufnr)
			return
		end
	end
	vim.cmd.enew()
	vim.b.vidir_dir = directory
	vim.api.nvim_buf_set_name(0, 'vidir://' .. require('dirali').shorten(directory))
	refresh()
	vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = 0, command = "lua require('vidir').run()" })
	vim.keymap.set({ 'n', 'i' }, '<M-CR>', "<Cmd>lua require('vidir').run()<CR>", { buffer = true })
	vim.bo.buftype = 'acwrite'
	vim.bo.filetype = 'sh'
end

return { open = open, run = run }
