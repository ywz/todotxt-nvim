# todotxt-nvim

A lightweight `todo.txt` plugin for Neovim, now fully implemented in Lua, with:

- `todo.txt` / `done.txt` filetype detection
- `todo.txt` syntax highlighting
- overdue `due:` highlighting
- buffer-local keymaps for `todo.txt`
- a floating calendar for the current month

## Repository Layout

```text
.
├── .github/workflows/   # GitHub Actions CI
├── lua/todotxt/         # Lua modules
├── plugin/              # Neovim plugin entrypoint
├── stylua.toml          # Lua formatting rules
├── tests/               # Headless regression tests
├── CONTRIBUTORS.md      # Contributors
├── LICENSE              # MIT license
└── README.md            # Project documentation
```

## Installation

### lazy.nvim

Use the GitHub repository directly:

```lua
{
  "ywz/todotxt-nvim",
  name = "todotxt-nvim",
  lazy = false,
  config = function()
    require("todotxt").setup()
  end,
}
```

Do not use:

```lua
{
  "ywz/todotxt-nvim",
  name = "todotxt-nvim",
  ft = { "todotxt" },
}
```

The plugin's Lua entrypoint is what detects the `todotxt` filetype in the first place, so lazy-loading it by `ft` creates a circular dependency.

## File Detection

The following files are recognized as `todotxt`:

```lua
vim.filetype.add({
  extension = { todotxt = "todotxt" },
  filename = {
    ["todo.txt"] = "todotxt",
    ["done.txt"] = "todotxt",
  },
  pattern = {
    [".*%.todo%.txt"] = { "todotxt", { priority = 100 } },
    [".*%.done%.txt"] = { "todotxt", { priority = 100 } },
  },
})
```

## Syntax Highlighting

The default theme is based on a dark Kitty-inspired palette. It does not rely on `link` to external highlight groups. Instead, it assigns colors directly to the `todotxt*` groups.

The following elements are highlighted:

- completion marker: `x`
- completion date: `x YYYY-MM-DD ...`
- creation date: `(A) YYYY-MM-DD ...`, `YYYY-MM-DD ...`, `x YYYY-MM-DD YYYY-MM-DD ...`
- priority: `(A)`, `(B)`, `(C)`
- lowest priority `(Z)`: the entire line is rendered in `#c4c6cd` instead of keeping separate highlighting for project, context, `due:`, and so on
- project: `+Work`
- context: `@phone`
- `due:` tag: `due:2026-03-19`
- today's `due:`: uses the same color as `due:` but with bold emphasis
- `pri:` tag: `pri:B`
- other valid extended key-value pairs: `rec:2026-03-20`, `t:now`
  Rule: only a single `:` is allowed, and neither `key` nor `value` may contain whitespace or extra `:`
- overdue `due:`: uses a dedicated warning color

If you want to override the default theme, see the semantic groups in [lua/todotxt/theme.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/theme.lua). You can also override only part of the theme in your own config:

```lua
require("todotxt").setup({
  theme = {
    todotxtProject = { fg = "#a6dbff", bold = true },
    todotxtContext = { fg = "#a6dbff" },
    todotxtOverdueDue = { fg = "#ffc0b9", bg = "#590008", bold = true },
  },
})
```

Core rules live in:

- [lua/todotxt/syntax.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/syntax.lua)
- [lua/todotxt/theme.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/theme.lua)
- [plugin/todotxt.lua](/Users/wz/copilot/todotxt-nvim/plugin/todotxt.lua)
- [lua/todotxt/ftplugin.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/ftplugin.lua)

## Keymaps

These keymaps are only active in `todotxt` buffers.
In normal mode they operate on the current line. In visual-line mode, select multiple lines with `V` and use the same keymap to apply the action to the whole range.

### Task Actions

- `<leader>tx`
  Mark the current line as completed, turning it into `x YYYY-MM-DD ...`

- `<leader>tq`
  Archive completed tasks to `done.txt`
  In normal mode it scans the whole current buffer; in visual-line mode it only scans the selected range
  Matching `x YYYY-MM-DD ...` lines are removed from the source file, appended to `done.txt` in the same directory, and both files are written immediately
  If `done.txt` does not exist yet, it is created automatically

