local prefill_title, add_stat

local function setup()
	vim.keymap.set('n', ']c', '/^diff --<CR>', { buffer = true })
	vim.keymap.set('n', '[c', '?^diff --<CR>', { buffer = true })
	vim.bo.expandtab = true
	vim.bo.tabstop = 4
	vim.bo.textwidth = 80
	require('diff').setup()
	prefill_title()
	add_stat()
end

function add_stat()
	if vim.b.gitcommit_stat_rows then return end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local header = vim.fn.match(lines, '^# Changes to be committed:$')
	local finish = vim.fn.match(lines, '^#$', header + 1)
	local cutoff = vim.fn.match(lines, '^# -\\+ >8 -\\+$')
	local first = vim.fn.match(lines, '^diff --git ', cutoff + 1)
	if header < 0 or finish < 0 or cutoff < 0 or first < 0 then return end
	local last = vim.fn.match(lines, '^#', first + 1)
	local patch = table.concat(lines, '\n', first + 1, last < 0 and #lines or last) .. '\n'
	local result
	local unprefixed = ('\n' .. patch):find('\ndiff %-%-git ([^\n]+) %1\n')
	for _, strip in ipairs(unprefixed and { 0, 1 } or { 1, 0 }) do
		result = vim.system({
			'git', '--no-pager', '-c', 'color.ui=false', '-c', 'core.quotePath=true',
			'apply', '--stat', '--numstat', '-p' .. strip,
		}, { stdin = patch, text = true, cwd = '/' }):wait()
		if result.code == 0 then break end
	end
	if result.code ~= 0 then return end
	local stat = vim.split(result.stdout, '\n', { trimempty = true })
	local count, tails = (#stat - 1) / 2, {}
	if count < 1 then return end
	-- Numstat supplies full paths even when the stat display truncates them.
	for i = 1, count do
		local path = stat[count + 1 + i]:match('^[^\t]+\t[^\t]+\t(.+)$')
		local tail = stat[i]:match('.* |(.-)%s*$')
		tails[path] = tail
		if path:sub(1, 1) == '"' then path = vim.fn.eval(path) end
		tails[path], tails[vim.json.encode(path)] = tail, tail
	end
	local rows, width = {}, 0
	for i = header + 2, finish do
		local row = lines[i]
		local path = row:match('^#\t[^:]+:%s+(.+)$')
		if not path then return end
		rows[#rows + 1] = { row, tails[path:match('.* %-> (.+)$') or path] }
		width = math.max(width, vim.fn.strdisplaywidth(row))
	end
	local output = { '#\tstat:       ' .. stat[count + 1]:gsub('^%s+', '') }
	local original = { [output[1]] = lines[header + 1] }
	for _, row in ipairs(rows) do
		local padding = string.rep(' ', width - vim.fn.strdisplaywidth(row[1]))
		output[#output + 1] = row[1] .. (row[2] and padding .. ' |' .. row[2] or '')
		original[output[#output]] = row[1]
	end
	vim.api.nvim_buf_set_lines(0, header + 1, finish, false, output)
	vim.b.gitcommit_stat_rows = original
end

function prefill_title()
	if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= 'COMMIT_EDITMSG' then return end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if lines[1] ~= '' then return end

	local files, staged = {}, false
	local original = vim.b.gitcommit_stat_rows or {}
	for _, line in ipairs(lines) do
		line = original[line] or line
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
