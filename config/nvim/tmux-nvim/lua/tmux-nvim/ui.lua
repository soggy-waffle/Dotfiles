local M = {}
local comments = require("tmux-nvim.comments")
local draft = ""

vim.api.nvim_set_hl(0, "TmuxNvimCommentSign", { default = true, fg = "#d7a65f", bold = true })
vim.api.nvim_set_hl(0, "TmuxNvimCommentText", { default = true, fg = "#d7a65f" })
vim.api.nvim_set_hl(0, "TmuxNvimCommentLine", { default = true, link = "CursorLine" })

local decorations = {}

function M.visual_range()
  local s = vim.api.nvim_buf_get_mark(0, "<")[1]
  local e = vim.api.nvim_buf_get_mark(0, ">")[1]
  if s > e then s, e = e, s end
  return s, e
end

-- centered floating input, rounded border, title, wrap, q to close, :w to save
function M.input_comment(on_done, opts)
  opts = opts or {}
  local title = opts.title or " Tmux Comment "
  local default = opts.default
  if default == nil then default = draft end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "tmux-nvim-comment") -- :w needs a name or it raises E32
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false

  local width = 60
  local height = 6
  local row = math.floor((vim.o.lines - height) / 2 - 1)
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, row),
    col = math.max(0, col),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = { { " :w save · :wq save+close · q close (keep draft) · :q discard ", "Comment" } },
    footer_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

  if default ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(default, "\n", { plain = true }))
  end
  vim.cmd("startinsert")

  local closed = false

  local function buffer_text()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return table.concat(lines, "\n")
  end

  local function close(kind)
    if closed then return end
    closed = true
    if kind == "preserve" then
      local text = vim.trim(buffer_text())
      if text ~= "" then draft = buffer_text() end
    elseif kind == "discard" or kind == "saved" then
      draft = ""
    end
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  -- :w saves (adds the comment) and keeps the box open.
  -- :wq / :x / ZZ save, then quit the window; WinClosed below cleans up.
  -- q / <Esc> close and keep draft; :q discards draft.
  local function save()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, "\n"))
    if text == "" then
      vim.notify("tmux-nvim: comment is empty", vim.log.levels.ERROR)
      vim.bo[buf].modified = false
      return
    end
    on_done(text)
    draft = ""
    -- clear the input so a second :w starts a fresh comment
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modified = false
  end

  vim.keymap.set("n", "q", function() close("preserve") end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function() close("preserve") end, { buffer = buf, nowait = true, silent = true })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = save,
  })
  -- <C-s> saves like :w (no close)
  vim.keymap.set({ "n", "i" }, "<C-s>", save, { buffer = buf, silent = true })

  -- :q / :wq / :q! — draft cleared (save() already cleared it for :wq)
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer = buf,
    callback = function()
      if closed then return end
      close("discard")
    end,
  })

  -- if user force-closes window, wipe buffer
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not closed then
        closed = true
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
      end
    end,
  })
end

