#!/usr/bin/env pwsh
# 只跑受本次改动影响的测试——开发循环的默认入口（tool/test_affected.sh 的 Windows 版）。
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArguments)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repositoryRoot
try {
    & dart run tool/test_select.dart @RemainingArguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
