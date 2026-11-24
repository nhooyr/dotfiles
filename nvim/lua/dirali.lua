local names = vim.env.AQSNOW_DIRALIS
if not names then
	vim.cmd.echoerr('"AQSNOW_DIRALIS is not set"')
elseif not (':' .. names .. ':'):find(':HOME:', 1, true) then
	vim.cmd.echoerr('"AQSNOW_DIRALIS must include HOME"')
end

local aliases = {}
for name in names:gmatch('[^:]+') do
	local directory = vim.env[name]
	if directory and directory ~= '' and vim.fn.isdirectory(directory) == 1 then
		directory = vim.fs.normalize(vim.fn.fnamemodify(directory, ':p'), { expand_env = false })
		aliases[#aliases + 1] = { directory = directory, label = name == 'HOME' and '~' or '$' .. name }
	end
end

local function shorten(path)
	local result, longest = path, -1
	for _, alias in ipairs(aliases) do
		local directory = alias.directory
		-- Match a whole directory, so /repo never abbreviates /repository.
		local prefix = directory == '/' and '/' or directory .. '/'
		local suffix
		if path == directory then
			suffix = ''
		elseif path:sub(1, #prefix) == prefix then
			suffix = '/' .. path:sub(#prefix + 1)
		end
		if suffix and #directory > longest then
			result, longest = alias.label .. suffix, #directory
		end
	end
	return result
end

local function expand(path)
	local result, longest = path, -1
	for _, alias in ipairs(aliases) do
		local prefix = alias.label .. '/'
		if #alias.label > longest and (path == alias.label or path:sub(1, #prefix) == prefix) then
			result = alias.directory .. path:sub(#alias.label + 1)
			longest = #alias.label
		end
	end
	return result:sub(1, 1) == '/' and result or vim.fn.getcwd() .. '/' .. result
end

local function filename()
	if vim.bo.filetype == 'netrw' and vim.b.netrw_curdir then
		return vim.fn.strtrans(shorten(vim.b.netrw_curdir))
	end
	local path = vim.api.nvim_buf_get_name(0)
	local shortened = shorten(path)
	-- Keep Neovim's own labels for unnamed and special buffers.
	if shortened == path and (path == '' or vim.bo.buftype ~= '') then
		return vim.api.nvim_eval_statusline('%f', {}).str
	end
	return vim.fn.strtrans(shortened)
end

local function quote(path)
	return path:match('^[%w_./-]+$') and path or vim.fn.shellescape(path)
end

local function shellescape(path)
	local shortened = shorten(path)
	if shortened == path then return quote(path) end
	local name, suffix = shortened:match('^%$([%w_]+)(.*)$')
	if name then
		if path:match('^[%w_./-]+$') then return shortened end
		return '"$' .. name .. vim.fn.escape(suffix, [[\"$`]]) .. '"'
	end
	if shortened == '~' then return '~' end
	return '~/' .. quote(shortened:sub(3))
end

return { shorten = shorten, expand = expand, filename = filename, aliases = aliases, shellescape = shellescape }
