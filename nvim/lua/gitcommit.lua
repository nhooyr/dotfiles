local prefill_title, add_stat

local function setup()
	vim.keymap.set('n', ']c', '/^diff --<CR>', { buffer = true })
	vim.keymap.set('n', '[c', '?^diff --<CR>', { buffer = true })
	vim.bo.expandtab = true
	vim.bo.tabstop = 4
	vim.bo.textwidth = 80
	require('diff').setup()
	add_stat()
	prefill_title()
end

function add_stat()
	if vim.b.gitcommit_stat then return end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local preview, first, last = false, nil, #lines
	for i, line in ipairs(lines) do
		if line:match('^# %-+ >8 %-+$') then preview = true end
		if preview and not first and line:match('^diff %-%-git ') then first = i end
		if first and line:match('^#') then last = i - 1; break end
	end
	if not first then return end
	local patch = table.concat(vim.list_slice(lines, first, last), '\n') .. '\n'
	local result
	-- Verbose diffs normally have path prefixes; diff.noprefix omits them.
	local unprefixed = ('\n' .. patch):find('\ndiff %-%-git ([^\n]+) %1\n')
	for _, strip in ipairs(unprefixed and { 0, 1 } or { 1, 0 }) do
		result = vim.system({ 'git', '--no-pager', '-c', 'color.ui=false', 'apply', '--stat', '-p' .. strip }, {
			stdin = patch, text = true,
		}):wait()
		if result.code == 0 then break end
	end
	if result.code ~= 0 then return end
	local stat = vim.split(result.stdout, '\n', { trimempty = true })
	if #stat == 0 then return end
	stat[#stat + 1] = ''
	vim.api.nvim_buf_set_lines(0, first - 1, first - 1, false, stat)
	vim.b.gitcommit_stat = true
end

function prefill_title()
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
		-- An outlying file should not hide the directory containing most changes.
		local counts = {}
		for _, file in ipairs(files) do
			local directory = vim.fs.dirname(file)
			while directory ~= '.' do
				counts[directory] = (counts[directory] or 0) + 1
				if counts[directory] > #files / 2 and (prefix == '.' or #directory > #prefix) then
					prefix = directory
				end
				directory = vim.fs.dirname(directory)
			end
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
				-- Keep underscores within words and punctuation inside shared chunks like foo-bar.
				for first in component:gmatch('()[%w_]+') do
					local tail = component:sub(first)
					for last in tail:gmatch('[%w_]+()') do
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

return { setup = setup, prefill_title = prefill_title }
