local uv = vim.uv
-- Keep data across config reloads; timers and processes belong to each module instance.
local state = package.loaded['gitstatus.state'] or { prompts = {}, directories = {}, pending = {} }
package.loaded['gitstatus.state'] = state
local prompts, directories, pending = state.prompts, state.directories, state.pending
local timer, queued_timer, job, loading
local interval = 2000
local refresh

local function current_directory(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if vim.b[buf].vidir_dir then return vim.b[buf].vidir_dir end
	if vim.bo[buf].filetype == 'netrw' then return vim.b[buf].netrw_curdir end
	if vim.bo[buf].buftype ~= '' then return nil end
	local name = vim.api.nvim_buf_get_name(buf)
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
	return a and a.ino == b.ino and a.size == b.size
		and a.mtime.sec == b.mtime.sec and a.mtime.nsec == b.mtime.nsec
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
	if job then return end
	local now = uv.hrtime() / 1e6
	if not cached.urgent and cached.started and now - cached.started < interval then
		if cached.pending and not queued_timer then
			queued_timer = vim.fn.timer_start(math.ceil(interval - (now - cached.started)), function(id)
				if queued_timer ~= id then return end
				queued_timer = nil
				refresh()
			end)
		end
		return
	end
	if queued_timer then vim.fn.timer_stop(queued_timer) queued_timer = nil end
	cached.started = now
	local request = { cached = cached, urgent = cached.urgent }
	cached.pending, cached.urgent = nil, nil
	job = request
	local ok, process = pcall(vim.system, {
		'fish', '--no-config', '-c', 'source "$argv[1]/fish/prompt.fish"; and aqsnow_vcs_prompt', vim.env.dotfiles,
	}, { text = true, detach = true, cwd = root, env = { TERM = 'dumb', GIT_OPTIONAL_LOCKS = '0' } }, vim.schedule_wrap(function(result)
		if job ~= request then return end
		job = nil
		if request.obsolete then
			cached.pending, cached.urgent = true, true
		elseif result.code == 0 and result.stdout and result.stdout ~= '' then
			local text = plain(result.stdout)
			if text ~= '' then cached.prompt, cached.live = text, true end
		end
		refresh()
	end))
	if ok then request.process = process else job = nil end
end

refresh = function()
	if not timer then return end
	local directory = current_directory()
	if not directory then loading = nil display('') return end
	local known = directories[directory]
	if known ~= nil then display(known and prompts[known].prompt or '') end
	if loading and loading.directory == directory then return end
	local request = { directory = directory }
	loading = request
	find_root(directory, function(root)
		if not timer or loading ~= request then return end
		directories[directory] = root or false
		if not root then loading = nil display('') return end
		local cached = prompts[root] or { prompt = '' }
		prompts[root] = cached
		if pending[directory] then
			cached.pending = true
			cached.urgent = cached.urgent or pending[directory].urgent
			pending[directory] = nil
		end
		display(cached.prompt)
		read_cache(root, cached, function(text, stat)
			if not timer or loading ~= request then return end
			loading = nil
			if text and text ~= '' and not cached.live then cached.prompt, cached.disk = text, stat end
			display(cached.prompt)
			update(root, cached)
		end)
	end)
end

local function enqueue(directory, urgent)
	if not directory then return end
	local cached = prompts[directories[directory]]
	if cached then
		cached.pending = true
		cached.urgent = cached.urgent or urgent
	else
		local queued = pending[directory] or {}
		queued.urgent = queued.urgent or urgent
		pending[directory] = queued
	end
	-- A result started before a write can no longer describe the worktree.
	if urgent and job then job.obsolete = true end
	refresh()
end

local function focus()
	enqueue(current_directory(), false)
end

local function written(buf)
	enqueue(current_directory(buf), true)
end

local function stop()
	vim.api.nvim_clear_autocmds({ group = 'aqsnow.gitstatus' })
	if timer then vim.fn.timer_stop(timer) end
	if queued_timer then vim.fn.timer_stop(queued_timer) end
	timer = nil
	queued_timer = nil
	loading = nil
	local request = job
	job = nil
	if request then
		request.cached.pending = true
		request.cached.urgent = request.cached.urgent or request.urgent
		if request.process and not request.process:is_closing() then uv.kill(-request.process.pid, 15) end
	end
end

local function setup()
	if timer then return end
	local group = vim.api.nvim_create_augroup('aqsnow.gitstatus', { clear = true })
	vim.api.nvim_create_autocmd({ 'BufEnter', 'BufFilePost', 'DirChanged' }, { group = group, callback = refresh })
	vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = focus })
	vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileWritePost' }, {
		group = group,
		callback = function(event) written(event.buf) end,
	})
	vim.api.nvim_create_autocmd('User', { group = group, pattern = 'AqsnowGitStatusStop', callback = stop })
	vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = stop })
	timer = vim.fn.timer_start(interval, refresh, { ['repeat'] = -1 })
	refresh()
end

return { setup = setup }
