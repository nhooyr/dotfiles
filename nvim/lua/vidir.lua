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
	vim.cmd('%Shdo mv -v -- {} {}')
end

return { open = open }
