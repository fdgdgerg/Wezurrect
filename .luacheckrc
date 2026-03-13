-- luacheck configuration for wezterm-resurrect
-- WezTerm plugin using Lua 5.4

-- Target Lua version (WezTerm embeds Lua 5.4)
std = "lua54"

-- Maximum line length (relaxed for annotation comments)
max_line_length = 150
max_code_line_length = 120
max_comment_line_length = false

-- Global variables injected by WezTerm runtime
globals = {
    "wezterm",
}

-- Read-only globals available in the WezTerm environment
read_globals = {
    "wezterm",
}

-- Warnings to ignore project-wide
ignore = {
    "212",      -- unused argument (common in WezTerm callbacks: function(window, pane))
    "213",      -- unused loop variable (common: for _, item in ipairs(...))
    "631",      -- max_line_length (handled separately above)
}

-- Per-path overrides
files["plugin/resurrect/spec/**"] = {
    -- Test files use busted globals (describe, it, assert, etc.)
    std = "+busted",
    -- Allow test-specific globals
    globals = {
        "_G",
    },
}

files["plugin/resurrect/test/**"] = {
    -- Test helper files
    std = "+busted",
}
