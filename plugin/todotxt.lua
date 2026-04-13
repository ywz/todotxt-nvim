if vim.g.loaded_todotxt_plugin then
  return
end

vim.g.loaded_todotxt_plugin = true
local uv = vim.uv or vim.loop
local rollover_timer

require("todotxt").setup()

local group = vim.api.nvim_create_augroup("todotxt_plugin", { clear = true })

local function setup_todotxt_buffer(args)
  if vim.bo[args.buf].filetype ~= "todotxt" then
    return
  end

  vim.api.nvim_buf_call(args.buf, function()
    require("todotxt.ftplugin").setup()
  end)
end

local function setup_existing_todotxt_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "todotxt" then
      setup_todotxt_buffer({ buf = buf })
    end
  end
end

local function refresh_due_highlights_for_day_change()
  local ok, ftplugin = pcall(require, "todotxt.ftplugin")
  if not ok then
    return
  end

  ftplugin.refresh_visible_todotxt_windows_if_day_changed()
end

local function stop_rollover_timer()
  if not rollover_timer then
    return
  end

  rollover_timer:stop()
  rollover_timer:close()
  rollover_timer = nil
end

local function milliseconds_until_next_day()
  local now = os.time()
  local next_day = os.time({
    year = tonumber(os.date("%Y", now)),
    month = tonumber(os.date("%m", now)),
    day = tonumber(os.date("%d", now)) + 1,
    hour = 0,
    min = 0,
    sec = 1,
  })

  return math.max(1000, (next_day - now) * 1000)
end

local function schedule_rollover_refresh()
  if not uv then
    return
  end

  stop_rollover_timer()
  rollover_timer = uv.new_timer()
  if not rollover_timer then
    return
  end

  rollover_timer:start(milliseconds_until_next_day(), 0, vim.schedule_wrap(function()
    refresh_due_highlights_for_day_change()
    schedule_rollover_refresh()
  end))
end

vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
  group = group,
  pattern = "*",
  callback = setup_todotxt_buffer,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  callback = setup_existing_todotxt_buffers,
})

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = setup_existing_todotxt_buffers,
})

vim.api.nvim_create_autocmd("FocusGained", {
  group = group,
  callback = refresh_due_highlights_for_day_change,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = stop_rollover_timer,
})

setup_existing_todotxt_buffers()
schedule_rollover_refresh()