-- Split text into screen lines of max `width` display cells.
-- Keeps words together. Splits a word only if the word is too long.
local function wrap_text(text, width)
  width = math.max(20, width or 60)
  local out = {}
  for _, para in ipairs(vim.split(text, "\n", { plain = true })) do
    if para == "" then
      out[#out + 1] = ""
    else
      local cur = ""
      for word in para:gmatch("%S+") do
        if cur == "" then
          if vim.fn.strdisplaywidth(word) <= width then
            cur = word
          else
            -- word too long: hard split it
            local part = ""
            for _, code in ipairs(vim.fn.str2list(word, true)) do
              local ch = vim.fn.nr2char(code)
              if vim.fn.strdisplaywidth(part .. ch) > width then
                out[#out + 1] = part
                part = ch
              else
                part = part .. ch
              end
            end
            if part ~= "" then out[#out + 1] = part end
          end
        elseif vim.fn.strdisplaywidth(cur .. " " .. word) <= width then
          cur = cur .. " " .. word
        else
          out[#out + 1] = cur
          cur = word
        end
      end
      if cur ~= "" then out[#out + 1] = cur end
    end
  end
  if #out == 0 then out = { "" } end
  return out
end

-- One virt line per wrapped line, so long comments use many
-- virtual lines and never run off the screen.
function M._callout(text, width)
  local lines = wrap_text(text, width)
  local virt = {}
  for i, line in ipairs(lines) do
    local prefix = i == 1 and "╭─ 💬 " or "│  "
    virt[#virt + 1] = { { prefix, "TmuxNvimCommentSign" }, { line, "TmuxNvimCommentText" } }
  end
  return virt
end

function M.decorate(id)
  if decorations[id] then return end
  local c = comments.get(id)
  if not c then return end
  if not c.bufnr or not vim.api.nvim_buf_is_valid(c.bufnr) then return end
  local ns = comments.ns
  local bars = {}
  local ok_bars, _ = pcall(function()
    for line = c.start_line, c.end_line do
      bars[#bars + 1] = vim.api.nvim_buf_set_extmark(c.bufnr, ns, line - 1, 0, {
        sign_text = "▌",
        sign_hl_group = "TmuxNvimCommentSign",
        line_hl_group = "TmuxNvimCommentLine",
        right_gravity = false,
      })
    end
  end)
  if not ok_bars then return end
  -- content width follows the code window width
  local winid = vim.fn.bufwinid(c.bufnr)
  if winid == -1 then winid = vim.api.nvim_get_current_win() end
  local win_width = 60
  pcall(function() win_width = vim.api.nvim_win_get_width(winid) end)
  local content_width = math.min(math.max(win_width - 8, 20), 100)
  local callout = vim.api.nvim_buf_set_extmark(c.bufnr, ns, c.start_line - 1, 0, {
    virt_lines = M._callout(c.text, content_width),
    virt_lines_above = true,
  })
  decorations[id] = { bars = bars, callout = callout, bufnr = c.bufnr }
end

function M.undecorate(id)
  local marks = decorations[id]
  if marks and vim.api.nvim_buf_is_valid(marks.bufnr) then
    for _, bar in ipairs(marks.bars) do
      vim.api.nvim_buf_del_extmark(marks.bufnr, comments.ns, bar)
    end
    vim.api.nvim_buf_del_extmark(marks.bufnr, comments.ns, marks.callout)
  end
  decorations[id] = nil
end

-- Single safe row for the list buffer (no newline chars).
function M.comment_row(c)
  local one = c.text:gsub("\n", " ⏎ ")
  return string.format("%s:%d-%d  %s", vim.fn.fnamemodify(c.file, ":t"), c.start_line, c.end_line, one)
end

function M.comment_list(handlers)
  local code_win = vim.api.nvim_get_current_win()
  local rows = comments.list()
  if #rows == 0 then
    vim.notify("tmux-nvim: no comments", vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "tmux-nvim-comments"

  local function win_config()
    local width = 46
    for _, c in ipairs(rows) do
      local head = string.format("%s:%d-%d  %s", vim.fn.fnamemodify(c.file, ":t"), c.start_line, c.end_line,
        c.text:gsub("\n", " ⏎ "):sub(1, 60))
      width = math.max(width, vim.fn.strdisplaywidth(head) + 2)
    end
    width = math.min(width, 100, math.max(46, vim.o.columns - 6))
    local height = math.max(1, math.min(#rows, 12))
    return {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, vim.o.lines - height - 4),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      style = "minimal",
      border = "rounded",
      title = { { " 💬 Comments ", "TmuxNvimCommentText" } },
      title_pos = "center",
      footer = { { " ↑↓ jump  ·  ⏎ edit  ·  d delete  ·  q close ", "Comment" } },
      footer_pos = "center",
    }
  end

  local win = vim.api.nvim_open_win(buf, true, win_config())
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local function render()
    rows = comments.list()
    if #rows == 0 then
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      return false
    end
    local lines = {}
    for _, c in ipairs(rows) do lines[#lines + 1] = M.comment_row(c) end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_config(win, win_config()) end
    return true
  end

  local function current()
    if not vim.api.nvim_win_is_valid(win) then return nil end
    return rows[vim.api.nvim_win_get_cursor(win)[1]]
  end

  local function preview()
    local c = current()
    if not c or not vim.api.nvim_win_is_valid(code_win) or not vim.api.nvim_buf_is_valid(c.bufnr) then return end
    if not pcall(vim.api.nvim_win_set_buf, code_win, c.bufnr) then return end
    local line = math.min(c.start_line, math.max(1, vim.api.nvim_buf_line_count(c.bufnr)))
    vim.api.nvim_win_set_cursor(code_win, { line, 0 })
    vim.api.nvim_win_call(code_win, function() vim.cmd("normal! zz") end)
  end

  render()
  preview()
  local grp = vim.api.nvim_create_augroup("TmuxNvimCommentList" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", { group = grp, buffer = buf, callback = preview })

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("q", close)
  map("<Esc>", close)
  map("<CR>", function()
    local c = current()
    if c then handlers.edit(c, function() if render() then preview() end end) end
  end)
  local function del()
    local c = current()
    if c then
      handlers.delete(c)
      if render() then preview() end
    end
  end
  map("d", del)
end

return M
