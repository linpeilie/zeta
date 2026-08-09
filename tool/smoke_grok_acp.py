#!/usr/bin/env python3
"""Real smoke against `grok agent stdio`, validating isolation and recovery.

04-目标态与步骤.md §S9 / 01-动机与止损线.md §6 已确认：AC1（会话级独立进程）
必须用真实 Grok CLI 验证，不接受只用测试替身。这个脚本起两个完全独立的
`grok agent stdio` 子进程（各自 initialize -> authenticate -> session/new），
并发各发一条消息，校验两条 session/prompt 请求都能正常返回终态；随后关闭
其中一个进程，用新进程 session/load 同一逻辑会话并再次发送，验证回收后恢复。

冒烟约束：临时只读 workspace（每个 session 一个空目录，不含真实项目文件）、
minimal 权限（默认 ask 模式；任何 session/request_permission 或其它
server->client 请求一律拒绝，保持非破坏性）、prompt 极简且不触发工具调用。

记录约束：只记录"哪个阶段成功/失败"，不记录 prompt/回复原文、原始 payload、
sessionId、stderr 原文或凭据。
"""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


@dataclass
class Peer:
    label: str
    proc: subprocess.Popen[str]
    responses: dict[str, dict[str, Any]] = field(default_factory=dict)
    stderr_line_count: int = 0
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
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            with self._cv:
                if "id" in msg and ("result" in msg or "error" in msg):
                    self.responses[str(msg["id"])] = msg
                    self._cv.notify_all()
                elif "method" in msg and "id" in msg:
                    self._reply_server_request(msg)
                # 纯通知（无 id）：这个冒烟不需要观察流式内容，直接丢弃。

    def _read_stderr(self) -> None:
        assert self.proc.stderr is not None
        for _ in self.proc.stderr:
            with self._cv:
                self.stderr_line_count += 1

    def _write(self, message: dict[str, Any]) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()

    def _reply_server_request(self, msg: dict[str, Any]) -> None:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "session/request_permission":
            self._write(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"outcome": {"outcome": "cancelled"}},
                }
            )
            return
        # 任何其它 server->client 请求一律拒绝：冒烟 prompt 设计上不应触发
        # 工具/文件/计划/提问，命中说明模型没有遵守指令，拒绝即可，不需要
        # 真的处理。
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

    def request(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        timeout: float = 30,
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
                    raise TimeoutError(f"wait response method={method}")
                self._cv.wait(timeout=remaining)
            return self.responses[key]

    def close(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except OSError:
            pass
        if self.proc.poll() is None:
            self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def resolve_grok(preferred: str | None) -> Path:
    candidates: list[Path] = []
    if preferred:
        candidates.append(Path(preferred))
    home_bin = Path.home() / ".grok" / "bin" / "grok"
    if home_bin.exists():
        candidates.append(home_bin)
    which = shutil.which("grok")
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
        return candidate
    raise SystemExit("未找到可执行的 Grok CLI，请用 --grok-bin 指定。")


def dig(obj: Any, *path: str) -> Any:
    cur = obj
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def start_peer(grok: Path, cwd: str, label: str) -> Peer:
    proc = subprocess.Popen(
        [str(grok), "agent", "stdio"],
        cwd=cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    return Peer(label=label, proc=proc)


def initialize_peer(peer: Peer, timeout: float) -> dict[str, Any] | None:
    init = peer.request(
        "initialize",
        {
            "protocolVersion": 1,
            "clientCapabilities": {
                "fs": {"readTextFile": False, "writeTextFile": False},
                "terminal": False,
            },
            "clientInfo": {
                "name": "zeta-smoke",
                "title": "Zeta Binding Smoke",
                "version": "0.1.0",
            },
        },
        timeout=timeout,
    )
    if "error" in init:
        return None

    # 鉴权是 best-effort：Zeta 自己的实现失败也不阻断后续（缓存 token
    # 可能已经隐式生效），这里保持一致。
    auth_methods = dig(init, "result", "authMethods")
    method_id: str | None = None
    if isinstance(auth_methods, list):
        for item in auth_methods:
            if isinstance(item, dict) and item.get("id") == "cached_token":
                method_id = "cached_token"
                break
        if method_id is None and auth_methods:
            first = auth_methods[0]
            if isinstance(first, dict):
                method_id = first.get("id")
    if method_id:
        try:
            peer.request("authenticate", {"methodId": method_id}, timeout=20)
        except TimeoutError:
            pass
    return init


def run_session(
    grok: Path,
    cwd: str,
    label: str,
    prompt_text: str,
    results: dict[str, dict[str, Any]],
    timeout: float,
) -> None:
    """独立子进程里跑一次 initialize -> authenticate(best-effort) ->
    session/new -> session/prompt，把结果写进 results[label]。不返回、不记录
    任何 prompt/回复/payload 原文。
    """
    peer: Peer | None = None
    try:
        peer = start_peer(grok, cwd, label)

        init = initialize_peer(peer, timeout)
        if init is None:
            results[label] = {"ok": False, "stage": "initialize"}
            return

        new_session = peer.request(
            "session/new",
            {"cwd": cwd, "mcpServers": [], "_meta": {"clientIdentifier": "zeta"}},
            timeout=60,
        )
        if "error" in new_session:
            results[label] = {"ok": False, "stage": "session/new"}
            return
        session_id = dig(new_session, "result", "sessionId")
        if not session_id:
            results[label] = {"ok": False, "stage": "session/new"}
            return

        prompt_result = peer.request(
            "session/prompt",
            {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": prompt_text}],
            },
            timeout=timeout,
        )
        if "error" in prompt_result:
            results[label] = {"ok": False, "stage": "session/prompt"}
            return
        stop_reason = dig(prompt_result, "result", "stopReason") or "end_turn"
        results[label] = {
            "ok": True,
            "stage": "session/prompt",
            "detail": f"stopReason={stop_reason}",
            # 仅保留在进程内供回收恢复步骤使用，绝不打印或写盘。
            "sessionId": session_id,
        }
    except TimeoutError:
        results[label] = {"ok": False, "stage": "timeout"}
    except Exception as exc:  # noqa: BLE001 - 冒烟脚本，记录类型即可
        results[label] = {"ok": False, "stage": "exception", "detail": type(exc).__name__}
    finally:
        if peer is not None:
            peer.close()


def run_recovery(
    grok: Path,
    cwd: str,
    session_id: str,
    prompt_text: str,
    timeout: float,
) -> dict[str, Any]:
    """旧进程退出后用新进程 load 同一会话；不返回或记录任何内容正文。"""
    peer: Peer | None = None
    try:
        peer = start_peer(grok, cwd, "session-a-recovered")
        init = initialize_peer(peer, timeout)
        if init is None:
            return {"ok": False, "stage": "recovery/initialize"}
        capabilities = dig(init, "result", "agentCapabilities")
        if isinstance(capabilities, dict) and capabilities.get("loadSession") is False:
            return {"ok": False, "stage": "recovery/unsupported"}

        loaded = peer.request(
            "session/load",
            {
                "sessionId": session_id,
                "cwd": cwd,
                "mcpServers": [],
                "_meta": {"clientIdentifier": "zeta"},
            },
            timeout=timeout,
        )
        if "error" in loaded:
            return {"ok": False, "stage": "recovery/session/load"}

        prompt_result = peer.request(
            "session/prompt",
            {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": prompt_text}],
            },
            timeout=timeout,
        )
        if "error" in prompt_result:
            return {"ok": False, "stage": "recovery/session/prompt"}
        stop_reason = dig(prompt_result, "result", "stopReason") or "end_turn"
        return {
            "ok": True,
            "stage": "recovery/session/prompt",
            "detail": f"stopReason={stop_reason}",
        }
    except TimeoutError:
        return {"ok": False, "stage": "recovery/timeout"}
    except Exception as exc:  # noqa: BLE001 - 冒烟脚本，记录类型即可
        return {
            "ok": False,
            "stage": "recovery/exception",
            "detail": type(exc).__name__,
        }
    finally:
        if peer is not None:
            peer.close()


def check(checks: list[Check], name: str, ok: bool, detail: str = "") -> None:
    checks.append(Check(name=name, ok=ok, detail=detail))
    mark = "PASS" if ok else "FAIL"
    suffix = f" - {detail}" if detail else ""
    print(f"[{mark}] {name}{suffix}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--grok-bin", default="")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()

    grok = resolve_grok(args.grok_bin or None)
    version = subprocess.check_output(
        [str(grok), "--version"], text=True, stderr=subprocess.STDOUT
    ).strip()
    print(f"Grok: {grok}")
    print(f"Version: {version}")
    print(f"Platform: {platform.platform()}")

    checks: list[Check] = []
    # 非破坏性、极简、明确禁止工具调用——避免触发权限/计划/提问等交互分支。
    prompt_text = "Reply with exactly the two words: smoke ok. Do not use any tools."

    tmp_a = tempfile.mkdtemp(prefix="zeta-grok-smoke-a-")
    tmp_b = tempfile.mkdtemp(prefix="zeta-grok-smoke-b-")
    results: dict[str, dict[str, Any]] = {}
    recovery: dict[str, Any] = {
        "ok": False,
        "stage": "recovery/source-session-unavailable",
    }
    try:
        threads = [
            threading.Thread(
                target=run_session,
                args=(grok, tmp_a, "session-a", prompt_text, results, args.timeout),
            ),
            threading.Thread(
                target=run_session,
                args=(grok, tmp_b, "session-b", prompt_text, results, args.timeout),
            ),
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        session_a_id = results.get("session-a", {}).get("sessionId")
        if isinstance(session_a_id, str) and session_a_id:
            recovery = run_recovery(
                grok,
                tmp_a,
                session_a_id,
                prompt_text,
                args.timeout,
            )
    finally:
        shutil.rmtree(tmp_a, ignore_errors=True)
        shutil.rmtree(tmp_b, ignore_errors=True)

    for label in ("session-a", "session-b"):
        outcome = results.get(label)
        if outcome is None:
            check(checks, f"{label} completed", False, "no result recorded")
            continue
        detail = f"stage={outcome['stage']}"
        if outcome.get("detail"):
            detail += f"; {outcome['detail']}"
        check(checks, f"{label} completed", outcome["ok"], detail)

    check(
        checks,
        "AC1: two concurrent independent-process sessions both succeed",
        all(results.get(label, {}).get("ok") for label in ("session-a", "session-b")),
    )
    recovery_detail = f"stage={recovery['stage']}"
    if recovery.get("detail"):
        recovery_detail += f"; {recovery['detail']}"
    check(
        checks,
        "recycled process resumes the existing session",
        bool(recovery.get("ok")),
        recovery_detail,
    )

    failed = [c for c in checks if not c.ok]
    passed = [c for c in checks if c.ok]
    print()
    print(f"Smoke summary: {len(passed)} passed, {len(failed)} failed")
    if failed:
        print("--- failures ---")
        for item in failed:
            print(f"- {item.name}: {item.detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
