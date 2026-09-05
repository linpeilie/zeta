#!/usr/bin/env bash
set -u

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_directory="$repository_root/.dart_tool/test-results"
report_path="$report_directory/full.json"

cd "$repository_root"
mkdir -p "$report_directory"

# git-bash/MSYS 下 `pwd` 给出 /d/... 形式的路径。MSYS 只会把**以 / 开头**的参数
# 自动转成原生路径，`json:/d/...` 不在转换范围内，Windows 版 flutter 拿到后无法
# 解析，会静默不写报告——耗时摘要于是读到上一次的旧文件。这里显式转一次。
reporter_path="$report_path"
if command -v cygpath >/dev/null 2>&1; then
  reporter_path="$(cygpath -w "$report_path")"
fi

flutter test --file-reporter "json:$reporter_path" "$@"
test_exit_code=$?

if [[ -f "$report_path" ]]; then
  dart run tool/report_test_timings.dart "$report_path"
fi

# 内部 Package 有各自的 test/ 入口，根 flutter test 不会覆盖。
bash tool/test_packages.sh
packages_exit_code=$?

if [[ "$test_exit_code" -ne 0 ]]; then
  exit "$test_exit_code"
fi
exit "$packages_exit_code"
