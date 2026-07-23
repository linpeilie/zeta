#!/usr/bin/env python3
"""Core smoke against a real `codex app-server --stdio`.

Validates handshake, turn streaming signals, interrupt, unsubscribe, and
localImage encoding. The caller may require an exact CLI version with
``--expected-version``; otherwise the harness reports the discovered version.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


TINY_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

OPT_OUT = [
    "thread/realtime/closed",
    "thread/realtime/error",
    "thread/realtime/itemAdded",
    "thread/realtime/outputAudio/delta",
    "thread/realtime/sdp",
    "thread/realtime/started",
    "thread/realtime/transcript/delta",
    "thread/realtime/transcript/done",
    "remoteControl/status/changed",
    "app/list/updated",
    "windows/worldWritableWarning",
    "windowsSandbox/setupCompleted",
    "model/safetyBuffering/updated",
    "model/verification",
    "turn/moderationMetadata",
]


@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


@dataclass
class Peer:
    proc: subprocess.Popen[str]
    responses: dict[str, dict[str, Any]] = field(default_factory=dict)
    notifications: list[dict[str, Any]] = field(default_factory=list)
    server_requests: list[dict[str, Any]] = field(default_factory=list)
    stderr_lines: list[str] = field(default_factory=list)
    raw_lines: list[str] = field(default_factory=list)
    user_input_answers_sent: int = 0
    _next_id: int = 1
    _lock: threading.Lock = field(default_factory=threading.Lock)
    _cv: threading.Condition = field(init=False)

    def __post_init__(self) -> None:
        self._cv = threading.Condition(self._lock)
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_stdout(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            with self._cv:
                self.raw_lines.append(line)
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            with self._cv:
                if "id" in msg and ("result" in msg or "error" in msg):
                    self.responses[str(msg["id"])] = msg
                    self._cv.notify_all()
                elif "method" in msg and "id" in msg:
                    self.server_requests.append(msg)
                    self._cv.notify_all()
                    self._reply_server_request(msg)
                elif "method" in msg:
                    self.notifications.append(msg)
                    self._cv.notify_all()

    def _read_stderr(self) -> None:
        assert self.proc.stderr is not None
        for line in self.proc.stderr:
            self.stderr_lines.append(line.rstrip())

    def _write(self, message: dict[str, Any]) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()

    def _reply_server_request(self, msg: dict[str, Any]) -> None:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "item/tool/requestUserInput":
            result: Any = {"answers": self._user_input_answers(msg.get("params"))}
            self.user_input_answers_sent += 1
        elif method == "mcpServer/elicitation/request":
            result = {"action": "decline"}
        elif method in {
            "item/tool/call",
            "account/chatgptAuthTokens/refresh",
            "attestation/generate",
        }:
            self._write(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {
                        "code": -32601,
                        "message": f"Smoke harness rejects {method}",
                    },
                }
            )
            return
        else:
            result = {"decision": "denied"}
        self._write({"jsonrpc": "2.0", "id": req_id, "result": result})

    def _user_input_answers(self, params: Any) -> dict[str, Any]:
        if not isinstance(params, dict):
            return {}
        questions = params.get("questions")
        if not isinstance(questions, list):
            return {}
        answers: dict[str, Any] = {}
        for question in questions:
            if not isinstance(question, dict):
                continue
            question_id = question.get("id")
            if not isinstance(question_id, str) or not question_id.strip():
                continue
            selected = "continue"
            options = question.get("options")
            if isinstance(options, list) and options:
                first = options[0]
                if isinstance(first, dict):
                    label = first.get("label")
                    if isinstance(label, str) and label.strip():
                        selected = label.strip()
                elif isinstance(first, str) and first.strip():
                    selected = first.strip()
            answers[question_id] = {"answers": [selected]}
        return answers

    def request(
        self, method: str, params: dict[str, Any] | None = None, timeout: float = 30
    ) -> dict[str, Any]:
        req_id = self._next_id
        self._next_id += 1
        self._write(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "method": method,
                "params": params or {},
            }
        )
        deadline = time.time() + timeout
        key = str(req_id)
        with self._cv:
            while key not in self.responses:
                remaining = deadline - time.time()
                if remaining <= 0:
                    raise TimeoutError(f"wait response id={req_id} method={method}")
                self._cv.wait(timeout=remaining)
            return self.responses[key]

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        payload: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        self._write(payload)

    def wait_notification(
        self,
        predicate: Callable[[dict[str, Any]], bool],
        *,
        timeout: float,
        label: str,
        start_index: int = 0,
    ) -> dict[str, Any]:
        deadline = time.time() + timeout
        idx = start_index
        with self._cv:
            while True:
                while idx < len(self.notifications):
                    item = self.notifications[idx]
                    idx += 1
                    if predicate(item):
                        return item
                remaining = deadline - time.time()
                if remaining <= 0:
                    raise TimeoutError(f"wait notification: {label}")
                self._cv.wait(timeout=remaining)

    def close(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except OSError:
            pass
        if self.proc.poll() is None:
            self.proc.kill()
        try:
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pass


def resolve_codex(preferred: str | None) -> Path:
    candidates: list[Path] = []
    if preferred:
        candidates.append(Path(preferred))
    local = Path(os.environ.get("LOCALAPPDATA", "")) / (
        "Programs/OpenAI/Codex/bin/codex.exe"
    )
    if local.exists():
        candidates.append(local)
    which = shutil.which("codex")
    if which:
        candidates.append(Path(which))

    for candidate in candidates:
        if not candidate.exists():
            continue
        try:
            subprocess.check_output(
                [str(candidate), "--version"], text=True, stderr=subprocess.STDOUT
            )
        except (OSError, subprocess.CalledProcessError):
            continue
        else:
            return candidate
    raise SystemExit("未找到可执行的 Codex CLI，请用 --codex-bin 指定。")


def normalized_codex_version(raw: str) -> str:
    prefix = "codex-cli "
    return raw[len(prefix) :].strip() if raw.startswith(prefix) else raw.strip()


def check(checks: list[Check], name: str, ok: bool, detail: str = "") -> None:
    checks.append(Check(name=name, ok=ok, detail=detail))
    mark = "PASS" if ok else "FAIL"
    suffix = f" - {detail}" if detail else ""
    print(f"[{mark}] {name}{suffix}")


def dig(obj: Any, *path: str) -> Any:
    cur = obj
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def notification_methods(peer: Peer) -> set[str]:
    return {n.get("method", "") for n in peer.notifications}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-bin", default="")
    parser.add_argument("--cwd", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument(
        "--expected-version",
        default="",
        help="Require an exact Codex CLI version, for example 0.144.5.",
    )
    args = parser.parse_args()

    codex = resolve_codex(args.codex_bin or None)
    version = subprocess.check_output(
        [str(codex), "--version"], text=True, stderr=subprocess.STDOUT
    ).strip()
    cwd = str(Path(args.cwd).resolve())
    print(f"Codex: {codex}")
    print(f"Version: {version}")
    print(f"Cwd: {cwd}")

    checks: list[Check] = []
    png_path: Path | None = None
    peer: Peer | None = None

    try:
        if args.expected_version:
            check(
                checks,
                "Codex version",
                normalized_codex_version(version) == args.expected_version,
                f"actual={normalized_codex_version(version)}; "
                f"expected={args.expected_version}",
            )

        proc = subprocess.Popen(
            [str(codex), "app-server", "--stdio"],
            cwd=cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        peer = Peer(proc=proc)

        init = peer.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "zeta-smoke",
                    "title": "Zeta Phase1 Smoke",
                    "version": "0.1.0",
                },
                "capabilities": {
                    "experimentalApi": False,
                    "requestAttestation": False,
                    "mcpServerOpenaiFormElicitation": False,
                    "optOutNotificationMethods": OPT_OUT,
                },
            },
        )
        check(
            checks,
            "initialize",
            "error" not in init,
            "ok" if "error" not in init else json.dumps(init["error"], ensure_ascii=False),
        )
        peer.notify("initialized", {})

        models = peer.request(
            "model/list", {"limit": 20, "includeHidden": False}
        )
        model_data = dig(models, "result", "data") or dig(models, "result", "models") or []
        check(
            checks,
            "model/list",
            "error" not in models and len(model_data) > 0,
            f"models={len(model_data)}",
        )

        started = peer.request(
            "thread/start",
            {
                "cwd": cwd,
                "approvalPolicy": "on-request",
                "ephemeral": True,
            },
        )
        thread_id = dig(started, "result", "thread", "id") or dig(started, "result", "id")
        check(checks, "thread/start", bool(thread_id), f"threadId={thread_id}")
        if not thread_id:
            raise RuntimeError("thread/start 未返回 threadId")

        png_path = Path(tempfile.gettempdir()) / f"zeta-smoke-{os.getpid()}.png"
        png_path.write_bytes(TINY_PNG)
        prompt = (
            "Phase1 smoke only. Reply with exactly one short sentence. "
            "Do not run tools, do not edit files, do not ask questions."
        )
        turn_start = peer.request(
            "turn/start",
            {
                "threadId": thread_id,
                "cwd": cwd,
                "effort": "low",
                "input": [
                    {"type": "text", "text": prompt},
                    {"type": "localImage", "path": str(png_path)},
                ],
            },
            timeout=45,
        )
        used_local_image = "error" not in turn_start
        if "error" in turn_start:
            check(
                checks,
                "turn/start(text+localImage)",
                False,
                json.dumps(turn_start["error"], ensure_ascii=False),
            )
            turn_start = peer.request(
                "turn/start",
                {
                    "threadId": thread_id,
                    "cwd": cwd,
                    "effort": "low",
                    "input": [{"type": "text", "text": prompt}],
                },
                timeout=45,
            )
        else:
            check(checks, "turn/start(text+localImage)", True, "accepted")

        turn_id = dig(turn_start, "result", "turn", "id") or dig(turn_start, "result", "id")
        check(
            checks,
            "turn/start",
            "error" not in turn_start and bool(turn_id),
            f"turnId={turn_id}",
        )

        if turn_id:
            notif_start = 0
            try:
                completed = peer.wait_notification(
                    lambda n: n.get("method") == "turn/completed",
                    timeout=args.timeout,
                    label="turn/completed",
                    start_index=notif_start,
                )
                status = dig(completed, "params", "turn", "status") or dig(
                    completed, "params", "status"
                )
                check(checks, "turn/completed", bool(status), f"status={status}")
            except TimeoutError as exc:
                check(checks, "turn/completed", False, str(exc))

            methods = notification_methods(peer)
            print(
                f"Notifications seen ({len(methods)}): "
                + ", ".join(sorted(m for m in methods if m))
            )

            has_reasoning = bool(
                methods
                & {
                    "item/reasoning/textDelta",
                    "item/reasoning/summaryTextDelta",
                    "item/reasoning/summaryPartAdded",
                }
            ) or any(
                n.get("method") in {"item/started", "item/completed"}
                and dig(n, "params", "item", "type") == "reasoning"
                for n in peer.notifications
            )
            check(
                checks,
                "reasoning signal",
                True,
                "seen" if has_reasoning else "optional for low-effort short reply",
            )

            has_plan = bool(methods & {"item/plan/delta", "turn/plan/updated"}) or any(
                n.get("method") in {"item/started", "item/completed"}
                and dig(n, "params", "item", "type") == "plan"
                for n in peer.notifications
            )
            check(
                checks,
                "plan signal (optional)",
                True,
                "seen" if has_plan else "not emitted for this prompt",
            )
            check(
                checks,
                "turn/diff (optional)",
                True,
                "seen"
                if "turn/diff/updated" in methods
                else "not emitted (no file edits)",
            )
            check(
                checks,
                "thread/status/changed",
                "thread/status/changed" in methods,
                "seen" if "thread/status/changed" in methods else "missing",
            )

            token_notes = [
                n
                for n in peer.notifications
                if n.get("method") == "thread/tokenUsage/updated"
            ]
            if token_notes:
                window = dig(token_notes[-1], "params", "tokenUsage", "modelContextWindow")
                check(
                    checks,
                    "thread/tokenUsage/updated",
                    True,
                    f"modelContextWindow={window}",
                )
            else:
                check(checks, "thread/tokenUsage/updated", False, "missing")

            has_agent = "item/agentMessage/delta" in methods or any(
                n.get("method") == "item/completed"
                and dig(n, "params", "item", "type") == "agentMessage"
                for n in peer.notifications
            )
            check(
                checks,
                "agent message",
                has_agent,
                "seen" if has_agent else "missing",
            )

            has_user_image = any(
                n.get("method") in {"item/started", "item/completed"}
                and dig(n, "params", "item", "type") == "userMessage"
                and any(
                    isinstance(c, dict) and c.get("type") == "localImage"
                    for c in (dig(n, "params", "item", "content") or [])
                )
                for n in peer.notifications
            )
            check(
                checks,
                "localImage in items (optional)",
                True,
                "seen in item notifications"
                if has_user_image
                else (
                    "accepted by turn/start but not observed in notifications"
                    if used_local_image
                    else "not used (turn/start rejected localImage)"
                ),
            )

        # interrupt path
        turn2 = peer.request(
            "turn/start",
            {
                "threadId": thread_id,
                "cwd": cwd,
                "effort": "low",
                "input": [
                    {
                        "type": "text",
                        "text": "Count slowly from 1 to 200 in words. Do not use tools.",
                    }
                ],
            },
            timeout=45,
        )
        turn2_id = dig(turn2, "result", "turn", "id") or dig(turn2, "result", "id")
        if turn2_id:
            time.sleep(0.3)
            interrupt = peer.request(
                "turn/interrupt",
                {"threadId": thread_id, "turnId": turn2_id},
                timeout=30,
            )
            check(
                checks,
                "turn/interrupt",
                "error" not in interrupt,
                f"turnId={turn2_id}"
                if "error" not in interrupt
                else json.dumps(interrupt["error"], ensure_ascii=False),
            )
            try:
                done = peer.wait_notification(
                    lambda n: n.get("method") == "turn/completed"
                    and (
                        dig(n, "params", "turn", "id") == turn2_id
                        or dig(n, "params", "turnId") == turn2_id
                    ),
                    timeout=60,
                    label="interrupted turn/completed",
                )
                st = dig(done, "params", "turn", "status")
                check(
                    checks,
                    "interrupt terminal status",
                    st in {"interrupted", "failed", "completed"},
                    f"status={st}",
                )
            except TimeoutError as exc:
                check(checks, "interrupt terminal status", False, str(exc))
        else:
            check(
                checks,
                "turn/interrupt",
                False,
                json.dumps(turn2.get("error", turn2), ensure_ascii=False),
            )

        unsub = peer.request("thread/unsubscribe", {"threadId": thread_id})
        check(
            checks,
            "thread/unsubscribe",
            "error" not in unsub,
            "ok"
            if "error" not in unsub
            else json.dumps(unsub["error"], ensure_ascii=False),
        )

        read = peer.request("thread/read", {"threadId": thread_id}, timeout=30)
        if "error" in read:
            check(
                checks,
                "thread/read after unsubscribe",
                True,
                f"error={dig(read, 'error', 'message')}",
            )
        else:
            turns = (
                dig(read, "result", "thread", "turns")
                or dig(read, "result", "turns")
                or []
            )
            item_types: list[str] = []
            for turn in turns:
                for item in turn.get("items") or []:
                    if isinstance(item, dict) and item.get("type"):
                        item_types.append(str(item["type"]))
            check(
                checks,
                "thread/read after unsubscribe",
                True,
                f"turns={len(turns)}; itemTypes={','.join(sorted(set(item_types)))}",
            )
    finally:
        if peer is not None:
            peer.close()
        if png_path is not None and png_path.exists():
            png_path.unlink(missing_ok=True)

    failed = [c for c in checks if not c.ok]
    passed = [c for c in checks if c.ok]
    print()
    print(f"Smoke summary: {len(passed)} passed, {len(failed)} failed")
    if peer and peer.stderr_lines:
        print(f"stderr lines captured (content suppressed): {len(peer.stderr_lines)}")
    if failed:
        print("--- failures ---")
        for item in failed:
            print(f"- {item.name}: {item.detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
