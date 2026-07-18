local wezterm = require 'wezterm'

local M = {}

function M.apply(config)
  local local_app_data = os.getenv('LOCALAPPDATA') or ''
  local user_profile = os.getenv('USERPROFILE') or ''
  local launcher = local_app_data .. '\\AgentSwitchboard\\GnhfFleet\\Start-BlacksmithGuildNightShift.ps1'
  local repo = os.getenv('TBG_REPO_PATH') or (user_profile .. '\\Desktop\\dev\\Mods\\Bannerlord\\BlacksmithGuild')

  config.launch_menu = config.launch_menu or {}
  table.insert(config.launch_menu, {
    label = 'BlacksmithGuild — GNHF Night Shift',
    args = {
      'pwsh.exe',
      '-NoLogo',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      launcher,
      '-RepoPath',
      repo,
      '-Stage',
      'Auto',
      '-Agent',
      'deepseek',
    },
  })

  return config
end

return M
