[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Apply')]
    [string]$Mode = 'Apply',

    [string]$Distribution = 'Ubuntu',

    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for Pi WSL bootstrap.'
}

$ContractPath = Join-Path $PSScriptRoot 'harness\wsl-user-bootstrap.contract.json'
if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "Missing Pi WSL bootstrap contract: $ContractPath"
}

$contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
if ($Distribution -ne [string]$contract.target.wslDistribution) {
    throw "WSL distribution mismatch. Contract=$($contract.target.wslDistribution) Requested=$Distribution"
}

$nvmVersion = [string]$contract.versions.nvm
$nodeVersion = [string]$contract.versions.node
$piVersion = [string]$contract.versions.pi
$piPackage = [string]$contract.versions.npmPackage
$aptPackages = @($contract.boundedMutation.ubuntuAptPackages | ForEach-Object { [string]$_ })

function Get-WslDistributions {
    $raw = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'wsl.exe --list --quiet failed. WSL must already be installed; this bootstrap does not enable Windows features or install distributions.'
    }
    return @($raw | ForEach-Object { ("$_").Replace(([char]0).ToString(), [string]::Empty).Trim() } | Where-Object { $_ })
}

function Invoke-WslBash {
    param([Parameter(Mandatory)][string]$Script)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'wsl.exe'
    $psi.UseShellExecute = $false
    foreach ($argument in @('--distribution', $Distribution, '--exec', 'bash', '-lc', $Script)) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw 'Unable to start wsl.exe.'
    }
    $process.WaitForExit()
    return $process.ExitCode
}

$distributions = Get-WslDistributions
if ($Distribution -notin $distributions) {
    Write-Host 'STATUS=BLOCKED_WSL_DISTRIBUTION_REQUIRED'
    Write-Host "WSL_DISTRIBUTION=$Distribution"
    Write-Host "NEXT=install or repair the $Distribution WSL distribution through the workstation prerequisite lane, then rerun Bootstrap-Pi-WSL.cmd"
    exit 46
}

$inspectScript = @'
set -u
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"; fi
node_path=$(command -v node 2>/dev/null || true)
npm_path=$(command -v npm 2>/dev/null || true)
pi_path=$(command -v pi 2>/dev/null || true)
node_version=$(node --version 2>/dev/null || true)
npm_version=$(npm --version 2>/dev/null || true)
pi_version=$(pi --version 2>/dev/null || true)
printf 'WSL_DISTRIBUTION=%s\n' '__DISTRIBUTION__'
printf 'NODE_PATH=%s\n' "$node_path"
printf 'NODE_VERSION=%s\n' "$node_version"
printf 'NPM_PATH=%s\n' "$npm_path"
printf 'NPM_VERSION=%s\n' "$npm_version"
printf 'PI_PATH=%s\n' "$pi_path"
printf 'PI_VERSION=%s\n' "$pi_version"
case "$node_path|$npm_path|$pi_path" in *'/mnt/'*) printf 'STATUS=BLOCKED_WINDOWS_PATH_LEAK\n'; exit 42;; esac
if [ -n "$node_path" ] && [ -n "$npm_path" ] && [ -n "$pi_path" ]; then
  printf 'PI_WSL_INSPECT=READY\n'
  exit 0
fi
printf 'PI_WSL_INSPECT=INCOMPLETE\n'
exit 43
'@
$inspectScript = $inspectScript.Replace('__DISTRIBUTION__', $Distribution)

if ($Mode -eq 'Inspect') {
    exit (Invoke-WslBash -Script $inspectScript)
}

$quotedPackages = ($aptPackages | ForEach-Object { "'$_'" }) -join ' '
$applyScript = @'
set -euo pipefail
export NVM_DIR="$HOME/.nvm"

missing_prereq=0
for tool in git curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then missing_prereq=1; fi
done
if [ "$missing_prereq" -eq 1 ]; then
  printf '[INFO] Installing bounded Ubuntu prerequisites for Pi bootstrap...\n'
  sudo apt-get update
  sudo apt-get install -y __APT_PACKAGES__
fi

