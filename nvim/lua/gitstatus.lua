local uv = vim.uv
-- Keep data across config reloads; timers and processes belong to each module instance.
local state = package.loaded['gitstatus.state'] or { prompts = {}, directories = {}, pending = {} }
package.loaded['gitstatus.state'] = state
local prompts, directories, pending = state.prompts, state.directories, state.pending
local active, queued_timer, job, loading
local interval = 2000
local refresh

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

local function plain(text)
	return (text:gsub('\27%[[0-?]*[ -/]*[@-~]', ''):gsub('\27[()][A-Za-z0-9]', ''):gsub('[\r\n]+$', ''))
end

local function same_file(a, b)
	return a and b and a.dev == b.dev and a.ino == b.ino and a.size == b.size
		and a.mtime.sec == b.mtime.sec and a.mtime.nsec == b.mtime.nsec
end

local function git_identity(directory)
	local path = vim.fs.joinpath(directory, '.git')
	local stat = uv.fs_stat(path)
	if not stat or stat.type ~= 'file' then return stat end
	local file = io.open(path)
	if not file then return nil end
	local target = (file:read('*l') or ''):match('^gitdir: (.+)$')
	file:close()
	if not target then return nil end
	if target:sub(1, 1) ~= '/' then target = vim.fs.joinpath(directory, target) end
	return uv.fs_stat(target)
end

local function read_cache(root, cached, done)
	-- Once we have live status, an older Fish cache must never replace it.
	if cached.live then done() return end
	local path = vim.fs.joinpath(root, '.fish_git_prompt')
	uv.fs_stat(path, vim.schedule_wrap(function(_, stat)
		if not stat or stat.type ~= 'file' or stat.size == 0 or same_file(cached.disk, stat) then done() return end
		uv.fs_open(path, 'r', 0, vim.schedule_wrap(function(_, fd)
			if not fd then done() return end
			uv.fs_fstat(fd, vim.schedule_wrap(function(_, opened)
				if not opened or opened.size == 0 then
					uv.fs_close(fd, vim.schedule_wrap(function() done() end))
					return
				end
				uv.fs_read(fd, opened.size, 0, vim.schedule_wrap(function(_, text)
					uv.fs_close(fd, vim.schedule_wrap(function()
						if text and #text == opened.size then done(plain(text), opened) else done() end
					end))
				end))
			end))
		end))
	end))
end

local function display(prompt)
	if vim.b.vcs_prompt ~= prompt then
		vim.b.vcs_prompt = prompt
		vim.cmd.redrawstatus()
	end
end

local function update(root, cached)
	if job or not cached.pending then return end
	local now = uv.hrtime() / 1e6
	if state.started and now - state.started < interval then
		if not queued_timer then
			queued_timer = vim.fn.timer_start(math.ceil(interval - (now - state.started)), function(id)
				if queued_timer ~= id then return end
				queued_timer = nil
				refresh()
			end)
		end
		return
	end
	if queued_timer then vim.fn.timer_stop(queued_timer) queued_timer = nil end
	local directory = uv.fs_realpath(root)
	local identity = directory and git_identity(directory)
	if not identity then return end
	state.started = now
	local request = { cached = cached }
	cached.pending = nil
	job = request
	local function finish()
		if job ~= request then return end
		job = nil
		refresh()
	end
	local ok, process = pcall(vim.system, {
		'fish', '--no-config', '-c', 'source "$argv[1]/fish/prompt.fish"; and aqsnow_vcs_prompt', vim.env.dotfiles,
	}, { text = true, detach = true, cwd = directory, env = { GIT_OPTIONAL_LOCKS = '0' } }, vim.schedule_wrap(function(result)
		if job ~= request then return end
		if request.obsolete or not same_file(identity, git_identity(directory)) then
			cached.pending = true
		elseif result.code == 0 and result.stdout and result.stdout ~= '' then
			local text = plain(result.stdout)
			if text ~= '' then
				local function publish()
					if job ~= request then return end
					if request.obsolete or not same_file(identity, git_identity(directory)) then
						cached.pending = true
					else
						cached.prompt, cached.live = text, true
					end
					finish()
				end
				local saved, writer = pcall(vim.system, {
					'fish', '--no-config', '-c',
					'source "$argv[1]"; and git_prompt_cache "$argv[2]" "$argv[3]" "$argv[4]"',
					vim.env.dotfiles .. '/fish/git_prompt_cache.fish',
					directory, result.stdout:gsub('[\r\n]+$', ''), identity.dev .. ':' .. identity.ino,
				}, { detach = true }, vim.schedule_wrap(publish))
				if saved then
					request.process = writer
				else
					publish()
				end
				return
			end
		end
		finish()
	end))
	if ok then request.process = process else job = nil end
end

refresh = function()
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
		read_cache(root, cached, function(text, stat)
			if not active or loading ~= request then return end
			loading = nil
			if text and text ~= '' and not cached.live then cached.prompt, cached.disk = text, stat end
			display(cached.prompt)
			update(root, cached)
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
	if changed and job then job.obsolete = true end
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
	if queued_timer then vim.fn.timer_stop(queued_timer) end
	queued_timer = nil
	loading = nil
	local request = job
	job = nil
	if request then
		request.cached.pending = true
		if request.process and not request.process:is_closing() then uv.kill(-request.process.pid, 15) end
	end
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
