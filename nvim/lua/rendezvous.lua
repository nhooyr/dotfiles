local function write_request(request)
	local path = vim.env.AQSNOW_FISH_RENDEZVOUS
	if path and path ~= '' then vim.fn.writefile({ request }, path) end
end

local function quit_and_run()
	if vim.fn.mode() == 'i' then
		vim.cmd.normal({ 'i' .. vim.fn['copilot#Accept'](''), bang = true })
	end
	vim.cmd.wall()
	if vim.fn.resolve(vim.api.nvim_buf_get_name(0)) == vim.g.aqsnow_orig_file
		and (vim.api.nvim_buf_line_count(0) > 1 or vim.api.nvim_get_current_line() ~= '') then
		write_request('exec')
	end
	vim.cmd.qall()
end

local function fzf_path_widget()
	vim.cmd.wall()
	write_request('<M-v>')
	vim.cmd.qall()
end

return { quit_and_run = quit_and_run, fzf_path_widget = fzf_path_widget }
