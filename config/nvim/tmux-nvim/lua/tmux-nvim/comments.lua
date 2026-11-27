local M = {}
M.ns = vim.api.nvim_create_namespace("tmux-nvim-comments")

-- id -> { bufnr, extmark, file, start_line, end_line, text, created_at }
local store = {}
local next_id = 1

local function data_file()
  return vim.fn.stdpath("data") .. "/tmux-nvim-comments.json"
end

local function resolve(id)
  local e = store[id]
  if not e then return nil end
  if e.bufnr and e.extmark and vim.api.nvim_buf_is_valid(e.bufnr) then
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, e.bufnr, M.ns, e.extmark, { details = true })
    if ok and pos and #pos > 0 then
      local start_line = pos[1] + 1
      local end_line = pos[3] and pos[3].end_row or (pos[1] + 1)
      if end_line < start_line then end_line = start_line end
      return {
        id = id,
        bufnr = e.bufnr,
        file = e.file ~= "" and e.file or vim.api.nvim_buf_get_name(e.bufnr),
        start_line = start_line,
        end_line = end_line,
        text = e.text,
        created_at = e.created_at,
      }
    end
  end
  -- Not attached (nvim restarted, buffer not open): use saved lines.
  if not e.file or e.file == "" then return nil end
  return {
    id = id,
    bufnr = e.bufnr,
    file = e.file,
    start_line = e.start_line,
    end_line = e.end_line,
    text = e.text,
    created_at = e.created_at,
  }
end

local function persist()
  local out = { next_id = next_id, comments = {} }
  for id in pairs(store) do
    local c = resolve(id)
    if c and c.file ~= "" then
      table.insert(out.comments, {
        id = id,
        file = c.file,
        start_line = c.start_line,
        end_line = c.end_line,
        text = c.text,
        created_at = c.created_at,
      })
    end
  end
  pcall(function()
    vim.fn.writefile({ vim.json.encode(out) }, data_file())
  end)
end

local function load_from_disk()
  local ok, lines = pcall(vim.fn.readfile, data_file())
  if not ok or not lines or #lines == 0 then return end
  local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok2 or type(data) ~= "table" then return end
  if type(data.next_id) == "number" then next_id = data.next_id end
  if type(data.comments) ~= "table" then return end
  for _, c in ipairs(data.comments) do
    if type(c) == "table" and c.file and c.file ~= "" and c.text then
      local id = type(c.id) == "number" and c.id or next_id
      if store[id] then id = next_id end
      if id >= next_id then next_id = id + 1 end
      store[id] = {
        bufnr = nil,
        extmark = nil,
        file = c.file,
        start_line = type(c.start_line) == "number" and c.start_line or 1,
        end_line = type(c.end_line) == "number" and c.end_line or (c.start_line or 1),
        text = c.text,
        created_at = type(c.created_at) == "number" and c.created_at or os.time(),
      }
    end
  end
end

function M.add(bufnr, start_line, end_line, text)
  local id = next_id
  next_id = next_id + 1
  local file = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
  local extmark = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    extmark = vim.api.nvim_buf_set_extmark(bufnr, M.ns, start_line - 1, 0, {
      end_row = end_line,
      end_col = 0,
      right_gravity = false,
      end_right_gravity = true,
    })
  end
  store[id] = { bufnr = bufnr, extmark = extmark, file = file, start_line = start_line, end_line = end_line, text = text, created_at = os.time() }
  persist()
  return id
end

function M.get(id) return resolve(id) end

function M.list()
  local out = {}
  for id in pairs(store) do
    local c = resolve(id)
    if c then table.insert(out, c) end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function M.edit(id, new_text)
  if not store[id] then return false end
  store[id].text = new_text
  persist()
  return true
end

function M.delete(id)
  local e = store[id]
  if not e then return false end
  if e.bufnr and e.extmark and vim.api.nvim_buf_is_valid(e.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, e.bufnr, M.ns, e.extmark)
  end
  store[id] = nil
  persist()
  return true
end

function M.clear()
  for id in pairs(store) do M.delete(id) end
end

-- Save now. Called on buffer write and on exit so line moves are kept.
function M.flush() persist() end

-- Create tracking extmarks for saved comments that match this buffer.
-- Returns the list of attached comment ids.
function M.attach(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return {} end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then return {} end
  local attached = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for id, e in pairs(store) do
    if e.file == name then
      local valid = false
      if e.bufnr == bufnr and e.extmark then
        local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, M.ns, e.extmark, {})
        valid = ok and pos and #pos > 0
      end
      if not valid then
        local s = math.min(math.max(1, e.start_line or 1), math.max(1, line_count))
        local en = math.min(math.max(s, e.end_line or s), math.max(1, line_count))
        local ok, mark = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, s - 1, 0, {
          end_row = en,
          end_col = 0,
          right_gravity = false,
          end_right_gravity = true,
        })
        if ok and mark then
          e.bufnr = bufnr
          e.extmark = mark
          e.start_line = s
          e.end_line = en
        end
      else
        e.bufnr = bufnr
      end
      table.insert(attached, id)
    end
  end
  return attached
end

function M.snippet(id)
  local c = resolve(id)
  if not c then return nil end
  if not c.bufnr or not vim.api.nvim_buf_is_valid(c.bufnr) then return {} end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, c.bufnr, c.start_line - 1, c.end_line, false)
  if not ok then return {} end
  return lines
end

load_from_disk()

return M
