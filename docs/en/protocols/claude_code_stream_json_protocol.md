# Claude Code stream-json protocol baseline

[中文](../../zh/protocols/claude_code_stream_json_protocol.md) ｜ English

Last updated: 2026-08-19 (migrated from old repo `bfd4241`; content baseline 2026-08-17)

This document records the actual protocol boundary, verified frame shapes and upgrade gates of Zeta's
Claude Code provider. It is the factual baseline for implementation and maintenance; early trade-offs and
unshipped ideas are in the
[Claude Code provider adapter document (historical proposal)](../../zh/history/claude_code_provider_adapter.md).

> **Reading this during migration**: the behaviour described here is the **functional-equivalence target**
> of the VGV migration; the implementation moves to `packages/claude_code_client/` (the Data layer).
> "Provider" and "data layer" in the text correspond to `claude_code_client` in the new topology;
> "application / shared layer" corresponds to `agent_conversation_repository`. Port signatures are in the
> [package API contracts](../architecture/package_api_contracts.md).

## 1. Baseline and scope

| Item | Baseline |
| --- | --- |
| Conversation sampling | Windows 10 / x64, CLI `2.1.224`, `system.init` self-reports `2.1.220` |
| Metadata sampling | macOS / arm64, CLI `2.1.228` |
| Core-path smoke | macOS / x86_64, CLI `2.1.227` |
| Sampling dates | 2026-08-11 to 2026-08-12 |
| Transport | line-delimited JSON over stdin/stdout (stream-json) |
| Fixtures | migration target `packages/claude_code_client/test/fixtures/` (old path `test/src/features/agent/data/datasources/claude_code/fixtures/`) |

The CLI's self-reported version and the `system.init` version may differ. Zeta keeps the diagnostic
meaning of both, never rewrites one into the other, and never infers protocol compatibility from them.

The current baseline covers: creating and resuming sessions, consecutive turns, text/thinking/tool
timelines, Edit/Write file-change evidence, cancellation, permission approval, plan approval and local
execution handoff, read-only history, hiding records from Zeta's list, the CLI's effective model options,
the plan name, optional quota details, next-turn model switching and `/compact`. Model and plan metadata
boundaries are in §7 and §11.

## 2. Process launch

Fixed argument prefix:

```text
claude --print --input-format stream-json --output-format stream-json --verbose
```

Zeta appends arguments in this stable order:

1. `--session-id <id>` for a new session, or `--resume <id>` to resume — mutually exclusive.
2. `--model <model>` when a model is selected.
3. `--effort <level>` when a reasoning level is selected.
4. `--permission-prompt-tool stdio` for interactive approval.
5. `--permission-mode <mode>`.
6. `--include-partial-messages` or `--no-session-persistence` only when explicitly enabled.
7. Any extra user-configured arguments, last.

The default live path does not enable partial messages. The process runs with the current project as its
working directory; Zeta never writes prompts, file contents or credentials into launch logs.

Model, plan name and explicit connection tests use a separate short-lived metadata process rather than
reusing the session peer:

```text
claude --print --input-format stream-json --output-format stream-json --verbose \
  --no-session-persistence --setting-sources user
```

That process receives only `control_request.initialize` and never sends `type:user` or a prompt. Zeta
creates no Claude session file — but the Claude CLI may still maintain its own auth, bootstrap or cache
state, so this is not a promise that the CLI writes nothing to its own directories.

## 3. Transport constraints

`StreamJsonPeer` treats each newline-delimited JSON object as an independent event and does not implement
JSON-RPC request/result pairing.

- Partial stdout lines may span chunks and are joined; malformed UTF-8 decodes with replacement characters
  and continues.
- A single line is capped at 4 MiB by default. Overlong or invalid JSON becomes a protocol diagnostic with
  no payload, and later lines keep processing.
- stdin writes are strictly serialized to avoid interleaved frames.
- `close` first drains queued writes, then closes stdin and terminates the process, force-killing after a
  timeout.
