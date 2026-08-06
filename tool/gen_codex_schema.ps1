# 从本机 Codex CLI 导出 app-server JSON Schema，写入仓库内的 pinned 快照。
#
# 用法:
#   ./tool/gen_codex_schema.ps1
#   ./tool/gen_codex_schema.ps1 -Diff
#   ./tool/gen_codex_schema.ps1 -Force
#   ./tool/gen_codex_schema.ps1 -Experimental
#   ./tool/gen_codex_schema.ps1 -CodexBin "C:\...\codex.exe"
#
# 升级协议时:先用新版本 CLI 跑本脚本，review schema diff，再改适配层。

[CmdletBinding()]
param(
    [switch]$Diff,
    [switch]$Force,
    [switch]$Experimental,
    [string]$CodexBin = $env:CODEX_BIN
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$OutDir = Join-Path $Root 'third_party/codex_app_server_schema'
$PinnedFile = Join-Path $OutDir 'PINNED_VERSION'

function Resolve-CodexBin {
    param([string]$Preferred)

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        if (Test-Path -LiteralPath $Preferred) {
            return (Resolve-Path -LiteralPath $Preferred).Path
        }
        $fromPath = Get-Command $Preferred -ErrorAction SilentlyContinue
        if ($null -ne $fromPath) {
            return $fromPath.Source
        }
        throw "Codex CLI not found: $Preferred"
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/OpenAI/Codex/bin/codex.exe'),
        'codex'
    )
    foreach ($candidate in $candidates) {
        if ($candidate -eq 'codex') {
            $cmd = Get-Command codex -ErrorAction SilentlyContinue
            if ($null -ne $cmd) {
                return $cmd.Source
            }
            continue
        }
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Codex CLI not found. Install Codex CLI or pass -CodexBin / set CODEX_BIN."
}

function Get-CodexCliVersion {
    param([string]$Bin)

    $versionLine = & $Bin --version 2>&1 | Select-Object -First 1
    if ($versionLine -match '(\d+\.\d+\.\d+)') {
        return $Matches[1]
    }
    throw "Could not parse Codex CLI version from: $versionLine"
}

function Write-SchemaMeta {
    param(
        [string]$TargetDir,
        [string]$CliVersion,
        [string]$Bin,
        [bool]$IncludeExperimental
    )

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    # PINNED_VERSION 只含版本号 + 换行，便于脚本与文档引用。
    [System.IO.File]::WriteAllText(
        (Join-Path $TargetDir 'PINNED_VERSION'),
        ($CliVersion + [Environment]::NewLine),
        $utf8NoBom
    )

    $experimentalFlag = if ($IncludeExperimental) { ' --experimental' } else { '' }
    $meta = [ordered]@{
        codexCliVersion = $CliVersion
        generatedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        command         = "$Bin app-server generate-json-schema --out <dir>$experimentalFlag"
        experimental    = $IncludeExperimental
        excludedNondeterministicFiles = @(
            'codex_app_server_protocol.v2.schemas.json'
        )
    }
    $json = $meta | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText(
        (Join-Path $TargetDir 'GENERATED.json'),
        $json + [Environment]::NewLine,
        $utf8NoBom
    )
}

function Get-RelativeSchemaFiles {
    param([string]$BaseDir)

    Get-ChildItem -LiteralPath $BaseDir -Recurse -File |
        Where-Object { $_.Name -ne 'README.md' } |
        ForEach-Object {
            [PSCustomObject]@{
                FullName = $_.FullName
                RelPath  = $_.FullName.Substring($BaseDir.Length).TrimStart('\', '/')
            }
        }
}

function Remove-NondeterministicSchemaFiles {
    param([string]$TargetDir)

    # CLI 对该聚合文件的 definitions 键序不稳定；v2/*.json 已覆盖同等信息。
    $unstable = Join-Path $TargetDir 'codex_app_server_protocol.v2.schemas.json'
    if (Test-Path -LiteralPath $unstable) {
        Remove-Item -LiteralPath $unstable -Force
    }
}

$resolvedBin = Resolve-CodexBin -Preferred $CodexBin
$cliVersion = Get-CodexCliVersion -Bin $resolvedBin

$pinnedVersion = $null
if (Test-Path -LiteralPath $PinnedFile) {
    $pinnedVersion = (Get-Content -LiteralPath $PinnedFile -Raw).Trim()
}

if (
    -not [string]::IsNullOrWhiteSpace($pinnedVersion) -and
    $cliVersion -ne $pinnedVersion -and
    -not $Force
) {
    Write-Error @"
Codex CLI version mismatch:
  pinned : $pinnedVersion (see $PinnedFile)
  current: $cliVersion ($resolvedBin)
Re-run with -Force after intentionally upgrading the pin,
or pass -CodexBin pointing at the pinned CLI.
"@
    exit 2
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zeta-codex-schema-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
try {
    Write-Host "Generating schema with $resolvedBin ($cliVersion) ..."
    $genArgs = @('app-server', 'generate-json-schema', '--out', $tmpDir)
    if ($Experimental) {
        $genArgs += '--experimental'
    }
    & $resolvedBin @genArgs
    if ($LASTEXITCODE -ne 0) {
        throw "codex exited with code $LASTEXITCODE"
    }

    Remove-NondeterministicSchemaFiles -TargetDir $tmpDir

    $required = @(
        'ClientRequest.json',
        'ClientNotification.json',
        'ServerNotification.json',
        'ServerRequest.json'
    )
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $tmpDir $name))) {
            throw "Schema generation incomplete: missing $name"
        }
    }

    Write-SchemaMeta -TargetDir $tmpDir -CliVersion $cliVersion -Bin $resolvedBin -IncludeExperimental:$Experimental

    if ($Diff) {
        if (-not (Test-Path -LiteralPath $OutDir)) {
            throw "No committed schema at $OutDir; run without -Diff first."
        }

        Write-Host "Diffing generated schema against $OutDir ..."
        $changed = $false
        $newFiles = Get-RelativeSchemaFiles -BaseDir $tmpDir
        $oldFiles = Get-RelativeSchemaFiles -BaseDir $OutDir |
            Where-Object { $_.RelPath -ne 'GENERATED.json' }

        foreach ($file in $newFiles) {
            if ($file.RelPath -eq 'GENERATED.json') {
                continue
            }
            $oldPath = Join-Path $OutDir $file.RelPath
            if (-not (Test-Path -LiteralPath $oldPath)) {
                Write-Host "CHANGED: $($file.RelPath) (added)"
                $changed = $true
                continue
            }
            $newHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $oldHash = (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash
            if ($newHash -ne $oldHash) {
                Write-Host "CHANGED: $($file.RelPath)"
                $changed = $true
            }
        }

        foreach ($file in $oldFiles) {
            $newPath = Join-Path $tmpDir $file.RelPath
            if (-not (Test-Path -LiteralPath $newPath)) {
                Write-Host "REMOVED: $($file.RelPath)"
                $changed = $true
            }
        }

        if (-not $changed) {
            Write-Host 'Schema snapshot matches current CLI output.'
            exit 0
        }

        Write-Error 'Schema drift detected. Review CHANGED/REMOVED files above.'
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Get-ChildItem -LiteralPath $OutDir -Force |
        Where-Object { $_.Name -ne 'README.md' } |
        Remove-Item -Recurse -Force

    Copy-Item -Path (Join-Path $tmpDir '*') -Destination $OutDir -Recurse -Force
    Write-SchemaMeta -TargetDir $OutDir -CliVersion $cliVersion -Bin $resolvedBin -IncludeExperimental:$Experimental

    $fileCount = (Get-RelativeSchemaFiles -BaseDir $OutDir).Count
    Write-Host "Wrote $fileCount schema files to $OutDir"
    Write-Host "Pinned Codex CLI version: $cliVersion"
    Write-Host 'Next: git diff --stat third_party/codex_app_server_schema'
    Write-Host 'Then update docs/protocols/codex_app_server_protocol.md if the pin changed.'
}
finally {
    if (Test-Path -LiteralPath $tmpDir) {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force
    }
}
