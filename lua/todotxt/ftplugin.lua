local M = {}
local date_provider = function(format, time)
	return os.date(format, time)
end

local keymaps = {
	{ "<leader>tx", "TodoTxtDone", "Toggle completion" },
	{ "<leader>tq", "TodoTxtArchiveDone", "Archive completed tasks" },
	{ "<leader>ta", "TodoTxtPriorityPicker", "Set priority" },
	{ "<leader>tb", "TodoTxtTogglePendingOnly", "Toggle pending-only view" },
	{ "<leader>td", "TodoTxtInsertToday", "Toggle creation date" },
	{ "<leader>tc", "TodoTxtShowCalendar", "Set due date" },
	{ "<leader>t+", "TodoTxtProjectPicker", "Set project" },
	{ "<leader>t@", "TodoTxtContextPicker", "Set context" },
}

local commands = {
	"TodoTxtDone",
	"TodoTxtArchiveDone",
	"TodoTxtPriorityUp",
	"TodoTxtPriorityPicker",
	"TodoTxtInsertToday",
	"TodoTxtShowCalendar",
	"TodoTxtProjectPicker",
	"TodoTxtContextPicker",
	"TodoTxtTogglePendingOnly",
}

local function current_buf()
	return vim.api.nvim_get_current_buf()
end

local function current_win()
	return vim.api.nvim_get_current_win()
end

local function today_ymd()
	return date_provider("%Y-%m-%d")
end

local function get_buf_var(buf, name, default)
	local ok, value = pcall(vim.api.nvim_buf_get_var, buf, name)
	if ok then
		return value
	end
	return default
end

local function set_buf_var(buf, name, value)
	vim.api.nvim_buf_set_var(buf, name, value)
end

local function del_buf_var(buf, name)
	pcall(vim.api.nvim_buf_del_var, buf, name)
end

local function get_win_var(win, name, default)
	local ok, value = pcall(vim.api.nvim_win_get_var, win, name)
	if ok then
		return value
	end
	return default
end

local function set_win_var(win, name, value)
	vim.api.nvim_win_set_var(win, name, value)
end

local function del_win_var(win, name)
	pcall(vim.api.nvim_win_del_var, win, name)
end

local calendar_keymaps = { "q", "<Esc>", "h", "l", "j", "k", "<Left>", "<Right>", "<Down>", "<Up>", "<CR>" }
local priority_choices = { "(A)", "(B)", "(C)", "(Z)", " " }

local function is_valid_buf(buf)
	return type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

local function stop_treesitter(buf)
	if not vim.treesitter or type(vim.treesitter.stop) ~= "function" then
		return
	end

	pcall(vim.treesitter.stop, buf)
end

local function ensure_syntax()
	local syntax = require("todotxt.syntax")

	if vim.bo.syntax == "todotxt" and vim.b.current_syntax == "todotxt" then
		syntax.apply_theme()
		return
	end

	vim.bo.syntax = "todotxt"
	syntax.setup()
end

local function echo(message)
	vim.api.nvim_echo({ { message } }, false, {})
end

local function echoerr(message)
	vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, {})
end

local function substitute(text, pattern, replacement)
	return vim.fn.substitute(text, pattern, replacement, "")
end

local function buf_path(buf)
	return vim.api.nvim_buf_get_name(buf)
end

local function path_exists(path)
	return vim.fn.filereadable(path) == 1
end

local function resolve_done_path(buf)
	local path = buf_path(buf)
	if path == "" then
		return nil
	end

	return vim.fn.fnamemodify(path, ":p:h") .. "/done.txt"
end

local function normalize_path(path)
	return vim.fn.fnamemodify(path, ":p")
end

local function get_done_buffer(path)
	local bufnr = vim.fn.bufnr(path)
	if bufnr == -1 or not is_valid_buf(bufnr) then
		return nil
	end

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		vim.fn.bufload(bufnr)
	end

	return bufnr
end

local function get_target_lines(path, buf)
	if buf and is_valid_buf(buf) then
		return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	end

	if path_exists(path) then
		return vim.fn.readfile(path)
	end

	return {}
end

local function write_target_lines(path, buf, lines)
	if buf and is_valid_buf(buf) then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent keepalt noautocmd write")
		end)
		return
	end

	vim.fn.writefile(lines, path)
end

local function extract_priority(body)
	return body:match("^%(([A-Z])%)%s+")
end

local function strip_priority_prefix(body)
	return (body:gsub("^%([A-Z]%)%s+", "", 1))
end

local function is_completed(line)
	return vim.fn.match(line, [[^\s*x \d\{4}-\d\d-\d\d\>]]) >= 0
end

local function resolve_range(opts)
	if opts and opts.range and opts.range > 0 then
		return opts.line1, opts.line2
	end

	local lnum = vim.fn.line(".")
	return lnum, lnum
end

local function apply_to_range(line1, line2, fn)
	local win = current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local last = vim.api.nvim_buf_line_count(0)

	line1 = math.max(1, math.min(line1, last))
	line2 = math.max(1, math.min(line2, last))

	for lnum = line1, line2 do
		vim.api.nvim_win_set_cursor(win, { lnum, 0 })
		fn(lnum)
	end

	cursor[1] = math.max(1, math.min(cursor[1], vim.api.nvim_buf_line_count(0)))
	vim.api.nvim_win_set_cursor(win, cursor)
end

local function command_runner(command)
	return function()
		vim.cmd(command)
	end
end