- Logs record only frame length, type and counts — never frame bodies or raw stderr.

In practice the `--print` + stream-json process stays alive after a `result` and can receive the next user
frame; only closing stdin ends it. Each turn may repeat the same session's `system.init`, so the mapper
must be idempotent.

## 4. Zeta → Claude Code

### 4.1 User turn

```json
{
  "type": "user",
  "session_id": "<session-id>",
  "parent_tool_use_id": null,
  "message": {
    "role": "user",
    "content": [
      {"type": "text", "text": "<prompt>"}
    ]
  }
}
```

The provider mints a neutral `turnId` before writing and keeps it stable for the whole turn. The Claude
Code wire has no host-side turn id, so this responsibility cannot be pushed down to a shared timeline store.

### 4.2 Interrupt

```json
{"type":"control","subtype":"interrupt"}
```

Cancellation, a permission denial that must end the turn, and plan cancellation may all write an
interrupt, but their domain decisions and pending registries stay isolated.

### 4.3 Permission, user question and plan responses

`control_request.request_id` is used only to match the corresponding `control_response`. Tool approval
pairs with a tool by `request.tool_use_id`; plan approval only takes over an `ExitPlanMode` tool id that
has already been observed. Each adapter encodes its own allow/deny payload; unknown, incomplete or
conflicting requests always fail closed.

`AskUserQuestion` also arrives inside `control_request/can_use_tool`, but it is a user question, not a
permission approval. The provider must route it through a separate question adapter **before** remembered
permissions and the ordinary permission handler: `input.questions` maps to `AgentQuestionRequest`, the
answer is written back through `AgentQuestionResponsePort` as `behavior: allow`, and the original input is
merged with `answers: {<question text>: <answer string>}` into `updatedInput`. Multi-select answers join
with `, `; an empty answers map means Skip. This tool must never enter the session-level allow/deny cache;
decisions written by older versions are cleaned up at session bind.

## 5. Claude Code → Zeta

| `type` / `subtype` | Current handling |
| --- | --- |
| `system.init` | validates the session, emits session started + idle; repeated init for the same session is idempotent |
| `assistant` text | maps to a message update; consecutive blocks of the same message are segmented by provider identity |
| `assistant` thinking | maps to a reasoning delta; a text/tool boundary closes the current phase |
| `assistant` tool_use | creates/updates the tool card in place by tool id; Edit/Write and friends produce file-change snapshots via the Claude-local tracker, `ExitPlanMode` goes to the plan adapter |
| `user` tool_result | updates to completed/failed by `tool_use_id`; a missing `is_error` counts as success and carries the full snapshot already recorded for the matching tool_use |
| `control_request` / `can_use_tool` | the provider routes to the plan, user-question or permission pending registry, in that order |
| `result` | first-terminal-wins; maps the turn's terminal state and this turn's usage |
| unrecognized type | increments a diagnostic counter and drops the frame; never throws, never blocks later frames |

Frames seen but deliberately ignored include `rate_limit_event` and `system/thinking_tokens`. They must
never masquerade as reasoning, usage or terminal events.

`result.usage` is this turn's absolute usage, mapped with `isSessionCumulative: false`. The sampled fields
are `input_tokens`, `output_tokens`, `cache_creation_input_tokens` and `cache_read_input_tokens`.

## 6. Identity, terminal state and scope

Claude Code's source message and tool ids are provider metadata only. entryId, message segmentation,
reasoning phases, deduplication, late events and terminal races are all decided in the data layer by
`ClaudeCodeStreamIdentity`.

- `beginTurn` runs before the user frame is written; every event of that turn uses the same Zeta turnId.
- Message, reasoning and tool boundaries are closed explicitly by the provider identity.
- Terminal is first-wins; content arriving after terminal is dropped, while a late terminal update for a
  known tool can still close it out.
- Events whose runtime/session/turn does not match fail closed.
- Live and history use separate identity/reducer instances, with positional regression compared only via a
  canonical signature.
