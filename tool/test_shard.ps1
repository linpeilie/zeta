#!/usr/bin/env pwsh
# 跑一个测试分片（tool/test_shard.sh 的 Windows 版）。分片清单在 tool/test_shards.dart。
param(
    [Parameter(Mandatory = $true, Position = 0)][int]$ShardId,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArguments
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repositoryRoot
try {
    $shardPaths = & dart run tool/test_select.dart --shard $ShardId --print
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $reportDirectory = Join-Path $repositoryRoot '.dart_tool/test-results'
    $reportPath = Join-Path $reportDirectory "shard-$ShardId.json"
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null

    & flutter test @($shardPaths -split ' ') --file-reporter "json:$reportPath" @RemainingArguments
    $testExitCode = $LASTEXITCODE

    # 每片各自打印耗时摘要，供后续重平衡分片使用。
    if (Test-Path $reportPath) {
        & dart run tool/report_test_timings.dart $reportPath
    }

    exit $testExitCode
} finally {
    Pop-Location
}
