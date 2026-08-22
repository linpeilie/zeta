#!/usr/bin/env bash
# 跑一个测试分片。分片清单在 tool/test_shards.dart。
#
#   bash tool/test_shard.sh 3            # 跑第 3 片
#   bash tool/test_shard.sh 3 --name foo # 额外参数透传给 flutter test
#
# CI 的 test Job 按矩阵 shard: [1..N] 逐片调用本脚本；本地想只跑受影响的分片，
# 先 `bash tool/test_affected.sh --shards` 拿到 id。
set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

if [[ $# -lt 1 ]]; then
  echo "用法: bash tool/test_shard.sh <分片 id> [透传给 flutter test 的参数...]" >&2
  exit 64
fi

shard_id="$1"
shift

shard_paths="$(dart run tool/test_select.dart --shard "$shard_id" --print)" || exit $?

report_directory="$repository_root/.dart_tool/test-results"
report_path="$report_directory/shard-$shard_id.json"
mkdir -p "$report_directory"

# shellcheck disable=SC2086  # shard_paths 是空格分隔的多个路径，需要分词。
flutter test $shard_paths --file-reporter "json:$report_path" "$@"
test_exit_code=$?

# 每片各自打印耗时摘要——重平衡分片时不用拍脑袋，直接看这份数据。
if [[ -f "$report_path" ]]; then
  dart run tool/report_test_timings.dart "$report_path"
fi

exit "$test_exit_code"
