local function prefill_title()
	if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= 'COMMIT_EDITMSG' then return end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if lines[1] ~= '' then return end

	local files, staged = {}, false
	for _, line in ipairs(lines) do
		if line == '# Changes to be committed:' then
			staged = true
		elseif staged then
			if line == '#' then break end
			local status, path = line:match('^#\t([^:]+):%s+(.+)$')
			if not path or path:find('"', 1, true) then return end
			if status == 'renamed' or status == 'copied' then
				local target = path:match('^.- %-> (.+)$')
				if not target or target:find(' -> ', 1, true) then return end
				path = target
			end
			files[#files + 1] = path
		elseif line:find('%S') and line:sub(1, 1) ~= '#' then
			return
		end
	end
	if #files == 0 then return end

	local prefix = files[1]
	if #files > 1 then prefix = vim.fs.dirname(prefix) end
	for i = 2, #files do
		while prefix ~= '.' and not vim.startswith(files[i], prefix .. '/') do
			prefix = vim.fs.dirname(prefix)
		end
	end
	if prefix == '.' then return end

	vim.api.nvim_buf_set_lines(0, 0, 1, false, { prefix .. ': ' })
	vim.api.nvim_win_set_cursor(0, { 1, #prefix + 1 })
end

return { prefill_title = prefill_title }
