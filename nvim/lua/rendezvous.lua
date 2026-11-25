local function quit_with_request(request)
	local path = request and vim.env.AQSNOW_FISH_RENDEZVOUS
	if path and path ~= '' then vim.fn.writefile({ request }, path) end
	local ok, err = pcall(vim.cmd.qall)
	if not ok then
		if path and path ~= '' then vim.fn.delete(path) end
		error(err, 0)
	end
end

local function quit_and_run()
	if vim.fn.mode() == 'i' then
		vim.cmd.normal({ 'i' .. vim.fn['copilot#Accept'](''), bang = true })
	end
	vim.cmd.wall()
	local request
	if vim.fn.resolve(vim.api.nvim_buf_get_name(0)) == vim.g.aqsnow_orig_file
		and (vim.api.nvim_buf_line_count(0) > 1 or vim.api.nvim_get_current_line() ~= '') then
		request = 'exec'
	end
	quit_with_request(request)
end

local function fzf_widget_request(request)
	vim.cmd.wall()
	quit_with_request(request)
end

return { quit_and_run = quit_and_run, fzf_widget_request = fzf_widget_request }
