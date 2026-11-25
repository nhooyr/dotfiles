local state = package.loaded['find.state'] or { generation = 0 }
package.loaded['find.state'] = state

local function run(pattern, mode)
	local cwd = vim.fn.getcwd()
	if state.pending then state.pending:kill(15) end
	if state.show then vim.api.nvim_del_autocmd(state.show) state.show = nil end
	state.generation = state.generation + 1
	local current = state.generation
	local args = { 'fd', '--hidden', '--follow', '--no-require-git', '--exclude', '.git',
		'--type', 'file', '--type', 'directory', '--color', 'never' }
	if mode then args[#args + 1] = '-' .. mode end
	local query = pattern
	if pattern:find('/', 1, true) then
		args[#args + 1] = '--full-path'
		if mode == 'g' and pattern:sub(1, 1) ~= '/' then query = '**/' .. pattern:gsub('^%./', '') end
	end
	vim.list_extend(args, { '--', query })
	state.pending = vim.system(args, { cwd = cwd }, vim.schedule_wrap(function(result)
		if current ~= state.generation then return end
		state.pending = nil
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
		if vim.fn.mode(1) == 'n' then
			vim.cmd.copen()
		else
			state.show = vim.api.nvim_create_autocmd('SafeState', {
				callback = function()
					if vim.fn.mode(1) ~= 'n' then return end
					state.show = nil
					vim.cmd.copen()
					return true
				end,
			})
		end
	end))
end

return { run = run }
