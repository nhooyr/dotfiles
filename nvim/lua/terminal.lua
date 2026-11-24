local function open(request)
	local action, cwd = request[1], request[2]
	local files = {}
	for i = 3, #request do
		local path = request[i]
		if not path:match('^%a[%w+.-]*://') and path:sub(1, 1) ~= '/' then
			path = cwd .. '/' .. path
		end
		files[#files + 1] = path
	end
	if action ~= 'edit' then vim.cmd[action]() end
	if #files == 0 then
		if action == 'edit' then vim.cmd.enew() end
	else
		-- :arglocal parses its own filename list.
		vim.api.nvim_cmd({ cmd = 'arglocal', args = vim.tbl_map(vim.fn.fnameescape, files),
			magic = { file = false, bar = false } }, {})
	end
end

return { open = open }
