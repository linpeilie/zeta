#!/usr/bin/env python3
"""Privacy-safe, no-Prompt smoke for Claude Code initialize metadata."""

from __future__ import annotations

import argparse
import json
import os
import platform
import queue
import re
import shutil
import stat
import subprocess
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


_MAX_LINE_CHARS = 4 * 1024 * 1024
_VERSION_PATTERN = re.compile(r"\b(\d+\.\d+\.\d+)\b")
_INVALID_FRAME = object()


@dataclass(frozen=True)
class MetadataSummary:
    model_count: int
    default_count: int
    subscription: str


def _command(executable: Path, arguments: list[str]) -> list[str]:
    suffix = executable.suffix.lower()
    if os.name == "nt" and suffix in {".cmd", ".bat"}:
        return [
            "cmd.exe",
            "/d",
            "/s",
            "/c",
            "call",
            str(executable),
            *arguments,
        ]
    if os.name == "nt" and suffix == ".ps1":
        return [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-File",
            str(executable),
            *arguments,
        ]
    return [str(executable), *arguments]


def _resolve_claude(preferred: str) -> Path | None:
    candidates: list[Path] = []
    if preferred.strip():
        candidates.append(Path(preferred.strip()))
    discovered = shutil.which("claude")
    if discovered:
        candidates.append(Path(discovered))
    return next(
        (
            candidate
            for candidate in candidates
            if candidate.exists() and candidate.is_file()
        ),
        None,
    )


