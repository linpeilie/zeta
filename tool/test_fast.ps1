param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repositoryRoot
try {
  & flutter test --exclude-tags slow @RemainingArguments
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
