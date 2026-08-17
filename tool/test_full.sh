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

exit "$test_exit_code"
