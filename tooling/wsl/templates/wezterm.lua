-- AgentSwitchboard managed WezTerm configuration
-- This file configures WezTerm to launch the selected WSL distribution.
-- Back up your existing configuration before applying.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.default_prog = { "wsl.exe", "-d", "Ubuntu", "--cd", os.getenv("USERPROFILE") .. "\\dev" }

config.color_scheme = "Catppuccin Mocha"

config.font = wezterm.font("Cascadia Code", { weight = "Medium" })
config.font_size = 11.0

config.window_background_opacity = 0.95
config.win32_system_backdrop = "Acrylic"

config.window_padding = {
    left = 8,
    right = 8,
    top = 8,
    bottom = 4,
}

config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false

config.colors = {
    tab_bar = {
        background = "#1e1e2e",
        active_tab = {
            bg_color = "#313244",
            fg_color = "#cdd6f4",
        },
        inactive_tab = {
            bg_color = "#181825",
            fg_color = "#6c7086",
        },
    },
}

config.keys = {
    { key = "|", mods = "CTRL|SHIFT", action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" } },
    { key = "-", mods = "CTRL|SHIFT", action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" } },
}

return config
