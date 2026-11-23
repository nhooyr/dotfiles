local job
local refresh_queued = false
local request_id = 0

local function stop()
	-- Invalidate callbacks before canceling their work.
	request_id = request_id + 1
	refresh_queued = false
	if job then job:kill(15) end
	job = nil
end

local function current_directory()
	if vim.b.vidir_dir then return vim.b.vidir_dir end
	if vim.bo.filetype == 'netrw' then return vim.b.netrw_curdir end
	if vim.bo.buftype ~= '' then return nil end
	local name = vim.api.nvim_buf_get_name(0)
	return name == '' and vim.fn.getcwd() or vim.fs.dirname(name)
end

local function refresh()
	stop()
	local buf = vim.api.nvim_get_current_buf()
	local directory = current_directory()
	if vim.b.vcs_directory ~= directory then
		vim.b.vcs_directory = directory
		local cached = directory == vim.env.PWD and vim.env.AQSNOW_FISH_GIT_PROMPT or ''
		vim.b.vcs_prompt = cached or ''
	end
	if not directory then return end
	local current = request_id
	job = vim.system({
		'fish', '--no-config', '-c', 'source "$argv[1]/fish/prompt.fish"; and fish_vcs_prompt', vim.env.dotfiles,
	}, { text = true, cwd = directory, env = { TERM = 'dumb', GIT_OPTIONAL_LOCKS = '0' } }, vim.schedule_wrap(function(result)
		if current ~= request_id then return end
		job = nil
		if vim.api.nvim_buf_is_valid(buf) then
			local text = result.code == 0 and result.stdout or ''
			vim.b[buf].vcs_prompt = text:gsub('[\r\n]+$', '')
			vim.cmd.redrawstatus()
		end
	end))
end

local function schedule()
	if refresh_queued then return end
	stop()
	refresh_queued = true
	local current = request_id
	vim.schedule(function()
		if current == request_id then refresh() end
	end)
end

return { refresh = refresh, schedule = schedule, stop = stop }
