# Shared deployment build identity helpers for deploy-ecs.ps1.
# Git metadata is optional; deployment must not depend on commit history.

function Resolve-DeployBuildVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    try {
        Push-Location -LiteralPath $WorkingDirectory
        try {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                return 'uncommitted'
            }

            $gitDir = & git rev-parse --git-dir 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitDir)) {
                return 'uncommitted'
            }

            $shortSha = & git rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($shortSha)) {
                return $shortSha.Trim()
            }

            return 'uncommitted'
        } finally {
            Pop-Location
        }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}
