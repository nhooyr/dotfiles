local function run()
	vim.cmd.write()
	vim.cmd('!sh ' .. vim.fn.shellescape(vim.api.nvim_buf_get_name(0), true))
	if vim.v.shell_error == 0 then vim.cmd.close() end
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
	vim.cmd('Dirvish ' .. vim.fn.fnameescape(directory))
	local listing = vim.api.nvim_get_current_buf()
	vim.cmd('%Shdo mv -v -- {} {}')
	if vim.api.nvim_get_current_buf() == listing then return end
	vim.api.nvim_buf_set_lines(0, 0, 0, false, { '#!/bin/sh', 'set -eu' })
	vim.keymap.set({ 'n', 'i' }, '<M-CR>', run, { buffer = true })
end

return { open = open, run = run }
