#!/usr/bin/env python3
"""Privacy-safe smoke against a real Claude Code stream-json process.

The harness uses an empty temporary read-only workspace, denies every tool
control request, and suppresses prompts, replies, file contents, credentials,
raw protocol frames, session identifiers, and stderr. CI must not run it.
"""

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


_VERSION_PATTERN = re.compile(r"\b(\d+\.\d+\.\d+)\b")
_INVALID_FRAME = object()
_SMOKE_PROMPT = (
    "Run a non-destructive protocol smoke. Do not inspect files, use tools, "
    "run commands, or modify anything. Return one short acknowledgement."
)


@dataclass
class SmokeState:
    init_seen: bool = False
    assistant_text_seen: bool = False
    result_seen: bool = False
    result_succeeded: bool = False
    session_mismatch: bool = False
    invalid_frame_count: int = 0
    denied_control_count: int = 0


def _command(executable: Path, arguments: list[str]) -> list[str]:
    suffix = executable.suffix.lower()
    if os.name == "nt" and suffix in {".cmd", ".bat"}:
        return ["cmd.exe", "/d", "/s", "/c", str(executable), *arguments]
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

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


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


def _stdout_reader(
    stream: Any,
    frames: queue.Queue[object],
) -> None:
    for line in stream:
        try:
            value = json.loads(line)
        except (json.JSONDecodeError, UnicodeError):
            frames.put(_INVALID_FRAME)
            continue
        frames.put(value if isinstance(value, dict) else _INVALID_FRAME)


def _stderr_drainer(stream: Any) -> None:
    # stderr may contain paths, hooks, or provider diagnostics. Drain only.
    for _ in stream:
        pass


def _send(process: subprocess.Popen[str], frame: dict[str, Any]) -> bool:
    if process.stdin is None:
        return False
    try:
        process.stdin.write(json.dumps(frame, separators=(",", ":")) + "\n")
        process.stdin.flush()
    except (BrokenPipeError, OSError):
        return False
    return True


def _deny_control_request(
    process: subprocess.Popen[str],
    frame: dict[str, Any],
) -> bool:
    request_id = frame.get("request_id")
    if not isinstance(request_id, str) or not request_id:
        return False
    return _send(
        process,
        {
            "type": "control_response",
            "response": {
                "subtype": "success",
                "request_id": request_id,
                "response": {
                    "behavior": "deny",
                    "message": "Protocol smoke denies all tool use",
                },
            },
        },
    )


def _has_text_block(frame: dict[str, Any]) -> bool:
    message = frame.get("message")
    if not isinstance(message, dict):
        return False
    content = message.get("content")
    if not isinstance(content, list):
        return False
    return any(
        isinstance(block, dict) and block.get("type") == "text"
        for block in content
    )


def _observe(
    state: SmokeState,
    frame: object,
    *,
    expected_session_id: str,
    process: subprocess.Popen[str],
) -> None:
    if frame is _INVALID_FRAME or not isinstance(frame, dict):
        state.invalid_frame_count += 1
        return

    frame_type = frame.get("type")
    if frame_type == "control_request":
        if _deny_control_request(process, frame):
            state.denied_control_count += 1
        else:
            state.invalid_frame_count += 1
        return

    session_id = frame.get("session_id")
    if isinstance(session_id, str) and session_id != expected_session_id:
        state.session_mismatch = True

    if frame_type == "system" and frame.get("subtype") == "init":
        state.init_seen = session_id == expected_session_id
    elif frame_type == "assistant" and _has_text_block(frame):
        state.assistant_text_seen = True
    elif frame_type == "result":
        state.result_seen = True
        state.result_succeeded = (
            session_id == expected_session_id
            and frame.get("subtype") == "success"
            and frame.get("is_error") is not True
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


def _run_smoke(
    executable: Path,
    *,
    model: str,
    timeout: float,
) -> tuple[bool, str]:
    state = SmokeState()
    session_id = str(uuid.uuid4())
    process: subprocess.Popen[str] | None = None

    with tempfile.TemporaryDirectory(prefix="zeta-claude-smoke-") as raw_workspace:
        workspace = Path(raw_workspace)
        _make_workspace_read_only(workspace)
        try:
            arguments = [
                "--print",
                "--input-format",
                "stream-json",
                "--output-format",
                "stream-json",
                "--verbose",
                "--session-id",
                session_id,
                "--model",
                model,
                "--permission-prompt-tool",
                "stdio",
                "--permission-mode",
                "default",
                "--no-session-persistence",
            ]
            try:
                process = subprocess.Popen(
                    _command(executable, arguments),
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
                return False, "process-start-failed"

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

            if not _send(
                process,
                {
                    "type": "user",
                    "session_id": session_id,
                    "parent_tool_use_id": None,
                    "message": {
                        "role": "user",
                        "content": [{"type": "text", "text": _SMOKE_PROMPT}],
                    },
                },
            ):
                return False, "stdin-write-failed"

            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline and not state.result_seen:
                if process.poll() is not None and frames.empty():
                    break
                remaining = max(0.0, deadline - time.monotonic())
                try:
                    frame = frames.get(timeout=min(0.25, remaining))
                except queue.Empty:
                    continue
                _observe(
                    state,
                    frame,
                    expected_session_id=session_id,
                    process=process,
                )

            if state.session_mismatch:
                return False, "session-mismatch"
            if state.invalid_frame_count:
                return False, "invalid-stream-json"
            if not state.init_seen:
                return False, "missing-init"
            if not state.result_seen:
                return False, "timeout-or-early-exit"
            if not state.result_succeeded:
                return False, "result-failed"
            if not state.assistant_text_seen:
                return False, "missing-assistant-text"
            return True, "init+assistant+result"
        finally:
            _close_process(process)
            _restore_workspace_permissions(workspace)


def _print_summary(os_name: str, architecture: str, version: str, result: str) -> None:
    print(f"OS: {os_name}")
    print(f"Architecture: {architecture}")
    print(f"Claude Code CLI: {version}")
    print(f"Result: {result}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-bin", default="")
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--model", default="haiku")
    parser.add_argument(
        "--expected-version",
        default="",
        help="Require an exact Claude Code CLI version, for example 2.1.224.",
    )
    args = parser.parse_args()

    os_name = platform.system() or "unknown"
    architecture = platform.machine() or "unknown"
    executable = _resolve_claude(args.claude_bin)
    if executable is None:
        _print_summary(os_name, architecture, "unavailable", "BLOCKED (cli-not-found)")
        return 2

    version = _read_version(executable, args.timeout)
    if version is None:
        _print_summary(
            os_name,
            architecture,
            "unavailable",
            "BLOCKED (version-unavailable)",
        )
        return 2

    expected = args.expected_version.strip()
    if expected and version != expected:
        _print_summary(
            os_name,
            architecture,
            version,
            f"FAIL (version-mismatch; expected={expected})",
        )
        return 1

    if args.timeout <= 0:
        _print_summary(os_name, architecture, version, "FAIL (invalid-timeout)")
        return 1

    model = args.model.strip()
    if not model:
        _print_summary(os_name, architecture, version, "FAIL (invalid-model)")
        return 1

    succeeded, detail = _run_smoke(executable, model=model, timeout=args.timeout)
    result = f"PASS ({detail})" if succeeded else f"FAIL ({detail})"
    _print_summary(os_name, architecture, version, result)
    return 0 if succeeded else 1


if __name__ == "__main__":
    raise SystemExit(main())
