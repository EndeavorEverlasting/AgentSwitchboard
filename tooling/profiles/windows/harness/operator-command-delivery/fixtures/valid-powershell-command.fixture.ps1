$ref = '0123456789abcdef0123456789abcdef01234567'
$root = Join-Path $env:TEMP 'AgentSwitchboard-command-fixture'
$artifact = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\operator-command-delivery\runs\fixture\operator-command-delivery-result.json'
$null = New-Item -ItemType Directory -Force -Path $root
$resolved = gh api --method GET 'repos/EndeavorEverlasting/AgentSwitchboard/commits/main' --jq '.sha'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) { throw 'Unable to resolve source commit.' }
$content = gh api --method GET 'repos/EndeavorEverlasting/AgentSwitchboard/contents/Open-AgentSwitchboard-Tmux.ps1' -f "ref=$ref" --jq '.content'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) { throw 'Unable to resolve source file.' }
& cmd.exe /d /c 'ver >nul'
$childExit = $LASTEXITCODE
Write-Host "CHILD_EXIT_CODE=$childExit"
Write-Host "ARTIFACT=$artifact"
if ($childExit -ne 0) { throw "Child command failed with exit $childExit" }
