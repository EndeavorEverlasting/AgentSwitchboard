-- AgentSwitchboard managed tmux/GNHF configuration
-- This file is rendered by Install-TmuxGnhfWorkspace.ps1.
-- WezTerm is the GUI; tmux is the persistent workspace; WSL is the Windows backend.

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

local distro = "__DISTRO__"
local session = "__SESSION__"
local attach_tmux =
  "tmux has-session -t '" .. session .. "' 2>/dev/null || " ..
  "tmux new-session -d -s '" .. session .. "'; " ..
  "exec tmux attach-session -t '" .. session .. "'"

local tmux_workspace = {
  "wsl.exe",
  "-d",
  distro,
  "-e",
  "bash",
  "-lc",
  attach_tmux,
}

config.default_prog = tmux_workspace
config.launch_menu = {
  {
    label = "tmux: Development",
    args = tmux_workspace,
  },
  {
    label = "WSL: Bash without tmux",
    args = { "wsl.exe", "-d", distro, "-e", "bash", "-l" },
  },
  {
    label = "Windows: PowerShell 7",
    args = { "pwsh.exe", "-NoLogo" },
  },
}

-- Do not require a patched font family. WezTerm's bundled fallback remains usable.
config.font_size = 11.0
config.line_height = 1.05
config.initial_cols = 132
config.initial_rows = 36
config.scrollback_lines = 20000
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.window_close_confirmation = "AlwaysPrompt"
config.audible_bell = "Disabled"
config.window_padding = {
  left = 8,
  right = 8,
  top = 6,
  bottom = 6,
}

-- WezTerm uses Ctrl+Shift+Space. tmux keeps its normal Ctrl+B prefix.
config.leader = {
  key = "Space",
  mods = "CTRL|SHIFT",
  timeout_milliseconds = 1500,
}
config.keys = {
  { key = "r", mods = "LEADER", action = act.ReloadConfiguration },
  { key = "l", mods = "LEADER", action = act.ShowLauncher },
  { key = "p", mods = "LEADER", action = act.ActivateCommandPalette },
}

return config
