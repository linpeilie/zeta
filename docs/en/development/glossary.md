# Glossary

[中文](../../zh/development/glossary.md) ｜ English

These terms appear constantly in the code and docs, and each has a specific meaning. Worth skimming once before your first read of the repo, then coming back when something is unclear.

For how it all fits together, see the [architecture overview](../architecture/overview.md).

## Sessions and turns

**Thread**
An ongoing conversation, scoped to a project directory. It's maintained provider-side and can be listed, read, resumed, forked, renamed, archived, or deleted — but every one of those depends on whether that provider declares support. Shown under the project node in the left Projects panel.

**Turn**
One complete "user sends something → agent finishes working" round trip. It's the unit of usage accounting: one turn is one call. Terminal states are `completed` / `failed` / `interrupted`; running and unknown states are excluded from the success-rate denominator.

**Turn steering**
Appending input to a turn that's still running, instead of starting a new one. Backed by the optional `turnSteering` port. Note: "run plan" is **not** steering — it must create a new turn.

**Default / Plan conversation mode**
A runtime mode catalog supplied by the provider (`conversationModes`). Default executes normally; Plan only plans. Mode selection applies to the **next** turn and doesn't modify one in flight. When the catalog is empty or lacks Default/Plan, the mode selector is hidden and normal conversation continues — **faking Plan mode via prompting is not allowed**.

**Permission Plan (`planningOnly`)**
A permission-catalog option marked read-only planning (`permissionPolicy`). It is not the same capability as conversation Plan: it constrains what the process may do. Local handoff "Run" must leave this option; execution must not keep a planning-only permission.

**Management runtime facts**
Immutable, allowlisted snapshots of Workbench session bindings, without content, paths, or raw errors. Grouped by exact provider configuration instance, independently of installation/account/connection-test diagnostics.

**Runtime observation attemptEpoch**
An in-memory controller counter advanced before a new startup attempt without a runtime. It isolates failures before an instance identity exists; binding identity, runtime identity and connection scope cover separate lifecycle boundaries. None is persisted.

**unobservedTurnRuntimeCount**
The number of attached runtimes without a current controller observation. Ready can establish a connection but cannot establish whether its turn is idle or active.

## Timeline

**Entry / entryId**
A mergeable unit on the timeline. `entryId` is the unifying layer's merge key, and it's **decided by the provider's own adapter/reducer**. That's the crux: TimelineStore updates when it sees a matching entryId and creates when it doesn't — it infers nothing.

**Source id**
The raw id from the provider protocol (`sourceItemId`, `sourceMessageId`, etc.). It is **metadata only**, kept for diagnostics, and plays no part in merge decisions. Treating a source id as an entryId is a classic mistake.

**Segment**
A subdivision within a single agent message. Also decided by the provider's reducer; shared layers don't guess.

**Reasoning phase**
Phases of the agent's thinking process, rendered collapsed on the timeline.

**File-change snapshot**
The complete ordered set of file changes for a tool or turn owner at one revision. A provider-local tracker decides change ids, actions, order, revision, and replayability before the shared pipeline; the Store only replaces the snapshot mechanically. `null` means no snapshot, while empty changes are an authoritative clear.

**File-change evidence**
Content explicitly supplied by the provider: before/after replacement snippets, written content, or a unified patch; a path/action-only summary is also valid. The three bodies must not be fabricated from one another, and a command-only path produces no file-change evidence. `replayable` can be rebuilt from history/replay; `liveOnly` is a current-stream fallback only.

**Live / history / replay**
The three timeline data sources: currently streaming, history read back from the provider, and local replay. **Each must use its own reducer instance**; sharing one bleeds state.

## Event pipeline

**AgentEvent**
The neutral domain event — the boundary between provider protocol and Zeta internals. Everything downstream of this type must be provider-agnostic. Adding or changing one requires the 16-item checklist in [developer guide §7](../../zh/development/developer_guide.md) (Chinese).

