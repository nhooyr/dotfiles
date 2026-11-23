local job, timer, focus_timer
local focus_pending = false
local last_focus_refresh = -math.huge
local refresh_on_focus

local function current_directory()
	if vim.b.vidir_dir then return vim.b.vidir_dir end
	if vim.bo.filetype == 'netrw' then return vim.b.netrw_curdir end
	if vim.bo.buftype ~= '' then return nil end
	local name = vim.api.nvim_buf_get_name(0)
	return name == '' and vim.fn.getcwd() or vim.fs.dirname(name)
end

local function refresh()
	if not timer or job then return end
	local buf = vim.api.nvim_get_current_buf()
	local directory = current_directory()
	if vim.b.vcs_directory ~= directory then
		vim.b.vcs_directory = directory
		local cached = directory == vim.env.PWD and vim.env.AQSNOW_FISH_GIT_PROMPT or ''
		vim.b.vcs_prompt = cached or ''
	end
	if not directory or vim.fn.isdirectory(directory) == 0 then return end
	local current_timer = timer
	job = vim.system({
		'fish', '--no-config', '-c', 'source "$argv[1]/fish/prompt.fish"; and fish_vcs_prompt', vim.env.dotfiles,
	}, { text = true, cwd = directory, env = { TERM = 'dumb', GIT_OPTIONAL_LOCKS = '0' } }, vim.schedule_wrap(function(result)
		if timer ~= current_timer then return end
		job = nil
		if vim.api.nvim_buf_is_valid(buf) then
			local text = result.code == 0 and result.stdout or ''
			vim.b[buf].vcs_prompt = text:gsub('[\r\n]+$', '')
			vim.cmd.redrawstatus()
		end
		if focus_pending then refresh_on_focus() end
	end))
	return true
end

refresh_on_focus = function()
	if not timer then return end
	focus_pending = true
	if job or focus_timer then return end
	-- Focus has its own cooldown, independent of the regular timer.
	local delay = 2000 - (vim.uv.hrtime() / 1e6 - last_focus_refresh)
	if delay > 0 then
		focus_timer = vim.fn.timer_start(math.ceil(delay), function(id)
			if focus_timer ~= id then return end
			focus_timer = nil
			refresh_on_focus()
		end)
		return
	end
	focus_pending = false
	if refresh() then last_focus_refresh = vim.uv.hrtime() / 1e6 end
end

local function start()
	if timer then return end
	timer = vim.fn.timer_start(2000, refresh, { ['repeat'] = -1 })
	refresh()
end

local function stop()
	if timer then vim.fn.timer_stop(timer) end
	if focus_timer then vim.fn.timer_stop(focus_timer) end
	timer = nil
	focus_timer = nil
	focus_pending = false
	if job then job:kill(15) end
	job = nil
end

return { start = start, stop = stop, focus = refresh_on_focus }
