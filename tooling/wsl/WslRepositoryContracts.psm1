Set-StrictMode -Version Latest

function ConvertTo-WslHomeRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if ($Path -eq "~") {
        return ""
    }

    if (-not $Path.StartsWith("~/", [System.StringComparison]::Ordinal)) {
        throw "Repository destination must be '~' or a path below '~/'."
    }

    $relativePath = $Path.Substring(2)
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        throw "Repository destination below '~/' must not be empty."
    }

    if ($relativePath -notmatch '^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*$') {
        throw "Repository destination contains unsupported path characters."
    }

    $segments = $relativePath -split "/"
    if ($segments | Where-Object { $_ -in @(".", "..") }) {
        throw "Repository destination must not contain traversal segments."
    }

    return $relativePath
}

function Assert-GitHubRepositoryUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url
    )

    $httpsPattern = '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$'
    $sshPattern = '^git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$'
    if ($Url -notmatch $httpsPattern -and $Url -notmatch $sshPattern) {
        throw "Repository URL must be a canonical GitHub HTTPS or SSH clone URL."
    }

    return $Url
}

function Assert-GitBranchName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Branch
    )

    if ([string]::IsNullOrWhiteSpace($Branch)) {
        throw "Repository branch must not be empty."
    }

    if ($Branch.Length -gt 255) {
        throw "Repository branch exceeds the supported length."
    }

    if ($Branch.StartsWith("-", [System.StringComparison]::Ordinal) -or
        $Branch.EndsWith("/", [System.StringComparison]::Ordinal) -or
        $Branch.EndsWith(".", [System.StringComparison]::Ordinal) -or
        $Branch.Contains("..", [System.StringComparison]::Ordinal) -or
        $Branch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$') {
        throw "Repository branch contains unsupported characters or structure."
    }

    return $Branch
}

Export-ModuleMember -Function @(
    "ConvertTo-WslHomeRelativePath",
    "Assert-GitHubRepositoryUrl",
    "Assert-GitBranchName"
)