**AgentEventPipeline**
Sole owner of event resources, tying together the listener gate, coalescing buffer, and bounded dispatcher. Subscription lifecycle lives here rather than being scattered across conversation facades.
`packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart`

**Listener gate**
Admission control for the event stream. When thread switches, provider restarts, and disposal interleave, this is what keeps a stale stream from projecting onto a new session.

**Coalescing**
The merge strategy for high-frequency events: text/reasoning deltas on the same item append, complete token/file-change snapshots for the same turn take the latest, and tool progress appends or replaces per protocol semantics. It reduces UI update frequency without changing semantics. Complete events, terminal states, approvals, and errors flush the buffer and publish immediately.

**Bounded dispatcher**
FIFO event delivery, capped at 64 per Dart event-loop turn by default, continuing via `Timer.run`. Independent of Flutter's frame scheduling.

**Reducer**
The functional component turning events into state transitions. **Must be purely synchronous**: no `Timer`, `Future`, Flutter scheduler, or external callbacks. It emits nextState (`AgentConversationSessionState`), timeline mutations, UI requests, and effects; side effects always go through EffectRunner.
`agent_conversation_reducer.dart`

**SessionState**
The immutable value object produced by reducing events for one conversation. Pure data, unit-testable, and diffable. It does not hold command-side tokens, the model selection controller, or Binding activity leases.
`agent_conversation_session_state.dart`

**EffectRunner**
The reducer's only exit for side effects. Validates scope (generation / runtime / thread) so stale effects never execute.
`agent_conversation_effect_runner.dart`

**TimelineStore**
Does exactly three things: update on matching entryId, create on new entryId, upsert on matching tool id. It doesn't infer open entries, rewrite ids, or judge UI urgency. Write methods raise dirty regions only when values actually change, so the processor can derive UI regions.
`agent_conversation_timeline_store.dart`

**Handler registry**
A shared table that dispatches reduction by `AgentEvent.runtimeType`. Default handlers live in `packages/zeta_agent_core/lib/src/application/reduction/`. A provider may override a non-approval event only from its own bundle via `register<E>()`. The four approval-semantics handlers cannot be overridden (G5).
`agent_event_handler_registry.dart`

**Override handler**
A provider-owned `AgentEventHandler<E>` that replaces the shared default. The PR must answer why the shared implementation does not apply; it must not relax approval or plan-handoff semantics.

**Dirty region**
A data-change flag TimelineStore raises after a write (history / liveTurn / liveTurnBinding / activity / expansion / pendingInteraction / usage / contextUsage). It describes which data changed, not how the UI is laid out. The processor maps it to `AgentUiRegion`, merges that with a SessionState field diff, and publishes. The reducer no longer hard-codes UI regions.

**AgentUiRegion**
A UI partition derived by the processor from dirty regions plus a SessionState field diff (header / composer / pendingInteraction / expansion / history / liveTurn, and so on). Widgets subscribe by region.

**Conversation slice**
Workspace and Conversation each have one writable owner. `AgentConversationWorkspaceNotifier` holds entry resources and immutable workspace state; an application `AgentConversationSliceNotifier` owns each entry's regions and command ledger. `AgentConversationOwnerKey(entryId, lifetimeToken)` survives draft promotion and runtime restart; reopening a thread allocates a new token. BindingKey is an alias: Live resolves the owner, Closing/Closed returns an empty terminal projection, and Unknown returns an unavailable projection.

**AgentConversationRuntimeController**
The application aggregate for a conversation: pipeline, region projection, `AgentUiUpdateScheduler`, CommandPort, and effects. A workspace entry holds it; there is no `AgentConversationViewModel`.
`agent_conversation_runtime_controller.dart`

**AgentCommandOutcome**
An explicit command result: succeeded, ignored(reason), or failed(kind). Session configuration throws UnsupportedError at the executor when the port is absent; the UI boundary translates it to unsupported. A skipped execution is never success, and currentValue still comes from Provider events.

