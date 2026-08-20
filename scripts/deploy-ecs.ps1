<#
.SYNOPSIS
  Cross-compile and deploy FinSight AI Gateway to Alibaba Cloud ECS (P0-5B1A).

.DESCRIPTION
  Builds a Linux binary on Windows, copies deploy artifacts via SCP, and runs
  install-on-ecs.sh over SSH. Does NOT contain or transmit secrets.

  Recommended SSH alias: finsight-ecs (see deploy/ssh-config.snippet).

.PARAMETER EcsHost
  ECS public IP or hostname. Optional if -SshAlias is configured in ~/.ssh/config.

.PARAMETER SshAlias
  SSH config Host alias (default: finsight-ecs).

.PARAMETER EcsUser
  SSH user when using -EcsHost (default: root).

.PARAMETER GoArch
  Target GOARCH for ECS (amd64 or arm64).

.PARAMETER Version
  Release version label (default: git short SHA, or `uncommitted` when unavailable).

.EXAMPLE
  .\scripts\deploy-ecs.ps1 -SshAlias finsight-ecs -GoArch amd64

.EXAMPLE
  .\scripts\deploy-ecs.ps1 -EcsHost 203.0.113.10 -GoArch amd64
#>
[CmdletBinding()]
param(
    [string] $EcsHost = "",

    [string] $SshAlias = "finsight-ecs",

    [string] $EcsUser = "root",

    [ValidateSet("amd64", "arm64")]
    [string] $GoArch = "amd64",

    [string] $Version = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GatewayRoot = Join-Path $RepoRoot "services\youshu-ai-gateway"
$DeployDir = Join-Path $GatewayRoot "deploy"
$BuildOut = Join-Path $GatewayRoot "dist"
$ScriptDir = Join-Path $RepoRoot "scripts"

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw "Go toolchain not found in PATH"
}
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw "OpenSSH ssh not found"
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    throw "OpenSSH scp not found"
}

$DeployVersionHelper = Join-Path $ScriptDir "deploy-ecs.version.ps1"
$DeployStagingHelper = Join-Path $ScriptDir "deploy-ecs.staging.ps1"
if (-not (Test-Path -LiteralPath $DeployVersionHelper)) {
    throw "Missing deployment helper: $DeployVersionHelper"
}
if (-not (Test-Path -LiteralPath $DeployStagingHelper)) {
    throw "Missing deployment helper: $DeployStagingHelper"
}
. $DeployVersionHelper
. $DeployStagingHelper

if ([string]::IsNullOrWhiteSpace($EcsHost) -and [string]::IsNullOrWhiteSpace($SshAlias)) {
    throw "Provide -EcsHost or -SshAlias (default: finsight-ecs)"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Resolve-DeployBuildVersion -WorkingDirectory $GatewayRoot
}

New-Item -ItemType Directory -Force -Path $BuildOut | Out-Null
$LocalBinary = Join-Path $BuildOut "finsight-ai-gateway-linux-$GoArch"
$RemoteBinaryStaging = "/tmp/finsight-ai-gateway-$Version"

$DeployTextFiles = @(
    "install-on-ecs.sh",
    "rollback-ecs.sh",
    "smoke-localhost.sh",
    "finsight-ai-gateway.service",
    "production.env.template",
    "nginx-api.conf.template",
    "README-deploy.txt",
    "ssh-config.snippet"
)

$RemoteTextPaths = @{
    "install-on-ecs.sh" = "/tmp/install-on-ecs.sh"
    "rollback-ecs.sh" = "/tmp/rollback-ecs.sh"
    "smoke-localhost.sh" = "/tmp/smoke-localhost.sh"
    "finsight-ai-gateway.service" = "/tmp/finsight-ai-gateway.service"
    "production.env.template" = "/tmp/production.env.template"
    "nginx-api.conf.template" = "/tmp/nginx-api.conf.template"
    "README-deploy.txt" = "/tmp/README-deploy.txt"
    "ssh-config.snippet" = "/tmp/ssh-config.snippet"
}

if ($EcsHost) {
    $Remote = "${EcsUser}@${EcsHost}"
} else {
    $Remote = $SshAlias
}

Write-Host "Building GOOS=linux GOARCH=$GoArch CGO_ENABLED=0 version=$Version"
Push-Location $GatewayRoot
try {
    $env:GOOS = "linux"
    $env:GOARCH = $GoArch
    $env:CGO_ENABLED = "0"
    & go build -trimpath -ldflags "-s -w" -o $LocalBinary .\cmd\server
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} finally {
    Remove-Item Env:GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
    Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}

$StagingDir = New-DeployStagingDirectory -ParentDirectory $BuildOut
try {
    Write-Host "Staging Unix deployment artifacts (LF, UTF-8 no BOM)"
    $StagedTextFiles = Stage-DeployUnixTextArtifacts `
        -SourceDirectory $DeployDir `
        -StagingDirectory $StagingDir `
        -RelativePaths $DeployTextFiles

    Write-Host "Uploading binary and normalized deploy files to $Remote"

    & ssh $Remote "rm -f /tmp/install-on-ecs.sh /tmp/rollback-ecs.sh /tmp/smoke-localhost.sh /tmp/finsight-ai-gateway.service /tmp/production.env.template /tmp/nginx-api.conf.template /tmp/README-deploy.txt /tmp/ssh-config.snippet"
    if ($LASTEXITCODE -ne 0) { throw "remote cleanup failed" }

    & scp $LocalBinary "${Remote}:${RemoteBinaryStaging}"
    if ($LASTEXITCODE -ne 0) { throw "scp binary failed" }

    foreach ($file in $DeployTextFiles) {
        $stagedPath = $StagedTextFiles[$file]
        $remotePath = $RemoteTextPaths[$file]
        & scp $stagedPath "${Remote}:${remotePath}"
        if ($LASTEXITCODE -ne 0) { throw "scp $file failed" }
    }

    Write-Host "Running remote install (requires sudo on ECS)"
    $RemoteCmd = "set -e`nchmod +x /tmp/install-on-ecs.sh /tmp/rollback-ecs.sh /tmp/smoke-localhost.sh`nsudo /tmp/install-on-ecs.sh '$Version'"
    & ssh $Remote $RemoteCmd
    if ($LASTEXITCODE -ne 0) { throw "remote install failed" }
} finally {
    Remove-Item -LiteralPath $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Deploy complete. BUILD_VERSION on ECS set to: $Version"
Write-Host "Next on ECS (manual, once per instance):"
Write-Host "  1. sudo nano /etc/finsight-ai-gateway/production.env"
Write-Host "  2. Set BAILIAN_API_KEY and GATEWAY_CLIENT_TOKEN if not already configured"
Write-Host "  3. sudo chmod 600 /etc/finsight-ai-gateway/production.env"
Write-Host "  4. sudo systemctl restart finsight-ai-gateway"
Write-Host "  5. bash /tmp/smoke-localhost.sh"
Write-Host ""
Write-Host "SSH tunnel from this PC:"
Write-Host "  ssh -L 18080:127.0.0.1:8080 $Remote"
Write-Host "  curl http://127.0.0.1:18080/health"
