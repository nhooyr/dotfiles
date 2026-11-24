local pending
local generation = 0

local function run(pattern, mode)
	local regex = mode == 'G' or mode == 'E'
	local ignore_case = vim.fn.tolower(pattern) == pattern
	local glob = not mode and pattern:find('[*?%[%]{}\\]') and vim.glob.to_lpeg(pattern)
	local full_path = pattern:find('/', 1, true)
	local cwd = vim.fn.getcwd()
	if pending then pending:kill(15) end
	generation = generation + 1
	local current = generation
	local command = ({ G = 'Findr', E = 'Finde', F = 'Findf' })[mode] or 'Find'
	local finish = vim.schedule_wrap(function(result)
		if current ~= generation then return end
		pending = nil
		if result.code > 1 then
			vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
			return
		end
		local items = {}
		for file in (result.stdout or ''):gmatch('[^\n]+') do
			local candidate = ignore_case and not regex and vim.fn.tolower(file) or file
			local matches = regex or glob and glob:match(full_path and candidate or vim.fs.basename(candidate))
				or not glob and candidate:find(pattern, 1, true)
			if matches then
				items[#items + 1] = { filename = cwd .. '/' .. file, lnum = 1, col = 1 }
			end
		end
		vim.fn.setqflist({}, ' ', { title = command .. ' ' .. pattern, items = items })
		vim.cmd.copen()
		vim.cmd.lcd(vim.fn.fnameescape(cwd))
	end)
	pending = vim.system({ 'fd', '--hidden', '--follow', '--no-require-git', '--exclude', '.git',
		'--type', 'file', '--type', 'directory', '--color', 'never' },
		{ cwd = cwd }, vim.schedule_wrap(function(result)
			if current ~= generation then return end
			result.stdout = (result.stdout or ''):gsub('/\n', '\n')
			if regex and result.code <= 1 then
				local args = { 'grep', '-' .. mode, '-a', '--color=never' }
				if ignore_case then args[#args + 1] = '-i' end
				vim.list_extend(args, { '--', pattern })
				pending = vim.system(args,
					{ stdin = result.stdout }, finish)
			else
				finish(result)
			end
		end))
end

return { run = run }
