# Regression checks for deploy-ecs Unix artifact staging (no ECS deploy).
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'deploy-ecs.staging.ps1')

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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('finsight-deploy-staging-test-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $fixtureDir = Join-Path $tempRoot 'source'
    $stagingDir = Join-Path $tempRoot 'staging'
    New-Item -ItemType Directory -Path $fixtureDir | Out-Null
    New-Item -ItemType Directory -Path $stagingDir | Out-Null

    $crlfFixture = Join-Path $fixtureDir 'sample.sh'
    $crlfBytes = [byte[]](0x23, 0x21, 0x2F, 0x75, 0x73, 0x72, 0x2F, 0x62, 0x69, 0x6E, 0x2F, 0x65, 0x6E, 0x76, 0x20, 0x62, 0x61, 0x73, 0x68, 0x0D, 0x0A, 0x73, 0x65, 0x74, 0x20, 0x2D, 0x65, 0x0D, 0x0A)
    [System.IO.File]::WriteAllBytes($crlfFixture, $crlfBytes)

    $binaryFixture = Join-Path $fixtureDir 'sample.bin'
    $binaryBytes = [byte[]](0x7F, 0x45, 0x4C, 0x46, 0x00, 0x00, 0x0A, 0x0D, 0x0A)
    [System.IO.File]::WriteAllBytes($binaryFixture, $binaryBytes)
    $binaryHashBefore = (Get-FileHash -LiteralPath $binaryFixture -Algorithm SHA256).Hash

    $staged = Stage-DeployUnixTextArtifacts -SourceDirectory $fixtureDir -StagingDirectory $stagingDir -RelativePaths @('sample.sh')
    $stagedPath = $staged['sample.sh']
    $stagedBytes = [System.IO.File]::ReadAllBytes($stagedPath)
    if ($stagedBytes -contains 0x0D) {
        throw 'FAIL CRLF fixture: staged shell script still contains CR bytes'
    }
    if ($stagedBytes.Length -ge 3 -and $stagedBytes[0] -eq 0xEF -and $stagedBytes[1] -eq 0xBB -and $stagedBytes[2] -eq 0xBF) {
        throw 'FAIL CRLF fixture: staged shell script contains UTF-8 BOM'
    }
    $firstLine = (Get-UnixUtf8Encoding).GetString($stagedBytes) -split "`n" | Select-Object -First 1
    Assert-Equal 'bash shebang' $firstLine '#!/usr/bin/env bash'
    Write-Host 'PASS CRLF fixture normalized to LF without BOM'

    $binaryCopy = Join-Path $stagingDir 'sample.bin.copy'
    Copy-BinaryArtifactVerbatim -SourcePath $binaryFixture -DestinationPath $binaryCopy
    Test-BinaryArtifactUnchanged -SourcePath $binaryFixture -DestinationPath $binaryCopy
    Write-Host 'PASS binary fixture copied byte-identical'

    $gatewayDeployDir = Join-Path (Split-Path -Parent $ScriptDir) 'services\youshu-ai-gateway\deploy'
    $gatewayStaging = New-DeployStagingDirectory -ParentDirectory $tempRoot
    $gatewayFiles = @(
        'install-on-ecs.sh',
        'rollback-ecs.sh',
        'smoke-localhost.sh',
        'finsight-ai-gateway.service',
        'production.env.template',
        'nginx-api.conf.template',
        'README-deploy.txt',
        'ssh-config.snippet'
    )
    $null = Stage-DeployUnixTextArtifacts -SourceDirectory $gatewayDeployDir -StagingDirectory $gatewayStaging -RelativePaths $gatewayFiles
    Write-Host 'PASS gateway deploy artifacts stage without CR/BOM/shebang errors'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'All deploy-ecs staging tests passed.'
