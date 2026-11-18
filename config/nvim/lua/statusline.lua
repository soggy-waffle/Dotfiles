-- statusline: clean transparent global statusline.
-- Shows mode, file path, filetype, line, column, percent.
local M = {}

local modes = {
    n = { name = "NORMAL", hl = "StatusLineModeNormal" },
    no = { name = "NORMAL", hl = "StatusLineModeNormal" },
    nov = { name = "NORMAL", hl = "StatusLineModeNormal" },
    noV = { name = "NORMAL", hl = "StatusLineModeNormal" },
    i = { name = "INSERT", hl = "StatusLineModeInsert" },
    ic = { name = "INSERT", hl = "StatusLineModeInsert" },
    ix = { name = "INSERT", hl = "StatusLineModeInsert" },
    v = { name = "VISUAL", hl = "StatusLineModeVisual" },
    vs = { name = "VISUAL", hl = "StatusLineModeVisual" },
    V = { name = "V-LINE", hl = "StatusLineModeVisual" },
    Vs = { name = "V-LINE", hl = "StatusLineModeVisual" },
    ["\22"] = { name = "V-BLOCK", hl = "StatusLineModeVisual" },
    ["\22s"] = { name = "V-BLOCK", hl = "StatusLineModeVisual" },
    R = { name = "REPLACE", hl = "StatusLineModeReplace" },
    Rc = { name = "REPLACE", hl = "StatusLineModeReplace" },
    Rx = { name = "REPLACE", hl = "StatusLineModeReplace" },
    c = { name = "COMMAND", hl = "StatusLineModeCommand" },
    cv = { name = "COMMAND", hl = "StatusLineModeCommand" },
    ce = { name = "COMMAND", hl = "StatusLineModeCommand" },
    t = { name = "TERMINAL", hl = "StatusLineModeTerminal" },
    ["!"] = { name = "SHELL", hl = "StatusLineModeTerminal" },
    s = { name = "SELECT", hl = "StatusLineModeVisual" },
    S = { name = "SELECT", hl = "StatusLineModeVisual" },
    ["\19"] = { name = "SELECT", hl = "StatusLineModeVisual" },
}

function M.render()
    local mode_info = modes[vim.api.nvim_get_mode().mode] or { name = "NORMAL", hl = "StatusLineModeNormal" }
    local path = vim.fn.expand("%:p:~:.")
    if path == "" then
        path = "[No Name]"
    end
    local flags = ""
    if vim.bo.modified then
        flags = flags .. " [+]"
    end
    if vim.bo.readonly then
        flags = flags .. " [RO]"
    end
    local ft = vim.bo.filetype
    if ft == "" then
        ft = "-"
    end
    local line = vim.fn.line(".")
    local total = vim.fn.line("$")
    local pct = total > 0 and math.floor(line / total * 100) or 0
    path = path:gsub("%%", "%%%%")
    flags = flags:gsub("%%", "%%%%")
    ft = ft:gsub("%%", "%%%%")
    return string.format(
        "%%#%s# %s %%#StatusLinePath#%s%s %%#StatusLine#%%=%%#StatusLineMeta#%s %%l:%%c %d%%%% ",
        mode_info.hl,
        mode_info.name,
        path,
        flags,
        ft,
        pct
    )
end

M.visible = false

-- Hide the bar. laststatus=0 alone still leaves a bar on some splits
-- (see neovim/neovim#18965), so turn the leftover bars into plain lines.
function M.hide()
    M.visible = false
    vim.o.laststatus = 0
    vim.o.statusline = "%{repeat('─',winwidth('.'))}"
    vim.api.nvim_set_hl(0, "StatusLine", { link = "WinSeparator" })
    vim.api.nvim_set_hl(0, "StatusLineNC", { link = "WinSeparator" })
end

function M.show()
    M.visible = true
    vim.o.laststatus = 3
    vim.o.statusline = "%!v:lua.require'statusline'.render()"
    local colorscheme = vim.g.colors_name
    if colorscheme then
        vim.cmd("colorscheme " .. colorscheme)
    end
end

function M.toggle()
    if M.visible then
        M.hide()
    else
        M.show()
    end
end

function M.setup()
    -- Start hidden: thin separator lines only. Alt+Shift+P or <leader>ts shows the bar.
    M.visible = false
    vim.o.laststatus = 0
    vim.o.statusline = "%{repeat('─',winwidth('.'))}"
    vim.api.nvim_set_hl(0, "StatusLine", { link = "WinSeparator" })
    vim.api.nvim_set_hl(0, "StatusLineNC", { link = "WinSeparator" })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("StatuslineHide", { clear = true }),
        callback = function()
            if not M.visible then
                vim.o.statusline = "%{repeat('─',winwidth('.'))}"
                vim.api.nvim_set_hl(0, "StatusLine", { link = "WinSeparator" })
                vim.api.nvim_set_hl(0, "StatusLineNC", { link = "WinSeparator" })
            end
        end,
    })
end

-- Keep line/col numbers live without extra autocmds:
-- render() reads cursor position on each redraw.
-- Call setup once at startup; mode text uses nvim_get_mode each time.

return M
