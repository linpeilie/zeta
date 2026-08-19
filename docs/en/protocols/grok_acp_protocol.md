# Grok ACP protocol baseline

[中文](../../zh/protocols/grok_acp_protocol.md) ｜ English

Last updated: 2026-08-19

This document records the actual protocol boundary, verified message shapes and upgrade gates of Zeta's
Grok provider. It is the implementation and maintenance baseline for `packages/grok_acp_client`.

> **Provenance**: the old repository had no Grok protocol document. This one is reverse-engineered from
> the implementation at migration baseline `bfd4241` — `grok_acp_agent_provider.dart` (2,574 lines),
> `acp_session_update_decoder.dart`, `grok_session_update_mapper.dart`,
> `grok_acp_notification_mapper.dart`, `grok_process_starter.dart`, `grok_session_history_reader.dart`,
> `grok_billing_quota_mapper.dart`, `grok_permission_mode_codec.dart`, `grok_skills_mapper.dart` and
> `tool/smoke_grok_acp.py`. Where this document and that code disagree, the code wins and this document
> must be corrected. Once migration completes, this becomes the sole baseline.

## 1. Baseline and scope

| Item | Baseline |
| --- | --- |
| Transport | stdio JSON-RPC 2.0 (standard ACP) |
| Launch command | `grok agent [flags] stdio` |
| Protocol family | Agent Client Protocol (ACP) + xAI `_x.ai/` extensions |
| Smoke script | `tool/smoke_grok_acp.py` (per-session isolated processes / recovery after reclaim) |
| Local history | `~/.grok/sessions` (overridable via `GROK_HOME`) |

The current baseline covers: creating and resuming sessions, consecutive turns, text/thinking/tool
timelines, structured diff file-change evidence, cancellation, permission approval, plan mode and plan
approval, structured user questions, read-only history, rename and delete, the model catalog, reasoning
effort, the skill catalog and plan quotas.

**ACP currently has exactly one consumer (Grok)**, so no shared ACP package is extracted;
`acp_session_update_decoder` and `acp_content_codec` migrate as internals of `grok_acp_client`
(see [migration tasks, step 14](../architecture/migration_tasks.md)).

## 2. Process launch

`GrokCliLocator` re-resolves the CLI **before every launch** and never reuses a persisted path — so that
upgrading or moving Grok cannot permanently block initialization. A failed lookup throws
`ProcessException`; there is no silent fallback.

Arguments normalize to `agent [flags] stdio`:

| Configured form | Normalized result |
| --- | --- |
| empty arguments | `agent` + model flags + `stdio` |
| already contains `agent` … `stdio` | model flags injected between `agent` and `stdio` |
| any other custom arguments | preserved verbatim; the caller must ensure ACP still starts |

Model flags are resolved dynamically from the current composer selection (read through a closure, not
frozen at construction):

- When a model is selected, append `-m <model>`.
- When a reasoning effort is selected, append `--effort <level>`.

The environment is `Platform.environment` overlaid with `config.environment`. Zeta never writes prompts,
file contents or credentials to launch logs.

## 3. Session lifecycle

Standard ACP methods:

| Method | Purpose |
| --- | --- |
| `initialize` | protocol handshake; performs best-effort authentication when `authMethods` is returned |
| `session/new` | create a session |
| `session/load` | resume a session; falls back to local history replay when unsupported |
| `session/prompt` | start a turn |
| `session/cancel` | cancel the current turn |
| `session/set_model` | switch model |
| `session/request_permission` | **server → client** permission approval request |
| `fs/read_text_file` / `fs/write_text_file` | server → client file access |

When `session/load` is unsupported, `_loadSupported` is set to `false` and resumption falls back to local
history replay. During replay `_suppressingSessionLoadReplay` suppresses duplicate events so history is
not ingested a second time as live content.

## 4. xAI extension methods

`_x.ai/` is the current prefix and `x.ai/` (no underscore) is the compatibility prefix. **Both must be
accepted**; recognizing only one is a bug.

| Extension method | Direction | Purpose |
| --- | --- | --- |
| `_x.ai/session/update` | server → client | session update, isomorphic to standard `session/update` |
| `_x.ai/session_notification` | server → client | session notification wrapper |
| `_x.ai/session/prompt_complete` | server → client | turn completion signal |
| `_x.ai/session/rename` | client → server | rename a session |
| `_x.ai/session/delete` | client → server | delete a session |
| `_x.ai/ask_user_question` | server → client | **structured user question**, not permission approval |
| `_x.ai/exit_plan_mode` | server → client | plan approval request |
| `_x.ai/billing` | client → server | account plan and quota snapshot |
| `_x.ai/skills/list` | client → server | skill catalog (local `SKILL.md` scan) |
| `_x.ai/yolo_mode_changed` | client → server | permission mode change notification |

## 5. Decoding session/update

`AcpSessionUpdateDecoder` decodes each update into a typed value object. A missing `sessionId` always
yields `AcpUnknownUpdate('missing_session_id')` rather than an exception.

