local api = vim.api
local dirali = require('dirali')
local M = {}
local open_selection, preview

function M.setup()
	for name, split in pairs({ Ls = 'edit', Explore = 'edit', Sexplore = 'split', Vexplore = 'vsplit' }) do
		api.nvim_create_user_command(name, function(options)
			local path = options.args ~= '' and dirali.expand(options.args) or M.current_directory()
			if vim.fn.isdirectory(path) == 0 then path = vim.fs.dirname(path) end
			M.open(path, split, options.smods)
		end, { nargs = '?', complete = 'dir', bar = true })
	end
end

local function bindings()
	local function map(mode, key, action) vim.keymap.set(mode, key, action, { buffer = true, silent = true }) end
	map('n', 'R', M.reload)
	map('n', 'gh', M.toggle_hidden)
	map('n', 't', M.expand_directory)
	map('n', '-', function() M.parent(vim.v.count1) end)
	for _, key in ipairs({ '<CR>', 'i' }) do map('n', key, function() open_selection('edit') end) end
	map('n', 'o', function() open_selection('split') end)
	map('n', 'a', function() open_selection('vsplit') end)
	map('n', 'p', preview)
	map('n', '!', '<Cmd>%Shdo<CR>')
	map('x', '!', ':Shdo<CR>')
	map('n', '<Leader>!', '!')
	map('x', '<Leader>!', '!')
	for key, command in pairs({ ['<CR>'] = 'edit', I = 'edit', O = 'split', A = 'vsplit' }) do
		map('x', key, function() open_selection(command, true) end)
	end
	map('n', 'q', function()
		local previous = vim.b.directory.previous
		if vim.fn.tabpagenr('$') == 1 and vim.fn.winnr('$') == 1 then vim.cmd.quit()
		elseif previous > 0 and previous ~= api.nvim_get_current_buf() and api.nvim_buf_is_valid(previous) then api.nvim_set_current_buf(previous)
		else vim.cmd.close() end
	end)
end

