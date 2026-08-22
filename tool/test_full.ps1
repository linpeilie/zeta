param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$reportDirectory = Join-Path $repositoryRoot '.dart_tool\test-results'
$reportPath = Join-Path $reportDirectory 'full.json'

Push-Location $repositoryRoot
try {
  New-Item -ItemType Directory -Force $reportDirectory | Out-Null
  & flutter test --file-reporter "json:$reportPath" @RemainingArguments
  $testExitCode = $LASTEXITCODE

  if (Test-Path -LiteralPath $reportPath) {
    & dart run tool/report_test_timings.dart $reportPath
  }

  # 内部 Package 有各自的 test/ 入口，根 flutter test 不会覆盖。
  $packagesExitCode = 0
  Get-ChildItem -Path (Join-Path $repositoryRoot 'packages') -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'test') } |
    ForEach-Object {
      Write-Host "==> packages/$($_.Name)"
      Push-Location $_.FullName
      try {
        # Flutter Package 必须用 flutter 工具链跑。
        $isFlutterPackage = Select-String -Path 'pubspec.yaml' -Pattern '^\s+sdk:\s+flutter$' -Quiet
        # analyze 与 shell 版对齐：根 `flutter analyze` 只分析根 Package。
        if ($isFlutterPackage) { & flutter analyze } else { & dart analyze }
        if ($LASTEXITCODE -ne 0) { $packagesExitCode = $LASTEXITCODE }
        if ($isFlutterPackage) { & flutter test } else { & dart test }
        if ($LASTEXITCODE -ne 0) { $packagesExitCode = $LASTEXITCODE }
      } finally {
        Pop-Location
      }
    }

  if ($testExitCode -ne 0) { exit $testExitCode }
  exit $packagesExitCode
} finally {
  Pop-Location
}