def _read_version(executable: Path, timeout: float) -> str | None:
    try:
        completed = subprocess.run(
            _command(executable, ["--version"]),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=min(timeout, 10.0),
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return None
    match = _VERSION_PATTERN.search(completed.stdout)
    return match.group(1) if match else None


def _metadata_arguments() -> list[str]:
    return [
        "--print",
        "--input-format",
        "stream-json",
        "--output-format",
        "stream-json",
        "--verbose",
        "--no-session-persistence",
        "--setting-sources",
        "user",
    ]


def _stdout_reader(stream: Any, frames: queue.Queue[object]) -> None:
    for line in stream:
        if len(line) > _MAX_LINE_CHARS:
            frames.put(_INVALID_FRAME)
            continue
        try:
            value = json.loads(line)
        except (json.JSONDecodeError, UnicodeError):
            frames.put(_INVALID_FRAME)
            continue
        frames.put(value if isinstance(value, dict) else _INVALID_FRAME)


def _stderr_drainer(stream: Any) -> None:
    # stderr may contain local paths or Provider diagnostics. Drain only.
    for _ in stream:
        pass


def _send_initialize(process: subprocess.Popen[str], request_id: str) -> bool:
    if process.stdin is None:
        return False
    frame = {
        "type": "control_request",
        "request_id": request_id,
        "request": {"subtype": "initialize"},
    }
    try:
        process.stdin.write(json.dumps(frame, separators=(",", ":")) + "\n")
        process.stdin.flush()
    except (BrokenPipeError, OSError):
        return False
    return True


def _non_empty_string(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def _safe_subscription(value: object) -> str:
    normalized = (_non_empty_string(value) or "").lower()
    known = {
        "pro": "Claude Pro",
        "claude pro": "Claude Pro",
        "max": "Claude Max",
        "claude max": "Claude Max",
        "team": "Claude Team",
        "claude team": "Claude Team",
        "enterprise": "Claude Enterprise",
        "claude enterprise": "Claude Enterprise",
        "free": "Claude Free",
        "claude free": "Claude Free",
    }
    if normalized in known:
        return known[normalized]
    return "present" if normalized else "unavailable"


def _project_frame(
    frame: object,
    *,
    expected_request_id: str | None,
) -> tuple[str, MetadataSummary | None]:
    if not isinstance(frame, dict) or frame.get("type") != "control_response":
        return "unrelated", None
    envelope = frame.get("response")
    if not isinstance(envelope, dict):
        return "unrelated", None
    if expected_request_id is not None and envelope.get("request_id") != expected_request_id:
        return "unrelated", None
    if envelope.get("subtype") != "success":
        return "response-error", None
    payload = envelope.get("response")
    if not isinstance(payload, dict):
        return "invalid-response", None

    seen: set[str] = set()
    default_count = 0
    models = payload.get("models")
    if isinstance(models, list):
        for item in models:
            if not isinstance(item, dict):
                continue
            model_id = _non_empty_string(item.get("value")) or _non_empty_string(
                item.get("name")
            )
            if model_id is None or model_id in seen:
                continue
            seen.add(model_id)
            if model_id == "default":
                default_count += 1

    account = payload.get("account")
    subscription = _safe_subscription(
        account.get("subscriptionType") if isinstance(account, dict) else None
    )
    return (
        "success",
        MetadataSummary(
            model_count=len(seen),
            default_count=default_count,
            subscription=subscription,
        ),
    )


def _make_workspace_read_only(path: Path) -> None:
    if os.name == "nt":
        os.chmod(path, stat.S_IREAD | stat.S_IEXEC)
    else:
        os.chmod(
            path,
            stat.S_IRUSR
            | stat.S_IXUSR
            | stat.S_IRGRP
            | stat.S_IXGRP
            | stat.S_IROTH
            | stat.S_IXOTH,
        )


def _restore_workspace_permissions(path: Path) -> None:
    try:
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
    except OSError:
        pass


def _close_process(process: subprocess.Popen[str] | None) -> None:
    if process is None:
        return
    try:
        if process.stdin is not None:
            process.stdin.close()
    except OSError:
        pass
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass


def _run_real(
    executable: Path,
    *,
    timeout: float,
) -> tuple[str, MetadataSummary | None]:
    request_id = f"zeta-metadata-{uuid.uuid4().hex}"
    process: subprocess.Popen[str] | None = None
    with tempfile.TemporaryDirectory(prefix="zeta-claude-metadata-") as raw_workspace:
        workspace = Path(raw_workspace)
        _make_workspace_read_only(workspace)
        try:
            try:
                process = subprocess.Popen(
                    _command(executable, _metadata_arguments()),
                    cwd=workspace,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1,
                )
            except OSError:
                return "process-start-failed", None

            assert process.stdout is not None
            assert process.stderr is not None
            frames: queue.Queue[object] = queue.Queue()
            threading.Thread(
                target=_stdout_reader,
                args=(process.stdout, frames),
                daemon=True,
            ).start()
            threading.Thread(
                target=_stderr_drainer,
                args=(process.stderr,),
                daemon=True,
            ).start()
            if not _send_initialize(process, request_id):
                return "stdin-write-failed", None

            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if process.poll() is not None and frames.empty():
                    return "early-exit", None
                remaining = max(0.0, deadline - time.monotonic())
                try:
                    frame = frames.get(timeout=min(0.25, remaining))
                except queue.Empty:
                    continue
                if frame is _INVALID_FRAME:
                    return "invalid-stream-json", None
                status, summary = _project_frame(
                    frame,
                    expected_request_id=request_id,
                )
                if status != "unrelated":
                    return status, summary
            return "timeout", None
        finally:
            _close_process(process)
            _restore_workspace_permissions(workspace)


def _run_fixture() -> tuple[str, str, str, MetadataSummary | None]:
    root = Path(__file__).resolve().parents[1]
    fixture = (
        root
        / "packages"
        / "claude_code_client"
        / "test"
        / "src"
        / "datasources"
        / "claude_code"
        / "fixtures"
        / "initialize_2_1_228_redacted.json"
    )
    try:
        frame = json.loads(fixture.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return "unavailable", "unknown", "unknown", None
    metadata = frame.get("_fixture") if isinstance(frame, dict) else None
    version = (
        _non_empty_string(metadata.get("cliVersion"))
        if isinstance(metadata, dict)
        else None
    )
    os_name = (
        _non_empty_string(metadata.get("os"))
        if isinstance(metadata, dict)
        else None
    )
    architecture = (
        _non_empty_string(metadata.get("architecture"))
        if isinstance(metadata, dict)
        else None
    )
    status, summary = _project_frame(frame, expected_request_id=None)
    return version or "unavailable", os_name or "unknown", architecture or "unknown", (
        summary if status == "success" else None
    )


def _print_summary(
    *,
    os_name: str,
    architecture: str,
    version: str,
    status: str,
    summary: MetadataSummary | None,
) -> None:
    passed = (
        status == "success"
        and summary is not None
        and summary.model_count > 0
        and summary.default_count == 1
    )
    print(f"OS: {os_name}")
    print(f"Architecture: {architecture}")
    print(f"Claude Code CLI: {version}")
    print(f"initialize={'PASS' if passed else f'FAIL ({status})'}")
    print(f"model_count={summary.model_count if summary else 0}")
    print(f"default_count={summary.default_count if summary else 0}")
    print(f"subscription={summary.subscription if summary else 'unavailable'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-bin", default="")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--expected-version", default="")
    parser.add_argument(
        "--fixture",
        action="store_true",
        help="Validate the bundled sanitized initialize fixture without starting Claude.",
    )
    args = parser.parse_args()

    if args.timeout <= 0:
        _print_summary(
            os_name=platform.system() or "unknown",
            architecture=platform.machine() or "unknown",
            version="unavailable",
            status="invalid-timeout",
            summary=None,
        )
        return 1

    if args.fixture:
        version, os_name, architecture, summary = _run_fixture()
        status = "success" if summary is not None else "fixture-invalid"
    else:
        os_name = platform.system() or "unknown"
        architecture = platform.machine() or "unknown"
        executable = _resolve_claude(args.claude_bin)
        if executable is None:
            _print_summary(
                os_name=os_name,
                architecture=architecture,
                version="unavailable",
                status="cli-not-found",
                summary=None,
            )
            return 2
        version = _read_version(executable, args.timeout) or "unavailable"
        if version == "unavailable":
            _print_summary(
                os_name=os_name,
                architecture=architecture,
                version=version,
                status="version-unavailable",
                summary=None,
            )
            return 2
        status, summary = _run_real(executable, timeout=args.timeout)

    expected = args.expected_version.strip()
    if expected and version != expected:
        status = "version-mismatch"
        summary = None
    _print_summary(
        os_name=os_name,
        architecture=architecture,
        version=version,
        status=status,
        summary=summary,
    )
    passed = (
        status == "success"
        and summary is not None
        and summary.model_count > 0
        and summary.default_count == 1
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