local function visual_command_runner(command)
	return function()
		local line1 = vim.fn.line("'<")
		local line2 = vim.fn.line("'>")
		vim.cmd(string.format("%d,%d%s", line1, line2, command))
	end
end

function M.clear_overdue_match()
	local win = current_win()
	local match_id = get_win_var(win, "todotxt_overdue_match_id")
	if not match_id then
		return
	end

	pcall(vim.fn.matchdelete, match_id)
	del_win_var(win, "todotxt_overdue_match_id")
end

function M.clear_today_due_match()
	local win = current_win()
	local match_id = get_win_var(win, "todotxt_today_due_match_id")
	if not match_id then
		return
	end

	pcall(vim.fn.matchdelete, match_id)
	del_win_var(win, "todotxt_today_due_match_id")
end

function M.clear_low_priority_line_match()
	local win = current_win()
	local match_id = get_win_var(win, "todotxt_low_priority_line_match_id")
	if not match_id then
		return
	end

	pcall(vim.fn.matchdelete, match_id)
	del_win_var(win, "todotxt_low_priority_line_match_id")
end

function M.refresh_overdue_due()
	M.clear_overdue_match()
	M.clear_today_due_match()
	M.clear_low_priority_line_match()

	local today = today_ymd()
	local positions = {}
	local today_positions = {}
	local low_priority_positions = {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	for lnum, line in ipairs(lines) do
		if not is_completed(line) then
			if vim.fn.match(line, [[^\s*(Z)\(\s\|$\)]]) >= 0 then
				table.insert(low_priority_positions, { lnum })
			end

			local start = 0
			while true do
				local match = vim.fn.matchstrpos(line, [[\<due:\d\{4}-\d\d-\d\d\>]], start)
				local matched = match[1]
				if matched == "" then
					break
				end

				local due = matched:sub(5)
				if due < today then
					table.insert(positions, { lnum, match[2] + 1, #matched })
				elseif due == today then
					table.insert(today_positions, { lnum, match[2] + 1, #matched })
				end

				start = match[3]
			end
		end
	end

	if #positions > 0 then
		set_win_var(current_win(), "todotxt_overdue_match_id", vim.fn.matchaddpos("todotxtOverdueDue", positions, 12))
	end

	if #today_positions > 0 then
		set_win_var(current_win(), "todotxt_today_due_match_id", vim.fn.matchaddpos("todotxtTodayDue", today_positions, 11))
	end

	if #low_priority_positions > 0 then
		set_win_var(
			current_win(),
			"todotxt_low_priority_line_match_id",
			vim.fn.matchaddpos("todotxtLowPriorityLine", low_priority_positions, 13)
		)
	end

	vim.g.todotxt_last_due_refresh_day = today
end

function M.refresh_visible_todotxt_windows_if_day_changed()
	local today = today_ymd()
	if vim.g.todotxt_last_due_refresh_day == today then
		return false
	end

	local refreshed = false

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if is_valid_win(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if is_valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "todotxt" then
				vim.api.nvim_win_call(win, function()
					M.refresh_overdue_due()
				end)
				refreshed = true
			end
		end
	end

	if not refreshed then
		vim.g.todotxt_last_due_refresh_day = today
	end

	return refreshed
end

function M.refresh_visible_todotxt_windows()
	local refreshed = false

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if is_valid_win(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if is_valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "todotxt" then
				vim.api.nvim_win_call(win, function()
					M.refresh_overdue_due()
				end)
				refreshed = true
			end
		end
	end

	return refreshed
end

function M._set_date_provider(fn)
	if type(fn) == "function" then
		date_provider = fn
		return
	end

	date_provider = function(format, time)
		return os.date(format, time)
	end
end

function M.mark_done()
	local line = vim.api.nvim_get_current_line()
	if line:match("^%s*$") then
		return
	end

	if is_completed(line) then
		echo("todo.txt: current task is already completed")
		return
	end

	local indent = vim.fn.matchstr(line, [[^\s*]])
	local body = substitute(line, [[^\s*]], "")
	body = strip_priority_prefix(body)
	vim.api.nvim_set_current_line(indent .. "x " .. os.date("%Y-%m-%d") .. " " .. body)
	M.refresh_overdue_due()
end

function M.mark_done_command(opts)
	local line1, line2 = resolve_range(opts)
	apply_to_range(line1, line2, function()
		M.mark_done()
	end)
end

function M.archive_done_command(opts)
	local buf = current_buf()
	local source_path = buf_path(buf)
	if source_path == "" then
		echoerr("todo.txt: cannot archive completed tasks from an unnamed buffer")
		return
	end

	local done_path = resolve_done_path(buf)
	if not done_path then
		echoerr("todo.txt: could not resolve done.txt path")
		return
	end

	if normalize_path(source_path) == normalize_path(done_path) then
		echo("todo.txt: current buffer is already done.txt")
		return
	end

	local last = vim.api.nvim_buf_line_count(buf)
	local line1, line2 = 1, last
	if opts and opts.range and opts.range > 0 then
		line1, line2 = resolve_range(opts)
	end

	local source_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local archived = {}
	local remaining = {}

	for lnum, line in ipairs(source_lines) do
		if lnum >= line1 and lnum <= line2 and is_completed(line) then
			table.insert(archived, line)
		else
			table.insert(remaining, line)
		end
	end

	if #archived == 0 then
		echo("todo.txt: no completed tasks to archive")
		return
	end

	local done_buf = get_done_buffer(done_path)
	local done_lines = get_target_lines(done_path, done_buf)
	local updated_done_lines = vim.list_extend(vim.deepcopy(done_lines), archived)

	local ok, err = pcall(function()
		write_target_lines(done_path, done_buf, updated_done_lines)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, remaining)
		vim.cmd("silent keepalt noautocmd write")
	end)

	if not ok then
		pcall(function()
			write_target_lines(done_path, done_buf, done_lines)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, source_lines)
		end)
		echoerr("todo.txt: failed to archive completed tasks: " .. tostring(err))
		return
	end

	M.refresh_visible_todotxt_windows()
	echo(string.format("todo.txt: archived %d completed task(s) to done.txt", #archived))
end

function M.raise_priority()
	local line = vim.api.nvim_get_current_line()
	if line:match("^%s*$") then
		return
	end

	if is_completed(line) then
		echo("todo.txt: cannot change the priority of a completed task")
		return
	end

	local indent = vim.fn.matchstr(line, [[^\s*]])
	local body = substitute(line, [[^\s*]], "")
	local current = extract_priority(body)

	if current then
		if current == "A" then
			echo("todo.txt: already at the highest priority")
			return
		end

		local next_priority = current == "Z" and "D" or string.char(string.byte(current) - 1)
		body = "(" .. next_priority .. ") " .. strip_priority_prefix(body)
	else
		body = "(C) " .. body
	end

	vim.api.nvim_set_current_line(indent .. body)
	M.refresh_overdue_due()
end

function M.raise_priority_command(opts)
	local line1, line2 = resolve_range(opts)
	apply_to_range(line1, line2, function()
		M.raise_priority()
	end)
end

function M.set_priority_on_current_line(priority)
	priority = vim.trim(priority or "")
	if priority ~= "" and not priority:match("^[A-DZ]$") then
		return false
	end

	local line = vim.api.nvim_get_current_line()
	if line:match("^%s*$") then
		return false
	end

	if is_completed(line) then
		echo("todo.txt: cannot change the priority of a completed task")
		return false
	end

	local indent = vim.fn.matchstr(line, [[^\s*]])
	local body = substitute(line, [[^\s*]], "")
	local current = extract_priority(body)

	if current then
		if priority == "" then
			body = strip_priority_prefix(body)
		else
			body = "(" .. priority .. ") " .. strip_priority_prefix(body)
		end
	elseif priority ~= "" then
		body = "(" .. priority .. ") " .. body
	end

	vim.api.nvim_set_current_line(indent .. body)
	M.refresh_overdue_due()
	return true
end

function M.insert_today()
	local line = vim.api.nvim_get_current_line()
	local indent = vim.fn.matchstr(line, [[^\s*]])
	local body = substitute(line, [[^\s*]], "")
	local date = os.date("%Y-%m-%d")
	local cursor_col = nil

	if vim.fn.match(body, [[^x \d\{4}-\d\d-\d\d \d\{4}-\d\d-\d\d\>]]) >= 0 then
		body = substitute(body, [[^\(x \d\{4}-\d\d-\d\d\) \d\{4}-\d\d-\d\d\(.*\)$]], [[\1\2]])
		vim.api.nvim_set_current_line(indent .. body)
		return
	end

	local current = extract_priority(body)
	if current and body:match("^%([A-Z]%)%s+%d%d%d%d%-%d%d%-%d%d%f[%s]") then
		body = body:gsub("^(%([A-Z]%)%s+)%d%d%d%d%-%d%d%-%d%d%s+", "%1", 1)
		vim.api.nvim_set_current_line(indent .. body)
		return
	end

	if vim.fn.match(body, [[^\d\{4}-\d\d-\d\d\>]]) >= 0 then
		body = substitute(body, [[^\d\{4}-\d\d-\d\d\s\+\(.*\)$]], [[\1]])
		vim.api.nvim_set_current_line(indent .. body)
		return
	end

	if vim.fn.match(body, [[^x \d\{4}-\d\d-\d\d\>]]) >= 0 then
		local done_date = body:match("^x (%d%d%d%d%-%d%d%-%d%d)%f[%s]")
		body = substitute(body, [[^x \d\{4}-\d\d-\d\d\zs\s\+]], " " .. date .. " ")
		if done_date then
			cursor_col = #indent + #("x " .. done_date .. " ") + #date
		end
	elseif current then
		local priority_prefix = body:match("^(%([A-Z]%)%s+)")
		body = body:gsub("^(%([A-Z]%)%s+)", "%1" .. date .. " ", 1)
		if priority_prefix then
			cursor_col = #indent + #priority_prefix + #date
		end
	elseif body:match("^%s*$") then
		body = date .. " "
		cursor_col = #indent + #date
	else
		body = date .. " " .. body
		cursor_col = #indent + #date
	end

	vim.api.nvim_set_current_line(indent .. body)
	if cursor_col ~= nil then
		vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], cursor_col })
	end
end

function M.insert_today_command(opts)
	if not (opts and opts.range and opts.range > 0) then
		M.insert_today()
		return
	end

	local line1, line2 = resolve_range(opts)
	apply_to_range(line1, line2, function()
		M.insert_today()
	end)
end

function M.day_to_ymd(year, month, day)
	return string.format("%04d-%02d-%02d", year, month, day)
end

function M.extract_due_date(line)
	local match = vim.fn.matchstr(line, [[\<due:\zs\d\{4}-\d\d-\d\d\>]])
	if match == "" then
		return ""
	end
	return match
end

function M.set_due_date_on_current_line(date)
	local line = vim.api.nvim_get_current_line()
	if line:match("^%s*$") then
		echo("todo.txt: cannot set due on an empty line")
		return false
	end

	if vim.fn.match(line, [[\<due:\d\{4}-\d\d-\d\d\>]]) >= 0 then
		line = substitute(line, [[\<due:\d\{4}-\d\d-\d\d\>]], "due:" .. date)
	else
		line = line .. " due:" .. date
	end

	vim.api.nvim_set_current_line(line)
	M.refresh_overdue_due()
	return true
end

function M.collect_tokens(prefix)
	local seen = {}
	local pattern = [[\(^\|\s\)\zs]] .. prefix .. [[\S\+]]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	for _, line in ipairs(lines) do
		local start = 0
		while true do
			local match = vim.fn.matchstrpos(line, pattern, start)
			local matched = match[1]
			if matched == "" then
				break
			end
			seen[matched] = true
			start = match[3]
		end
	end

	return vim.fn.sort(vim.tbl_keys(seen))
end

function M.normalize_token(prefix, value)
	value = vim.trim(value or "")
	if value == "" then
		return ""
	end

	if value:sub(1, 1) == prefix then
		value = value:sub(2)
	end

	value = value:gsub("%s+", "")
	if value == "" then
		return ""
	end

	return prefix .. value
end

function M.insert_token_on_current_line(token)
	if token == "" then
		return false
	end

	local line = vim.api.nvim_get_current_line()
	local escaped = vim.fn.escape(token, "\\.^$~[]")
	if vim.fn.match(line, [[\(^\|\s\)]] .. escaped .. [[\(\s\|$\)]]) >= 0 then
		echo("todo.txt: current task already contains " .. token)
		return false
	end

	if line:match("^%s*$") then
		vim.api.nvim_set_current_line(token)
	else
		vim.api.nvim_set_current_line(substitute(line, [[\s*$]], "") .. " " .. token)
	end

	return true
end

function M.insert_token_in_range(token, line1, line2)
	apply_to_range(line1, line2, function()
		M.insert_token_on_current_line(token)
	end)
end

function M.close_token_picker()
	local picker_winid = current_win()
	local picker_buf = current_buf()
	local source_winid = get_buf_var(picker_buf, "todotxt_picker_source_winid", -1)

	if source_winid > 0 then
		pcall(vim.api.nvim_set_current_win, source_winid)
	end

	pcall(vim.api.nvim_win_close, picker_winid, true)
end

function M.apply_token_picker(token)
	local picker_buf = current_buf()
	local picker_winid = current_win()
	local source_winid = get_buf_var(picker_buf, "todotxt_picker_source_winid", -1)
	local source_line1 = get_buf_var(picker_buf, "todotxt_picker_source_line1", 1)
	local source_line2 = get_buf_var(picker_buf, "todotxt_picker_source_line2", source_line1)

	if source_winid <= 0 then
		echoerr("todo.txt: source task window not found")
		pcall(vim.api.nvim_win_close, picker_winid, true)
		return
	end

	local ok, err = pcall(vim.api.nvim_win_call, source_winid, function()
		M.insert_token_in_range(token, source_line1, source_line2)
	end)

	if not ok then
		echoerr("todo.txt: source task window not found")
		pcall(vim.api.nvim_win_close, picker_winid, true)
		return err
	end

	pcall(vim.api.nvim_win_close, picker_winid, true)
end

function M.token_picker_choose()
	local token = vim.api.nvim_get_current_line()
	if token:match("^%s*$") then
		return
	end

	M.apply_token_picker(token)
end

function M.token_picker_prompt_new()
	local prefix = get_buf_var(current_buf(), "todotxt_picker_prefix", "")
	vim.fn.inputsave()
	local value = vim.fn.input("Add new " .. prefix .. ": ")
	vim.fn.inputrestore()

	local token = M.normalize_token(prefix, value)
	if token == "" then
		return
	end

	M.apply_token_picker(token)
end

function M.show_token_picker(prefix)
	M.show_token_picker_command(prefix, nil)
end

function M.show_token_picker_command(prefix, opts)
	local items = M.collect_tokens(prefix)
	local line1, line2 = resolve_range(opts)
	if #items == 0 then
		vim.fn.inputsave()
		local value = vim.fn.input("Add new " .. prefix .. ": ")
		vim.fn.inputrestore()
		local token = M.normalize_token(prefix, value)
		if token == "" then
			return
		end
		M.insert_token_in_range(token, line1, line2)
		return
	end

	local source_winid = current_win()
	local width = 0
	for _, item in ipairs(items) do
		width = math.max(width, vim.fn.strdisplaywidth(item))
	end

	local height = math.min(#items, math.max(1, vim.o.lines - 6))
	local win_width = math.min(math.max(width + 2, 20), vim.o.columns - 4)
	local row = math.max(1, math.floor((vim.o.lines - height) / 2))
	local col = math.max(1, math.floor((vim.o.columns - win_width) / 2))
	local buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, items)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	set_buf_var(buf, "todotxt_picker_source_winid", source_winid)
	set_buf_var(buf, "todotxt_picker_source_line1", line1)
	set_buf_var(buf, "todotxt_picker_source_line2", line2)
	set_buf_var(buf, "todotxt_picker_prefix", prefix)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = win_width,
		height = height,
		row = row,
		col = col,
	})

	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true

	vim.keymap.set("n", "q", M.close_token_picker, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Esc>", M.close_token_picker, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<CR>", M.token_picker_choose, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "a", M.token_picker_prompt_new, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "i", M.token_picker_prompt_new, { buffer = buf, silent = true, nowait = true })
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

function M.apply_priority_picker(priority)
	local picker_buf = current_buf()
	local picker_winid = current_win()
	local source_winid = get_buf_var(picker_buf, "todotxt_picker_source_winid", -1)
	local source_line1 = get_buf_var(picker_buf, "todotxt_picker_source_line1", 1)
	local source_line2 = get_buf_var(picker_buf, "todotxt_picker_source_line2", source_line1)

	if source_winid <= 0 then
		echoerr("todo.txt: source task window not found")
		pcall(vim.api.nvim_win_close, picker_winid, true)
		return
	end

	local ok, err = pcall(vim.api.nvim_win_call, source_winid, function()
		apply_to_range(source_line1, source_line2, function()
			M.set_priority_on_current_line(priority)
		end)
	end)

	if not ok then
		echoerr("todo.txt: source task window not found")
		pcall(vim.api.nvim_win_close, picker_winid, true)
		return err
	end

	pcall(vim.api.nvim_win_close, picker_winid, true)
end

function M.priority_picker_choose()
	local choice = vim.api.nvim_get_current_line()
	if choice == " " then
		M.apply_priority_picker("")
		return
	end

	local priority = choice:match("^%(([A-DZ])%)$")
	if not priority then
		return
	end

	M.apply_priority_picker(priority)
end

function M.priority_picker_move(delta)
	local win = current_win()
	local row = vim.api.nvim_win_get_cursor(win)[1] + delta

	if row < 1 then
		row = #priority_choices
	elseif row > #priority_choices then
		row = 1
	end

	vim.api.nvim_win_set_cursor(win, { row, 0 })
end

function M.show_priority_picker()
	M.show_priority_picker_command(nil)
end

function M.show_priority_picker_command(opts)
	local line = vim.api.nvim_get_current_line()
	if line:match("^%s*$") then
		return
	end

	if is_completed(line) then
		echo("todo.txt: cannot change the priority of a completed task")
		return
	end

	local source_winid = current_win()
	local line1, line2 = resolve_range(opts)
	local width = 0
	for _, item in ipairs(priority_choices) do
		width = math.max(width, vim.fn.strdisplaywidth(item))
	end

	local height = math.min(#priority_choices, math.max(1, vim.o.lines - 6))
	local win_width = math.min(math.max(width + 2, 8), vim.o.columns - 4)
	local row = math.max(1, math.floor((vim.o.lines - height) / 2))
	local col = math.max(1, math.floor((vim.o.columns - win_width) / 2))
	local buf = vim.api.nvim_create_buf(false, true)
	local initial_row = 1

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, priority_choices)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	set_buf_var(buf, "todotxt_picker_source_winid", source_winid)
	set_buf_var(buf, "todotxt_picker_source_line1", line1)
	set_buf_var(buf, "todotxt_picker_source_line2", line2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = win_width,
		height = height,
		row = row,
		col = col,
	})

	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true

	vim.keymap.set("n", "q", M.close_token_picker, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Esc>", M.close_token_picker, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<CR>", M.priority_picker_choose, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "k", function()
		M.priority_picker_move(-1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Up>", function()
		M.priority_picker_move(-1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "j", function()
		M.priority_picker_move(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Down>", function()
		M.priority_picker_move(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.api.nvim_win_set_cursor(win, { initial_row, 0 })
end

function M.get_calendar_lines(month, year)
	local lines

	if vim.fn.executable("cal") == 1 then
		lines = vim.fn.systemlist({ "cal", tostring(month), tostring(year) })
	elseif vim.fn.executable("ncal") == 1 then
		lines = vim.fn.systemlist({ "ncal", tostring(month), tostring(year) })
	else
		return {}
	end

	if vim.v.shell_error ~= 0 then
		return {}
	end

	return lines
end

local function disable_calendar_builtin_syntax(buf)
	if not is_valid_buf(buf) then
		return
	end

	vim.bo[buf].syntax = "OFF"
end

function M.clear_calendar_today_match()
	local win = current_win()
	local match_id = get_win_var(win, "todotxt_calendar_today_match_id")
	if not match_id then
		return
	end

	pcall(vim.fn.matchdelete, match_id)
	del_win_var(win, "todotxt_calendar_today_match_id")
end

function M.clear_calendar_selected_match()
	local win = current_win()
	local match_id = get_win_var(win, "todotxt_calendar_selected_match_id")
	if not match_id then
		return
	end

	pcall(vim.fn.matchdelete, match_id)
	del_win_var(win, "todotxt_calendar_selected_match_id")
end

function M.highlight_calendar_today(month, year)
	M.clear_calendar_today_match()

	if month ~= tonumber(os.date("%m")) or year ~= tonumber(os.date("%Y")) then
		return
	end

	local day = tonumber(os.date("%d"))
	local positions = {}
	local lines = vim.api.nvim_buf_get_lines(0, 2, -1, false)

	for offset, text in ipairs(lines) do
		local match = vim.fn.matchstrpos(text, [[\(^\|\s\)\zs]] .. day .. [[\ze\(\s\|$\)]])
		if match[1] ~= "" then
			table.insert(positions, { offset + 2, match[2] + 1, #match[1] })
			break
		end
	end

	if #positions > 0 then
		set_win_var(
			current_win(),
			"todotxt_calendar_today_match_id",
			vim.fn.matchaddpos("todotxtCalendarToday", positions, 15)
		)
	end
end

function M.find_calendar_day_position(day)
	local lines = vim.api.nvim_buf_get_lines(0, 2, -1, false)

	for offset, text in ipairs(lines) do
		local match = vim.fn.matchstrpos(text, [[\(^\|\s\)\zs]] .. day .. [[\ze\(\s\|$\)]])
		if match[1] ~= "" then
			return { offset + 2, match[2] + 1 }
		end
	end

	return nil
end

function M.highlight_calendar_selected_day(day)
	M.clear_calendar_selected_match()

	local pos = M.find_calendar_day_position(day)
	if not pos then
		return
	end

	set_win_var(
		current_win(),
		"todotxt_calendar_selected_match_id",
		vim.fn.matchaddpos("todotxtCalendarSelected", { { pos[1], pos[2], #tostring(day) } }, 16)
	)
end

function M.is_leap_year(year)
	return (year % 400 == 0) or (year % 4 == 0 and year % 100 ~= 0)
end

function M.days_in_month(month, year)
	if vim.tbl_contains({ 1, 3, 5, 7, 8, 10, 12 }, month) then
		return 31
	end

	if vim.tbl_contains({ 4, 6, 9, 11 }, month) then
		return 30
	end

	if M.is_leap_year(year) then
		return 29
	end
	return 28
end

function M.calendar_move(delta)
	local state = M.get_calendar_state()
	if not state then
		return
	end

	local buf = state.calendar_buf
	local year = get_buf_var(buf, "todotxt_calendar_year", tonumber(os.date("%Y")))
	local month = get_buf_var(buf, "todotxt_calendar_month", tonumber(os.date("%m")))
	local day = get_buf_var(buf, "todotxt_calendar_selected_day", 1) + delta

	while day < 1 do
		month = month - 1
		if month < 1 then
			month = 12
			year = year - 1
		end
		day = day + M.days_in_month(month, year)
	end

	while day > M.days_in_month(month, year) do
		day = day - M.days_in_month(month, year)
		month = month + 1
		if month > 12 then
			month = 1
			year = year + 1
		end
	end

	set_buf_var(buf, "todotxt_calendar_selected_day", day)
	M.render_calendar(month, year)
end

function M.get_calendar_state()
	local buf = current_buf()

	if get_buf_var(buf, "todotxt_calendar_ready", 0) == 1 then
		return {
			source_buf = get_buf_var(buf, "todotxt_calendar_source_bufnr", -1),
			source_winid = get_buf_var(buf, "todotxt_calendar_source_winid", -1),
			source_line1 = get_buf_var(buf, "todotxt_calendar_source_line1", 1),
			source_line2 = get_buf_var(buf, "todotxt_calendar_source_line2", 1),
			calendar_buf = buf,
			calendar_winid = current_win(),
		}
	end

	local calendar_buf = get_buf_var(buf, "todotxt_calendar_bufnr", -1)
	local calendar_winid = get_buf_var(buf, "todotxt_calendar_winid", -1)
	if not is_valid_buf(calendar_buf) or not is_valid_win(calendar_winid) then
		return nil
	end

	return {
		source_buf = buf,
		source_winid = current_win(),
		source_line1 = get_buf_var(buf, "todotxt_calendar_pending_line1", vim.fn.line(".")),
		source_line2 = get_buf_var(buf, "todotxt_calendar_pending_line2", vim.fn.line(".")),
		calendar_buf = calendar_buf,
		calendar_winid = calendar_winid,
	}
end

local function clear_calendar_source_state(source_buf)
	if not is_valid_buf(source_buf) then
		return
	end

	for _, lhs in ipairs(calendar_keymaps) do
		pcall(vim.keymap.del, "n", lhs, { buffer = source_buf })
	end

	local group_name = get_buf_var(source_buf, "todotxt_calendar_source_augroup")
	if group_name then
		pcall(vim.api.nvim_del_augroup_by_name, group_name)
		del_buf_var(source_buf, "todotxt_calendar_source_augroup")
	end

	del_buf_var(source_buf, "todotxt_calendar_bufnr")
	del_buf_var(source_buf, "todotxt_calendar_winid")
	del_buf_var(source_buf, "todotxt_calendar_pending_line1")
	del_buf_var(source_buf, "todotxt_calendar_pending_line2")
end

function M.close_calendar()
	local state = M.get_calendar_state()
	if not state then
		return
	end

	clear_calendar_source_state(state.source_buf)
	if is_valid_win(state.calendar_winid) then
		pcall(vim.api.nvim_win_close, state.calendar_winid, true)
	end
end

local function create_calendar_source_keymaps(source_buf)
	vim.keymap.set("n", "q", M.close_calendar, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Esc>", M.close_calendar, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "h", function()
		M.calendar_move(-1)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "l", function()
		M.calendar_move(1)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "j", function()
		M.calendar_move(7)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "k", function()
		M.calendar_move(-7)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Left>", function()
		M.calendar_move(-1)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Right>", function()
		M.calendar_move(1)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Down>", function()
		M.calendar_move(7)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Up>", function()
		M.calendar_move(-7)
	end, { buffer = source_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<CR>", M.calendar_apply_due, { buffer = source_buf, silent = true, nowait = true })
end

local function create_calendar_buffer_keymaps(buf)
	vim.keymap.set("n", "q", M.close_calendar, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Esc>", M.close_calendar, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "h", function()
		M.calendar_move(-1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "l", function()
		M.calendar_move(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "j", function()
		M.calendar_move(7)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "k", function()
		M.calendar_move(-7)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Left>", function()
		M.calendar_move(-1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Right>", function()
		M.calendar_move(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Down>", function()
		M.calendar_move(7)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Up>", function()
		M.calendar_move(-7)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<CR>", M.calendar_apply_due, { buffer = buf, silent = true, nowait = true })
end

local function create_calendar_source_autocmds(source_buf)
	local group_name = "todotxt_calendar_source_" .. source_buf
	local group = vim.api.nvim_create_augroup(group_name, { clear = true })

	vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
		group = group,
		buffer = source_buf,
		callback = function()
			M.close_calendar()
		end,
	})

	set_buf_var(source_buf, "todotxt_calendar_source_augroup", group_name)
end

function M.calendar_apply_due()
	local state = M.get_calendar_state()
	if not state then
		echoerr("todo.txt: calendar window not found")
		return
	end

	local buf = state.calendar_buf
	local day = get_buf_var(buf, "todotxt_calendar_selected_day", -1)
	if day < 1 then
		echo("todo.txt: please select a date")
		return
	end

	local source_winid = get_buf_var(buf, "todotxt_calendar_source_winid", -1)
	local source_line1 = get_buf_var(buf, "todotxt_calendar_source_line1", 1)
	local source_line2 = get_buf_var(buf, "todotxt_calendar_source_line2", source_line1)
	local year = get_buf_var(buf, "todotxt_calendar_year", tonumber(os.date("%Y")))
	local month = get_buf_var(buf, "todotxt_calendar_month", tonumber(os.date("%m")))
	local date = M.day_to_ymd(year, month, day)

	if source_winid <= 0 then
		echoerr("todo.txt: source task window not found")
		return
	end

	local ok = pcall(vim.api.nvim_win_call, source_winid, function()
		apply_to_range(source_line1, source_line2, function()
			if M.set_due_date_on_current_line(date) then
				set_buf_var(current_buf(), "todotxt_calendar_last_due", date)
			end
		end)
	end)

	if not ok then
		echoerr("todo.txt: source task window not found")
		return
	end

	M.close_calendar()
end

function M.render_calendar(month, year)
	local lines = M.get_calendar_lines(month, year)
	if #lines == 0 then
		echoerr("todo.txt: failed to run the calendar command")
		return
	end

	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end

	local height = #lines
	local win_width = math.min(math.max(width + 2, 24), vim.o.columns - 4)
	local win_height = math.min(height, vim.o.lines - 4)
	local row = math.max(1, math.floor((vim.o.lines - win_height) / 2))
	local col = math.max(1, math.floor((vim.o.columns - win_width) / 2))

	local state = M.get_calendar_state()
	local calendar_buf
	local calendar_winid

	if state then
		calendar_buf = state.calendar_buf
		calendar_winid = state.calendar_winid
		vim.bo[calendar_buf].modifiable = true
		vim.api.nvim_buf_set_lines(calendar_buf, 0, -1, false, lines)
		vim.bo[calendar_buf].modifiable = false
		disable_calendar_builtin_syntax(calendar_buf)
		vim.api.nvim_win_set_config(calendar_winid, {
			relative = "editor",
			style = "minimal",
			border = "rounded",
			width = win_width,
			height = win_height,
			row = row,
			col = col,
		})
	else
		local source_winid = current_win()
		local source_buf = current_buf()
		local source_line1 = get_buf_var(source_buf, "todotxt_calendar_pending_line1", vim.fn.line("."))
		local source_line2 = get_buf_var(source_buf, "todotxt_calendar_pending_line2", source_line1)
		local focus_calendar = source_line1 ~= source_line2
		local buf = vim.api.nvim_create_buf(false, true)

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].modifiable = false
		vim.bo[buf].filetype = "calendar"
		disable_calendar_builtin_syntax(buf)
		set_buf_var(buf, "todotxt_calendar_source_bufnr", source_buf)
		set_buf_var(buf, "todotxt_calendar_source_winid", source_winid)
		set_buf_var(buf, "todotxt_calendar_source_line1", source_line1)
		set_buf_var(buf, "todotxt_calendar_source_line2", source_line2)

		local win = vim.api.nvim_open_win(buf, focus_calendar, {
			relative = "editor",
			style = "minimal",
			border = "rounded",
			width = win_width,
			height = win_height,
			row = row,
			col = col,
			focusable = focus_calendar,
		})

		vim.wo[win].wrap = false
		vim.wo[win].cursorline = false

		set_buf_var(source_buf, "todotxt_calendar_bufnr", buf)
		set_buf_var(source_buf, "todotxt_calendar_winid", win)
		create_calendar_source_keymaps(source_buf)
		create_calendar_buffer_keymaps(buf)
		create_calendar_source_autocmds(source_buf)
		set_buf_var(buf, "todotxt_calendar_ready", 1)

		if month == tonumber(os.date("%m")) and year == tonumber(os.date("%Y")) then
			set_buf_var(buf, "todotxt_calendar_selected_day", tonumber(os.date("%d")))
		else
			set_buf_var(buf, "todotxt_calendar_selected_day", 1)
		end

		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			callback = function(args)
				local source_bufnr = get_buf_var(args.buf, "todotxt_calendar_source_bufnr", -1)
				clear_calendar_source_state(source_bufnr)
			end,
		})

		calendar_buf = buf
		calendar_winid = win
	end

	set_buf_var(calendar_buf, "todotxt_calendar_month", month)
	set_buf_var(calendar_buf, "todotxt_calendar_year", year)
	vim.api.nvim_win_call(calendar_winid, function()
		M.highlight_calendar_today(month, year)
		local selected_day = get_buf_var(calendar_buf, "todotxt_calendar_selected_day", 1)
		M.highlight_calendar_selected_day(selected_day)
		local pos = M.find_calendar_day_position(selected_day)
		if pos then
			vim.api.nvim_win_set_cursor(0, { pos[1], math.max(0, pos[2] - 1) })
		end
	end)
end

function M.show_calendar(opts)
	if vim.fn.executable("cal") == 0 and vim.fn.executable("ncal") == 0 then
		echoerr("todo.txt: could not find cal or ncal")
		return
	end

	local line1, line2 = resolve_range(opts)
	set_buf_var(current_buf(), "todotxt_calendar_pending_line1", line1)
	set_buf_var(current_buf(), "todotxt_calendar_pending_line2", line2)
	M.render_calendar(tonumber(os.date("%m")), tonumber(os.date("%Y")))
end

function M.show_project_picker(opts)
	M.show_token_picker_command("+", opts)
end

function M.show_context_picker(opts)
	M.show_token_picker_command("@", opts)
end

function M.toggle_pending_only()
	local buf = current_buf()
	if get_buf_var(buf, "todotxt_pending_only", 0) == 1 then
		vim.wo.foldmethod = get_buf_var(buf, "todotxt_saved_foldmethod", "manual")
		vim.wo.foldexpr = get_buf_var(buf, "todotxt_saved_foldexpr", "0")
		vim.wo.foldminlines = get_buf_var(buf, "todotxt_saved_foldminlines", 1)
		vim.cmd("normal! zE")
		set_buf_var(buf, "todotxt_pending_only", 0)
		echo("todo.txt: showing all tasks")
		return
	end

	set_buf_var(buf, "todotxt_saved_foldmethod", vim.wo.foldmethod)
	set_buf_var(buf, "todotxt_saved_foldexpr", vim.wo.foldexpr)
	set_buf_var(buf, "todotxt_saved_foldminlines", vim.wo.foldminlines)

	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = [[getline(v:lnum)=~#'^\s*x\s'?1:0]]
	vim.wo.foldminlines = 0
	set_buf_var(buf, "todotxt_pending_only", 1)
	vim.cmd("normal! zM")
	echo("todo.txt: showing pending tasks only")
end

local function create_commands(buf)
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtDone", M.mark_done_command, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtArchiveDone", M.archive_done_command, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtPriorityUp", M.raise_priority_command, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtPriorityPicker", M.show_priority_picker_command, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtInsertToday", M.insert_today_command, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtShowCalendar", M.show_calendar, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtProjectPicker", M.show_project_picker, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtContextPicker", M.show_context_picker, { bar = true, range = true })
	vim.api.nvim_buf_create_user_command(buf, "TodoTxtTogglePendingOnly", M.toggle_pending_only, { bar = true, range = true })
end

local function create_keymaps(buf)
	for _, mapping in ipairs(keymaps) do
		vim.keymap.set("n", mapping[1], command_runner(mapping[2]), {
			buffer = buf,
			silent = true,
			desc = mapping[3],
		})
		vim.keymap.set("x", mapping[1], visual_command_runner(mapping[2]), {
			buffer = buf,
			silent = true,
			desc = mapping[3],
		})
	end
end

local function create_autocmds(buf)
	local group_name = "todotxt_buffer_state_" .. buf
	local group = vim.api.nvim_create_augroup(group_name, { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
		group = group,
		buffer = buf,
		callback = function()
			M.refresh_overdue_due()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
		group = group,
		buffer = buf,
		callback = function()
			M.clear_overdue_match()
			M.clear_today_due_match()
			M.clear_low_priority_line_match()
		end,
	})

	set_buf_var(buf, "todotxt_augroup_name", group_name)
end

function M.setup()
	stop_treesitter(current_buf())
	ensure_syntax()

	if vim.b.did_todotxt_ftplugin then
		return
	end

	vim.b.did_todotxt_ftplugin = true

	local buf = current_buf()
	create_autocmds(buf)
	create_commands(buf)
	create_keymaps(buf)
	M.refresh_overdue_due()
	vim.b.undo_ftplugin = [[lua require("todotxt.ftplugin").teardown()]]
end

function M.teardown()
	local buf = current_buf()
	local group_name = get_buf_var(buf, "todotxt_augroup_name")
	if group_name then
		pcall(vim.api.nvim_del_augroup_by_name, group_name)
		del_buf_var(buf, "todotxt_augroup_name")
	end

	for _, mapping in ipairs(keymaps) do
		pcall(vim.keymap.del, "n", mapping[1], { buffer = buf })
		pcall(vim.keymap.del, "x", mapping[1], { buffer = buf })
	end

	for _, command in ipairs(commands) do
		pcall(vim.api.nvim_buf_del_user_command, buf, command)
	end

	M.clear_overdue_match()
	M.clear_today_due_match()
	M.clear_low_priority_line_match()
	del_buf_var(buf, "todotxt_pending_only")
	del_buf_var(buf, "todotxt_saved_foldmethod")
	del_buf_var(buf, "todotxt_saved_foldexpr")
	del_buf_var(buf, "todotxt_saved_foldminlines")
	vim.b.did_todotxt_ftplugin = nil
end

return M
