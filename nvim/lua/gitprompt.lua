local uv = vim.uv
local queued_timer, job
local interval = 2000

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

local function update(root, cached, state, refresh)
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
		'fish', '--no-config', '-c', 'source "$argv[1]/fish/functions/git_prompt.fish"; and git_prompt', vim.env.dotfiles,
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

local function invalidate()
	if job then job.obsolete = true end
end

local function stop()
	if queued_timer then vim.fn.timer_stop(queued_timer) end
	queued_timer = nil
	local request = job
	job = nil
	if request then
		request.cached.pending = true
		if request.process and not request.process:is_closing() then uv.kill(-request.process.pid, 15) end
	end
end

return { read_cache = read_cache, update = update, invalidate = invalidate, stop = stop }
