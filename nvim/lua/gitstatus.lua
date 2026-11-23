local uv = vim.uv
local prompts, directories = {}, {}
local timer, job, loading
local interval = 2000
local refresh

local function current_directory()
	if vim.b.vidir_dir then return vim.b.vidir_dir end
	if vim.bo.filetype == 'netrw' then return vim.b.netrw_curdir end
	if vim.bo.buftype ~= '' then return nil end
	local name = vim.api.nvim_buf_get_name(0)
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

local function worktree(directory, done)
	find_root(directory, function(root)
		local metadata = root and vim.fs.joinpath(root, '.git')
		done(root ~= nil and directory ~= metadata and not vim.startswith(directory, metadata .. '/'))
	end)
end

local function plain(text)
	return (text:gsub('\27%[[0-?]*[ -/]*[@-~]', ''):gsub('\27[()][A-Za-z0-9]', ''):gsub('[\r\n]+$', ''))
end

local function same_file(a, b)
	return a and a.ino == b.ino and a.size == b.size
		and a.mtime.sec == b.mtime.sec and a.mtime.nsec == b.mtime.nsec
end

local function read_cache(root, cached, done)
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
	if cached.started and now - cached.started < interval then return end
	cached.started = now
	local request = {}
	job = request
	local ok, process = pcall(vim.system, {
		'fish', '--no-config', '-c', 'source "$argv[1]/fish/prompt.fish"; and aqsnow_vcs_prompt', vim.env.dotfiles,
	}, { text = true, detach = true, cwd = root, env = { TERM = 'dumb', GIT_OPTIONAL_LOCKS = '0' } }, vim.schedule_wrap(function(result)
		if job ~= request then return end
		job = nil
		if result.code == 0 and result.stdout and result.stdout ~= '' then
			local text = plain(result.stdout)
			if text ~= '' then cached.prompt = text end
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
		display(cached.prompt)
		read_cache(root, cached, function(text, stat)
			if not timer or loading ~= request then return end
			loading = nil
			if text and text ~= '' then cached.prompt, cached.disk = text, stat end
			display(cached.prompt)
			update(root, cached)
		end)
	end)
end

local function start()
	if timer then return end
	timer = vim.fn.timer_start(interval, refresh, { ['repeat'] = -1 })
	refresh()
end

local function stop()
	if timer then vim.fn.timer_stop(timer) end
	timer = nil
	loading = nil
	local request = job
	job = nil
	if request and request.process and not request.process:is_closing() then
		uv.kill(-request.process.pid, 15)
	end
end

return { start = start, refresh = refresh, stop = stop, worktree = worktree }
