$ErrorActionPreference = 'Stop'

function Invoke-Forge {
    param([string[]]$Arguments)
    & forge @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "forge $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Invoke-Forge @('fmt', '--check')
Invoke-Forge @('build', '--sizes')
Invoke-Forge @('test')

$previousProfile = $env:FOUNDRY_PROFILE
try {
    $env:FOUNDRY_PROFILE = 'ci'
    Invoke-Forge @('test')
}
finally {
    $env:FOUNDRY_PROFILE = $previousProfile
}