**AgentConversationOwnerKey**
entryId plus an in-memory lifetimeToken. Promotion preserves it; reopening does not reuse it.

**AgentConversationOwnerResolution**
Live / Closing / Closed / Unknown resolution of a BindingKey alias. Only Live resolves session dependencies. Other selector states are empty and reject new commands.

**AgentRegionBuilder**
Presentation subscription to one region selector: `ref.watch(selector(bindingKey))`. Send goes through `agentConversationCommandProvider`.

## Provider abstraction

**Provider**
An integration with one agent CLI. Currently active: Codex (default), Grok, and Claude Code. Cursor has been fully removed.

**AgentProviderBundle**
The strict neutral entry point to a provider's capabilities, created directly by `AgentProviderBundleFactory.createBundle`. Required ports: `runtime` and `conversation`. Everything else (`threadCatalog`, `threadSubscription`, `threadNaming`, `threadArchival`, `threadDeletion`, `threadCompaction`, `threadBranching`, `turnSteering`, `permissionResponses`, `questions`, `deniedActionOverride`, `modelCatalog`, `localThreadList`, `sessionConfiguration`, `planApproval`, `conversationModes`, `skills`, `permissionPolicy`, `usageQuota`) is optional. Unsupported ports must be `null`. The old `AgentProvider` facade has been deleted.
`agent_provider_bundle.dart`

**Capability**
A provider's declaration of what it supports. **UI renders by capability and port presence, never hard-coded on provider name.** Unsupported capabilities must report `capability = false` and throw `UnsupportedError` — never succeed silently. `AgentProviderCapabilities` is a neutral value object; vendor defaults are injected by the data-layer `AgentProviderStaticCapabilities` catalog.
`agent_provider_capabilities.dart`

**Runtime lease**
A releasable registry reference to a provider instance. It stays inside infrastructure and global-runtime/binding code; RuntimeControllers and panes do not own it directly.

**Conversation binding**
The application aggregate for one logical conversation, uniquely keyed as a draft or thread. It owns the optional session runtime, generation-filtered events, a single-binding immutable permission snapshot, and active operations. Only `beginTurn()` may create a runtime. The binding manager owns mapping, draft promotion, and ten-minute idle reclamation. A binding attached to a real thread is never rebound in place; the workspace gives it a fixed-identity RuntimeController, and switching threads selects another entry. A fork result is registered as a newly created thread and receives a separate binding.

**Global runtime**
The single non-reaped instance per provider ID, used for history, thread management, models, skills, usage, connection tests, and other pre-session/global information.

**runtimeId / connectionEpoch**
A pair of identifiers minted per connection, used to decide whether an event or effect still belongs to the current connection. Together with `providerId + threadId + listenerGeneration` they form the full scope of an event binding.

**ProviderOperationScheduler**
Distinguishes concurrency semantics: thread list/read use `sharedRead` (concurrent), while resume/fork/rename/archive/delete/compact use `exclusive`.
`data/datasources/transport/provider_operation_scheduler.dart`

## Interaction and approval

**Permission request**
The provider asks to run a command, write a file, or access the network. The default policy is conservative and **auto-authorizes nothing**.

**Question request**
The provider needs a user answer to continue.

**Plan approval**
The provider asks for approval of a plan.

> These three are **independent domain semantics** and do not share request/decision models. They may reuse the same pending-interaction surface, but the models must stay separate.

**Plan execution handoff**
A local Zeta workflow, **not** provider plan approval. It appears after a Plan turn succeeds with a non-empty plan; choosing to run **starts an explicit new Default turn** and pre-authorizes nothing. Its default permission restores the user's still-valid pre-Plan selection, otherwise falls back to the provider catalog default; a card override affects only that new turn. Non-persistent — it disappears on restart.
`agent_plan_execution_models.dart`

**AgentAttentionSignal**
The neutral signal that turn terminal states, permissions, questions, plan approvals, and execution handoffs are all normalized into. It's the sole input to desktop notifications and unread indicators. Notification bodies contain no prompts, responses, commands, or full paths.
`agent_attention_models.dart`

