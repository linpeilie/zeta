[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-beta\.[1-9][0-9]*)?$')]
  [string]$ReleaseVersion,
  [string]$ProjectRoot,
  [string]$InnoCompiler
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
  $ProjectRoot = Join-Path $PSScriptRoot '..\..'
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

$metadataTool = Join-Path $PSScriptRoot 'release_metadata.dart'
$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
$metadataJson = (& dart $metadataTool `
    --tag "v$ReleaseVersion" `
    --pubspec $pubspec).Trim()
if ($LASTEXITCODE -ne 0) {
  throw 'Release version does not match pubspec.yaml.'
}
$metadata = $metadataJson | ConvertFrom-Json
$appFullVersion = [string]$metadata.app_full_version
$windowsVersion = "$($metadata.app_version).$($metadata.build_number)"

$buildDirectory = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$executable = Join-Path $buildDirectory 'zeta.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
  throw "Windows release executable not found: $executable"
}

$distDirectory = Join-Path $ProjectRoot 'dist'
New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null

$portablePackage = Join-Path $distDirectory "zeta-$ReleaseVersion-windows-x86_64.zip"
$installerPackage = Join-Path $distDirectory "zeta-$ReleaseVersion-windows-x86_64-setup.exe"
foreach ($path in @(
    $portablePackage,
    $installerPackage,
    "$portablePackage.sha256",
    "$installerPackage.sha256"
  )) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
  }
}

Compress-Archive -Path (Join-Path $buildDirectory '*') `
  -DestinationPath $portablePackage `
  -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($portablePackage)
try {
  $containsExecutable = $null -ne (
    $archive.Entries |
      Where-Object { $_.FullName -ieq 'zeta.exe' } |
      Select-Object -First 1
  )
  if (-not $containsExecutable) {
    throw 'The Windows portable package does not contain zeta.exe.'
  }
}
finally {
  $archive.Dispose()
}

if ([string]::IsNullOrWhiteSpace($InnoCompiler)) {
  $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    $InnoCompiler = $command.Source
  }
}
if ([string]::IsNullOrWhiteSpace($InnoCompiler)) {
  $compilerCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  )
  $InnoCompiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($InnoCompiler) -or
  -not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) {
  throw 'Inno Setup 6 compiler (ISCC.exe) was not found.'
}

$installerDefinition = Join-Path $PSScriptRoot 'zeta.iss'
& $InnoCompiler `
  "/DProjectRoot=$ProjectRoot" `
  "/DBuildDir=$buildDirectory" `
  "/DOutputDir=$distDirectory" `
  "/DAppVersion=$appFullVersion" `
  "/DArtifactVersion=$ReleaseVersion" `
  "/DVersionInfoVersion=$windowsVersion" `
  $installerDefinition
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $installerPackage -PathType Leaf)) {
  throw "Windows installer was not generated: $installerPackage"
}

function Write-Sha256File {
  param([Parameter(Mandatory = $true)][string]$Path)

  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  $fileName = Split-Path -Leaf $Path
  [System.IO.File]::WriteAllText(
    "$Path.sha256",
    "$hash  $fileName`n",
    [System.Text.Encoding]::ASCII
  )
}

Write-Sha256File -Path $portablePackage
Write-Sha256File -Path $installerPackage

Write-Host "Created Windows packages in $distDirectory"
