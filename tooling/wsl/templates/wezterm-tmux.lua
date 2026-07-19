-- Managed by AgentSwitchboard. Do not edit the managed block markers.
-- This template is rendered by Install-AgentSwitchboardWezTermLauncher.ps1.
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local distro = '@DISTRO@'
local session = '@SESSION@'
local workspace = '@WORKSPACE@'

local tmux_command = {
  'wsl.exe', '-d', distro, '-e', 'bash', '-lc',
  'exec tmux new-session -A -s ' .. session
}

config.default_prog = tmux_command

config.launch_menu = config.launch_menu or {}
table.insert(config.launch_menu, {
  label = 'tmux: ' .. session,
  args = tmux_command,
})
table.insert(config.launch_menu, {
  label = 'PowerShell 7 (fallback/admin)',
  args = { 'pwsh.exe', '-NoLogo' },
})

config.check_for_updates = false

return config