- Diagnostics and runtime diagnostic snapshots contain only counters and allowlisted status — no source
  ids, no content, no raw payloads. This does not refer to the in-memory typed file-change snapshots.

### 6.1 File-change evidence

Claude Code's structured file evidence comes from `assistant.tool_use.input`, not from the plain-string
`user.tool_result`. `ClaudeCodeFileChangeTracker` isolates by runtime/session/turn/toolUseId, records a
typed snapshot at tool_use, and re-attaches the same snapshot when updating the terminal state in place at
tool_result:

| Claude Code tool | Zeta evidence |
| --- | --- |
| `Edit` | `file_path + old_string + new_string + replace_all` → modified replacement snippets; the snippet is not the whole file |
| `Write` | `file_path + content` → written content; with no protocol guarantee the action stays unknown, never guessing created vs. modified from whether the file exists |
| `NotebookEdit` / `MultiEdit` | maps only confirmed paths plus an unknown summary; unknown bodies are not parsed until a real structured fixture exists |
| any other tool | produces no file-change snapshot |

Both successful and failed tools keep "the evidence the provider gave when attempting the action"; the
actual outcome is expressed by tool status. A tool_use write request must never be described as already
written to disk. Turn completion, session/runtime invalidation and dispose all clear the tracker. Live and
history use separate mappers/trackers, with positional regression over the replayable snapshot's owner,
change id, order, action, evidence and terminal state.

Presentation consumes only typed snapshots and never reads the `file_path`, `old_string`, `new_string` or
`content` wire keys; that content must not enter logs, caches, notifications, thread summaries or Zeta's
persisted JSON.

## 7. Session init, resume, model catalog and switching

The first `system.init.session_id` must match the requested new or resumed session. If it does not, the
provider raises an error and refuses to bind that runtime to an unexpected conversation; later inits on the
same runtime do not re-open the gate.

`ClaudeCodeCliMetadataProbe` sends `control_request.initialize` with a random request id to a separate
process and accepts only a successful `control_response` with the same id. The model catalog comes from
`response.models`, preserves CLI order, and uses `value` as the stable id and the `--model` argument;
`name` is read only when an older shape lacks `value`. Claude's `value=default` alias does not reach the
composer; `resolvedModel` is projected only into the neutral `AgentModelInfo.model`, used to normalize the
actual model name found in history back to a stable `value`, and never retains the raw model payload. When
a model declares `supportsEffort=true`, `supportedEffortLevels` maps to the neutral
`supportedReasoningEfforts` in CLI order; the selected value becomes the `--effort` argument on the next
turn. Account identity fields, unknown fields, and Fast/auto capabilities not yet in the neutral contract
are neither surfaced nor persisted.

This catalog represents **a snapshot of the effective options the current CLI offers under the current
configuration**. `initialize` may be affected by the Claude CLI's own bootstrap, account permissions and
caches; it is not a live remote API Zeta calls directly, and it does not guarantee listing every Anthropic
model. Zeta no longer calls `/v1/models` and maintains no built-in static Claude catalog.

The application-level `AgentModelCatalogRepository` is the single TTL source of truth: a fresh cache is
kept for 1 hour, and on failure a stale snapshot is kept for up to 7 days; `agent_models_v1.json` is
overwritten only on a successful refresh. On a first-read failure or an empty catalog from the CLI, no
empty cache is written and the composer shows a model load failure. The provider-local coordinator only
merges concurrent metadata probes; it never blocks an explicit refresh with an already-completed snapshot.

When opening history, if the cached catalog has no matching resolved model, Zeta forces one catalog
refresh; if it still cannot match, the current effective model is kept rather than writing a retired
historical model as an orphan selection in the composer.

Switching model or reasoning level does not interrupt a running turn: the selection affects only the next
turn. Before that turn, the provider closes the peer at an idle boundary and resumes the same session with
`--resume` plus the new `--model` / `--effort`. If the new peer fails to start, it attempts to restore the
previous model configuration without silently swallowing the original failure.

