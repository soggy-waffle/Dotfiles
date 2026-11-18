-- Browsers that open fullscreen (RE2, case-insensitive).
local BROWSER_CLASS = "(?i)^(zen|zen-browser|chromium|chromium-browser)$"

-- Browsers open fullscreen.
hl.window_rule({
    name = "browser-fullscreen",
    match = { class = BROWSER_CLASS },
    fullscreen = true,
})


-- Picture-in-picture floats instead (later rule wins over browser-fullscreen).
hl.window_rule({
    name  = "pip-float",
    match = { class = BROWSER_CLASS, title = "^Picture-in-Picture$" },
    float = true,
    fullscreen = false,
    suppress_event = "fullscreen maximize",
    size  = { 480, 270 },
})


-- Browser color picker dialog floats centered (later rule wins over browser-fullscreen).
hl.window_rule({
    name  = "color-picker-float",
    match = { class = BROWSER_CLASS, title = "^Choose a colou?r$" },
    float = true,
    fullscreen = false,
    suppress_event = "fullscreen maximize",
    center = true,
})


-- Scratchpad: i3-like floating, centered and resizable (Hypr special workspace)
-- Matches default special (SUPER+grave) and named magic (SUPER+S)
-- Windows spawned directly in special will use this size (bigger than default 600x400)
hl.window_rule({
    name  = "scratchpad-float",
    match = { workspace = "^special.*" },
    float = true,
    size  = { 1100, 700 },
    center = true,
})


-- Obsidian opacity. Default is opaque.
-- Uncomment the block below for glass. Keep solid-window OFF when glass is ON.
hl.window_rule({
    name = "obsidian-glass",
    match = { class = "md.obsidian.Obsidian" },
    opacity = "0.95 0.95",
})

-- Smart gaps: no border and no rounding when one tiled window.
hl.window_rule({
    name = "smart-gaps-single-tiled",
    match = { float = false, workspace = "w[tv1]" },
    border_size = 0,
    rounding = 0,
})

hl.window_rule({
    name = "smart-gaps-single-fullscreen",
    match = { float = false, workspace = "f[1]" },
    border_size = 0,
    rounding = 0,
})
