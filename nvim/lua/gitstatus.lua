local prompts = {}

local function current_directory()
	if vim.b.vidir_dir then return vim.b.vidir_dir end
	if vim.bo.filetype == 'netrw' then return vim.b.netrw_curdir end
	if vim.bo.buftype ~= '' then return nil end
	local name = vim.api.nvim_buf_get_name(0)
	return name == '' and vim.fn.getcwd() or vim.fs.dirname(name)
end

local function refresh()
	local directory = current_directory()
	local root = directory and vim.fs.root(directory, '.git')
	local prompt = ''
	if root then
		local path = root .. '/.fish_git_prompt'
		local stat = vim.uv.fs_stat(path)
		local cached = prompts[root]
		if stat and (not cached or cached.ino ~= stat.ino or cached.size ~= stat.size
			or cached.sec ~= stat.mtime.sec or cached.nsec ~= stat.mtime.nsec) then
			local file = io.open(path, 'rb')
			if file then
				local text = file:read('*a')
				file:close()
				if text and text ~= '' then
					-- Fish stores terminal styling; the status line only needs the text.
					text = text:gsub('\27%[[0-?]*[ -/]*[@-~]', ''):gsub('\27[()][A-Za-z0-9]', ''):gsub('[\r\n]+$', '')
					cached = { prompt = text, ino = stat.ino, size = stat.size, sec = stat.mtime.sec, nsec = stat.mtime.nsec }
					prompts[root] = cached
				end
			end
		end
		prompt = cached and cached.prompt or ''
	end
	if vim.b.vcs_prompt ~= prompt then
		vim.b.vcs_prompt = prompt
		vim.cmd.redrawstatus()
	end
end

return { refresh = refresh }
