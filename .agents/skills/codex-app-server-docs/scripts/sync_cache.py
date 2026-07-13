#!/usr/bin/env python3
"""同步 Codex App-Server 官方文档与本机版本 API schema 缓存。"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, NamedTuple
import urllib.error
import urllib.request
from datetime import datetime, timezone


SKILL_DIR = Path(__file__).resolve().parents[1]
REFERENCES_DIR = SKILL_DIR / "references"
MANIFEST_PATH = REFERENCES_DIR / "cache-manifest.json"
DOCUMENT_PATH = REFERENCES_DIR / "cached-app-server.md"
STABLE_SCHEMA_PATH = REFERENCES_DIR / "app-server-api.stable.schema.json"
EXPERIMENTAL_SCHEMA_PATH = (
    REFERENCES_DIR / "app-server-api.experimental.schema.json"
)

DOCUMENT_SOURCE = (
    "https://raw.githubusercontent.com/openai/codex/main/"
    "codex-rs/app-server/README.md"
)
PUBLISHED_DOCUMENT_URL = "https://developers.openai.com/codex/app-server"
LATEST_RELEASE_SOURCE = (
    "https://api.github.com/repos/openai/codex/releases/latest"
)
GENERATED_SCHEMA_NAME = "codex_app_server_protocol.v2.schemas.json"
USER_AGENT = "zeta-codex-app-server-docs-cache/1.0"
FORMAT_VERSION = 1


class FetchResult(NamedTuple):
    """一次带条件请求的结果。"""

    modified: bool
    body: bytes | None
    etag: str | None
    last_modified: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="检查并同步 Codex App-Server 文档与 API schema 缓存。"
    )
    parser.add_argument(
        "--codex",
        default=os.environ.get("CODEX_BIN", "codex"),
        help="Codex CLI 可执行文件，默认读取 CODEX_BIN 或使用 codex。",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="每个网络请求和 CLI 探测的超时秒数。",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="忽略缓存版本并重新抓取文档、生成 schema。",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="跳过网络版本检查，仅核对本机 CLI 和现有缓存。",
    )
    return parser.parse_args()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def relative_path(path: Path) -> str:
    return path.relative_to(SKILL_DIR).as_posix()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_manifest(warnings: list[str]) -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        return {"format_version": FORMAT_VERSION}
    try:
        value = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        warnings.append(f"缓存 manifest 无法读取，将重建：{error}")
        return {"format_version": FORMAT_VERSION}
    if not isinstance(value, dict):
        warnings.append("缓存 manifest 不是 JSON object，将重建。")
        return {"format_version": FORMAT_VERSION}
    if value.get("format_version") != FORMAT_VERSION:
        warnings.append("缓存 manifest 版本不兼容，将重建。")
        return {"format_version": FORMAT_VERSION}
    return value


def atomic_write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_manifest(manifest: dict[str, Any]) -> None:
    payload = json.dumps(
        manifest,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ).encode("utf-8") + b"\n"
    atomic_write_bytes(MANIFEST_PATH, payload)


def fetch(url: str, *, etag: str | None, timeout: float) -> FetchResult:
    headers = {
        "Accept": "application/json, text/plain, text/markdown, */*",
        "User-Agent": USER_AGENT,
    }
    if etag:
        headers["If-None-Match"] = etag
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return FetchResult(
                modified=True,
                body=response.read(),
                etag=response.headers.get("ETag"),
                last_modified=response.headers.get("Last-Modified"),
            )
    except urllib.error.HTTPError as error:
        if error.code == 304:
            return FetchResult(
                modified=False,
                body=None,
                etag=etag,
                last_modified=error.headers.get("Last-Modified"),
            )
        raise RuntimeError(f"{url} 返回 HTTP {error.code}: {error.reason}") from error
    except (OSError, urllib.error.URLError) as error:
        raise RuntimeError(f"无法访问 {url}: {error}") from error


def extract_version(value: str | None) -> str | None:
    if not value:
        return None
    match = re.search(
        r"(?<!\d)(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)",
        value,
    )
    return match.group(1) if match else None


def version_core(value: str | None) -> tuple[int, int, int] | None:
    if not value:
        return None
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", value)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def resolve_codex(command: str) -> str:
    resolved = shutil.which(command)
    if resolved:
        return resolved
    path = Path(command).expanduser()
    if path.exists():
        return str(path.resolve())
    return command


def detect_codex_version(
    command: str,
    *,
    timeout: float,
) -> tuple[str, str]:
    completed = subprocess.run(
        [command, "--version"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    raw = (completed.stdout or completed.stderr).strip().splitlines()[0]
    version = extract_version(raw)
    if not version:
        raise RuntimeError(f"无法从 Codex CLI 输出解析版本：{raw!r}")
    return raw, version


def validate_document(data: bytes) -> str:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError("官方 App-Server 文档不是 UTF-8。") from error
    lowered = text.lower()
    if "codex-app-server" not in lowered or "## protocol" not in lowered:
        raise RuntimeError("官方 App-Server 文档缺少预期标题或 Protocol 章节。")
    return text


def validate_schema(data: bytes, *, label: str) -> None:
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} schema 不是有效 JSON：{error}") from error
    if not isinstance(value, dict) or len(data) < 1_000:
        raise RuntimeError(f"{label} schema 内容不完整。")


def generate_schemas(
    codex_command: str,
    *,
    timeout: float,
) -> tuple[bytes, bytes]:
    """生成 stable 与 experimental V2 合并 schema，全部成功后再写缓存。"""

    with tempfile.TemporaryDirectory(prefix="codex-app-server-schema-") as root:
        root_path = Path(root)
        stable_dir = root_path / "stable"
        experimental_dir = root_path / "experimental"
        commands = (
            (
                "stable",
                [
                    codex_command,
                    "app-server",
                    "generate-json-schema",
                    "--out",
                    str(stable_dir),
                ],
            ),
            (
                "experimental",
                [
                    codex_command,
                    "app-server",
                    "generate-json-schema",
                    "--experimental",
                    "--out",
                    str(experimental_dir),
                ],
            ),
        )
        for label, command in commands:
            try:
                subprocess.run(
                    command,
                    check=True,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=max(timeout, 30.0),
                )
            except subprocess.CalledProcessError as error:
                detail = (error.stderr or error.stdout or "").strip()
                raise RuntimeError(f"生成 {label} schema 失败：{detail}") from error

        stable = (stable_dir / GENERATED_SCHEMA_NAME).read_bytes()
        experimental = (experimental_dir / GENERATED_SCHEMA_NAME).read_bytes()
        validate_schema(stable, label="stable")
        validate_schema(experimental, label="experimental")
        return stable, experimental


def documentation_record(
    result: FetchResult,
    data: bytes,
    *,
    updated_at: str,
) -> dict[str, Any]:
    return {
        "source": DOCUMENT_SOURCE,
        "published_url": PUBLISHED_DOCUMENT_URL,
        "path": relative_path(DOCUMENT_PATH),
        "sha256": sha256_bytes(data),
        "etag": result.etag,
        "last_modified": result.last_modified,
        "updated_at": updated_at,
    }


def release_record(
    result: FetchResult,
    data: bytes,
    *,
    updated_at: str,
) -> dict[str, Any]:
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"GitHub latest release 响应不是有效 JSON：{error}") from error
    if not isinstance(value, dict) or not isinstance(value.get("tag_name"), str):
        raise RuntimeError("GitHub latest release 响应缺少 tag_name。")
    tag_name = value["tag_name"]
    return {
        "source": LATEST_RELEASE_SOURCE,
        "tag_name": tag_name,
        "version": extract_version(tag_name),
        "published_at": value.get("published_at"),
        "html_url": value.get("html_url"),
        "etag": result.etag,
        "updated_at": updated_at,
    }


def main() -> int:
    args = parse_args()
    warnings: list[str] = []
    notices: list[str] = []
    updated: list[str] = []
    checked_at = utc_now()
    manifest = load_manifest(warnings)
    original_manifest = json.loads(json.dumps(manifest))
    previous_release_cache = manifest.get("latest_release")
    if (
        isinstance(previous_release_cache, dict)
        and "checked_at" in previous_release_cache
        and "updated_at" not in previous_release_cache
    ):
        migrated_release = dict(previous_release_cache)
        migrated_release["updated_at"] = migrated_release.pop("checked_at")
        manifest["latest_release"] = migrated_release
        updated.append("cache_manifest")

    codex_command = resolve_codex(args.codex)
    codex_version_raw: str | None = None
    codex_version: str | None = None
    try:
        codex_version_raw, codex_version = detect_codex_version(
            codex_command,
            timeout=args.timeout,
        )
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        warnings.append(f"无法探测本机 Codex CLI：{error}")

    document_result: FetchResult | None = None
    latest_release_result: FetchResult | None = None
    if args.offline:
        notices.append("已按 --offline 跳过官方文档与 latest release 检查。")
    else:
        previous_document = manifest.get("documentation")
        previous_release = manifest.get("latest_release")
        document_etag = None
        release_etag = None
        if not args.force and DOCUMENT_PATH.exists() and isinstance(previous_document, dict):
            document_etag = previous_document.get("etag")
        if not args.force and isinstance(previous_release, dict):
            release_etag = previous_release.get("etag")

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            document_future = executor.submit(
                fetch,
                DOCUMENT_SOURCE,
                etag=document_etag,
                timeout=args.timeout,
            )
            release_future = executor.submit(
                fetch,
                LATEST_RELEASE_SOURCE,
                etag=release_etag,
                timeout=args.timeout,
            )
            try:
                document_result = document_future.result()
            except RuntimeError as error:
                warnings.append(f"官方文档检查失败：{error}")
            try:
                latest_release_result = release_future.result()
            except RuntimeError as error:
                warnings.append(f"latest release 检查失败：{error}")

    if document_result and document_result.modified:
        assert document_result.body is not None
        try:
            document_text = validate_document(document_result.body)
            old_hash = None
            previous = manifest.get("documentation")
            if isinstance(previous, dict):
                old_hash = previous.get("sha256")
            new_hash = sha256_bytes(document_result.body)
            if old_hash != new_hash or not DOCUMENT_PATH.exists():
                atomic_write_bytes(DOCUMENT_PATH, document_text.encode("utf-8"))
                updated.append("documentation")
                record = documentation_record(
                    document_result,
                    document_result.body,
                    updated_at=checked_at,
                )
                manifest["documentation"] = record
            elif not isinstance(previous, dict):
                manifest["documentation"] = documentation_record(
                    document_result,
                    document_result.body,
                    updated_at=checked_at,
                )
        except (OSError, RuntimeError) as error:
            warnings.append(f"官方文档缓存更新失败：{error}")

    if latest_release_result and latest_release_result.modified:
        assert latest_release_result.body is not None
        try:
            record = release_record(
                latest_release_result,
                latest_release_result.body,
                updated_at=checked_at,
            )
            previous = manifest.get("latest_release")
            semantic_keys = ("tag_name", "version", "published_at", "html_url")
            release_changed = not isinstance(previous, dict) or any(
                previous.get(key) != record.get(key) for key in semantic_keys
            )
            if release_changed:
                manifest["latest_release"] = record
                updated.append("latest_release")
        except RuntimeError as error:
            warnings.append(f"latest release 缓存更新失败：{error}")

    previous_api = manifest.get("api")
    api_cache_missing = not (
        STABLE_SCHEMA_PATH.exists() and EXPERIMENTAL_SCHEMA_PATH.exists()
    )
    api_version_changed = not (
        isinstance(previous_api, dict)
        and codex_version is not None
        and previous_api.get("codex_version") == codex_version
    )
    should_generate = codex_version is not None and (
        args.force or api_cache_missing or api_version_changed
    )
    if should_generate:
        try:
            stable_schema, experimental_schema = generate_schemas(
                codex_command,
                timeout=args.timeout,
            )
            atomic_write_bytes(STABLE_SCHEMA_PATH, stable_schema)
            atomic_write_bytes(EXPERIMENTAL_SCHEMA_PATH, experimental_schema)
            manifest["api"] = {
                "codex_version_raw": codex_version_raw,
                "codex_version": codex_version,
                "generated_at": checked_at,
                "stable": {
                    "path": relative_path(STABLE_SCHEMA_PATH),
                    "sha256": sha256_bytes(stable_schema),
                    "experimental": False,
                },
                "experimental": {
                    "path": relative_path(EXPERIMENTAL_SCHEMA_PATH),
                    "sha256": sha256_bytes(experimental_schema),
                    "experimental": True,
                },
            }
            updated.append("api_schemas")
        except (OSError, subprocess.SubprocessError, RuntimeError) as error:
            warnings.append(f"API schema 缓存更新失败：{error}")

    latest_release = manifest.get("latest_release")
    latest_version = (
        latest_release.get("version") if isinstance(latest_release, dict) else None
    )
    installed_core = version_core(codex_version)
    latest_core = version_core(latest_version)
    release_update_available = (
        latest_core > installed_core
        if installed_core is not None and latest_core is not None
        else None
    )
    if release_update_available:
        notices.append(
            f"官方最新 release {latest_version} 高于本机 {codex_version}；"
            "文档已检查，但 API schema 仍严格对应本机版本。"
        )

    if manifest != original_manifest:
        try:
            write_manifest(manifest)
        except OSError as error:
            warnings.append(f"缓存 manifest 写入失败：{error}")

    cached_api = manifest.get("api")
    schema_matches_installed = (
        isinstance(cached_api, dict)
        and codex_version is not None
        and cached_api.get("codex_version") == codex_version
    )
    cache_usable = (
        DOCUMENT_PATH.exists()
        and STABLE_SCHEMA_PATH.exists()
        and EXPERIMENTAL_SCHEMA_PATH.exists()
    )
    if codex_version is not None and not schema_matches_installed:
        warnings.append("缓存 API schema 与本机 Codex CLI 版本不匹配。")

    status = "degraded" if warnings or not cache_usable else (
        "updated" if updated else "current"
    )
    output = {
        "status": status,
        "checked_at": checked_at,
        "updated": updated,
        "warnings": warnings,
        "notices": notices,
        "installed_codex_version": codex_version,
        "latest_release_version": latest_version,
        "release_update_available": release_update_available,
        "schema_matches_installed": schema_matches_installed,
        "cache_usable": cache_usable,
        "paths": {
            "manifest": relative_path(MANIFEST_PATH),
            "documentation": relative_path(DOCUMENT_PATH),
            "stable_schema": relative_path(STABLE_SCHEMA_PATH),
            "experimental_schema": relative_path(EXPERIMENTAL_SCHEMA_PATH),
        },
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0 if cache_usable else 1


if __name__ == "__main__":
    sys.exit(main())
