#!/usr/bin/env bash
# 从本机 Codex CLI 导出 app-server JSON Schema，写入仓库内的 pinned 快照。
#
# 用法:
#   ./tool/gen_codex_schema.sh              # 生成并覆盖 third_party/codex_app_server_schema
#   ./tool/gen_codex_schema.sh --diff       # 生成到临时目录，与已提交快照做 diff（不写入）
#   ./tool/gen_codex_schema.sh --force      # 允许 CLI 版本与 PINNED_VERSION 不一致
#   ./tool/gen_codex_schema.sh --experimental
#   CODEX_BIN=/path/to/codex ./tool/gen_codex_schema.sh
#
# 升级协议时:先用新版本 CLI 跑本脚本，review schema diff，再改适配层。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/third_party/codex_app_server_schema"
PINNED_FILE="${OUT_DIR}/PINNED_VERSION"

DIFF_ONLY=0
FORCE=0
EXPERIMENTAL=0
CODEX_BIN="${CODEX_BIN:-codex}"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

# CLI 对该聚合文件的 definitions 键序不稳定，逐方法 v2/*.json 已覆盖同等信息。
strip_nondeterministic_files() {
  local target_dir="$1"
  rm -f "$target_dir/codex_app_server_protocol.v2.schemas.json"
}

write_meta() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  printf '%s\n' "$cli_version" >"$target_dir/PINNED_VERSION"
  cat >"$target_dir/GENERATED.json" <<EOF
{
  "codexCliVersion": "$cli_version",
  "generatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "command": "$CODEX_BIN app-server generate-json-schema --out <dir>$([[ "$EXPERIMENTAL" -eq 1 ]] && printf ' --experimental')",
  "experimental": $([[ "$EXPERIMENTAL" -eq 1 ]] && echo true || echo false),
  "excludedNondeterministicFiles": [
    "codex_app_server_protocol.v2.schemas.json"
  ]
}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff) DIFF_ONLY=1 ;;
    --force) FORCE=1 ;;
    --experimental) EXPERIMENTAL=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if ! command -v "$CODEX_BIN" >/dev/null 2>&1 && [[ ! -x "$CODEX_BIN" ]]; then
  echo "Codex CLI not found: $CODEX_BIN" >&2
  echo "Install Codex CLI, or set CODEX_BIN to an absolute path." >&2
  exit 127
fi

version_line="$("$CODEX_BIN" --version 2>/dev/null | head -n 1 || true)"
# 期望形如 "codex-cli 0.142.5"
cli_version="$(printf '%s\n' "$version_line" | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
if [[ -z "$cli_version" ]]; then
  echo "Could not parse Codex CLI version from: ${version_line:-<empty>}" >&2
  exit 1
fi

pinned_version=""
if [[ -f "$PINNED_FILE" ]]; then
  pinned_version="$(tr -d '[:space:]' <"$PINNED_FILE")"
fi

if [[ -n "$pinned_version" && "$cli_version" != "$pinned_version" && "$FORCE" -ne 1 ]]; then
  echo "Codex CLI version mismatch:" >&2
  echo "  pinned : $pinned_version (see $PINNED_FILE)" >&2
  echo "  current: $cli_version ($CODEX_BIN)" >&2
  echo "Re-run with --force after intentionally upgrading the pin," >&2
  echo "or set CODEX_BIN to the pinned CLI." >&2
  exit 2
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zeta-codex-schema.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

gen_args=(app-server generate-json-schema --out "$tmp_dir")
if [[ "$EXPERIMENTAL" -eq 1 ]]; then
  gen_args+=(--experimental)
fi

echo "Generating schema with $CODEX_BIN ($cli_version) ..."
"$CODEX_BIN" "${gen_args[@]}"
strip_nondeterministic_files "$tmp_dir"

# 基本完整性检查：四个联合类型必须存在。
for required in ClientRequest.json ClientNotification.json ServerNotification.json ServerRequest.json; do
  if [[ ! -f "$tmp_dir/$required" ]]; then
    echo "Schema generation incomplete: missing $required" >&2
    exit 1
  fi
done

if [[ "$DIFF_ONLY" -eq 1 ]]; then
  if [[ ! -d "$OUT_DIR" ]]; then
    echo "No committed schema at $OUT_DIR; run without --diff first." >&2
    exit 1
  fi
  write_meta "$tmp_dir"
  echo "Diffing generated schema against $OUT_DIR ..."

  changed=0
  while IFS= read -r -d '' file; do
    rel="${file#"$tmp_dir"/}"
    [[ "$rel" == "GENERATED.json" ]] && continue
    old="$OUT_DIR/$rel"
    if [[ ! -f "$old" ]] || ! cmp -s "$file" "$old"; then
      echo "CHANGED: $rel"
      changed=1
    fi
  done < <(find "$tmp_dir" -type f -print0 | sort -z)

  while IFS= read -r -d '' file; do
    rel="${file#"$OUT_DIR"/}"
    [[ "$rel" == "GENERATED.json" || "$rel" == "README.md" ]] && continue
    if [[ ! -f "$tmp_dir/$rel" ]]; then
      echo "REMOVED: $rel"
      changed=1
    fi
  done < <(find "$OUT_DIR" -type f -print0 | sort -z)

  if [[ "$changed" -eq 0 ]]; then
    echo "Schema snapshot matches current CLI output."
    exit 0
  fi
  echo "Schema drift detected. Review CHANGED/REMOVED files above." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
# 保留 README.md，其余由本次生成覆盖。
find "$OUT_DIR" -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec rm -rf {} +
cp -a "$tmp_dir"/. "$OUT_DIR"/
write_meta "$OUT_DIR"

file_count="$(find "$OUT_DIR" -type f ! -name 'README.md' | wc -l | tr -d ' ')"
echo "Wrote $file_count schema files to $OUT_DIR"
echo "Pinned Codex CLI version: $cli_version"
echo "Next: git diff --stat third_party/codex_app_server_schema"
echo "Then update docs/protocols/codex_app_server_protocol.md if the pin changed."
