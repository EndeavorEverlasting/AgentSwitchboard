Set-StrictMode -Version Latest

function Get-GnhfFleetAbsolutePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BaseDirectory = (Get-Location).Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path cannot be blank."
    }

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $BaseDirectory $Path
    }

    return [IO.Path]::GetFullPath($candidate)
}

function Ensure-GnhfFleetDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BaseDirectory = (Get-Location).Path
    )

    $fullPath = Get-GnhfFleetAbsolutePath -Path $Path -BaseDirectory $BaseDirectory

    if (Test-Path -LiteralPath $fullPath) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            throw "Expected a directory at '$fullPath', but an existing non-directory item occupies that path."
        }

        return (Get-Item -LiteralPath $fullPath -Force).FullName
    }

    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    return (Get-Item -LiteralPath $fullPath -Force).FullName
}

function Resolve-GnhfFleetDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BaseDirectory = (Get-Location).Path,
        [string]$Description = "directory"
    )

    $fullPath = Get-GnhfFleetAbsolutePath -Path $Path -BaseDirectory $BaseDirectory
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "$Description not found: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "Expected $Description to be a directory, but found a non-directory item: $fullPath"
    }

    return (Get-Item -LiteralPath $fullPath -Force).FullName
}

function Resolve-GnhfFleetFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BaseDirectory = (Get-Location).Path,
        [string]$Description = "file"
    )

    $fullPath = Get-GnhfFleetAbsolutePath -Path $Path -BaseDirectory $BaseDirectory
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "$Description not found: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Expected $Description to be a file, but found a directory: $fullPath"
    }

    return (Get-Item -LiteralPath $fullPath -Force).FullName
}

function Ensure-GnhfFleetParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BaseDirectory = (Get-Location).Path
    )

    $fullPath = Get-GnhfFleetAbsolutePath -Path $Path -BaseDirectory $BaseDirectory
    $parent = Split-Path -Parent $fullPath
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "Cannot determine the parent directory for '$fullPath'."
    }

    return Ensure-GnhfFleetDirectory -Path $parent
}