local function label(path)
	local name = path:match('([^/]+/?)$')
	if not name then return path end
	local parent = path:sub(1, #path - #name):gsub('/$', '')
	return dirali.shorten(parent) .. '/' .. name
end

local function entries(path, hidden)
	local scan, err = vim.uv.fs_scandir(path)
	if not scan then error(err) end
	local directories, files = {}, {}
	local prefix = path:gsub('/$', '') .. '/'
	while true do
		local name, kind = vim.uv.fs_scandir_next(scan)
		if not name then break end
		if not hidden or name:sub(1, 1) ~= '.' then
			local file = prefix .. name
			if kind == 'directory' or kind == 'link' and vim.fn.isdirectory(file) == 1 then
				directories[#directories + 1] = file .. '/'
			else
				files[#files + 1] = file
			end
		end
	end
	table.sort(directories)
	table.sort(files)
	return vim.list_extend(directories, files)
end

local function current_options()
	local options = {}
	for _, name in ipairs({ 'wrap', 'cursorline', 'conceallevel', 'concealcursor' }) do options[name] = vim.wo[name] end
	return options
end

local function window_options(enter)
	local options = vim.w.directory_options
	if enter then
		if not options then
			options = vim.w.directory_base_options or current_options()
			vim.w.directory_options = options
		end
		vim.wo.wrap, vim.wo.cursorline = false, true
		vim.wo.conceallevel, vim.wo.concealcursor = 2, 'nvc'
	elseif options then
		for name, value in pairs(options) do vim.wo[name] = value end
		vim.w.directory_options = nil
	end
end

function M.selected(first, last)
	first = first or vim.fn.line('.')
	last = last or first
	local paths = {}
	for _, line in ipairs(api.nvim_buf_get_lines(0, first - 1, last, false)) do
		if line ~= '' then paths[#paths + 1] = dirali.expand(line) end
	end
	return paths
end

local function display(lines)
	local current = api.nvim_get_current_line()
	api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.bo.modified = false
	local row = vim.fn.index(lines, current)
	if row >= 0 then api.nvim_win_set_cursor(0, { row + 1, 0 }) end
	window_options(true)
end

local function render()
	local state = vim.b.directory
	display(vim.tbl_map(label, entries(state.path, state.hidden)))
end

function M.reload()
	vim.b.directory = vim.tbl_extend('force', vim.b.directory, { hidden = false })
	render()
end

function M.toggle_hidden()
	local state = vim.b.directory
	if state.hidden then M.reload(); return end
	state.hidden = true
	vim.b.directory = state
	display(vim.tbl_filter(function(path) return not path:match('/%.[^/]+/?$') end,
		api.nvim_buf_get_lines(0, 0, -1, false)))
end

function M.expand_directory()
	local path = M.selected()[1]
	if not path or vim.fn.isdirectory(path) == 0 then return end
	local listed = {}
	for _, file in ipairs(M.selected(1, vim.fn.line('$'))) do listed[file] = true end
	local lines = {}
	for _, file in ipairs(entries(path, vim.b.directory.hidden)) do
		if not listed[file] then lines[#lines + 1] = label(file) end
	end
	api.nvim_buf_set_lines(0, vim.fn.line('.'), vim.fn.line('.'), false, lines)
	vim.bo.modified = false
end

function M.current_directory()
	if vim.b.directory then return vim.b.directory.path end
	local name = api.nvim_buf_get_name(0)
	if name ~= '' and vim.fn.isdirectory(name) == 1 then return name end
	return name ~= '' and vim.bo.buftype == '' and vim.fs.dirname(name) or vim.fn.getcwd()
end

open_selection = function(command, visual)
	local window = api.nvim_get_current_win()
	local paths = visual and M.selected(math.min(vim.fn.line('v'), vim.fn.line('.')), math.max(vim.fn.line('v'), vim.fn.line('.'))) or M.selected()
	if visual then api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false) end
	for _, path in ipairs(paths) do
		M.open(path, command)
		if command ~= 'edit' then api.nvim_set_current_win(window) end
	end
end

preview = function()
	local path, window = M.selected()[1], api.nvim_get_current_win()
	if not path then return end
	local windows = api.nvim_tabpage_list_wins(0)
	if #windows > 1 then
		api.nvim_set_current_win(windows[1] == window and windows[2] or windows[1])
		M.open(path)
	else
		M.open(path, 'split')
	end
	api.nvim_set_current_win(window)
end

local function initialize(path)
	local fresh = not vim.b.directory
	if fresh then
		vim.b.directory = { path = path, previous = vim.fn.bufnr('#'), hidden = false }
		vim.bo.buftype, vim.bo.bufhidden = 'nofile', 'hide'
		vim.bo.swapfile, vim.bo.modifiable, vim.bo.modeline = false, true, false
		vim.bo.filetype = 'directory'
		vim.cmd([[syntax clear]])
		vim.cmd([[syntax match DirectoryPathHead =.*/\ze[^/]\+/\?$= conceal]])
		vim.cmd([[syntax match DirectoryPathTail =[^/]\+/$=]])
		vim.cmd([[highlight default link DirectoryPathTail Directory]])
	end
	bindings()
	if fresh then render() else window_options(true) end
end

function M.open(path, command, modifiers)
	path = dirali.expand(path and path ~= '' and path or M.current_directory())
	local directory = vim.fn.isdirectory(path) == 1 and vim.uv.fs_realpath(path)
	local options = vim.w.directory_options
	if directory then path = directory == '/' and directory or directory .. '/' end
	api.nvim_cmd({ cmd = command or 'edit', args = { path }, mods = modifiers, magic = { file = false, bar = false } }, {})
	if directory then initialize(directory) end
	if options and command and command ~= 'edit' then
		if vim.bo.filetype == 'directory' then
			vim.w.directory_options = options
			window_options(true)
		else
			for name, value in pairs(options) do vim.wo[name] = value end
			vim.w.directory_options = nil
		end
	end
end

function M.parent(count)
	local path = api.nvim_buf_get_name(0)
	if path == '' or vim.bo.buftype ~= '' and not vim.b.directory then path = vim.fn.getcwd() .. '/' end
	for _ = 1, count or 1 do path = path == '/' and '/' or vim.fs.dirname(path:gsub('/$', '')) or '/' end
	M.open(path)
end

function M.configure()
	vim.g.loaded_nvim_dir_plugin = true
	local group = api.nvim_create_augroup('aqsnow.directory', { clear = true })
	local entered = vim.v.vim_did_enter == 1
	local function enter()
		local path = api.nvim_buf_get_name(0)
		if entered and vim.fn.isdirectory(path) == 1 then initialize(vim.uv.fs_realpath(path)) end
	end
	api.nvim_create_autocmd('BufEnter', { group = group, callback = enter })
	api.nvim_create_autocmd('BufLeave', { group = group, callback = function()
		if vim.bo.filetype ~= 'directory' then vim.w.directory_base_options = current_options() end
	end })
	api.nvim_create_autocmd('BufWinLeave', { group = group, callback = function() window_options(false) end })
	api.nvim_create_autocmd('VimEnter', { group = group, once = true, callback = function()
		entered = true
		vim.cmd('silent! autocmd! FileExplorer')
		for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do api.nvim_win_call(window, enter) end
	end })
	if entered then vim.cmd('silent! autocmd! FileExplorer'); enter() end
end

return M
