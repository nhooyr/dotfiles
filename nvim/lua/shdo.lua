local generate, run

local function setup()
	vim.api.nvim_create_user_command('Shdo', generate,
		{ nargs = '*', range = true, bang = true, complete = 'file' })
end

local function bindings()
	vim.keymap.set({ 'n', 'i' }, '<M-CR>', run, { buffer = true })
	vim.keymap.set('n', '<Leader>1', run, { buffer = true })
end

function run()
	local listing = vim.b.shdo_listing
	vim.cmd.stopinsert()
	vim.cmd.write()
	vim.cmd('!sh ' .. vim.fn.shellescape(vim.api.nvim_buf_get_name(0), true))
	if vim.v.shell_error == 0 and vim.api.nvim_buf_is_valid(listing) then
		vim.api.nvim_set_current_buf(listing)
		if vim.bo.filetype == 'directory' then require('ls').reload() end
	end
end

function generate(options)
	local helper = require('dirali')
	local paths, seen = {}, {}
	for _, value in ipairs(options.bang and vim.fn.argv() or vim.fn.getline(options.line1, options.line2)) do
		if value ~= '' then
			local path = helper.expand(value)
			path = path == '/' and path or path:gsub('/+$', '')
			if not seen[path] then
				if not vim.uv.fs_lstat(path) then error('Shdo: invalid path: ' .. value) end
				paths[#paths + 1], seen[path] = path, true
			end
		end
	end
	if #paths == 0 then error('Shdo: no paths selected') end
	table.sort(paths)
	local directory = vim.fs.dirname(paths[1])
	local relative = true
	for _, path in ipairs(paths) do
		if vim.fs.dirname(path) ~= directory then relative = false; break end
	end
	if not relative then directory = vim.fn.getcwd() end
	local command = options.args ~= '' and options.args or 'mv -v -- {} {}'
	if not command:find('{}', 1, true) then command = command .. ' {}' end
	local lines, shell = { '#!/bin/sh', 'set -eu' }, vim.o.shell
	vim.o.shell = 'sh'
	local ok, err = pcall(function()
		lines[#lines + 1] = 'cd -- ' .. helper.shellescape(directory)
		for _, path in ipairs(paths) do
			local quoted = helper.shellescape(relative and vim.fs.basename(path) or path)
			lines[#lines + 1] = command:gsub('{}', function() return quoted end)
		end
	end)
	vim.o.shell = shell
	if not ok then error(err) end

	local listing = vim.api.nvim_get_current_buf()
	local script = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(script, vim.fn.tempname() .. '.sh')
	vim.api.nvim_buf_set_lines(script, 0, -1, false, lines)
	vim.bo[script].undofile = false
	vim.bo[script].swapfile = false
	vim.bo[script].bufhidden = 'hide'
	vim.api.nvim_set_current_buf(script)
	vim.b.shdo_directory, vim.b.shdo_listing = directory, listing
	vim.bo.filetype = 'sh'
	bindings()
	vim.cmd('silent write')
end

return { setup = setup, generate = generate, run = run }
