local aliases = {}
for name in ('HOME:' .. (vim.env.AQSNOW_DIRALIS or '')):gmatch('[^:]+') do
	local directory = vim.env[name]
	if directory and directory ~= '' and vim.fn.isdirectory(directory) == 1 then
		directory = vim.fs.normalize(vim.fn.fnamemodify(directory, ':p'), { expand_env = false })
		aliases[#aliases + 1] = { directory = directory, name = name == 'HOME' and '~' or '$' .. name }
	end
end

local function shorten(path)
	local result, longest = path, -1
	for _, alias in ipairs(aliases) do
		local directory = alias.directory
		local prefix = directory == '/' and '/' or directory .. '/'
		local suffix
		if path == directory then
			suffix = ''
		elseif path:sub(1, #prefix) == prefix then
			suffix = '/' .. path:sub(#prefix + 1)
		end
		if suffix and #directory > longest then
			result, longest = alias.name .. suffix, #directory
		end
	end
	return result
end

local function filename()
	if vim.bo.filetype == 'netrw' and vim.b.netrw_curdir then
		return vim.fn.strtrans(shorten(vim.b.netrw_curdir))
	end
	local path = vim.api.nvim_buf_get_name(0)
	local shortened = shorten(path)
	if shortened == path then return vim.api.nvim_eval_statusline('%f', {}).str end
	return vim.fn.strtrans(shortened)
end

return { shorten = shorten, filename = filename }
