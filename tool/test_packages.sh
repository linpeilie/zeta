#!/usr/bin/env bash
# 运行 packages/ 下每个内部 Package 的独立测试入口。
#
# 根目录的 `flutter test` 只跑 test/；纯 Dart Package 有自己的 test/ 目录，
# 必须单独跑，否则拆出去的边界就没人守。
set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

exit_code=0
for package_dir in packages/*/; do
  [[ -f "${package_dir}pubspec.yaml" ]] || continue
  [[ -d "${package_dir}test" ]] || continue
  echo "==> ${package_dir}"
  # analyze 也要跑：根目录的 `flutter analyze` 只分析根 Package。
  (cd "$package_dir" && dart analyze) || exit_code=1
  (cd "$package_dir" && dart test "$@") || exit_code=1
done

exit "$exit_code"
