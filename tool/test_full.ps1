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

  exit $testExitCode
} finally {
  Pop-Location
}