| `sessionUpdate` kind | Typed result | Required fields (missing ⇒ invalid) |
| --- | --- | --- |
| `user_message_chunk` | `AcpUserMessageChunk` | `content`; `_meta.hideFromScrollback` controls timeline entry |
| `agent_message_chunk` | `AcpAgentMessageChunk` | `content` |
| `agent_thought_chunk` | `AcpAgentThoughtChunk` | `content` |
| `tool_call` / `tool_call_update` | `AcpToolCallUpdate` | `toolCallId` |
| `plan` | `AcpPlanUpdate` | none (`entries` may be empty) |
| `usage_update` | `AcpUsageUpdate` | `used` |
| `turn_completed` | `AcpTurnCompletedUpdate` | none; a missing `stop_reason` falls back to `end_turn` |
| `current_mode_update` | `AcpCurrentModeUpdate` | `currentModeId` |
| `retry_state` | `AcpRetryStateUpdate` | none; a missing `type` falls back to `unknown` |
| `session_info_update` | `AcpSessionInfoUpdate` | none; carries live `title` and `modelId` |
| `session_summary_generated` | `AcpSessionSummaryGenerated` | none; `session_summary` usually matches the final title |
| unknown kind | `AcpUnknownUpdate('unknown_kind')` | diagnostics only; never blocks later frames |

Identity fields resolve in a fixed order, accepting both snake_case and camelCase:

- `promptId`: `update._meta.promptId` → `params._meta.promptId` → `update.promptId` → `update.prompt_id`
- `eventId`: `update._meta.eventId` → `params._meta.eventId`

A `retry_state` with `type == 'exhausted'` or `is_rate_limited == true` is a terminal failure.

## 6. Permission modes

Grok's permission modes are encoded and decoded by `GrokPermissionModeCodec` with a fixed
`clientIdentifier` of `zeta`:

| Zeta mode | Wire id | Display | Notification flags |
| --- | --- | --- | --- |
| `ask` | `ask` | Ask | `permission_mode: ask`, `yolo_mode: false`, `auto_mode: false` |
| `auto` | `auto` | Auto | `autoMode: true` / `auto_mode: true` |
| `alwaysApprove` | `always-approve` | Always approve | `yoloMode: true` / `yolo_mode: true` |

Aliases tolerated when parsing: `default` → `ask`; `always_approve`, `alwaysapprove`, `yolo`,
`bypasspermissions`, `bypass_permissions` → `alwaysApprove`. **Unknown or empty values always fall back
to `ask`, never to always-approve.** Mode changes are notified via `_x.ai/yolo_mode_changed`.

## 7. User questions and plan approval

The three semantics use **separate pending registries, request/decision models and write-back paths**, and
never convert into one another:

| Semantic | Protocol entry | Neutral model | Write-back port |
| --- | --- | --- | --- |
| Permission approval | `session/request_permission` | `AgentPermissionRequest/Decision` | `AgentPermissionResponsePort` |
| User question | `_x.ai/ask_user_question` | `AgentQuestionRequest/Response` | `AgentQuestionResponsePort` |
| Plan approval | `_x.ai/exit_plan_mode` | `AgentPlanApprovalRequest/Decision` | `AgentPlanApprovalPort` |

`_x.ai/ask_user_question` is **not** permission approval: `GrokQuestionMapper` intercepts it ahead of the
permission handler, parks it for the UI and writes back through `respondToQuestion`. It must never enter
the session-level allow/deny cache.

Unknown, incomplete or conflicting server requests always **fail closed** — deny rather than allow.

## 8. Model catalog and reasoning effort

The ACP handshake does not supply a model list, so the catalog uses a **separate subprocess fallback**:

```text
grok models
```

`GrokModelsCli` parses its text output into a neutral `AgentModelList`; a failed lookup returns an empty
list with a warning and never fabricates a catalog. Context windows are parsed by `ContextWindowCodec`,
discarding non-positive values.

There are two paths for switching models: in-session via `session/set_model`, and process-level via the
`-m` flag on the next launch. `updateModelSelection` only updates the in-memory selection, which the peer
factory closure reads at the next launch.

## 9. Skill catalog

`_x.ai/skills/list` returns the result of a local `SKILL.md` scan. The response may carry an ACP
`ExtMethodResult` envelope (`{"result": {"skills": [...]}}`) or be a bare `{"skills": [...]}` —
`GrokSkillsMapping` tolerates both and counts them separately:

- `entries`: skills successfully mapped under that cwd.
- The number of unparseable responses/entries.
- The number of skills dropped for missing key fields or being disabled.

When sending, skills are invoked as a `$name` text marker (Grok has no structured skill item channel —
unlike Codex).

## 10. File-change evidence

Grok's structured file evidence comes from `diff` blocks inside tool content, **not** from plain text:

- Ordinary content blocks continue to form the tool body.
- A `diff` block is retained separately as structured `AgentFileChangeSnapshot` evidence and no longer
  produces a `diff: <path>` placeholder string.
- `GrokFileChangeTracker` accumulates per runtime/session/turn/tool; starting a new turn releases the
  previous accumulation for that session.

