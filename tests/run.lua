local function fail(message)
  error(message, 0)
end

local function assert_eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    fail(string.format("%s\nexpected: %s\nactual: %s", message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    fail(message)
  end
end

local function syntax_name_at(line, column)
  return vim.fn.synIDattr(vim.fn.synID(line, column, 1), "name")
end

local function syntax_stack_at(line, column)
  return vim.iter(vim.fn.synstack(line, column))
    :map(function(id)
      return vim.fn.synIDattr(id, "name")
    end)
    :totable()
end

local function hl_color(name, key)
  return vim.api.nvim_get_hl(0, { name = name, link = false })[key]
end

local function literal_column(line, token, offset)
  local start = assert(line:find(token, 1, true), "token not found: " .. token)
  return start + (offset or 0)
end

local function split_lines(text)
  if text == "" then
    return {}
  end
  return vim.split(text, "\n", { plain = true })
end

local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo)
vim.cmd("runtime plugin/todotxt.lua")
vim.cmd("set nomore")
vim.cmd("filetype plugin on")

local ftplugin = require("todotxt.ftplugin")
local tempdir = vim.fn.tempname()
vim.fn.mkdir(tempdir, "p")

local function cleanup_windows()
  vim.cmd("silent! only")
  vim.cmd("silent! %bwipeout!")
end

local function write_file(path, content)
  vim.fn.writefile(split_lines(content), path)
end

local function read_file(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  return vim.fn.readfile(path)
end

local function edit_file(path)
  cleanup_windows()
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
end

local function make_file(name, content)
  local path = tempdir .. "/" .. name
  write_file(path, content or "")
  return path
end

local function find_calendar_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "calendar" then
      return win, buf
    end
  end
  return nil, nil
end

local tests = {}

tests[#tests + 1] = function()
  local cases = {
    { "todo.txt", "todotxt" },
    { "done.txt", "todotxt" },
    { "work.todo.txt", "todotxt" },
    { "work.done.txt", "todotxt" },
    { "notes.todotxt", "todotxt" },
  }

  for _, case in ipairs(cases) do
    edit_file(make_file(case[1], "task"))
    assert_eq(vim.bo.filetype, case[2], "filetype detection failed: " .. case[1])
    assert_true(vim.b.did_todotxt_ftplugin == true, "todotxt initialization was not loaded: " .. case[1])
  end
end

tests[#tests + 1] = function()
  edit_file(make_file("visual-maps.todo.txt", "alpha\nbeta"))
  for _, lhs in ipairs({ "<leader>tx", "<leader>tq", "<leader>ta", "<leader>tb", "<leader>td", "<leader>tc", "<leader>t+", "<leader>t@" }) do
    local visual_mapping = vim.fn.maparg(lhs, "x", false, true)
    local normal_mapping = vim.fn.maparg(lhs, "n", false, true)
    assert_true(type(visual_mapping) == "table" and visual_mapping.lhs ~= nil, "missing visual-mode mapping: " .. lhs)
    assert_true(type(normal_mapping) == "table" and normal_mapping.lhs ~= nil, "missing normal-mode mapping: " .. lhs)
    assert_true(type(visual_mapping.desc) == "string" and visual_mapping.desc ~= "", "visual-mode mapping is missing desc: " .. lhs)
    assert_true(type(normal_mapping.desc) == "string" and normal_mapping.desc ~= "", "normal-mode mapping is missing desc: " .. lhs)
  end
end

tests[#tests + 1] = function()
  local line = "(A) 2026-03-18 call +Work @phone due:2026-03-19 pri:B rec:2026-03-20 t:now"
  edit_file(make_file("syntax.todo.txt", line))
  local due_key_col = literal_column(line, "due:")
  local due_date_col = literal_column(line, "due:", 4)
  local pri_key_col = literal_column(line, "pri:")
  local pri_value_col = literal_column(line, "pri:", 4)
  local rec_key_col = literal_column(line, "rec:")
  local rec_date_col = literal_column(line, "rec:", 4)
  local t_key_col = literal_column(line, "t:")
  local t_value_col = literal_column(line, "t:", 2)

  assert_eq(vim.bo.syntax, "todotxt", "buffer syntax was not set")
  assert_eq(vim.b.current_syntax, "todotxt", "syntax was not loaded")
  assert_eq(vim.fn.hlexists("todotxtPriority"), 1, "priority syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtDoneLine"), 1, "done-line syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtLowPriorityLine"), 1, "low-priority line syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtMeta"), 1, "metadata syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtCreationDate"), 1, "creation-date syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtContext"), 1, "context syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtProject"), 1, "project syntax group is missing")
  assert_eq(vim.fn.hlexists("todotxtDue"), 1, "due syntax group is missing")
  assert_eq(vim.fn.synIDattr(vim.fn.hlID("todotxtProject"), "name"), "todotxtProject", "project highlight group is missing")
  assert_eq(syntax_name_at(1, 2), "todotxtPriority", "priority did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, 6), "todotxtCreationDate", "creation date did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, 21), "todotxtProject", "project did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, 27), "todotxtContext", "context did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, due_key_col), "todotxtDueKey", "due key did not hit its dedicated highlight group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, due_date_col), "todotxtDueDate"), "due date did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, pri_key_col), "todotxtMetaKey", "pri key should use normal metadata highlighting")
  assert_true(vim.tbl_contains(syntax_stack_at(1, pri_value_col), "todotxtMetaValue"), "pri value should use normal metadata highlighting")
  assert_eq(syntax_name_at(1, rec_key_col), "todotxtMetaKey", "extended key-value key did not hit its dedicated highlight group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, rec_date_col), "todotxtMetaDate"), "extended key-value date did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, t_key_col), "todotxtMetaKey", "second extended key-value key did not hit its dedicated highlight group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, t_value_col), "todotxtMetaValue"), "extended key-value value did not hit its dedicated highlight group")
  assert_eq(hl_color("todotxtProject", "fg"), 0xA6DBFF, "default theme project color is wrong")
  assert_eq(hl_color("todotxtContext", "fg"), 0x8CF8F7, "default theme context color is wrong")
  assert_eq(hl_color("todotxtLowPriorityLine", "fg"), 0xC4C6CD, "low-priority line color is wrong")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtDoneLine", link = false }).strikethrough == true, "done-task strikethrough is not enabled")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtPriority", link = false }).bold == true, "default theme priority bold is not enabled")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtDueKey", link = false }).bold ~= true, "default theme due key should not be bold")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtDueDate", link = false }).bold ~= true, "default theme due date should not be bold")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtTodayDue", link = false }).bold == true, "today's due highlight should be bold")
