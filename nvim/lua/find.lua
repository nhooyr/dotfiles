local pending
local generation = 0

local function run(pattern, mode)
	local regex = mode == 'G' or mode == 'E'
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
			local matches = regex or glob and glob:match(full_path and file or vim.fs.basename(file))
				or not glob and file:find(pattern, 1, true)
			if matches then
				items[#items + 1] = { filename = cwd .. '/' .. file, lnum = 1, col = 1 }
			end
		end
		vim.fn.setqflist({}, ' ', { title = command .. ' ' .. pattern, items = items })
		vim.cmd.copen()
		vim.cmd.lcd(vim.fn.fnameescape(cwd))
	end)
	pending = vim.system({ 'rg', '--files', '--hidden', '--follow', '--no-require-git', '-g', '!.git' },
		{ cwd = cwd }, vim.schedule_wrap(function(result)
			if current ~= generation then return end
			if regex and result.code <= 1 then
				pending = vim.system({ 'grep', '-' .. mode, '-a', '--color=never', '--', pattern },
					{ stdin = result.stdout }, finish)
			else
				finish(result)
			end
		end))
end

return { run = run }
