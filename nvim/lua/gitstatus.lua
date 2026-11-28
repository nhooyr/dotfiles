local gitprompt = require('gitprompt')
local uv = vim.uv
-- Keep data across config reloads; timers and processes belong to each module instance.
local state = package.loaded['gitstatus.state'] or { prompts = {}, directories = {}, pending = {} }
package.loaded['gitstatus.state'] = state
local prompts, directories, pending = state.prompts, state.directories, state.pending
local active, loading

local function current_directory(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if vim.bo[buf].buftype == 'quickfix' then return require('quickfix').directory(buf) end
	local netrw = vim.bo[buf].filetype == 'netrw'
	local name = vim.api.nvim_buf_get_name(buf)
	if netrw then name = vim.b[buf].netrw_curdir end
	if not name or name:match('^%a[%w+.-]*://') then return nil end
	if netrw then return name end
	if vim.b[buf].nvim_dir then return vim.fs.normalize(name) end
	if vim.bo[buf].buftype ~= '' then return nil end
	return name == '' and vim.fn.getcwd() or vim.fs.dirname(name)
end

local function find_root(directory, done)
	uv.fs_stat(vim.fs.joinpath(directory, '.git'), vim.schedule_wrap(function(_, stat)
		if stat and (stat.type == 'directory' or stat.type == 'file') then
			done(directory)
			return
		end
		local parent = vim.fs.dirname(directory)
		if not parent or parent == directory then done(nil) else find_root(parent, done) end
	end))
end

local function display(prompt)
	if vim.b.vcs_prompt ~= prompt then
		vim.b.vcs_prompt = prompt
		vim.cmd.redrawstatus()
	end
end

local function refresh()
	if not active then return end
	local directory = current_directory()
	if not directory then loading = nil display('') return end
	local known = directories[directory]
	if known ~= nil then display(known and prompts[known].prompt or '') end
	if loading and loading.directory == directory then return end
	local request = { directory = directory }
	loading = request
	find_root(directory, function(root)
		if not active or loading ~= request then return end
		directories[directory] = root or false
		if not root then loading = nil display('') return end
		local cached = prompts[root] or { prompt = '' }
		prompts[root] = cached
		if pending[directory] then
			cached.pending = true
			pending[directory] = nil
		end
		display(cached.prompt)
		gitprompt.read_cache(root, cached, function(text, stat)
			if not active or loading ~= request then return end
			loading = nil
			if text and text ~= '' and not cached.live then cached.prompt, cached.disk = text, stat end
			display(cached.prompt)
			gitprompt.update(root, cached, state, refresh)
		end)
	end)
end

local function enqueue(directory, changed)
	if not active then return end
	if not directory then refresh() return end
	pending[directory] = true
	local cached = prompts[directories[directory]]
	if cached then cached.pending = true end
	loading = nil
	-- A result started before a change may be stale.
	if changed then gitprompt.invalidate() end
	refresh()
end

local function trigger(event)
	enqueue(current_directory(event.buf))
end

local function changed(event)
	enqueue(current_directory(event.buf), true)
end

local function stop()
	active = false
	vim.api.nvim_clear_autocmds({ group = 'aqsnow.gitstatus' })
	loading = nil
	gitprompt.stop()
end

local function setup()
	if active then return end
	active = true
	local group = vim.api.nvim_create_augroup('aqsnow.gitstatus', { clear = true })
	vim.api.nvim_create_autocmd({ 'BufEnter', 'BufFilePost', 'DirChanged' }, { group = group, callback = refresh })
	vim.api.nvim_create_autocmd({
		'BufReadPost', 'FileReadPost', 'FocusGained', 'FocusLost', 'WinEnter', 'WinLeave', 'BufWinEnter', 'BufWinLeave',
		'QuickFixCmdPost',
	}, {
		group = group,
		callback = trigger,
	})
	vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileWritePost', 'ShellCmdPost', 'ShellFilterPost' }, {
		group = group,
		callback = changed,
	})
	local command_pending = false
	vim.api.nvim_create_autocmd('CmdlineLeave', {
		group = group, pattern = ':',
		callback = function()
			if vim.v.event.abort or command_pending then return end
			command_pending = true
			vim.api.nvim_create_autocmd('SafeState', {
				group = group, once = true,
				callback = function()
					command_pending = false
					enqueue(current_directory(), true)
				end,
			})
		end,
	})
	vim.api.nvim_create_autocmd('User', { group = group, pattern = 'AqsnowGitStatusStop', callback = stop })
	vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = stop })
	enqueue(current_directory())
end

return { setup = setup }
