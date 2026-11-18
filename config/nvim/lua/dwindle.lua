-- dwindle: tiling splits plus go-to-definition in a new split.
-- <C-w><CR> makes a new split. gd opens the definition in a new split.
-- Split direction alternates by window count:
-- 1 window -> side-by-side split, 2 windows -> top-bottom split, then repeat.
local M = {}

local function normal_win_count()
    local count = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local ok, config = pcall(vim.api.nvim_win_get_config, win)
        if ok and config.relative == "" then
            count = count + 1
        end
    end
    return count
end

local function next_split_cmd()
    if normal_win_count() % 2 == 1 then
        return "vsplit"
    end
    return "split"
end

function M.split()
    vim.cmd(next_split_cmd())
end

---@param bufnr integer
---@param lnum integer|nil 1-based line
---@param col integer|nil 0-based column
function M.open(bufnr, lnum, col)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        vim.notify("dwindle: invalid buffer", vim.log.levels.ERROR)
        return
    end
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        pcall(vim.fn.bufload, bufnr)
    end
    lnum = lnum or 1
    col = col or 0
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    lnum = math.min(math.max(lnum, 1), math.max(line_count, 1))

    vim.cmd(next_split_cmd())
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
    pcall(vim.cmd, "normal! zz")
end

---@param loc table LSP Location or LocationLink
function M.open_location(loc)
    local uri = loc.uri or loc.targetUri
    if not uri then
        vim.notify("dwindle: definition has no file", vim.log.levels.WARN)
        return
    end
    local range = loc.range or loc.targetSelectionRange or loc.targetRange
    if not range then
        vim.notify("dwindle: definition has no range", vim.log.levels.WARN)
        return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    M.open(bufnr, range.start.line + 1, range.start.character or 0)
end

---@param path string
---@param anchor string|nil key name to search for (e.g. OpenAPI $ref anchor)
local function open_file_in_split(path, anchor)
    local bufnr = vim.fn.bufadd(path)
    pcall(vim.fn.bufload, bufnr)
    local lnum = 1
    if anchor and anchor ~= "" then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local pattern = "^%s*" .. vim.fn.escape(anchor, "\\") .. "%s*:"
        for i, text in ipairs(lines) do
            if text:match(pattern) then
                lnum = i
                break
            end
        end
    end
    M.open(bufnr, lnum, 0)
end

function M.goto_definition()
    -- Keep the OpenAPI $ref shortcut, but open the target in a split.
    local line = vim.api.nvim_get_current_line()
    local ref = line:match("%$ref:%s*['\"]([^'\"]+)['\"]")
    if ref then
        local file, anchor = ref:match("^(.-)#(.*)$")
        if anchor then
            anchor = anchor:match("[^/]+$")
        end
        if file and file ~= "" then
            local base = vim.fn.expand("%:h")
            open_file_in_split(base .. "/" .. file, anchor)
            return
        elseif anchor and anchor ~= "" then
            open_file_in_split(vim.api.nvim_buf_get_name(0), anchor)
            return
        end
    end

    local clients = vim.lsp.get_clients({ bufnr = 0 })
    local supported = false
    for _, client in ipairs(clients) do
        if client.supports_method("textDocument/definition") then
            supported = true
            break
        end
    end
    if not supported then
        -- No LSP here: split first so the current view stays, then use gd.
        M.split()
        pcall(vim.cmd, "normal! gd")
        return
    end

    local encoding = (clients[1] and clients[1].offset_encoding) or "utf-8"
    local params = vim.lsp.util.make_position_params(0, encoding)
    vim.lsp.buf_request(0, "textDocument/definition", params, function(err, result)
        vim.schedule(function()
            if err then
                vim.notify("dwindle: " .. tostring(err.message or err), vim.log.levels.ERROR)
                return
            end
            if not result or vim.tbl_isempty(result) then
                vim.notify("No definition found", vim.log.levels.INFO)
                return
            end
            local locs = result
            if result.uri or result.targetUri then
                locs = { result }
            end
            if #locs == 1 then
                M.open_location(locs[1])
                return
            end
            local items = {}
            for i, loc in ipairs(locs) do
                local uri = loc.uri or loc.targetUri or ""
                local fname = uri ~= "" and vim.fn.fnamemodify(vim.uri_to_fname(uri), ":~:.") or "?"
                local range = loc.range or loc.targetSelectionRange or loc.targetRange
                local lnum = range and (range.start.line + 1) or 1
                items[i] = string.format("%d: %s:%d", i, fname, lnum)
            end
            vim.ui.select(items, { prompt = "Definition:" }, function(_, idx)
                if idx then
                    M.open_location(locs[idx])
                end
            end)
        end)
    end)
end

return M
