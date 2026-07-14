#!/usr/bin/env python3
"""Run a conservative smoke test against a real Cursor ``agent acp``.

The harness creates a temporary Git workspace by default, rejects every tool
permission request, never logs prompt bodies or raw protocol payloads, and
removes the temporary workspace when finished.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


SECRET_PATTERN = re.compile(
    r"(?i)(api[_-]?key|auth[_-]?token|access[_-]?token|authorization)"
    r"(\s*[:=]\s*)([^\s,;]+)"
)


@dataclass(frozen=True)
class CursorCommand:
    display_path: Path
    prefix: tuple[str, ...]
    version: str

    def argv(self, *arguments: str) -> list[str]:
        return [*self.prefix, *arguments]


@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


class HandshakeComplete(Exception):
    """Internal control flow used to keep cleanup and summary reporting shared."""


@dataclass
class Peer:
    process: subprocess.Popen[str]
    responses: dict[str, dict[str, Any]] = field(default_factory=dict)
    notifications: list[dict[str, Any]] = field(default_factory=list)
    server_request_methods: list[str] = field(default_factory=list)
    stderr_lines: list[str] = field(default_factory=list)
    _next_id: int = 1
    _lock: threading.Lock = field(default_factory=threading.Lock)
    _condition: threading.Condition = field(init=False)

    def __post_init__(self) -> None:
        self._condition = threading.Condition(self._lock)
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for raw_line in self.process.stdout:
            try:
                message = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            with self._condition:
                if "id" in message and ("result" in message or "error" in message):
                    self.responses[str(message["id"])] = message
                    self._condition.notify_all()
                elif "id" in message and "method" in message:
                    self.server_request_methods.append(str(message["method"]))
                    self._reply_to_server_request(message)
                elif "method" in message:
                    self.notifications.append(message)
                    self._condition.notify_all()

    def _read_stderr(self) -> None:
        assert self.process.stderr is not None
        for line in self.process.stderr:
            self.stderr_lines.append(redact(line.rstrip()))

    def _write(self, message: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.process.stdin.flush()

    def _reply_to_server_request(self, message: dict[str, Any]) -> None:
        method = str(message.get("method", ""))
        request_id = message.get("id")
        if method == "session/request_permission":
            options = (message.get("params") or {}).get("options") or []
            rejected = next(
                (
                    item
                    for item in options
                    if isinstance(item, dict)
                    and any(
                        token in str(item.get("kind", "")).lower()
                        for token in ("reject", "deny")
                    )
                ),
                None,
            )
            outcome: dict[str, Any] = {"outcome": "cancelled"}
            if rejected is not None:
                option_id = rejected.get("optionId") or rejected.get("option_id")
                if option_id:
                    outcome = {"outcome": "selected", "optionId": option_id}
            result: Any = {"outcome": outcome}
        elif method in {"cursor/ask_question", "cursor/create_plan"}:
            result = {"outcome": {"outcome": "cancelled"}}
        else:
            self._write(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {
                        "code": -32601,
                        "message": f"Zeta smoke does not support {method}",
                    },
                }
            )
            return
        self._write({"jsonrpc": "2.0", "id": request_id, "result": result})

    def request(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        *,
        timeout: float = 30,
    ) -> dict[str, Any]:
        request_id = self._next_id
        self._next_id += 1
        self._write(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params or {},
            }
        )
        deadline = time.time() + timeout
        key = str(request_id)
        with self._condition:
            while key not in self.responses:
                if self.process.poll() is not None:
                    raise RuntimeError(
                        f"Cursor ACP exited with code {self.process.returncode} "
                        f"while waiting for {method}"
                    )
                remaining = deadline - time.time()
                if remaining <= 0:
                    raise TimeoutError(f"Timed out waiting for {method}")
                self._condition.wait(timeout=min(remaining, 0.5))
            return self.responses.pop(key)

    def notify(self, method: str, params: dict[str, Any]) -> None:
        self._write({"jsonrpc": "2.0", "method": method, "params": params})

    def close(self) -> None:
        try:
            if self.process.stdin is not None:
                self.process.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(
                    [
                        "taskkill.exe",
                        "/PID",
                        str(self.process.pid),
                        "/T",
                        "/F",
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=8,
                    check=False,
                )
            else:
                self.process.kill()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()


def redact(value: str) -> str:
    value = SECRET_PATTERN.sub(r"\1\2<redacted>", value)
    home = str(Path.home())
    if home:
        value = value.replace(home, "<home>")
    return value[:1000]


def run_output(argv: list[str], *, timeout: float = 8) -> tuple[int, str]:
    completed = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        check=False,
    )
    return completed.returncode, completed.stdout.strip()


def launcher_prefix(path: Path) -> tuple[str, ...]:
    suffix = path.suffix.lower()
    if os.name == "nt" and suffix == ".ps1":
        powershell = shutil.which("powershell.exe") or shutil.which("pwsh.exe")
        if not powershell:
            raise RuntimeError("PowerShell is required to launch the selected .ps1")
        return (
            powershell,
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-File",
            str(path),
        )
    if os.name == "nt" and suffix in {".cmd", ".bat"}:
        return ("cmd.exe", "/d", "/s", "/c", str(path))
    return (str(path),)


def candidate_paths(preferred: str | None) -> list[Path]:
    raw: list[str] = []
    if preferred:
        raw.append(preferred)
    for name in ("cursor-agent", "agent"):
        located = shutil.which(name)
        if located:
            raw.append(located)
    home = Path.home()
    names = ("cursor-agent", "agent")
    if os.name == "nt":
        names = tuple(
            f"{name}{suffix}"
            for name in names
            for suffix in (".exe", ".cmd", ".bat", ".ps1")
        )
    for name in names:
        raw.append(str(home / ".local" / "bin" / name))
    result: list[Path] = []
    seen: set[str] = set()
    for value in raw:
        path = Path(value).expanduser()
        key = str(path.resolve(strict=False)).lower() if os.name == "nt" else str(path)
        if key not in seen:
            seen.add(key)
            result.append(path)
    return result


def resolve_cursor(preferred: str | None) -> CursorCommand:
    failures: list[str] = []
    for path in candidate_paths(preferred):
        if not path.is_file():
            continue
        try:
            prefix = launcher_prefix(path)
            version_code, version_output = run_output([*prefix, "--version"])
            _, about_output = run_output([*prefix, "about", "--format", "json"])
            help_code, help_output = run_output([*prefix, "help", "acp"])
        except (OSError, subprocess.SubprocessError, RuntimeError) as error:
            failures.append(f"{path.name}: {type(error).__name__}")
            continue
        identity = f"{version_output}\n{about_output}\n{help_output}".lower()
        is_cursor = "cursor" in identity and not re.search(r"\bgrok\b", identity)
        supports_acp = help_code == 0 and "acp" in help_output.lower()
        if version_code == 0 and is_cursor and supports_acp:
            version = version_output.splitlines()[0].strip() or "unknown"
            return CursorCommand(path, prefix, version)
        failures.append(f"{path.name}: identity/acp probe rejected")
    detail = "; ".join(failures[-4:]) or "no candidate files"
    raise SystemExit(
        "No verified Cursor CLI with ACP support was found. "
        f"Use --cursor-bin to select it. Probes: {detail}"
    )


def start_peer(command: CursorCommand, workspace: Path) -> Peer:
    process = subprocess.Popen(
        command.argv("acp"),
        cwd=workspace,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
    )
    return Peer(process)


def dig(value: Any, *path: str) -> Any:
    current = value
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def record(checks: list[Check], name: str, ok: bool, detail: str = "") -> None:
    checks.append(Check(name, ok, detail))
    suffix = f" — {redact(detail)}" if detail else ""
    print(f"[{'PASS' if ok else 'FAIL'}] {name}{suffix}")


def initialize(peer: Peer, timeout: float) -> dict[str, Any]:
    response = peer.request(
        "initialize",
        {
            "protocolVersion": 1,
            "clientCapabilities": {
                "fs": {"readTextFile": False, "writeTextFile": False},
                "terminal": False,
                "session": {"configOptions": {"boolean": {}}},
            },
            "clientInfo": {
                "name": "zeta-smoke",
                "title": "Zeta Cursor ACP Smoke",
                "version": "0.1.0",
            },
        },
        timeout=timeout,
    )
    if "error" in response:
        raise RuntimeError(f"initialize failed: {dig(response, 'error', 'message')}")
    result = response.get("result") or {}
    auth_methods = result.get("authMethods") or []
    if any(
        isinstance(item, dict) and item.get("id") == "cursor_login"
        for item in auth_methods
    ):
        authenticated = peer.request(
            "authenticate", {"methodId": "cursor_login"}, timeout=timeout
        )
        if "error" in authenticated:
            raise RuntimeError(
                f"authenticate failed: {dig(authenticated, 'error', 'message')}"
            )
    return result


def run_prompt_async(
    peer: Peer, session_id: str, prompt: str, timeout: float
) -> tuple[threading.Thread, dict[str, Any]]:
    result: dict[str, Any] = {}

    def worker() -> None:
        try:
            result["response"] = peer.request(
                "session/prompt",
                {"sessionId": session_id, "prompt": [{"type": "text", "text": prompt}]},
                timeout=timeout,
            )
        except BaseException as error:  # surfaced on the main smoke thread
            result["error"] = error

    thread = threading.Thread(target=worker, daemon=True)
    thread.start()
    return thread, result


def cleanup_temporary(temporary: tempfile.TemporaryDirectory[str]) -> None:
    """Retry Windows cleanup while a just-closed wrapper releases its cwd."""
    for attempt in range(10):
        try:
            temporary.cleanup()
            return
        except PermissionError:
            if attempt == 9:
                raise
            time.sleep(0.2 * (attempt + 1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cursor-bin", default="", help="Cursor agent executable or wrapper")
    parser.add_argument("--workspace", default="", help="Existing workspace; default is temporary")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument(
        "--handshake-only",
        action="store_true",
        help="Stop after identity, initialize, and authenticate",
    )
    parser.add_argument(
        "--skip-cancel",
        action="store_true",
        help="Skip the long-turn cancellation check",
    )
    args = parser.parse_args()

    command = resolve_cursor(args.cursor_bin or None)
    temporary: tempfile.TemporaryDirectory[str] | None = None
    if args.workspace:
        workspace = Path(args.workspace).expanduser().resolve()
        if not workspace.is_dir():
            raise SystemExit(f"Workspace does not exist: {workspace}")
    else:
        temporary = tempfile.TemporaryDirectory(prefix="Zeta Cursor 冒烟 空格 ")
        workspace = Path(temporary.name)
        git = shutil.which("git")
        if git:
            subprocess.run(
                [git, "init", "--quiet"], cwd=workspace, check=False, timeout=10
            )

    print(f"Cursor: {command.display_path}")
    print(f"Version: {command.version}")
    print(f"Platform: {sys.platform}; machine={os.environ.get('PROCESSOR_ARCHITECTURE', 'unknown')}")
    print(f"Workspace shape: temporary={temporary is not None}; spaces=True; unicode=True")

    checks: list[Check] = []
    peer: Peer | None = None
    session_id: str | None = None
    try:
        record(checks, "Cursor identity and ACP probe", True, command.version)
        peer = start_peer(command, workspace)
        init = initialize(peer, min(args.timeout, 30))
        info = init.get("agentInfo") or {}
        identity = " ".join(str(info.get(key, "")) for key in ("name", "title"))
        record(
            checks,
            "initialize/authenticate",
            init.get("protocolVersion") == 1
            and (not identity.strip() or "cursor" in identity.lower()),
            f"protocol={init.get('protocolVersion')}; agent={identity.strip() or 'not reported'}",
        )
        capabilities = init.get("agentCapabilities") or {}
        session_capabilities = capabilities.get("sessionCapabilities") or {}
        record(
            checks,
            "capability negotiation",
            isinstance(capabilities, dict),
            "session=" + ",".join(sorted(session_capabilities))
            if isinstance(session_capabilities, dict)
            else "session=none",
        )
        if args.handshake_only:
            raise HandshakeComplete

        created = peer.request(
            "session/new",
            {"cwd": str(workspace), "mcpServers": []},
            timeout=min(args.timeout, 60),
        )
        session_id = dig(created, "result", "sessionId")
        record(checks, "session/new", bool(session_id), "sessionId=present")
        if not session_id:
            raise RuntimeError("session/new did not return sessionId")

        notification_start = len(peer.notifications)
        prompt_response = peer.request(
            "session/prompt",
            {
                "sessionId": session_id,
                "prompt": [
                    {
                        "type": "text",
                        "text": (
                            "Read-only smoke test. Do not use tools, read files, or modify files. "
                            "Reply with exactly: ZETA_CURSOR_SMOKE_OK"
                        ),
                    }
                ],
            },
            timeout=args.timeout,
        )
        updates = [
            item
            for item in peer.notifications[notification_start:]
            if item.get("method") == "session/update"
        ]
        update_kinds = {
            str(dig(item, "params", "update", "sessionUpdate")) for item in updates
        }
        stop_reason = dig(prompt_response, "result", "stopReason")
        record(
            checks,
            "session/prompt streaming",
            "error" not in prompt_response and "agent_message_chunk" in update_kinds,
            f"updates={len(updates)}; stopReason={stop_reason}",
        )
        record(
            checks,
            "permission safety",
            True,
            "all tool requests rejected; requests="
            + ",".join(sorted(set(peer.server_request_methods))),
        )

        peer.close()
        peer = start_peer(command, workspace)
        init_after_restart = initialize(peer, min(args.timeout, 30))
        replay_start = len(peer.notifications)
        loaded = peer.request(
            "session/load",
            {"sessionId": session_id, "cwd": str(workspace), "mcpServers": []},
            timeout=args.timeout,
        )
        replay = [
            item
            for item in peer.notifications[replay_start:]
            if item.get("method") == "session/update"
        ]
        can_load = init_after_restart.get("agentCapabilities", {}).get("loadSession") is True
        record(
            checks,
            "restart and session/load replay",
            can_load and "error" not in loaded and bool(replay),
            f"loadCapability={can_load}; replayUpdates={len(replay)}",
        )

        if not args.skip_cancel:
            thread, cancel_result = run_prompt_async(
                peer,
                session_id,
                "Count from 1 to 10000 slowly. Do not use tools.",
                args.timeout,
            )
            time.sleep(0.5)
            peer.notify("session/cancel", {"sessionId": session_id})
            thread.join(timeout=min(args.timeout, 60))
            response = cancel_result.get("response")
            cancel_error = cancel_result.get("error")
            record(
                checks,
                "session/cancel",
                not thread.is_alive() and cancel_error is None and isinstance(response, dict),
                "prompt request settled after cancel",
            )

        session_caps = init_after_restart.get("agentCapabilities", {}).get(
            "sessionCapabilities", {}
        )
        if isinstance(session_caps, dict) and "list" in session_caps:
            listed = peer.request(
                "session/list", {"cwd": str(workspace)}, timeout=min(args.timeout, 30)
            )
            record(checks, "session/list (negotiated)", "error" not in listed)
        else:
            record(checks, "session/list (optional)", True, "not advertised; skipped")

        if isinstance(session_caps, dict) and "delete" in session_caps:
            deleted = peer.request(
                "session/delete", {"sessionId": session_id}, timeout=min(args.timeout, 30)
            )
            record(checks, "session/delete (negotiated)", "error" not in deleted)
        else:
            record(checks, "session/delete (optional)", True, "not advertised; skipped")
    except HandshakeComplete:
        pass
    except BaseException as error:
        record(checks, "smoke execution", False, f"{type(error).__name__}: {error}")
    finally:
        if peer is not None:
            peer.close()
        if temporary is not None:
            try:
                cleanup_temporary(temporary)
            except PermissionError as error:
                record(checks, "temporary workspace cleanup", False, str(error))

    passed = sum(item.ok for item in checks)
    failed = len(checks) - passed
    print(f"\nSmoke summary: {passed} passed, {failed} failed")
    if peer is not None and peer.stderr_lines:
        print("stderr tail (redacted):")
        for line in peer.stderr_lines[-10:]:
            print(f"  {line}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