end

tests[#tests + 1] = function()
  edit_file(make_file("done-syntax.todo.txt", "x 2026-03-19 2026-03-18 close ticket +Ops @desk due:2026-03-20"))
  assert_eq(syntax_name_at(1, 1), "todotxtDoneLine", "done marker should use the full-line highlight group")
  assert_eq(syntax_name_at(1, 4), "todotxtDoneLine", "done date should use the full-line highlight group")
  assert_eq(syntax_name_at(1, 15), "todotxtDoneLine", "creation date on a completed task should use the full-line highlight group")
  assert_eq(syntax_name_at(1, 38), "todotxtDoneLine", "completed task project should not keep a separate highlight group")
  assert_eq(syntax_name_at(1, 43), "todotxtDoneLine", "completed task context should not keep a separate highlight group")
  ftplugin.refresh_overdue_due()
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtDoneLine", link = false }).strikethrough == true, "completed-task strikethrough is not enabled")
end

tests[#tests + 1] = function()
  edit_file(make_file("meta-syntax.todo.txt", "task rec:2026-03-20 mail:foo@bar invalid:foo:bar due:2026-03-22"))
  assert_eq(syntax_name_at(1, 6), "todotxtMetaKey", "valid extended key-value key did not hit its dedicated highlight group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, 10), "todotxtMetaDate"), "valid extended key-value date did not hit its dedicated highlight group")
  assert_eq(syntax_name_at(1, 21), "todotxtMetaKey", "extended key-value with a non-date value did not hit its dedicated highlight group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, 26), "todotxtMetaValue"), "extended key-value with special characters did not hit its dedicated highlight group")
  assert_true(not vim.tbl_contains(syntax_stack_at(1, 41), "todotxtMeta"), "token with multiple colons should not be treated as a valid extended key-value pair")
end

tests[#tests + 1] = function()
  local line = "(Z) 2026-03-18 task +Proj @ctx due:2026-03-19 pri:B rec:2026-03-20"
  edit_file(make_file("low-priority.todo.txt", line))
  ftplugin.refresh_overdue_due()
  local match_id = vim.api.nvim_win_get_var(0, "todotxt_low_priority_line_match_id")
  assert_true(type(match_id) == "number" and match_id > 0, "full-line gray match for Z priority was not created")
  assert_eq(syntax_name_at(1, 2), "", "Z priority prefix should not hit the normal priority syntax group")
end

tests[#tests + 1] = function()
  edit_file(make_file("late-load.todo.txt", "task"))
  ftplugin.teardown()
  vim.b.current_syntax = nil
  vim.bo.syntax = ""
  vim.g.loaded_todotxt_plugin = nil
  dofile(repo .. "/plugin/todotxt.lua")
  assert_eq(vim.bo.filetype, "todotxt", "filetype is incorrect in the late-load scenario")
  assert_eq(vim.bo.syntax, "todotxt", "buffer syntax was not restored in the late-load scenario")
  assert_eq(vim.b.current_syntax, "todotxt", "syntax was not loaded in the late-load scenario")
  assert_true(vim.b.did_todotxt_ftplugin == true, "ftplugin was not rerun in the late-load scenario")
end

tests[#tests + 1] = function()
  edit_file(make_file("restore-syntax.todo.txt", "task"))
  assert_eq(vim.b.did_todotxt_ftplugin, true, "ftplugin should already be initialized before restoring syntax")
  vim.bo.syntax = ""
  vim.b.current_syntax = nil
  ftplugin.setup()
  assert_eq(vim.bo.syntax, "todotxt", "syntax was not restored after being cleared")
  assert_eq(vim.b.current_syntax, "todotxt", "current_syntax was not restored after being cleared")
  assert_eq(vim.b.did_todotxt_ftplugin, true, "restoring syntax should not break ftplugin initialization state")
end

tests[#tests + 1] = function()
  local todotxt = require("todotxt")
  local default_config = todotxt.get_default_config()

  todotxt.setup({
    theme = {
      todotxtProject = { fg = "#112233", bold = true },
      todotxtContext = { fg = "#445566", italic = true },
    },
  })

  assert_eq(hl_color("todotxtProject", "fg"), 0x112233, "custom theme project color was not applied")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtProject", link = false }).bold == true, "custom theme project bold was not applied")
  assert_eq(hl_color("todotxtContext", "fg"), 0x445566, "custom theme context color was not applied")
  assert_true(vim.api.nvim_get_hl(0, { name = "todotxtContext", link = false }).italic == true, "custom theme context italic was not applied")

  todotxt.setup(default_config)
end

tests[#tests + 1] = function()
  local line = "(A) 2026-03-18 task +Proj @ctx due:2026-03-19 pri:B rec:2026-03-20 mail:foo@bar invalid:foo:bar"
  edit_file(make_file("syntax-overlap.todo.txt", line))

  local due_key_col = literal_column(line, "due:")
  local due_date_col = literal_column(line, "due:", 4)
  local pri_key_col = literal_column(line, "pri:")
  local pri_value_col = literal_column(line, "pri:", 4)
  local meta_key_col = literal_column(line, "rec:")
  local meta_date_col = literal_column(line, "rec:", 4)
  local mail_key_col = literal_column(line, "mail:")
  local mail_value_col = literal_column(line, "mail:", 5)
  local email_at_col = literal_column(line, "@bar")
  local invalid_col = literal_column(line, "invalid:")

  assert_eq(syntax_name_at(1, due_key_col), "todotxtDueKey", "due key was overridden by another syntax group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, due_key_col), "todotxtDue"), "due key was not kept inside the due region")
  assert_true(not vim.tbl_contains(syntax_stack_at(1, due_key_col), "todotxtMeta"), "due key should not fall into the meta region")

  assert_eq(syntax_name_at(1, due_date_col), "todotxtDueDate", "due date was overridden by another syntax group")
  assert_true(not vim.tbl_contains(syntax_stack_at(1, due_date_col), "todotxtMetaDate"), "due date should not fall into the meta date group")

  assert_eq(syntax_name_at(1, pri_key_col), "todotxtMetaKey", "pri key should use normal metadata highlighting")
  assert_eq(syntax_name_at(1, pri_value_col), "todotxtMetaValue", "pri value should use normal metadata highlighting")
  assert_true(vim.tbl_contains(syntax_stack_at(1, pri_key_col), "todotxtMeta"), "pri key did not fall into the meta region")
  assert_true(vim.tbl_contains(syntax_stack_at(1, pri_value_col), "todotxtMetaValue"), "pri value did not fall into the meta value group")

  assert_eq(syntax_name_at(1, meta_key_col), "todotxtMetaKey", "meta key was overridden by another syntax group")
  assert_true(vim.tbl_contains(syntax_stack_at(1, meta_key_col), "todotxtMeta"), "meta key was not kept inside the meta region")
  assert_eq(syntax_name_at(1, meta_date_col), "todotxtMetaDate", "meta date was overridden by another syntax group")

  assert_eq(syntax_name_at(1, mail_key_col), "todotxtMetaKey", "mail key was overridden by another syntax group")
  assert_eq(syntax_name_at(1, mail_value_col), "todotxtMetaValue", "mail value was overridden by another syntax group")
  assert_eq(syntax_name_at(1, email_at_col), "todotxtMetaValue", "@ inside mail value should not be recognized as context")
  assert_true(not vim.tbl_contains(syntax_stack_at(1, email_at_col), "todotxtContext"), "@ inside mail value was incorrectly recognized as context")

  assert_eq(syntax_name_at(1, invalid_col), "", "invalid token with multiple colons should not partially match any syntax group")
end

tests[#tests + 1] = function()
  edit_file(make_file("mark.todo.txt", "(B) ship feature"))
  vim.cmd("TodoTxtDone")
  local today = os.date("%Y-%m-%d")
  assert_eq(vim.api.nvim_get_current_line(), "x " .. today .. " ship feature", "completed task format is incorrect")
end

tests[#tests + 1] = function()
  edit_file(make_file("priority.todo.txt", "ship feature"))
  vim.cmd("TodoTxtPriorityUp")
  assert_eq(vim.api.nvim_get_current_line(), "(C) ship feature", "first priority raise failed")
  vim.cmd("TodoTxtPriorityUp")
  assert_eq(vim.api.nvim_get_current_line(), "(B) ship feature", "second priority raise failed")
  vim.cmd("TodoTxtPriorityUp")
  assert_eq(vim.api.nvim_get_current_line(), "(A) ship feature", "third priority raise failed")
end

tests[#tests + 1] = function()
  edit_file(make_file("priority-picker.todo.txt", "2026-03-18 ship feature"))
  vim.cmd("TodoTxtPriorityPicker")
  assert_eq(vim.bo.buftype, "nofile", "priority picker did not open a scratch buffer")
  assert_eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "(A)", "(B)", "(C)", "(Z)", " " }, "priority picker list is incorrect")
  assert_eq(vim.api.nvim_win_get_cursor(0), { 1, 0 }, "priority picker should place the default cursor on A")
  ftplugin.priority_picker_move(-1)
  assert_eq(vim.api.nvim_win_get_cursor(0), { 5, 0 }, "moving up from A should wrap to the space entry")
  ftplugin.apply_priority_picker("B")
  assert_eq(vim.api.nvim_get_current_line(), "(B) 2026-03-18 ship feature", "priority picker insert failed")

  vim.cmd("TodoTxtPriorityPicker")
  ftplugin.apply_priority_picker("A")
  assert_eq(vim.api.nvim_get_current_line(), "(A) 2026-03-18 ship feature", "existing priority should be replaced directly")

  vim.cmd("TodoTxtPriorityPicker")
  ftplugin.apply_priority_picker("Z")
  assert_eq(vim.api.nvim_get_current_line(), "(Z) 2026-03-18 ship feature", "lowest priority Z should be supported")

  vim.cmd("TodoTxtPriorityPicker")
  ftplugin.apply_priority_picker("")
  assert_eq(vim.api.nvim_get_current_line(), "2026-03-18 ship feature", "space option should clear the existing priority")
end

tests[#tests + 1] = function()
  edit_file(make_file("batch-done.todo.txt", "alpha\nbeta\ngamma"))
  vim.cmd("1,2TodoTxtDone")
  local today = os.date("%Y-%m-%d")
  assert_eq(vim.api.nvim_buf_get_lines(0, 0, 3, false), {
    "x " .. today .. " alpha",
    "x " .. today .. " beta",
    "gamma",
  }, "TodoTxtDone range operation failed")
end

tests[#tests + 1] = function()
  local dir = tempdir .. "/archive-all"
  vim.fn.mkdir(dir, "p")
  local todo_path = dir .. "/todo.txt"
  local done_path = dir .. "/done.txt"
  write_file(todo_path, "alpha\nx 2026-03-18 close ticket\nbeta\nx 2026-03-19 ship feature")

  edit_file(todo_path)
  vim.cmd("TodoTxtArchiveDone")

  assert_eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    "alpha",
    "beta",
  }, "TodoTxtArchiveDone should remove completed tasks from the source buffer")
  assert_eq(read_file(todo_path), {
    "alpha",
    "beta",
  }, "TodoTxtArchiveDone should persist the updated todo.txt content")
  assert_eq(read_file(done_path), {
    "x 2026-03-18 close ticket",
    "x 2026-03-19 ship feature",
  }, "TodoTxtArchiveDone should create done.txt and append archived tasks")
end

tests[#tests + 1] = function()
  local dir = tempdir .. "/archive-range"
  vim.fn.mkdir(dir, "p")
  local todo_path = dir .. "/range.todo.txt"
  local done_path = dir .. "/done.txt"
  write_file(todo_path, "x 2026-03-18 alpha\nbeta\nx 2026-03-19 gamma")
  write_file(done_path, "x 2026-03-17 existing")

  edit_file(done_path)
  edit_file(todo_path)
  vim.cmd("1,2TodoTxtArchiveDone")

  assert_eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    "beta",
    "x 2026-03-19 gamma",
  }, "TodoTxtArchiveDone range operation should only remove completed tasks inside the selected range")
  assert_eq(read_file(done_path), {
    "x 2026-03-17 existing",
    "x 2026-03-18 alpha",
  }, "TodoTxtArchiveDone range operation should append only the selected completed tasks to done.txt")
end

tests[#tests + 1] = function()
  local dir = tempdir .. "/archive-hidden-done-buffer"
  vim.fn.mkdir(dir, "p")
  local todo_path = dir .. "/todo.txt"
  local done_path = dir .. "/done.txt"
  write_file(todo_path, "alpha\nx 2026-03-18 hidden buffer case")
  write_file(done_path, "x 2026-03-17 existing")

  cleanup_windows()
  vim.cmd("badd " .. vim.fn.fnameescape(done_path))
  local done_buf = vim.fn.bufnr(done_path)
  vim.fn.bufload(done_buf)
  vim.cmd("silent edit " .. vim.fn.fnameescape(todo_path))
  vim.cmd("TodoTxtArchiveDone")

  assert_eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    "alpha",
  }, "TodoTxtArchiveDone should work when done.txt is loaded in a hidden buffer")
  assert_eq(read_file(done_path), {
    "x 2026-03-17 existing",
    "x 2026-03-18 hidden buffer case",
  }, "TodoTxtArchiveDone should append to a loaded hidden done.txt buffer")
end

tests[#tests + 1] = function()
  edit_file(make_file("batch-priority.todo.txt", "alpha\nbeta\ngamma"))
  vim.cmd("1,2TodoTxtPriorityPicker")
  ftplugin.apply_priority_picker("B")
  assert_eq(vim.api.nvim_buf_get_lines(0, 0, 3, false), {
    "(B) alpha",
    "(B) beta",
    "gamma",
  }, "TodoTxtPriorityPicker range operation failed")
end

tests[#tests + 1] = function()
  edit_file(make_file("batch-project.todo.txt", "alpha +Work\nbeta\ngamma"))
  vim.cmd("1,2TodoTxtProjectPicker")
  ftplugin.apply_token_picker("+Desk")
  assert_eq(vim.api.nvim_buf_get_lines(0, 0, 3, false), {
    "alpha +Work +Desk",
    "beta +Desk",
    "gamma",
  }, "TodoTxtProjectPicker range operation failed")
end

tests[#tests + 1] = function()
  edit_file(make_file("today.todo.txt", "ship feature"))
  vim.cmd("TodoTxtInsertToday")
  local today = os.date("%Y-%m-%d")
  assert_eq(vim.api.nvim_get_current_line(), today .. " ship feature", "failed to insert creation date")
  assert_eq(vim.api.nvim_win_get_cursor(0), { 1, 10 }, "cursor should land on the space after the inserted creation date")
  vim.cmd("TodoTxtInsertToday")
  assert_eq(vim.api.nvim_get_current_line(), "ship feature", "failed to remove creation date")
end

tests[#tests + 1] = function()
  edit_file(make_file("today-empty.todo.txt", ""))
  vim.cmd("TodoTxtInsertToday")
  local today = os.date("%Y-%m-%d")
  assert_eq(vim.api.nvim_get_current_line(), today .. " ", "failed to insert creation date on an empty line")
  assert_eq(vim.api.nvim_win_get_cursor(0), { 1, 10 }, "cursor should land on the space after the inserted creation date on an empty line")
  vim.cmd("TodoTxtInsertToday")
  assert_eq(vim.api.nvim_get_current_line(), "", "failed to remove creation date from an empty line")
end

tests[#tests + 1] = function()
  edit_file(make_file("today-priority.todo.txt", "(A) ship feature"))
  vim.cmd("TodoTxtInsertToday")
  local today = os.date("%Y-%m-%d")
  assert_eq(vim.api.nvim_get_current_line(), "(A) " .. today .. " ship feature", "failed to insert creation date on a prioritized task")
  assert_eq(vim.api.nvim_win_get_cursor(0), { 1, 14 }, "cursor should land on the space after the inserted creation date on a prioritized task")
end

tests[#tests + 1] = function()
  edit_file(make_file("due.todo.txt", "ship feature due:2026-03-19"))
  assert_eq(ftplugin.extract_due_date(vim.api.nvim_get_current_line()), "2026-03-19", "failed to extract due")
  assert_true(ftplugin.set_due_date_on_current_line("2026-03-21"), "failed to overwrite due")
  assert_eq(vim.api.nvim_get_current_line(), "ship feature due:2026-03-21", "due overwrite result is incorrect")
  vim.api.nvim_set_current_line("")
  assert_true(not ftplugin.set_due_date_on_current_line("2026-03-21"), "empty lines should not accept due")
end

tests[#tests + 1] = function()
  edit_file(make_file("token.todo.txt", "alpha +Work @home\nbeta +Side @office"))
  assert_eq(ftplugin.collect_tokens("+"), { "+Side", "+Work" }, "failed to collect project tokens")
  assert_eq(ftplugin.collect_tokens("@"), { "@home", "@office" }, "failed to collect context tokens")
  assert_eq(ftplugin.normalize_token("+", " + Foo Bar "), "+FooBar", "failed to normalize token")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert_true(ftplugin.insert_token_on_current_line("+Desk"), "failed to insert token")
  assert_eq(vim.api.nvim_get_current_line(), "alpha +Work @home +Desk", "token insert result is incorrect")
  assert_true(not ftplugin.insert_token_on_current_line("+Desk"), "duplicate token should not be inserted twice")
end

tests[#tests + 1] = function()
  edit_file(make_file("overdue.todo.txt", "todo due:2000-01-01\nx 2026-03-18 done due:2000-01-01"))
  ftplugin.refresh_overdue_due()
  local match_id = vim.api.nvim_win_get_var(0, "todotxt_overdue_match_id")
  assert_true(type(match_id) == "number" and match_id > 0, "overdue highlight was not created")
end

tests[#tests + 1] = function()
  local today = os.date("%Y-%m-%d")
  edit_file(make_file("today-due.todo.txt", "todo due:" .. today .. "\nnext due:2099-01-01"))
  ftplugin.refresh_overdue_due()
  local match_id = vim.api.nvim_win_get_var(0, "todotxt_today_due_match_id")
  assert_true(type(match_id) == "number" and match_id > 0, "today due highlight was not created")
end

tests[#tests + 1] = function()
  local fake_today = "2026-03-20"
  edit_file(make_file("day-rollover.todo.txt", "todo due:2026-03-20"))
  ftplugin._set_date_provider(function(format, time)
    if format == "%Y-%m-%d" and time == nil then
      return fake_today
    end
    return os.date(format, time)
  end)
  vim.g.todotxt_last_due_refresh_day = nil

  ftplugin.refresh_overdue_due()
  local today_match_id = vim.api.nvim_win_get_var(0, "todotxt_today_due_match_id")
  assert_true(type(today_match_id) == "number" and today_match_id > 0, "initial today-due highlight was not created")

  fake_today = "2026-03-21"
  assert_true(ftplugin.refresh_visible_todotxt_windows_if_day_changed(), "day rollover should refresh visible todo windows")

  local has_today_match = pcall(vim.api.nvim_win_get_var, 0, "todotxt_today_due_match_id")
  assert_true(not has_today_match, "today-due highlight should be cleared after day rollover")

  local overdue_match_id = vim.api.nvim_win_get_var(0, "todotxt_overdue_match_id")
  assert_true(type(overdue_match_id) == "number" and overdue_match_id > 0, "overdue highlight was not recreated after day rollover")

  ftplugin._set_date_provider(nil)
  vim.g.todotxt_last_due_refresh_day = nil
end

tests[#tests + 1] = function()
  edit_file(make_file("fold.todo.txt", "todo\nx 2026-03-18 done"))
  vim.cmd("TodoTxtTogglePendingOnly")
  assert_eq(vim.wo.foldmethod, "expr", "pending-only view did not switch to expr fold")
  assert_eq(vim.b.todotxt_pending_only, 1, "pending-only flag was not set")
  vim.cmd("TodoTxtTogglePendingOnly")
  assert_eq(vim.b.todotxt_pending_only, 0, "pending-only flag was not restored")
end

tests[#tests + 1] = function()
  edit_file(make_file("picker.todo.txt", "alpha +Work\nbeta +Side"))
  ftplugin.show_project_picker()
  local picker_buf = vim.api.nvim_get_current_buf()
  assert_eq(vim.bo.buftype, "nofile", "token picker did not open a scratch buffer")
  assert_eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "+Side", "+Work" }, "token picker list is incorrect")
  ftplugin.apply_token_picker("+Side")
  assert_eq(vim.api.nvim_get_current_line(), "alpha +Work +Side", "picker failed to apply token")
  assert_eq(vim.bo.filetype, "todotxt", "did not return to the source buffer after closing the picker")
end

tests[#tests + 1] = function()
  assert_true(ftplugin.is_leap_year(2024), "leap year detection failed")
  assert_true(not ftplugin.is_leap_year(2025), "common year detection failed")
  assert_eq(ftplugin.days_in_month(2, 2024), 29, "February day count is wrong in a leap year")
  assert_eq(ftplugin.days_in_month(2, 2025), 28, "February day count is wrong in a common year")
end

tests[#tests + 1] = function()
  local current_month = tonumber(os.date("%m"))
  local current_year = tonumber(os.date("%Y"))
  local current_month_text = os.date("%B")
  local current_date_prefix = string.format("%04d-%02d-", current_year, current_month)
  local days_in_month = ftplugin.days_in_month(current_month, current_year)

  edit_file(make_file("calendar.todo.txt", "ship feature due:" .. current_date_prefix .. "20"))
  local original = ftplugin.get_calendar_lines
  local today = tonumber(os.date("%d"))
  ftplugin.get_calendar_lines = function()
    local lines = {
      string.format("     %s %d", current_month_text, current_year),
      "Su Mo Tu We Th Fr Sa",
    }

    local row = {}
    for day = 1, days_in_month do
      row[#row + 1] = string.format("%2d", day)
      if #row == 7 or day == days_in_month then
        lines[#lines + 1] = table.concat(row, " ")
        row = {}
      end
    end

    return lines
  end

  ftplugin.render_calendar(current_month, current_year)
  local calendar_win, calendar_buf = find_calendar_window()
  assert_true(calendar_win ~= nil and calendar_buf ~= nil, "calendar popup was not opened")
  assert_eq(vim.bo.filetype, "todotxt", "opening the calendar should not move focus away from the source buffer")
  assert_eq(vim.bo[calendar_buf].filetype, "calendar", "calendar popup buffer has the wrong filetype")
  assert_eq(vim.bo[calendar_buf].syntax, "OFF", "calendar popup should not enable the built-in calendar syntax")
  assert_eq(vim.api.nvim_buf_get_var(calendar_buf, "todotxt_calendar_selected_day"), today, "calendar should select today by default")
  ftplugin.calendar_move(1)
  assert_eq(vim.api.nvim_buf_get_var(calendar_buf, "todotxt_calendar_selected_day"), today + 1, "calendar movement failed")
  ftplugin.calendar_apply_due()
  assert_eq(vim.bo.filetype, "todotxt", "did not return to the original buffer after applying the date")
  assert_eq(vim.api.nvim_get_current_line(), "ship feature due:" .. current_date_prefix .. string.format("%02d", today + 1), "calendar failed to write back due")
  assert_true(not vim.api.nvim_win_is_valid(calendar_win), "calendar popup was not closed after applying the date")

  ftplugin.get_calendar_lines = original
end

tests[#tests + 1] = function()
  local current_month = tonumber(os.date("%m"))
  local current_year = tonumber(os.date("%Y"))
  local current_month_text = os.date("%B")
  local current_date_prefix = string.format("%04d-%02d-", current_year, current_month)
  local days_in_month = ftplugin.days_in_month(current_month, current_year)

  edit_file(make_file("calendar-range.todo.txt", "alpha due:" .. current_date_prefix .. "20\nbeta due:" .. current_date_prefix .. "21\ngamma"))
  local original = ftplugin.get_calendar_lines
  local today = tonumber(os.date("%d"))
  ftplugin.get_calendar_lines = function()
    local lines = {
      string.format("     %s %d", current_month_text, current_year),
      "Su Mo Tu We Th Fr Sa",
    }

    local row = {}
    for day = 1, days_in_month do
      row[#row + 1] = string.format("%2d", day)
      if #row == 7 or day == days_in_month then
        lines[#lines + 1] = table.concat(row, " ")
        row = {}
      end
    end

    return lines
  end

  vim.cmd("1,2TodoTxtShowCalendar")
  local calendar_win = find_calendar_window()
  assert_true(calendar_win ~= nil, "range calendar popup was not opened")
  assert_eq(calendar_win, vim.api.nvim_get_current_win(), "range calendar should receive focus immediately")
  ftplugin.calendar_move(1)
  ftplugin.calendar_apply_due()
  assert_eq(vim.api.nvim_buf_get_lines(0, 0, 3, false), {
    "alpha due:" .. current_date_prefix .. string.format("%02d", today + 1),
    "beta due:" .. current_date_prefix .. string.format("%02d", today + 1),
    "gamma",
  }, "TodoTxtShowCalendar range write-back failed")

  ftplugin.get_calendar_lines = original
end

local ok, err = xpcall(function()
  for index, test in ipairs(tests) do
    test()
    print(string.format("ok %d", index))
  end
end, debug.traceback)

cleanup_windows()
vim.fn.delete(tempdir, "rf")

if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
  return
end

print(string.format("passed %d tests", #tests))
vim.cmd("qa!")
