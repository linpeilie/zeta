#!/usr/bin/env python3
"""Privacy-safe Plan-mode smoke against a real Codex app-server.

The harness verifies the experimental collaboration-mode wire contract without
printing or persisting prompts, replies, file contents, credentials, raw JSONL,
thread ids, or turn ids. It uses a temporary empty workspace and archives the
smoke-created thread after restart/resume unless ``--keep-thread`` is supplied.
"""

from __future__ import annotations

import argparse
import platform
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from smoke_codex_app_server import (
    Check,
    Peer,
    check,
    dig,
    normalized_codex_version,
    resolve_codex,
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

PLAN_PROMPT = (
    "Run a non-destructive protocol smoke without reading files or running "
    "commands. First use request_user_input exactly once with one short "
    "single-select question and two options. After the answer, use update_plan "
    "with exactly two steps, then return a concise proposed plan. Do not edit "
    "files."
)
DEFAULT_PROMPT = (
    "Run a non-destructive protocol smoke. Do not read files, run commands, "
    "edit files, or ask questions. Return one short acknowledgement."
)


def start_peer(codex: Path, cwd: str) -> Peer:
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
    return Peer(proc=proc)


def initialize(peer: Peer) -> dict[str, Any]:
    response = peer.request(
        "initialize",
        {
            "clientInfo": {
                "name": "zeta-plan-smoke",
                "title": "Zeta Plan Mode Smoke",
                "version": "0.1.0",
            },
            "capabilities": {
                "experimentalApi": True,
                "requestAttestation": False,
                "mcpServerOpenaiFormElicitation": False,
                "optOutNotificationMethods": OPT_OUT,
            },
        },
    )
    if "error" not in response:
        peer.notify("initialized", {})
    return response


def error_detail(response: dict[str, Any]) -> str:
    error = response.get("error")
    if not isinstance(error, dict):
        return "ok"
    return f"code={error.get('code')}; type=rpc-error"


def mode_from_value(value: Any) -> str | None:
    if isinstance(value, str):
        normalized = value.strip().lower()
        return normalized or None
    if isinstance(value, dict):
        return mode_from_value(value.get("mode"))
    return None


def settings_mode(notification: dict[str, Any]) -> str | None:
    return mode_from_value(
        dig(notification, "params", "threadSettings", "collaborationMode")
    )


def response_data(response: dict[str, Any]) -> list[dict[str, Any]]:
    value = dig(response, "result", "data")
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def choose_model(response: dict[str, Any]) -> tuple[str | None, str | None]:
    models = response_data(response)
    if not models:
        return None, None
    selected = next((item for item in models if item.get("isDefault") is True), models[0])
    model = selected.get("model") or selected.get("id")
    effort = selected.get("defaultReasoningEffort")
    if not isinstance(effort, str) or not effort.strip():
        efforts = selected.get("supportedReasoningEfforts")
        effort = None
        if isinstance(efforts, list):
            for item in efforts:
                if isinstance(item, dict):
                    candidate = item.get("reasoningEffort")
                    if isinstance(candidate, str) and candidate.strip():
                        effort = candidate.strip()
                        break
    return (
        model.strip() if isinstance(model, str) and model.strip() else None,
        effort.strip() if isinstance(effort, str) and effort.strip() else None,
    )


def collaboration_mode(mode: str, model: str, effort: str | None) -> dict[str, Any]:
    return {
        "mode": mode,
        "settings": {
            "model": model,
            "reasoning_effort": effort,
            "developer_instructions": None,
        },
    }


def turn_params(
    *,
    thread_id: str,
    cwd: str,
    prompt: str,
    mode: str,
    model: str,
    effort: str | None,
) -> dict[str, Any]:
    return {
        "threadId": thread_id,
        "cwd": cwd,
        "input": [{"type": "text", "text": prompt}],
        "collaborationMode": collaboration_mode(mode, model, effort),
        "approvalPolicy": "never",
        "sandboxPolicy": {"type": "readOnly"},
    }


def wait_for_turn_completion(
    peer: Peer, *, turn_id: str, timeout: float, start_index: int
) -> dict[str, Any]:
    return peer.wait_notification(
        lambda item: item.get("method") == "turn/completed"
        and (
            dig(item, "params", "turn", "id") == turn_id
            or dig(item, "params", "turnId") == turn_id
        ),
        timeout=timeout,
        label="turn/completed",
        start_index=start_index,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-bin", default="")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument(
        "--expected-version",
        default="",
        help="Require an exact Codex CLI version, for example 0.144.5.",
    )
    parser.add_argument(
        "--keep-thread",
        action="store_true",
        help="Leave the smoke-created thread active instead of archiving it.",
    )
    args = parser.parse_args()

    codex = resolve_codex(args.codex_bin or None)
    version_raw = subprocess.check_output(
        [str(codex), "--version"], text=True, stderr=subprocess.STDOUT
    ).strip()
    version = normalized_codex_version(version_raw)
    print(f"Platform: {platform.system()} {platform.machine()}")
    print(f"Codex CLI: {version}")
    print("Schema mode: experimental")
    print("Payload logging: suppressed")

    checks: list[Check] = []
    peer: Peer | None = None
    resumed_peer: Peer | None = None
    thread_id: str | None = None
    thread_archived = False

    with tempfile.TemporaryDirectory(prefix="zeta-plan-smoke-") as workspace:
        try:
            if args.expected_version:
                check(
                    checks,
                    "Codex version",
                    version == args.expected_version,
                    f"actual={version}; expected={args.expected_version}",
                )

            peer = start_peer(codex, workspace)
            initialized = initialize(peer)
            check(
                checks,
                "initialize experimentalApi",
                "error" not in initialized,
                error_detail(initialized),
            )
            if "error" in initialized:
                raise RuntimeError("initialize failed")

            catalog = peer.request("collaborationMode/list", {})
            modes = {
                mode
                for item in response_data(catalog)
                if (mode := mode_from_value(item.get("mode"))) is not None
            }
            check(
                checks,
                "collaborationMode/list",
                "error" not in catalog and {"default", "plan"} <= modes,
                f"builtins={','.join(sorted(modes & {'default', 'plan'}))}",
            )

            models = peer.request(
                "model/list", {"limit": 20, "includeHidden": False}
            )
            model, default_effort = choose_model(models)
            check(
                checks,
                "model/list",
                "error" not in models and model is not None,
                "default model resolved" if model is not None else error_detail(models),
            )
            if model is None:
                raise RuntimeError("model/list returned no usable model")

            started = peer.request(
                "thread/start",
                {
                    "cwd": workspace,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": False,
                },
            )
            thread_id = dig(started, "result", "thread", "id") or dig(
                started, "result", "id"
            )
            check(
                checks,
                "thread/start",
                "error" not in started and isinstance(thread_id, str),
                error_detail(started),
            )
            if not isinstance(thread_id, str):
                raise RuntimeError("thread/start returned no thread id")

            plan_notification_start = len(peer.notifications)
            plan_request_start = len(peer.server_requests)
            plan_turns_started = True
            plan_attempts = 0
            next_turn_mode = "plan"
            for plan_attempts in range(1, 3):
                plan_turn = peer.request(
                    "turn/start",
                    turn_params(
                        thread_id=thread_id,
                        cwd=workspace,
                        prompt=PLAN_PROMPT,
                        mode="plan",
                        model=model,
                        effort="medium",
                    ),
                    timeout=45,
                )
                plan_turn_id = dig(plan_turn, "result", "turn", "id") or dig(
                    plan_turn, "result", "id"
                )
                if "error" in plan_turn or not isinstance(plan_turn_id, str):
                    plan_turns_started = False
                    break
                if plan_attempts == 1:
                    # 模拟活动 Plan turn 中只修改 Composer 的“下一回合”草稿。
                    # 当前 turn 已冻结并发出，不会产生任何额外 RPC。
                    next_turn_mode = "default"
                wait_for_turn_completion(
                    peer,
                    turn_id=plan_turn_id,
                    timeout=args.timeout,
                    start_index=plan_notification_start,
                )
                observed_methods = {
                    item.get("method")
                    for item in peer.notifications[plan_notification_start:]
                    if isinstance(item.get("method"), str)
                }
                requested_user_input = any(
                    item.get("method") == "item/tool/requestUserInput"
                    for item in peer.server_requests[plan_request_start:]
                )
                if (
                    "item/plan/delta" in observed_methods
                    and requested_user_input
                    and peer.user_input_answers_sent > 0
                ):
                    break
            check(
                checks,
                "Plan turn/start",
                plan_turns_started,
                f"attempts={plan_attempts}",
            )
            if not plan_turns_started:
                raise RuntimeError("Plan turn/start returned no turn id")

            plan_notifications = peer.notifications[plan_notification_start:]
            plan_methods = {
                item.get("method")
                for item in plan_notifications
                if isinstance(item.get("method"), str)
            }
            plan_settings_indices = [
                index
                for index, item in enumerate(plan_notifications)
                if item.get("method") == "thread/settings/updated"
                and settings_mode(item) == "plan"
            ]
            check(
                checks,
                "thread/settings/updated Plan",
                bool(plan_settings_indices),
                "seen" if plan_settings_indices else "missing",
            )
            check(
                checks,
                "item/plan/delta",
                "item/plan/delta" in plan_methods,
                (
                    f"seen; attempts={plan_attempts}"
                    if "item/plan/delta" in plan_methods
                    else f"missing; attempts={plan_attempts}"
                ),
            )
            check(
                checks,
                "turn/plan/updated",
                "turn/plan/updated" in plan_methods,
                (
                    "seen"
                    if "turn/plan/updated" in plan_methods
                    else f"missing; methods={','.join(sorted(plan_methods))}"
                ),
            )
            plan_requests = peer.server_requests[plan_request_start:]
            requested_user_input = any(
                item.get("method") == "item/tool/requestUserInput"
                for item in plan_requests
            )
            check(
                checks,
                "item/tool/requestUserInput answered",
                requested_user_input and peer.user_input_answers_sent > 0,
                (
                    f"answered; attempts={plan_attempts}"
                    if requested_user_input
                    else f"missing; attempts={plan_attempts}"
                ),
            )
            default_seen_before_next_turn = any(
                item.get("method") == "thread/settings/updated"
                and settings_mode(item) == "default"
                for item in plan_notifications[
                    (plan_settings_indices[-1] + 1) if plan_settings_indices else 0 :
                ]
            )
            check(
                checks,
                "active-turn mode remains Plan",
                next_turn_mode == "default" and not default_seen_before_next_turn,
                "Default deferred to next turn",
            )

            default_notification_start = len(peer.notifications)
            default_turn = peer.request(
                "turn/start",
                turn_params(
                    thread_id=thread_id,
                    cwd=workspace,
                    prompt=DEFAULT_PROMPT,
                    mode=next_turn_mode,
                    model=model,
                    effort=default_effort,
                ),
                timeout=45,
            )
            default_turn_id = dig(default_turn, "result", "turn", "id") or dig(
                default_turn, "result", "id"
            )
            check(
                checks,
                "Default turn/start",
                "error" not in default_turn and isinstance(default_turn_id, str),
                error_detail(default_turn),
            )
            if not isinstance(default_turn_id, str):
                raise RuntimeError("Default turn/start returned no turn id")
            wait_for_turn_completion(
                peer,
                turn_id=default_turn_id,
                timeout=args.timeout,
                start_index=default_notification_start,
            )
            default_settings_seen = any(
                item.get("method") == "thread/settings/updated"
                and settings_mode(item) == "default"
                for item in peer.notifications[default_notification_start:]
            )
            check(
                checks,
                "thread/settings/updated Default",
                default_settings_seen,
                "seen" if default_settings_seen else "missing",
            )
            persisted_mode = next_turn_mode

            peer.close()
            peer = None
            resumed_peer = start_peer(codex, workspace)
            resumed_init = initialize(resumed_peer)
            check(
                checks,
                "restart initialize",
                "error" not in resumed_init,
                error_detail(resumed_init),
            )
            resumed = resumed_peer.request(
                "thread/resume",
                {
                    "threadId": thread_id,
                    "cwd": workspace,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                },
                timeout=45,
            )
            check(
                checks,
                "thread/resume after restart",
                "error" not in resumed,
                error_detail(resumed),
            )
            check(
                checks,
                "client snapshot restored mode",
                persisted_mode == "default",
                f"mode={persisted_mode}",
            )
            history = resumed_peer.request(
                "thread/read",
                {"threadId": thread_id, "includeTurns": True},
                timeout=45,
            )
            check(
                checks,
                "thread/read after resume",
                "error" not in history,
                error_detail(history),
            )

            convergence_start = len(resumed_peer.notifications)
            convergence_turn = resumed_peer.request(
                "turn/start",
                turn_params(
                    thread_id=thread_id,
                    cwd=workspace,
                    prompt=DEFAULT_PROMPT,
                    mode=persisted_mode,
                    model=model,
                    effort=default_effort,
                ),
                timeout=45,
            )
            convergence_turn_id = dig(
                convergence_turn, "result", "turn", "id"
            ) or dig(convergence_turn, "result", "id")
            if not isinstance(convergence_turn_id, str):
                raise RuntimeError("resumed Default turn returned no turn id")
            wait_for_turn_completion(
                resumed_peer,
                turn_id=convergence_turn_id,
                timeout=args.timeout,
                start_index=convergence_start,
            )
            converged_to_default = any(
                item.get("method") == "thread/settings/updated"
                and settings_mode(item) == persisted_mode
                for item in resumed_peer.notifications[convergence_start:]
            )
            check(
                checks,
                "settings converge after restart",
                converged_to_default,
                "mode=default" if converged_to_default else "missing",
            )

            if not args.keep_thread:
                archived = resumed_peer.request(
                    "thread/archive", {"threadId": thread_id}, timeout=30
                )
                check(
                    checks,
                    "archive smoke thread",
                    "error" not in archived,
                    error_detail(archived),
                )
                thread_archived = "error" not in archived
        except Exception as error:
            check(checks, "smoke execution", False, type(error).__name__)
        finally:
            cleanup_peer = resumed_peer or peer
            if (
                not args.keep_thread
                and not thread_archived
                and thread_id is not None
                and cleanup_peer is not None
            ):
                try:
                    archived = cleanup_peer.request(
                        "thread/archive", {"threadId": thread_id}, timeout=15
                    )
                    thread_archived = "error" not in archived
                except Exception:
                    thread_archived = False
                check(
                    checks,
                    "cleanup smoke thread",
                    thread_archived,
                    "archived" if thread_archived else "archive failed",
                )
            if peer is not None:
                peer.close()
            if resumed_peer is not None:
                resumed_peer.close()

    failed = [item for item in checks if not item.ok]
    passed = [item for item in checks if item.ok]
    print()
    print(f"Plan smoke summary: {len(passed)} passed, {len(failed)} failed")
    stderr_count = sum(
        len(candidate.stderr_lines)
        for candidate in (peer, resumed_peer)
        if candidate is not None
    )
    if stderr_count:
        print(f"stderr lines captured (content suppressed): {stderr_count}")
    if failed:
        print("--- failures ---")
        for item in failed:
            print(f"- {item.name}: {item.detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
