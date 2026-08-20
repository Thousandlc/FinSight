# Regression checks for Resolve-DeployBuildVersion (no ECS deploy, no git mutations).
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'deploy-ecs.version.ps1')

function Assert-Equal {
    param(
        [string] $Name,
        [string] $Actual,
        [string] $Expected
    )
    if ($Actual -ne $Expected) {
        throw "FAIL ${Name}: expected '$Expected', got '$Actual'"
    }
    Write-Host "PASS $Name"
}

$nonGitDir = Join-Path ([System.IO.Path]::GetTempPath()) ("finsight-deploy-version-test-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $nonGitDir | Out-Null
try {
    Assert-Equal 'non-git directory' (Resolve-DeployBuildVersion -WorkingDirectory $nonGitDir) 'uncommitted'
} finally {
    Remove-Item -LiteralPath $nonGitDir -Recurse -Force -ErrorAction SilentlyContinue
}

$gatewayRoot = Join-Path (Split-Path -Parent $ScriptDir) 'services\youshu-ai-gateway'
if (-not (Test-Path -LiteralPath $gatewayRoot)) {
    throw "missing gateway root: $gatewayRoot"
}

$repoVersion = Resolve-DeployBuildVersion -WorkingDirectory $gatewayRoot
if ([string]::IsNullOrWhiteSpace($repoVersion)) {
    throw 'FAIL gateway root: version must not be empty'
}
if ($repoVersion -match '[\\/\s]') {
    throw "FAIL gateway root: version must be path-safe, got '$repoVersion'"
}
Write-Host "PASS gateway root returns non-empty path-safe identity: $repoVersion"

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
try {
    $null = Resolve-DeployBuildVersion -WorkingDirectory $gatewayRoot
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
Write-Host 'PASS git lookup does not throw under Stop'

Write-Host 'All deploy-ecs version tests passed.'
