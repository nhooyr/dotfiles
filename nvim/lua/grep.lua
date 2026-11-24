local state = package.loaded['grep.state'] or { repositories = {}, generation = 0 }
package.loaded['grep.state'] = state
state.generation = state.generation + 1
local generation, repositories = state.generation, state.repositories
local pending = {}
local source = vim.fn.resolve(debug.getinfo(1, 'S').source:sub(2))
local vgrep = vim.fn.shellescape(vim.fn.fnamemodify(source, ':h:h:h') .. '/bin/vgrep')

local function cache_repository(directory, in_git)
	if generation ~= state.generation then return end
	repositories[directory] = in_git
	pending[directory] = nil
end

local function update()
	local directory = vim.fn.getcwd()
	if repositories[directory] == nil and not pending[directory] then
		pending[directory] = true
		-- Resolve the current gitstatus module after config sourcing finishes.
		vim.schedule(function()
			if generation ~= state.generation then return end
			require('gitstatus').worktree(directory, function(in_git)
				cache_repository(directory, in_git)
			end)
		end)
	end
	-- Apply cached results on entry, never while an asynchronous :grep is running.
	vim.o.grepprg = vgrep .. (repositories[directory] and ' --git' or '')
	vim.o.grepformat = repositories[directory] and '%f:%l:%c:%m' or '%f:%l:%m'
end

return { update = update }