- `<leader>ta`
  Open the priority picker
  Only five options are available: `(A) / (B) / (C) / (Z) / Space`
  The cursor starts on `(A)`; pressing `k` or the Up arrow on `(A)` wraps to the trailing space entry
  The selected item inserts or replaces the current priority; choosing Space clears the existing priority

- `<leader>td`
  Toggle the creation date in `YYYY-MM-DD` format
  If the task has no creation date, one is inserted in the correct `todo.txt` position; if it already has one, it is removed

- `<leader>tb`
  Toggle pending-only view
  Completed tasks are folded away until you toggle it again

- `<leader>t+`
  Open the `+Project` picker
  Use Up/Down or `j/k` to select an existing project and press Enter to insert it; press `a` or `i` to create a new one

- `<leader>t@`
  Open the `@Context` picker
  Use Up/Down or `j/k` to select an existing context and press Enter to insert it; press `a` or `i` to create a new one

### Calendar

- `<leader>tc`
  Open a floating calendar for the current month

Inside the calendar:

- `h`
  Select the previous day

- `l`
  Select the next day

- `k`
  Select the same weekday in the previous week

- `j`
  Select the same weekday in the next week

- `←/→/↑/↓`
  Same behavior as `h/j/k/l` for moving the selected day

- `<CR>`
  Write the selected date back to the original task as `due:YYYY-MM-DD`
  If the task already has `due:`, it is replaced directly

- `q`
  Close the floating window

- `<Esc>`
  Close the floating window

Today in the current month is highlighted separately.

## Commands

```vim
TodoTxtDone
TodoTxtArchiveDone
TodoTxtPriorityUp
TodoTxtPriorityPicker
TodoTxtInsertToday
TodoTxtShowCalendar
TodoTxtProjectPicker
TodoTxtContextPicker
TodoTxtTogglePendingOnly
```

## Tests

The project includes a headless Neovim regression suite covering:

- filetype detection
- syntax group loading
- completed tasks, priorities, creation dates, and `due:` updates
- archiving completed tasks into `done.txt`
- project/context token collection and picker write-back
- overdue highlighting
- pending-only task folding
- calendar write-back to tasks

Run it with:

```sh
nvim --headless -u NONE -i NONE -n -c 'lua dofile("tests/run.lua")'
```

Format Lua code with StyLua:

```sh
stylua .
```

## License

MIT. See [LICENSE](/Users/wz/copilot/todotxt-nvim/LICENSE).

## Contributors

See [CONTRIBUTORS.md](/Users/wz/copilot/todotxt-nvim/CONTRIBUTORS.md).

## Implementation Notes

Filetype detection is implemented in [plugin/todotxt.lua](/Users/wz/copilot/todotxt-nvim/plugin/todotxt.lua) and [lua/todotxt/init.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/init.lua):

```lua
require("todotxt").setup()
```

Syntax highlighting lives in [lua/todotxt/syntax.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/syntax.lua), for example:

```lua
vim.api.nvim_set_hl(0, "todotxtProject", { fg = 0xA6DBFF, bold = false })
vim.api.nvim_set_hl(0, "todotxtContext", { fg = 0x8CF8F7, bold = true })
vim.api.nvim_set_hl(0, "todotxtTodayDue", { fg = 0xFCE094, bold = true })
vim.api.nvim_set_hl(0, "todotxtOverdueDue", { fg = 0xFFC0B9, bg = 0x590008, bold = true })
```

The interaction entrypoint is [plugin/todotxt.lua](/Users/wz/copilot/todotxt-nvim/plugin/todotxt.lua), and the core behavior lives in [lua/todotxt/ftplugin.lua](/Users/wz/copilot/todotxt-nvim/lua/todotxt/ftplugin.lua), for example:

```lua
vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
  pattern = "*",
  callback = function(args)
    if vim.bo[args.buf].filetype == "todotxt" then
      require("todotxt.ftplugin").setup()
    end
  end,
})
```

The floating calendar depends on the system `cal` or `ncal` command.
