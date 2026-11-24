local function open()
	local buffer = vim.api.nvim_get_current_buf()
	local name = vim.api.nvim_buf_get_name(buffer)
	local path, line, column = name:match('^(.*):(%d+):(%d+)$')
	if not path then path, line = name:match('^(.*):(%d+)$') end
	if not path or vim.fn.filereadable(path) == 0 then return end

	vim.cmd('edit ' .. vim.fn.fnameescape(path))
	vim.fn.cursor(math.max(1, tonumber(line)), math.max(1, tonumber(column) or 1))
	vim.api.nvim_buf_delete(buffer, { force = true })
	if vim.g.aqsnow_orig_file == vim.fn.resolve(name) then
		vim.g.aqsnow_orig_file = vim.fn.resolve(path)
	end
end

return { open = open }