## Input and composer

**Composer**
The rich-text input area at the bottom. Supports pasting or attaching images, `$` to insert a Skill, `/` for the command menu, and `@` to reference project files.

**Skill token**
An atomic chip in the composer, rendered from a `U+FFFC` placeholder plus a `WidgetSpan` as `$name`, deleted as a whole on backspace. Serialized to text on send with a `type: skill` input item. Controlled by `supportsSkillInput` and the Skills port; currently supported by Codex and Grok.

**Pending interaction**
The approval/question card area pinned above the composer. Cards are removed once answered and don't reappear in the timeline.

## UI skeleton

**Workbench**
The persistent skeleton of `WindowFrame` + `IdeWorkbenchScaffold`. The app composition layer creates and starts business resources; `IdeHome` subscribes and assembles the interface. Page switching only swaps slot content.

**Slot**
Three positions: Navigation (left), Canvas (center), Inspector (right). Feature pages supply slot content and **must not replace the top-level workbench**.

**IdeRetainedPageView**
The cross-page retention container. Mounts lazily, preserves State and scroll position for visited pages, pauses off-screen tickers, and keeps inactive pages out of focus traversal. **Don't substitute `IndexedStack`** — it keeps paying layout cost for long timelines.

**Graphite tokens**
The dark Graphite Night / light Graphite Day semantic token sets, with `IdeThemeScope` as the source of truth. The `shadcn_flutter` theme is only a projection and must never be read back from. Business code must not hard-code colors, radii, or shadows. Surfaces follow a strictly monotonic luminance ladder (frame to canvas to pane to control to popover); depth comes from that ladder plus 1px translucent hairlines, with zero shadows anywhere except a deliberately faint fallback on floating layers.
`packages/zeta_ui/lib/`

## Interface language

**AppLanguage**
Currently supports only `english` / `simplifiedChinese`, persisted as `en` / `zh-Hans`. Flutter `Locale` is not a domain model; it exists only in the app/UI composition layer.

**Text catalog**
An immutable, pure-Dart port declared at a feature's domain boundary — for example `AgentUiTextCatalog`. Application / data / reducer code uses it to produce this process's Zeta copy and must not hold a `BuildContext`, generated l10n, or Flutter `Locale`.

**Startup-frozen Locale**
`MainApp` pins the process language after general settings load. The settings page writes the next-launch language; the current process neither follows the OS locale nor remounts the workbench.

**First system locale**
A fresh install inspects only the first entry of `PlatformDispatcher`'s preferred locales. If that entry is unsupported (including Traditional Chinese), the app falls back to English and does not keep scanning the list.

## Data and diagnostics

