#!/usr/bin/env bash
# 只跑受本次改动影响的测试——开发循环的默认入口。
#
# 选择逻辑（git 变更集 → import 反向闭包 → 测试文件）在 tool/test_select.dart。
# 全量仍然是 CI 的强制门禁，这里漏了合并前一定会被抓到。
#
#   bash tool/test_affected.sh                  # 跑受影响的测试
#   bash tool/test_affected.sh --print          # 只看会跑哪些
#   bash tool/test_affected.sh --shards         # 只看命中哪些分片
#   bash tool/test_affected.sh --base origin/dev
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

dart run tool/test_select.dart "$@"
