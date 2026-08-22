#!/usr/bin/env bash
set -u

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_directory="$repository_root/.dart_tool/test-results"
report_path="$report_directory/full.json"

cd "$repository_root"
mkdir -p "$report_directory"

flutter test --file-reporter "json:$report_path" "$@"
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
