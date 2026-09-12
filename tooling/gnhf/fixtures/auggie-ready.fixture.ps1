if ($args -contains '--version') {
    Write-Output '0.36.0-fixture'
    exit 0
}

if ($args -contains '--help') {
    Write-Output 'Usage: auggie [options]'
    Write-Output '  --acp     Runs Auggie in ACP server mode'
    Write-Output '  --print   Runs non-interactively'
    exit 0
}

Write-Error 'unsupported fixture arguments'
exit 2