## 8. Permissions and plans

Stable permission mode mapping:

| Zeta optionId | `--permission-mode` |
| --- | --- |
| `:ask` | `default` |
| `:accept-edits` | `acceptEdits` |
| `:plan` | `plan` |
| `:bypass` | `bypassPermissions` |

Unknown or empty values always fall back to `:ask`, never to bypass. Switching permissions while idle
restarts and resumes the peer on the same session; switching while running is rejected. Session-level
remembered decisions may store only the tool name and allow/deny allowlist fields.

Plan approval and ordinary permission approval use different registries, request/decision models and
write-back paths. Execution confirmation after `ExitPlanMode` is approved is a local Zeta workflow: after a
successful terminal state it starts a new explicit Default turn. It does not steer the current turn, does
not call the plan approval port, and does not pre-authorize any command, file or network access in the plan.

## 9. Local history and the hidden list

The Claude Code project history directory is:

```text
~/.claude/projects/<encoded-project-path>/*.jsonl
```

The path encoding rule is frozen by a Windows fixture:

```dart
absolutePath.replaceAll(RegExp(r'[\\/:]'), '-')
```

Listing reads only a bounded head/tail window of each file, skips and counts corrupt lines, does not follow
symlinks, and never rewrites Claude Code's files. Full history has its own parser/identity/reducer; on-disk
JSONL must not be fed into the live mapper as-is.

On-disk JSONL often splits one Anthropic assistant message across multiple lines (one content block per
line), repeating the same `message.id` and `message.stop_reason` on each. The history parser must not treat
a single line's `stop_reason: end_turn` as the turn's terminal state, or a thinking line will close the
identity first and the subsequent text will be dropped as late content. History closes out only at the next
user content, an on-disk `type: result`, or end of file; `completedAt` is taken from the turn's last
`end_turn` or last assistant timestamp, not from the next user's timestamp. `usage` for the same
`message.id` is last-write-wins, and different ids are summed.

The local JSONL's `assistant.message.model` gives the turn's model, and the top level may also carry
`effort`. The history parser must project these at the Claude data boundary into a typed
`AgentHistoryTurn.modelId` and an explicit `reasoningEffort`; a missing effort stays unknown and conflicting
values are conservatively discarded. The current protocol has no reliable composer service tier / Fast
evidence in history, so `serviceTierId` and `explicitFast` stay unknown and must never be inferred from
usage `service_tier`, the current selection, model defaults, thinking content or neighbouring turns. Shared
stores, view models and UI never read the raw payload.

"Remove from list" only writes a project-scoped thread key into Zeta's own versioned, leniently decoded
hidden list; the original Claude history is left untouched.

## 10. Compact and connection detection

Claude Code has no dedicated compact control frame. Zeta sends `/compact` as an ordinary user turn and
releases the current binding's activity lease only after that turn reaches a terminal state. The composer
entry point appears only when the capability is on and the current session is writable and idle; later
ordinary turns continue on the same session.

Agent management's automatic detection sends no prompt and performs no connection handshake. It only:

- runs `claude --version`;
- projects an allowlisted view of `claude auth status --json`;
- enumerates log paths without reading log contents.

A legitimate `loggedIn=false` is definite evidence of being logged out; a missing command, corrupt output or
failed probe means "auth evidence unavailable" and must not be guessed into loggedOut from file names such
as `.credentials.json` or `oauth.json`. Auth evidence and CLI availability are independent: even with
`loggedIn=false`, the user may still explicitly test a custom provider / API-key path.

A short-lived metadata peer starts only when the user explicitly clicks "test connection", using a temporary
directory and `--no-session-persistence`, and waits only for an initialize response with a matching id. It
creates no session, sends no prompt and waits for no model result — but the Claude CLI may access the
network and maintain its own auth/bootstrap cache, and the UI must state that boundary honestly. The login
instruction is `claude auth login`.

## 11. Plan name and optional quota details

