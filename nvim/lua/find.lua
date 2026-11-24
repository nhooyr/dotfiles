local pending
local generation = 0

local function run(pattern, mode)
	local cwd = vim.fn.getcwd()
	if pending then pending:kill(15) end
	generation = generation + 1
	local current = generation
	local args = { 'fd', '--hidden', '--follow', '--no-require-git', '--exclude', '.git',
		'--type', 'file', '--type', 'directory', '--color', 'never' }
	if mode then args[#args + 1] = '-' .. mode end
	local query = pattern
	if pattern:find('/', 1, true) then
		args[#args + 1] = '--full-path'
		if mode == 'g' and pattern:sub(1, 1) ~= '/' then query = '**/' .. pattern end
	end
	vim.list_extend(args, { '--', query })
	pending = vim.system(args, { cwd = cwd }, vim.schedule_wrap(function(result)
		if current ~= generation then return end
		pending = nil
		if result.code ~= 0 then
			vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
			return
		end
		local items = {}
		for file in (result.stdout or ''):gmatch('[^\n]+') do
			items[#items + 1] = { filename = cwd .. '/' .. file:gsub('/$', ''), lnum = 1, col = 1 }
		end
		local title = 'Find' .. (mode and mode:lower() or '') .. ' ' .. pattern
		vim.fn.setqflist({}, ' ', { title = title, items = items, context = { cwd = cwd } })
		vim.cmd.copen()
		vim.cmd.lcd({ vim.fn.fnameescape(cwd), mods = { silent = true } })
	end))
end

return { run = run }
