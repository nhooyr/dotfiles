local function open(request)
	local action, cwd, stdin = request[1], request[2], request[3]
	local files = {}
	for i = 4, #request do
		local path = request[i]
		if not path:match('^%a[%w+.-]*://') and path:sub(1, 1) ~= '/' then
			path = cwd .. '/' .. path
		end
		files[#files + 1] = path
	end
	if action ~= 'edit' then vim.cmd[action]() end
	if #files == 0 then
		vim.cmd.enew()
	else
		-- :arglocal parses its own filename list.
		vim.api.nvim_cmd({ cmd = 'arglocal', args = vim.tbl_map(vim.fn.fnameescape, files),
			magic = { file = false, bar = false } }, {})
	end
	if stdin ~= '' and vim.fn.getfsize(stdin) > 0 then
		vim.cmd('silent 0read ++edit ' .. vim.fn.fnameescape(stdin))
		vim.api.nvim_buf_set_lines(0, -2, -1, false, {})
	end
end

return { open = open }