if [ -e "$NVM_DIR" ] && [ ! -d "$NVM_DIR/.git" ]; then
  printf 'STATUS=BLOCKED_NVM_ROOT_OWNERSHIP\n'
  printf 'NEXT=preserve or remove non-git path %s, then rerun\n' "$NVM_DIR"
  exit 51
fi
if [ ! -d "$NVM_DIR/.git" ]; then
  git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
else
  if [ -n "$(git -C "$NVM_DIR" status --porcelain=v1)" ]; then
    printf 'STATUS=BLOCKED_NVM_DIRTY\n'
    printf 'NEXT=preserve dirty NVM work in %s, then rerun\n' "$NVM_DIR"
    exit 52
  fi
  git -C "$NVM_DIR" fetch --tags origin
fi
git -C "$NVM_DIR" checkout --detach '__NVM_VERSION__'

if ! grep -Fq 'export NVM_DIR="$HOME/.nvm"' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'ASB_NVM'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
ASB_NVM
fi

. "$NVM_DIR/nvm.sh"
nvm install '__NODE_VERSION__'
nvm alias default '__NODE_VERSION__'
nvm use '__NODE_VERSION__'
hash -r

node_path=$(command -v node)
npm_path=$(command -v npm)
case "$node_path|$npm_path" in *'/mnt/'*) printf 'STATUS=BLOCKED_WINDOWS_PATH_LEAK\n'; exit 42;; esac
case "$node_path" in "$HOME/.nvm/versions/node/"*) ;; *) printf 'STATUS=BLOCKED_NODE_OWNER\n'; printf 'NODE_PATH=%s\n' "$node_path"; exit 53;; esac
case "$npm_path" in "$HOME/.nvm/versions/node/"*) ;; *) printf 'STATUS=BLOCKED_NPM_OWNER\n'; printf 'NPM_PATH=%s\n' "$npm_path"; exit 54;; esac

npm install -g --ignore-scripts '__PI_PACKAGE__@__PI_VERSION__'
hash -r
pi_path=$(command -v pi)
case "$pi_path" in *'/mnt/'*) printf 'STATUS=BLOCKED_WINDOWS_PATH_LEAK\n'; exit 42;; esac
case "$pi_path" in "$HOME/.nvm/versions/node/"*) ;; *) printf 'STATUS=BLOCKED_PI_OWNER\n'; printf 'PI_PATH=%s\n' "$pi_path"; exit 55;; esac

node_version=$(node --version)
npm_version=$(npm --version)
pi_version=$(pi --version)
printf 'PI_WSL_BOOTSTRAP=PASS\n'
printf 'WSL_DISTRIBUTION=%s\n' '__DISTRIBUTION__'
printf 'NVM_VERSION=%s\n' '__NVM_VERSION__'
printf 'NODE_PATH=%s\n' "$node_path"
printf 'NODE_VERSION=%s\n' "$node_version"
printf 'NPM_PATH=%s\n' "$npm_path"
printf 'NPM_VERSION=%s\n' "$npm_version"
printf 'PI_PATH=%s\n' "$pi_path"
printf 'PI_VERSION=%s\n' "$pi_version"
printf 'AUTH_MUTATION=false\n'
printf 'NEXT=Pi provider authentication is per-user; inside Pi run /login.\n'
'@
$applyScript = $applyScript.Replace('__APT_PACKAGES__', $quotedPackages)
$applyScript = $applyScript.Replace('__NVM_VERSION__', $nvmVersion)
$applyScript = $applyScript.Replace('__NODE_VERSION__', $nodeVersion)
$applyScript = $applyScript.Replace('__PI_PACKAGE__', $piPackage)
$applyScript = $applyScript.Replace('__PI_VERSION__', $piVersion)
$applyScript = $applyScript.Replace('__DISTRIBUTION__', $Distribution)

$applyExit = Invoke-WslBash -Script $applyScript
if ($applyExit -ne 0) {
    exit $applyExit
}

if (-not $NoLaunch) {
    Write-Host '[INFO] Pi bootstrap is complete. Launching Pi in Ubuntu.'
    Write-Host '[INFO] Provider credentials are not copied or automated. In Pi, run /login if this user is not configured.'
    $launchScript = @'
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"
exec pi
'@
    exit (Invoke-WslBash -Script $launchScript)
}

exit 0
