#!/usr/bin/env bash
# 运行 packages/ 下每个内部 Package 的独立测试入口。
#
# 根目录的 `flutter test` 只跑 test/；纯 Dart Package 有自己的 test/ 目录，
# 必须单独跑，否则拆出去的边界就没人守。
set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

# --only 是本脚本的选择参数；其余选项仍透传到测试 runner。
selected_package=""
list_json=false
test_arguments=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list-json) list_json=true; shift ;;
    --only)
      if [[ -n "$selected_package" || $# -lt 2 || ! "$2" =~ ^[a-z][a-z0-9_]*$ ]]; then
        echo "用法: bash tool/test_packages.sh [--only <package>] [测试参数...]" >&2
        exit 64
      fi
      selected_package="$2"
      shift 2
      ;;
    --)
      shift
      test_arguments+=("$@")
      break
      ;;
    *) test_arguments+=("$1"); shift ;;
  esac
done

package_directories=(packages/*/)
if [[ -n "$selected_package" ]]; then
  package_dir="packages/$selected_package/"
  if [[ ! -f "${package_dir}pubspec.yaml" || ! -d "${package_dir}test" ]]; then
    echo "找不到可测试的内部包: $selected_package" >&2
    exit 66
  fi
  package_directories=("$package_dir")
fi

if [[ "$list_json" == true ]]; then
  if [[ -n "$selected_package" || ${#test_arguments[@]} -ne 0 ]]; then
    echo "--list-json 不接受包选择或测试参数" >&2
    exit 64
  fi
  separator=""
  printf '['
  for package_dir in "${package_directories[@]}"; do
    [[ -f "${package_dir}pubspec.yaml" && -d "${package_dir}test" ]] || continue
    package_name="${package_dir#packages/}"
    package_name="${package_name%/}"
    if [[ ! "$package_name" =~ ^[a-z][a-z0-9_]*$ ]]; then
      echo "非法内部包目录名" >&2
      exit 64
    fi
    printf '%s"%s"' "$separator" "$package_name"
    separator=,
  done
  printf ']\n'
  [[ -n "$separator" ]] || exit 66
  exit 0
fi

exit_code=0
package_count=0
for package_dir in "${package_directories[@]}"; do
  [[ -f "${package_dir}pubspec.yaml" ]] || continue
  [[ -d "${package_dir}test" ]] || continue
  package_count=$((package_count + 1))
  echo "==> ${package_dir}"
  # Flutter Package 必须用 flutter 工具链跑，否则解析不到 sdk: flutter 依赖。
  if grep -qE '^\s+sdk:\s+flutter$' "${package_dir}pubspec.yaml"; then
    runner=(flutter)
  else
    runner=(dart)
  fi
  # analyze 也要跑：根目录的 `flutter analyze` 只分析根 Package。
  (cd "$package_dir" && "${runner[@]}" analyze) || exit_code=1
  (cd "$package_dir" && "${runner[@]}" test ${test_arguments[@]+"${test_arguments[@]}"}) || exit_code=1
done

if [[ "$package_count" -eq 0 ]]; then
  echo "没有发现可测试的内部包" >&2
  exit 66
fi
exit "$exit_code"
