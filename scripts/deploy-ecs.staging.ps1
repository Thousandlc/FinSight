# Staging helpers for Unix deployment artifacts (LF, UTF-8 no BOM).

function ConvertTo-UnixLineEndings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-UnixUtf8Encoding {
    return New-Object System.Text.UTF8Encoding $false
}

function Read-UnixTextArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF-8 BOM is not allowed in Unix deployment artifact: $Path"
    }

    $encoding = Get-UnixUtf8Encoding
    return $encoding.GetString($bytes)
}

function Write-StagedUnixTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    $normalized = ConvertTo-UnixLineEndings -Text (Read-UnixTextArtifact -Path $SourcePath)
    $encoding = Get-UnixUtf8Encoding
    [System.IO.File]::WriteAllText($DestinationPath, $normalized, $encoding)
}

function Test-StagedUnixArtifactBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [switch] $RequireBashShebang
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "Staged artifact contains UTF-8 BOM: $Path"
    }

    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 0x0D) {
            throw "Staged artifact contains CR byte at offset ${i}: $Path"
        }
    }

    if ($RequireBashShebang) {
        $encoding = Get-UnixUtf8Encoding
        $firstLine = ($encoding.GetString($bytes) -split "`n", 2)[0]
        if ($firstLine -ne '#!/usr/bin/env bash') {
            throw "Invalid bash shebang in staged artifact ${Path}: '$firstLine'"
        }
    }
}

function New-DeployStagingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ParentDirectory
    )

    $stagingRoot = Join-Path $ParentDirectory ('deploy-staging-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    return $stagingRoot
}

function Stage-DeployUnixTextArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string] $StagingDirectory,

        [Parameter(Mandatory = $true)]
        [string[]] $RelativePaths
    )

    $staged = @{}
    foreach ($relativePath in $RelativePaths) {
        $sourcePath = Join-Path $SourceDirectory $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Missing deployment artifact: $sourcePath"
        }

        $destinationPath = Join-Path $StagingDirectory $relativePath
        Write-StagedUnixTextFile -SourcePath $sourcePath -DestinationPath $destinationPath

        $requireShebang = $relativePath.EndsWith('.sh')
        Test-StagedUnixArtifactBytes -Path $destinationPath -RequireBashShebang:$requireShebang

        $staged[$relativePath] = $destinationPath
    }

    return $staged
}

function Copy-BinaryArtifactVerbatim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    [System.IO.File]::Copy($SourcePath, $DestinationPath, $true)
}

function Test-BinaryArtifactUnchanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    $destHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $destHash) {
        throw "Binary artifact changed during staging: $SourcePath"
    }
}