**Zeta data directory**
Production startup gets the system application Documents directory through `ZetaUserDirectory`, then creates `.zeta` with `config/`, `state/`, `logs/` and `cache/`. Do not abbreviate this as `~/.zeta`, which suggests the user home directory. See [Data and Privacy](../guide/data-and-privacy.md#what-zeta-saves) for locations and cleanup effects.

**Derived index**
A rebuildable statistics cache storing normalized allow-listed fields only. Prompts, response bodies, tool output, raw error text, credentials, and provider raw payloads must never be persisted.

**Redaction**
Processing applied before writing logs or showing diagnostics: authorization headers, `Bearer` tokens, `sk-` keys, and `api_key`/`token`/`secret`/`password` style values are masked, and the home directory becomes `~`.
`packages/zeta_foundation/lib/src/security/sensitive_data_redactor.dart`

**Pinned schema**
The Codex app-server JSON Schema snapshot under `third_party/codex_app_server_schema/`. Before upgrading the protocol, run `tool/gen_codex_schema.sh --diff` to review changes, then update the adapter.

**Smoke**
`tool/smoke_codex_app_server.py` and `tool/smoke_codex_plan_mode.py`, which exercise the core path against a real CLI. They use a temporary read-only workspace and emit no business content.

## Test execution

**Affected tests**
The set of tests that could change behavior because of the current change, computed by starting from the git change set and walking the import graph **backwards**. `bash tool/test_affected.sh` is the default rung of the dev loop; the selection logic lives in `tool/test_select.dart` and is designed to over-select rather than ever under-select. CI always runs the full suite. Local refactoring, releases and test infrastructure changes also require the full gate.

**Shard (runner)**
One of the 6 groups the root `test/` tree is split into by `kRootTestShards` in `tool/test_shards.dart`, each running as its own parallel CI job (`fail-fast: false`). Shards are grouped **semantically** and matched by directory prefix, so a test dropped into an existing directory is picked up automatically. Run one locally with `bash tool/test_shard.sh <id>`.

**Shard coverage guard**
`test/src/architecture/test_shard_coverage_guard_test.dart`: asserts every test file belongs to exactly one shard, that every manifest path exists, and that the CI matrix matches the manifest. Without it, a new test file can silently belong to no shard and never run.

**Full-run trigger**
`pubspec.yaml`, `dart_test.yaml`, `analysis_options.yaml`, `.github/workflows/`, and the selector's own files. When one of these foundation files changes, the import graph cannot bound the blast radius, so `tool/test_affected.sh` falls back to the full suite.

## Provider package manifest

`provider_api` defines neutral host assembly contracts. `provider_sdk` provides shared protocol mechanisms and a separate testing entrypoint. Each `provider_<vendor>` owns its protocol implementation and tests. The compile-time manifest (`lib/src/app/plugins/agent_provider_manifest.dart`) registers definitions, settings and factories; it is not a runtime discovery system. `AgentManagementContribution` declares management metadata and a repository factory. `AgentUsageContribution` declares a token-source factory by provider type. Both host seams consume the same activated and validated snapshot; transitional imports are removed.

The three contribution kinds are `zeta.agent.provider-bundle-factory`, `zeta.agent.management-repository`, and `zeta.agent.token-usage-source`; every activated Provider must own all three with matching identities. **D7** freezes persisted IDs, types, versions and private setting keys. **D8** moves neutral text interfaces and immutable fallback catalogs into the API while keeping ARB implementations in the host. The **dynamic package matrix** discovers test packages using `test_packages.sh --list-json` and runs each through `--only`; this is CI discovery, not runtime plugin discovery.

**Provider icon descriptor (`AgentProviderSvgIcon`)**: pure Dart static metadata in the API package containing the owning package name, relative SVG path and color policy. Declared by a plugin definition and rendered by the host; it is neither a protocol capability nor activation or persistence state.

### Management ResultSink and execution drain

`AgentManagementResultSink` is the named result interface captured by a runner for one app-session owner. A logical waiter tracks the command caller; a physical execution Future tracks completion of already-started I/O. Closing can settle the waiter with `StateError` immediately, but borrowed resources remain alive until `drainExecutions()` finishes. This ledger stays private to the owner, outside UI state and persistence.


Conversation UI writes use `AgentConversationActions`. A live handle is the entry's `AgentConversationSliceNotifier`; closed or unknown targets return a stateless rejecting handle. Each call freezes its typed payload, operation ID, owner lifetime and scope, then runs through the synchronous reducer and scoped executor with a typed result. Approval admission remains separate for all four meanings. Only permission preferences and each session config key serialize; cancellation and approvals stay independent. Closing immediately settles UI waiters as staleTarget while the existing lifecycle still owns I/O and lease release.

Model saves report each request's success, confirmation requirement, supersession, unchanged value or failure. Fork results distinguish createdSession from activation and never persist the product. Edit-and-retry sends through the new entry's Actions and propagates its actual result. Widgets capture a stable Actions handle instead of resolving a reusable BindingKey in a late callback. RuntimeController remains the executor and read source, with internal bootstrap calls explicitly identified.