The plan display name comes from `account.subscriptionType` in the same initialize payload, normalized by a
Claude-local mapper into `Claude Pro`, `Claude Max`, `Claude Team` or `Claude Enterprise`. It does not
depend on `claudeCode.accountDataEnrichment`; with quota-detail enrichment disabled, the model catalog and
plan name are still readable.

Quota windows are a separate, disableable read-only enhancement:

- `GET /api/oauth/usage` is requested only when `claudeCode.accountDataEnrichment=true`, the mode is not
  API-key, the OAuth token has not expired, and the scopes include both `user:inference` and `user:profile`.
- The HTTP timeout is 5 seconds with no retry; concurrency is single-flighted within the provider instance
  and both successful and failed attempts are throttled for 60 seconds. 401, 429, timeouts, corrupt
  responses and network failures all degrade to a plan-only snapshot.
- It maps `five_hour`, `seven_day`, the optional `seven_day_sonnet` / `seven_day_opus`, and `extra_usage`.
  `monthly_limit=null` means unlimited only; currency, balance and absolute token totals are never guessed.
- On macOS it first reads the Claude Code keychain entry via a parameterized `security find-generic-password`,
  falling back to Claude's own credentials file only on a miss, denial, corruption or timeout; Windows uses
  Claude's own credentials file. Credentials exist in memory only for the duration of one request and never
  enter Zeta's config, caches or logs.

The config key is retained for compatibility with older data, but the UI name is "quota detail enhancement".
It controls only the credential reads and usage REST call above, not the initialize model list or plan name.
Zeta never refreshes, migrates, rewrites or deletes Claude credentials — and equally, "Zeta does not persist
tokens" must not be over-read as "the Claude CLI writes no state of its own".

## 12. Upgrading and verification

Claude Code stream-json has no in-repo generatable official schema pin. When upgrading the CLI:

1. Re-sample redacted frames in a temporary, least-privilege, read-only workspace.
2. Compare the fixed arguments, the user/control wire, init, assistant, tool, result/usage,
   `control_response.initialize`, `auth status --json` and the usage schema.
3. Update the provider's own fixtures; Claude fixtures must never go into shared-layer tests.
4. Run the provider mapper/identity/peer, live-history parity, permission, plan, metadata, auth, quota,
   model cache and compact tests.
5. Run the shared-layer purity guard to confirm the pipeline, coalescing and timeline aggregate in
   `agent_conversation_repository` and the `agent_provider_contracts` ports have no Claude-specific changes.
6. Run the real-platform smoke of `tool/smoke_claude_code_metadata.py` and
   `tool/smoke_claude_code_stream_json.py` separately. If the device or credentials are unavailable, mark it
   explicitly "pending/blocked" and never infer a pass. Fixtures and smoke output only the version, OS/arch,
   model count, plan display name and pass/fail — never raw model payloads, account identity, paths,
   credentials, content or stderr.

### 12.1 Real compatibility smoke record

On 2026-08-11 a redacted real run was completed with `tool/smoke_claude_code_stream_json.py`:

| Item | Result |
| --- | --- |
| OS / arch | Darwin / x86_64 |
| Claude Code CLI | `2.1.227` |
| Schema / wrapper | stream-json line protocol |
| Result | `PASS (init+assistant+result)` |

That record verifies 2.1.227's compatibility with this baseline's core init / assistant / result path. It
does not silently rewrite the 2.1.224 sampling baseline into a new minimum supported version, and it does
not substitute for real acceptance on the other declared platforms. The output contained no prompt,
response, file contents, paths, session/turn ids, stderr or raw payloads.

The 2026-08-12 metadata contract is additionally pinned by a redacted real shape from macOS / arm64 with CLI
2.1.228, plus a shape constructed from Claude Code 2.8.4 reverse-engineered source. Together they cover
`value`, the optional `resolvedModel`, unknown fields and `subscriptionType` — but fixtures do not replace
real smoke runs on both Windows and macOS.
