local M = {}

function M.setup()
	vim.keymap.set('n', ']c', '/^diff --<CR>', { buffer = true })
	vim.keymap.set('n', '[c', '?^diff --<CR>', { buffer = true })
	vim.bo.expandtab = false
	vim.bo.tabstop = 4
	vim.bo.shiftwidth = 0
	vim.bo.textwidth = 80
	require('diff').setup()
	M.prefill_title()
end

function M.prefill_title()
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
	if prefix == '.' then
		local counts, words = {}, {}
		for _, file in ipairs(files) do
			local seen = {}
			local function add(word)
				if seen[word] then return end
				if not counts[word] then words[#words + 1] = word end
				counts[word] = (counts[word] or 0) + 1
				seen[word] = true
			end
			for component in file:gmatch('[^/]+') do
				add(component)
				-- Keep punctuation inside shared chunks, such as foo-bar in foo-bar.test.js.
				for first in component:gmatch('()%w+') do
					local tail = component:sub(first)
					for last in tail:gmatch('%w+()') do
						add(tail:sub(1, last - 1))
					end
				end
			end
		end
		for _, word in ipairs(words) do
			if counts[word] > 1 and (prefix == '.' or #word > #prefix
				or (#word == #prefix and counts[word] > counts[prefix])) then
				prefix = word
			end
		end
		if prefix == '.' then prefix = files[1] end
	end

	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.snippet.expand(prefix:gsub('[\\$}]', '\\%0') .. ': ${1:desc}')
end

return M