Presentation consumes only typed snapshots and never reads the `rawInput` / `rawOutput` wire keys. That
content must not enter logs, caches, notifications, thread summaries or Zeta's persisted JSON.

## 11. Local history

Grok ACP **does not implement `session/list`**, so the project thread list depends on scanning local
storage.

Home directory resolution has a fixed priority: `GROK_HOME` → an injected path (tests only) → `~/.grok`;
if none is available it falls back to the relative path `.grok`.

```text
<grok-home>/sessions/
```

History parsing prefers `updates.jsonl` (isomorphic to `session/load` replay) and falls back to
`chat_history.jsonl`. Both parsers use **reducer/identity instances separate from the live mapper** —
on-disk JSONL must never be fed into the live mapper as-is.

Grok writes `generated_title` asynchronously, so after the first turn the local `summary.json` is polled
at preset intervals. Polling is bounded and never retries indefinitely.

## 12. Plan quotas

The `_x.ai/billing` response is mapped to a neutral `AgentUsageQuotaSnapshot` by `mapGrokBillingQuota`:

- `subscription_tier` (top level or inside `config`) → `planType`, also used as `limitName`.
- `config` → the primary window and the on-demand window.
- Credit details are mapped separately.
- When all three are absent it returns `null` and **does not construct an empty snapshot**.

Window labels share the duration wording used by Codex ("1 week" / "5 hours"), not "weekly quota".
**Only fields the protocol actually returns are used**; absolute token totals and unreported windows are
never inferred.

## 13. Capability declaration

Grok's static capability set (the conservative pre-handshake declaration; after the handshake,
`runtime.capabilities` wins):

| Enabled | Disabled, and why |
| --- | --- |
| `canCreateSession`, `canResumeSession`, `canListThreads`, `canReadHistory`, `canDeleteThread`, `canRenameThread` | `canArchiveThread` / `canUnarchiveThread`: archiving has no protocol support |
| `canPrompt`, `canCancelTurn` | `canSteerTurn`: ACP has no way to append to an active turn |
| `supportsResourceInput`, `supportsSkillInput` | `supportsLocalImageInput`: local images currently degrade to path text |
| `supportsPermissionRequests`, `supportsUserQuestions`, `supportsPlanApproval` | `canForkThread` / `canForkThreadAtTurn` / `canCompactThread`: no matching protocol method |
| `supportsModelSelection`, `supportsModeSelection`, `supportsReasoningOptions`, `supportsUsage` | `supportsServiceTierSelection`: Grok has no service-tier concept |

Capability semantics are **conservative**: `true` only when the operation can genuinely complete. The UI
uses them to hide entry points; the Bloc and the provider still re-check before executing
(see [migration tasks, step 33](../architecture/migration_tasks.md)).

## 14. Upgrading and verification

Grok ACP has no in-repo generatable official schema pin. When upgrading the Grok CLI:

1. Re-sample redacted frames in a temporary, least-privilege, read-only workspace.
2. Compare launch arguments, the `initialize` return, the `session/*` methods, every `sessionUpdate` kind,
   the `_x.ai/` extension method names and prefix compatibility, and the billing and skills response shapes.
3. Update `grok_acp_client`'s own fixtures. **Never** place Grok fixtures in the tests of
   `agent_provider_contracts` or `agent_conversation_repository`.
4. Run the decoder / mapper / identity / peer, live-history parity, permission, plan, question, billing,
   skills and model catalog tests.
5. Run the architecture gates to confirm `agent_conversation_repository` and `agent_provider_contracts`
   contain no Grok-specific changes.
6. Run the real smoke via `tool/smoke_grok_acp.py`. If the device or credentials are unavailable, mark it
   explicitly "pending/blocked" — **never infer a pass**.

### 14.1 Smoke script constraints

`tool/smoke_grok_acp.py` verifies per-session process isolation and recovery after reclaim: it starts two
fully independent `grok agent stdio` subprocesses (each doing initialize → authenticate → session/new),
sends one message concurrently on each, and checks that both `session/prompt` requests reach a terminal
state; it then closes one process, uses a new process to `session/load` the same logical session, and
sends again.

Isolation constraints: a temporary read-only workspace (one empty directory per session, containing no
real project files); default `ask` mode with every `session/request_permission` or other server request
denied, keeping the run non-destructive; and a minimal prompt that triggers no tool calls.

Recording constraints: it records only "which stage passed or failed" and **never** prompt/response text,
raw payloads, session ids, raw stderr or credentials.

## 15. Gaps to fill

The following left no citable measurement on the migration baseline. They must be completed and folded
back into this document when `grok_acp_client` lands:

- [ ] Sampling platform, Grok CLI version and sampling date (matching the §1 table of the Claude/Codex docs).
- [ ] The actual shape of `authMethods` from `initialize`, plus the success/failure branches of
      best-effort authentication.
- [ ] Which of `_x.ai/` and `x.ai/` the current CLI actually emits (which is primary, which is compatibility).
- [ ] A stable sample of `grok models` text output (parsing is currently tolerant; the shape is not frozen).
- [ ] The complete field list of `_x.ai/billing`'s `config` object.
