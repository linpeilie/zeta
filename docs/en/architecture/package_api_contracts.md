# Package API contracts

[中文](../../zh/architecture/package_api_contracts.md) ｜ English

This document freezes each package's **barrel exports** and **key interface signatures**. It is the
precondition for developing the three vendor clients in parallel during P2: they implement the same set
of capability ports, so the contract must be settled first or all three will diverge.

Companion documents: [migration topology §4](./migration_topology.md),
[ownership map](./ownership_map.md), [file-by-file manifest](./migration_manifest.md).

> **How binding this is**: signatures may be adjusted during implementation, but **any adjustment must
> change this document before it changes code**, and every package depending on that signature must be
> notified. While the three vendor clients run in parallel in P2, this is the only coordination mechanism.

---

## 0. Universal rules

### 0.1 The barrel is the only public entry point

```text
packages/<name>/
├── lib/
│   ├── <name>.dart          <- the only barrel; external code imports only this
│   └── src/                 <- implementation; an external import here fails the gate
├── test/
└── pubspec.yaml
```

Gate: `external imports of package src/ = 0` ([tasks appendix](./migration_tasks.md)).

### 0.2 Dependency direction

```text
app (lib/)
  └→ *_repository ──→ *_client ──→ agent_provider_contracts
                                    json_rpc_transport
                                    zeta_logging / zeta_storage
                                    desktop_platform_api
```

- Repositories have zero dependencies **on each other**.
- Vendor clients have zero dependencies **on each other**.
- No `packages/` may import the app's `lib/`.
- Data / Repository packages are **Flutter-free**.

### 0.3 Expressing failure

All cross-layer failures use a typed sealed family. **No bare `Exception` is thrown and no localized
string is returned**:

```dart
sealed class XxxFailure {
  const XxxFailure({this.cause, this.stackTrace});
  final Object? cause;
  final StackTrace? stackTrace;
}
```

`cause` / `stackTrace` are for logging; the UI reads only the sealed subtype and maps it in
`lib/l10n/failure_messages.dart`.

### 0.4 The standard shape for exposing external data

```dart
/// Every Repository exposes external data as "stream + synchronous snapshot".
Stream<T> get changes;
T get snapshot;
Future<void> close();
```

**Never** `ChangeNotifier` / `ValueNotifier` / `Listenable` ([ownership map §1.1](./ownership_map.md)).
`close()` must release every subscription, timer and lease, provably, under test.

---

## 1. `agent_provider_contracts` (ADR-001)

**The only model-ownership exception.** It admits immutable contracts, typed codes and pure functions
only — no business state, no vendor fields, no IO, no Flutter.

### 1.1 Barrel

```dart
library agent_provider_contracts;

export 'src/bundle/agent_provider_bundle.dart';      // 21 ports + bundle
export 'src/bundle/agent_provider_capabilities.dart';
export 'src/models/agent_event_models.dart';         // 35 AgentEvent subtypes
export 'src/models/agent_attention_models.dart';
export 'src/models/agent_session_models.dart';
export 'src/models/agent_thread_models.dart';
export 'src/models/agent_message_models.dart';
export 'src/models/agent_tool_models.dart';
export 'src/models/agent_permission_models.dart';
export 'src/models/agent_permission_policy_models.dart';
export 'src/models/agent_question_models.dart';
export 'src/models/agent_plan_approval_models.dart';
export 'src/models/agent_plan_execution_models.dart';
export 'src/models/agent_model_catalog_models.dart';
export 'src/models/agent_model_selection_models.dart';
export 'src/models/agent_conversation_mode_models.dart';
export 'src/models/agent_skill_models.dart';
export 'src/models/agent_file_change_models.dart';
export 'src/models/agent_usage_models.dart';
export 'src/models/agent_turn_context_models.dart';
export 'src/models/agent_turn_history_models.dart';
export 'src/models/agent_turn_terminal_signal.dart';
export 'src/models/agent_runtime_models.dart';
export 'src/models/agent_user_input_models.dart';
export 'src/failures/agent_provider_failure.dart';   // typed codes, replacing TextCatalog
export 'src/codecs/context_window_codec.dart';
export 'src/cli/resolved_cli_process_command.dart';
```

**Not exported**: `AgentUiTextCatalog`, `FallbackAgentUiTextCatalog`, `ZetaTextCatalogs`,
`cursor_retirement_policy`, `AgentProviderErrorPresentation` — all deleted
([steps 7 / 28](./migration_tasks.md)).

`AgentTurnActivityPhase` / `AgentTurnActivitySnapshot` are also excluded: they are live interaction
state owned by `AgentConversationBloc`. Elapsed-time calculation and formatting stay in app
Presentation/l10n rather than this contracts package.

### 1.2 Port count: 21 = 2 required + 19 optional

The fields of `AgentProviderBundle` *are* the port list. **Whether an operation exists is determined
solely by whether its port is non-null.**

| # | Port | Required | Key methods |
| ---: | --- | :---: | --- |
| 1 | `AgentRuntimePort` | ✅ | `config`, `capabilities`, `events`, `runtimeInfo`, `lifecycleState`, `runtimeScope`, `updateModelSelection()`, `initialize()`, `dispose()` |
| 2 | `AgentConversationPort` | ✅ | `startSession()`, `resumeSession()`, `sendMessage()`, `cancelTurn()` |
| 3 | `AgentThreadCatalogPort` | | `listThreads()`, `readThreadHistory()` |
| 4 | `AgentThreadSubscriptionPort` | | `unsubscribeThread()` |
| 5 | `AgentThreadNamingPort` | | `renameThread()` |
| 6 | `AgentThreadArchivalPort` | | `archiveThread()`, `unarchiveThread()` |
| 7 | `AgentThreadDeletionPort` | | `deleteThread()` |
| 8 | `AgentThreadCompactionPort` | | `compactThread()` |
| 9 | `AgentThreadBranchingPort` | | `forkThread()` |
| 10 | `AgentTurnSteeringPort` | | `steerTurn()` |
| 11 | `AgentPermissionResponsePort` | | `respondToPermission()` |
| 12 | `AgentQuestionResponsePort` | | `respondToQuestion()` |
| 13 | `AgentDeniedActionOverridePort` | | `approveDeniedAction()` |
| 14 | `AgentModelCatalogPort` | | `listModels()` |
| 15 | `AgentConversationModeCatalogPort` | | `listConversationModes()` |
| 16 | `AgentSkillsPort` | | `listSkills()`, `skillsChanged` |
| 17 | `AgentLocalThreadListPort` | | `removeThreadFromList()` |
| 18 | `AgentSessionConfigurationPort` | | `sessionConfigOptions()`, `setSessionConfigOption()` |
| 19 | `AgentPlanApprovalPort` | | `respondToPlanApproval()` |
| 20 | `AgentPermissionPolicyPort` | | `listPermissionOptions()`, `applyPermissionSelection()` |
| 21 | `AgentUsageQuotaProvider` | | `readUsageQuota()` |

Plus `AgentProviderBundleFactory.createBundle(AgentProviderConfig)` — a factory, not a capability port.

> **"19 optional capabilities" in [step 33](./migration_tasks.md) means ports 3–21.** Each needs a
> widget test asserting "when the port is null, the UI entry point does not render".

### 1.3 Ports ≠ capability flags

They are **different axes** and must not be conflated:

| | Ports (21) | Capability flags (27) |
| --- | --- | --- |
| Declared in | `AgentProviderBundle` fields | `bool` fields of `AgentProviderCapabilities` |
| Meaning | whether the operation **has an implementation** | whether the operation **is usable** in the current configuration |
| Determined | when the bundle is constructed (shape fixed at compile time) | statically before the handshake, then overridden by the runtime |
| UI use | whether the entry point renders | whether the entry point is enabled |

26 of the 27 flags default to `false`; only `supportsTextInput` defaults to `true`. Semantics are
**conservative**: a flag is `true` only when the operation can genuinely complete.

One port may map to several flags (`AgentThreadArchivalPort` ↔ `canArchiveThread` +
`canUnarchiveThread`), and some have none (`AgentPermissionPolicyPort` explicitly does not use a
capability bit — see the source comment).

### 1.4 Capability matrix for the three providers (migration baseline)

| Flag | Codex | Claude | Grok |
| --- | :---: | :---: | :---: |
| `canCreateSession` | ✅ | ✅ | ✅ |
| `canResumeSession` | ✅ | ✅ | ✅ |
| `canListThreads` | ✅ | ✅ | ✅ |
| `canReadHistory` | ✅ | ✅ | ✅ |
| `canDeleteThread` | ✅ | | ✅ |
| `canRemoveThreadFromList` | | ✅ | |
| `canPrompt` | ✅ | ✅ | ✅ |
| `canCancelTurn` | ✅ | ✅ | ✅ |
| `canSteerTurn` | ✅ | | |
| `canRenameThread` | ✅ | | ✅ |
| `canArchiveThread` | ✅ | | |
| `canUnarchiveThread` | ✅ | | |
| `canForkThread` | ✅ | | |
| `canForkThreadAtTurn` | dynamic | | |
| `canCompactThread` | ✅ | ✅ | |
| `supportsTextInput` | ✅ | ✅ | ✅ |
| `supportsLocalImageInput` | ✅ | | |
| `supportsResourceInput` | ✅ | | ✅ |
| `supportsSkillInput` | ✅ | | ✅ |
| `supportsPermissionRequests` | ✅ | ✅ | ✅ |
| `supportsUserQuestions` | ✅ | ✅ | ✅ |
| `supportsPlanApproval` | | ✅ | ✅ |
| `supportsModelSelection` | ✅ | ✅ | ✅ |
| `supportsModeSelection` | | | ✅ |
| `supportsReasoningOptions` | ✅ | ✅ | ✅ |
| `supportsServiceTierSelection` | ✅ | | |
| `supportsUsage` | ✅ | ✅ | ✅ |

`canForkThreadAtTurn` is statically `false` and enabled dynamically after the handshake based on the
Codex version — the only dynamic bit, and the reference example of "declare conservatively, let the
runtime widen".

**After migration this table must match the three clients' actual declarations bit for bit**, asserted
by a cross-package test.

### 1.5 The `AgentEvent` sealed family (35 subtypes)

All provider events normalize into one family. Grouped as follows (full list in the source):

| Group | Events |
| --- | --- |
| Runtime | `AgentStatusEvent`, `AgentErrorEvent`, `AgentModelListEvent` |
| Session | `AgentSessionStartedEvent`, `AgentSessionConfigUpdatedEvent`, `AgentConversationModeUpdatedEvent` |
| Thread | `AgentThreadStatusChangedEvent`, `...NameUpdated`, `...PreviewUpdated`, `...Archived`, `...Unarchived`, `...Deleted`, `...Closed`, `...Compacted`, `...SettingsUpdated` |
| Turn | `AgentTurnStartedEvent`, `AgentTurnCompletedEvent`, `AgentTurnFileChangesEvent` |
| Content | `AgentMessageDeltaEvent`, `AgentReasoningDeltaEvent`, `AgentMessageUpdatedEvent`, `AgentSystemItemEvent` |
| Tools | `AgentToolCallEvent` |
| Approval | `AgentPermissionRequestedEvent` / `Resolved`, `AgentAutoApprovalReviewEvent` |
| Questions | `AgentQuestionRequestedEvent` / `Resolved` |
| Plans | `AgentPlanUpdatedEvent`, `AgentPlanApprovalRequestedEvent` / `Resolved` |
| Usage | `AgentTokenUsageEvent`, `AgentContextWindowUsageEvent` |
| Other | `AgentModelReroutedEvent`, `AgentDeprecationNoticeEvent` |

**Permission, question and plan approval are three independent event pairs** and must never convert into
one another — the basis of security semantic isolation ([step 32](./migration_tasks.md)).

### 1.6 Admission checklist

Before a new type enters this package, confirm each item:

- [ ] Immutable (all fields `final`, collections `unmodifiable`).
- [ ] No vendor field names (`session_id`, `tool_use_id`, `_x.ai/*` and the like must not appear).
- [ ] No IO, no `dart:io`, no Flutter.
- [ ] No business state (no `isLoading`, `selected`, `expanded`).
- [ ] Has `Equatable` or an equivalent `==`/`hashCode`.
- [ ] At least two clients need it — a type with a single consumer belongs to that client.

---

## 2. Infrastructure packages

### 2.1 `json_rpc_transport`

```dart
export 'src/json_rpc_stdio_transport.dart';
export 'src/provider_operation_scheduler.dart';
export 'src/provider_runtime_json_rpc_peer.dart';
export 'src/transport_exception.dart';

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

sealed class TransportException {}
final class TransportMalformedFrame extends TransportException {}
final class TransportLineTooLong extends TransportException {}
final class TransportTimeout extends TransportException {}
final class TransportProcessExited extends TransportException {}
final class TransportClosed extends TransportException {}
```

Constructors must accept an injectable `ProcessStarter`, `Clock` and `AppLogger`
([step 9](./migration_tasks.md)); tests never start a real process.

### 2.2 `zeta_logging`

```dart
export 'src/app_logging.dart';
export 'src/structured_error_logging.dart';
export 'src/sensitive_data_redactor.dart';
export 'src/ignored_message_logger.dart';

AppLogger loggerFor(String name);
void configureAppLogging({Level? level, Directory? logDirectory});
Future<void> flushAppLogging();
Future<void> shutdownAppLogging();
```

**The redactor lives in the same package as the logger and every sink passes through it by default** —
no API bypasses the redactor. Message, error, and stack data are sanitized before a log event reaches
the console, listener, or file sink. Errors retain only a broad category; structured prompt/content/
payload/raw fields are masked wholesale. Credentials, prompts and provider content must never enter
structured attributes ([step 8](./migration_tasks.md)).

### 2.3 `zeta_storage`

```dart
export 'src/atomic_text_file.dart';
export 'src/zeta_data_paths.dart';
export 'src/path_utils.dart';
export 'src/storage_exception.dart';

Future<void> writeAtomic(File target, String contents);
sealed class StorageException {}
final class StorageReadException extends StorageException {}
final class StorageWriteException extends StorageException {}
final class StoragePathException extends StorageException {}
final class StorageClosedException extends StorageException {}

String normalizePath(String value, {bool? isWindows});
Future<String> canonicalDirectoryPath(String value);
```

Implements atomic reads/writes for the **current schema only**. No SharedPreferences bridge, no version
upgrades or migration-marker path. A failed write **must not** clobber the target file. Canonical
directory resolution accepts only an existing absolute directory and fails closed with a typed path
exception ([step 8](./migration_tasks.md)).

### 2.4 `desktop_platform_api`

Pure Dart ports with **zero implementation**. Flutter adapters live only in `lib/app/platform/`.

```dart
abstract interface class SystemFontCatalogApi {
  Future<List<SystemFontFamily>> listFontFamilies({required String localeName});
}

abstract interface class DesktopNotificationApi {
  /// [title] / [body] must already be localized — this package does no l10n.
  Future<void> show({required String title, required String body, String? tag});
}

abstract interface class DesktopAttentionApi {
  Future<void> setBadgeCount(int count);
  Future<void> requestUserAttention();
}

abstract interface class DirectoryPickerApi {
  Future<String?> pickDirectory({String? initialDirectory});
}

abstract interface class FilePickerApi {
  Future<List<String>> pickFiles({
    List<FileTypeFilter> acceptedTypes = const <FileTypeFilter>[],
  });
}

abstract interface class ClipboardApi {
  Future<void> writeText(String text);
  Future<String?> readText();
  Future<Uint8List?> readImage();
  Future<List<String>> readFilePaths();
}

abstract interface class SystemFileManagerApi {
  Future<void> openDirectory(String path);
}

abstract interface class WindowBootstrapApi {
  Future<void> initialize(WindowBootstrapConfiguration configuration);
}

abstract interface class WindowCommandApi {
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Stream<WindowLifecycleEvent> get lifecycle;
}

abstract interface class MenuCommandApi {
  Stream<MenuCommand> get commands;
  Future<bool> configure(MenuConfiguration configuration);
  Future<void> setMenuEnabled({required String commandId, required bool enabled});
}
```

`SystemFontFamily`, `FileTypeFilter`, `WindowSize`, `WindowBootstrapConfiguration`, and
`MenuConfiguration` are platform-neutral immutable values with defensive collection snapshots and
value equality. The structured font payload preserves canonical/display names, aliases, and the
monospace flag; no Flutter `XFile`, `Size`, `Color`, or plugin type crosses this boundary.

**Platform ports are implemented by app adapters and consumed by Repositories through the
composition root.** A Bloc or presentation file importing `desktop_platform_api` directly is a
zero-tolerance gate failure ([step 10](./migration_tasks.md)).

---

## 3. Provider Data clients

### 3.1 The shared contract for all three

Each vendor client's barrel **must** export a bundle factory, and **only** that plus its own config types:

```dart
// packages/codex_app_server_client/lib/codex_app_server_client.dart
export 'src/codex_provider_bundle_factory.dart';
export 'src/codex_static_capabilities.dart';
export 'src/codex_cli_locator.dart';

final class CodexProviderBundleFactory implements AgentProviderBundleFactory {
  CodexProviderBundleFactory({
    required JsonRpcPeerFactory peerFactory,
    required ProcessStarter processStarter,
    required AppLogger logger,
    Clock clock = const Clock(),
  });

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config);
}
```

`claude_code_client` and `grok_acp_client` are structurally identical, only the prefix changes.

**Must not be exported**: mappers, codecs, decoders, identities, trackers, peers and other implementation
detail. They are internal to `src/`.

### 3.2 Static capability declaration

The old repo's centralized `AgentProviderStaticCapabilities.forKind(kind)` **is removed** — it is a
cross-vendor switch that violates "vendor clients do not depend on each other". Each client declares its
own instead:

```dart
// inside each client
abstract final class CodexStaticCapabilities {
  static const value = AgentProviderCapabilities(/* the Codex column of §1.4 */);
}
```

`agent_provider_repository` holds a `Map<AgentProviderKind, AgentProviderBundleFactory>` injected by
`bootstrap.dart` — the kind→client mapping exists only in the composition root.

### 3.3 CLI locator: exactly one per vendor

The shared **value type** goes to contracts; the **behaviour** is duplicated per vendor:

```dart
// agent_provider_contracts
final class ResolvedCliProcessCommand {
  const ResolvedCliProcessCommand({required this.executable, required this.arguments});
  final String executable;
  final List<String> arguments;
  ResolvedCliProcessCommand processCommandFor(List<String> protocolArguments);
}

// inside each vendor client
final class CodexCliLocator {
  Future<ResolvedCliProcessCommand?> locate(AgentProviderConfig config);
}
```

Neither `agent_config_client` nor any Repository may reimplement a locator
([step 17](./migration_tasks.md)).

### 3.4 `agent_history_client`

Keeps only the **provider-agnostic** history merge / replay input and generic fault tolerance.
Vendor-specific parsers stay in their own client ([step 15](./migration_tasks.md)).

```dart
export 'src/history_merge.dart';

final class HistoryReplayInput {
  final String sourceId;
  final Future<String> Function() read;
  final AgentHistoryTurn? Function(Map<String, Object?> record) decode;
}

final class HistoryMergeResult {
  final List<AgentHistoryTurn> turns;
  /// A single corrupt record may be skipped with a warning; a whole-file IO failure
  /// must be thrown, never swallowed.
  final List<HistoryDecodeWarning> warnings;
}

Future<HistoryMergeResult> mergeHistoryInputs(
  Iterable<HistoryReplayInput> inputs,
);
```

**Does not produce UI timeline cards or projections** — that is presentation's job.

### 3.5 `agent_config_client`

```dart
export 'src/agent_config_decode_exception.dart';
export 'src/provider_config_store.dart';
export 'src/model_catalog_cache_store.dart';
export 'src/turn_context_store.dart';

abstract interface class ProviderConfigStore {
  Future<List<AgentProviderConfig>> read();
  Future<void> write(List<AgentProviderConfig> configs);
}
```

Current schema only. Unknown or corrupt files return a **typed decode failure** — no historical upgrade,
no silent truncation.

### 3.6 `agent_management_client`

```dart
export 'src/agent_management_data_source.dart';
export 'src/agent_management_file_system.dart';
export 'src/agent_management_responses.dart';
export 'src/claude_code_auth_status_probe.dart';
export 'src/cli_process_runner.dart';
// The barrel also shows only the locator/probe seams and three concrete
// vendor management data sources from managed_cli_data_source.dart.

abstract interface class AgentManagementDataSource {
  Future<DetectResponse> detect({required String executablePath});
  Future<ConnectionTestResponse> testConnection({required AgentProviderConfig config});
  Future<ConfigurationDocumentResponse> readConfiguration();
  Future<ConfigurationSaveResponse> saveConfiguration({required String contents});
  Future<List<String>> discoverLogPaths();
  Future<List<LogEntryResponse>> readLogs(String path, {int maxLines});
}
```

Returns **vendor-neutral responses**, does not depend on `agent_provider_repository`, and stores no
selected agent or loading/progress UI state ([step 16](./migration_tasks.md)). Concrete vendor
locators and protocol probes are constructor-injected from their owning packages; this package does
not implement a second locator or import a vendor client. Configuration writes validate the current
JSON/TOML syntax, refuse symbolic links, use `zeta_storage` atomic replacement, and return a backup
path when an existing file was copied. Log reads are bounded and redacted before they cross the Data
boundary; the Claude auth decoder retains only `loggedIn`, `authMethod`, `apiProvider`, and
`subscriptionType`.

---

## 4. The remaining Data clients

| Package | Key barrel exports | Hard constraints |
| --- | --- | --- |
| `settings_client` | `GeneralSettingsStore`, `AppearanceSettingsStore`, their codecs | **No** concrete system-font implementation; use `SystemFontCatalogApi` |
| `workspace_client` | `WorkspaceScanner`, `WorkspaceNodeResponse`, `GitignoreReader` | `WorkspaceNodeResponse` reflects the filesystem only — **no** `expanded`/`selected` |
| `project_session_client` | `ProjectSessionStore`, `SessionSnapshotCodec` | Data models never reference Bloc State; debounced writes are cancellable and flush on close |
| `usage_statistics_storage_client` | `UsagePartitionStore`, `UsageScanCache`, `UsageIndexCodec` | The cache is **rebuildable derived data**: on corruption, clear and recompute — never fake success |

`settings_client` accepts general schema v3 and appearance schema v1 only. Missing or blank documents
use injected clean-install defaults; malformed, invalid, and unsupported documents raise typed,
content-free decode failures, while storage failures propagate. Its production storage adapter uses
`zeta_storage` atomic replacement. Domain conversion and `SystemFontCatalogApi` consumption belong to
`settings_repository`, not this Data client.

`workspace_client` exposes cancellable bounded file scans, sorted one-level directory reads, raw
gitignore documents, and recursive filesystem change streams. It does not parse gitignore patterns:
the Repository supplies a pure include/skip/prune filter over the active raw documents. Roots and
requested directories reject symbolic links and canonical/lexical escape; enumerated links and
disappearing entries are omitted. Filesystem failures are typed and content-free.

`project_session_client` accepts only IDE session schema v4. Missing or blank documents represent a
clean install; malformed JSON, non-v4 documents, and invalid current fields raise content-free typed
decode failures. `SessionSnapshotResponse` and its nested responses contain persistence values only;
domain conversion, restore plans, path pruning, and interaction sequencing stay above Data. The store
serializes atomic writes, coalesces the latest debounced snapshot, exposes explicit pre-write
cancellation, flushes on close, and still closes storage before propagating background/flush failures.

The three vendor clients supply raw provider usage data through `CodexUsageReader`,
`ClaudeCodeUsageReader`, and `GrokUsageReader`; `usage_statistics_storage_client` only handles caching
and derived indexes ([step 21](./migration_tasks.md)). Each reader accepts injected discovery/parser/stat
seams, applies a half-open time range, cooperatively cancels large scans, and returns content-free usage
responses. Source paths are memory-only inputs: persisted cache keys use a deterministic path hash and
never contain the path itself. The storage client accepts only root schema v4, serializes partition
mutations, and atomically rewrites corrupt rebuildable data as an empty current-schema index; underlying
read, write, and close failures still propagate.

---

## 5. Repository public APIs

### 5.1 `agent_provider_repository`

```dart
final class AgentProviderRepository {
  AgentProviderRepository({
    required ProviderConfigStore configStore,
    required AgentModelCatalogCacheStore modelCatalogCache,
    required Map<AgentProviderKind, AgentProviderBundleFactory> bundleFactories,
    required AppLogger logger,
  });

  /// Explicit constructor-started initialization barrier; await before bundleFor.
  Future<void> get ready;
  Stream<ProviderConfigSnapshot> get configChanges;
  ProviderConfigSnapshot get configSnapshot;

  /// The Bloc calls this first to obtain a bundle, then passes it to the
  /// conversation repository.
  AgentProviderBundle bundleFor(String providerId);

  Future<AgentModelList> modelCatalog(String providerId, {bool forceRefresh = false});
  Future<AgentConversationModeCatalog> conversationModes(String providerId);
  Future<AgentSkillsCatalog> skills(String providerId, {List<String> cwds});
  Future<AgentPermissionCatalog> permissionOptions(String providerId);
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    String providerId,
    AgentPermissionSelection selection,
  );

  Future<void> persistDefaultModel(String providerId, AgentModelSelection selection);
  Future<void> close();
}
```

**Does not receive** `AgentConversationRepository` or `AgentManagementRepository`.
**Does not store** the current model / permission / mode selection — those live in Bloc State
([step 22](./migration_tasks.md)).

The model catalog TTL is owned here: fresh for 1 hour, stale retained up to 7 days on failure, and the
cache file is overwritten only on a successful refresh. On a first-read failure or an empty catalog,
**no empty cache is written**.

`ProviderConfigStore.read()` is asynchronous while `bundleFor` must remain synchronous, so construction
starts the read and exposes `ready`. Async catalog APIs await the barrier automatically; `bundleFor`
raises a content-free typed `repository_not_ready` failure before it completes instead of creating a
temporary default runtime. A clean-install empty list expands to the Codex/Grok defaults in memory and
is not written until an explicit persistence input arrives.

### 5.2 `agent_conversation_repository`

```dart
typedef ConversationHistoryInputFactory =
    Future<Iterable<HistoryReplayInput>> Function({
      required ConversationKey key,
      required AgentProviderBundle bundle,
    });

final class AgentConversationRepository {
  AgentConversationRepository({
    required AgentTurnContextStore turnContextStore,
    required AppLogger logger,
    ConversationHistoryInputFactory? historyInputs,
    Clock clock = const Clock(),
  });

  /// The Bloc obtains the bundle from the provider repository and passes it in —
  /// this package **does not depend on** agent_provider_repository.
  Future<ConversationHandle> openConversation({
    required AgentProviderBundle bundle,
    required ConversationKey key,
    required AgentContext context,
  });

  /// Exposes domain timeline snapshots only; never a UI slice.
  Stream<ConversationSnapshot> snapshots(ConversationKey key);
  ConversationSnapshot? snapshotOf(ConversationKey key);

  Future<AgentTurn> submit({required ConversationKey key, required TurnRequest request});
  Future<void> cancel(ConversationKey key);
  Future<void> steer({required ConversationKey key, required SteerRequest request});

  // Four security semantics, each with its own method — never merged
  Future<void> respondToPermission(ConversationKey key, AgentPermissionDecision decision);
  Future<void> respondToQuestion(ConversationKey key, AgentQuestionResponse response);
  Future<void> respondToPlanApproval(ConversationKey key, AgentPlanApprovalDecision decision);

  Future<void> closeConversation(ConversationKey key);
  Future<void> close();
}
```

> **Plan execution handoff is deliberately absent.** It is a local Zeta workflow (starting a new Default
> turn) initiated by `AgentConversationBloc` through `submit()`. Making it a repository method would make
> "approve the plan" look like a protocol call and blur the security boundary
> ([Codex protocol §8.2](../protocols/codex_app_server_protocol.md)).

live / history / replay **must use separate reducer instances** ([step 23](./migration_tasks.md)).

`agent_history_client` intentionally exports the Step 15 functional merge boundary rather than an
`AgentHistoryClient` object. The optional history-input factory above supplies those neutral replay
inputs; provider-owned typed history still enters through `bundle.threadCatalog`. Turn metadata uses the
already exported `AgentTurnContextStore`. This keeps vendor parsers and shared Provider ports unchanged.

### 5.3 The remaining Repositories

| Package | Constructor dependencies | Key methods | Forbidden |
| --- | --- | --- | --- |
| `agent_management_repository` | management client, config client | `detect()`, `testConnection()`, `readConfiguration()`, `saveConfiguration()`, `discoverLogPaths()`, `readLogs()`, `validateConfiguration()` | selected agent, progress, loading, localized messages |
| `settings_repository` | settings client, `SystemFontCatalogApi` | `settings` / `settingsChanges`, `persist()`, `fontFamilies()` | UI display option models |
| `workspace_repository` | workspace client | `index()`, `query()`, `loadChildren(path)`, `treeChanges` | `expanded` / `selected` |
| `project_session_repository` | project session client, vendor thread ports | `restore()`, `save()`, `threadCatalog()`, `threadPage(query)` | search terms, selection, load status |
| `usage_statistics_repository` | three vendor clients, usage storage client | `report(query)`, `quotaSnapshots()` | filter selection |
| `desktop_notifications_repository` | `DesktopNotificationApi`, `DesktopAttentionApi` | `notify(NotificationRequest)`, `setBadge(int)` | **no** dependency on `settings_repository`; accepts already-localized copy only |
| `desktop_platform_repository` | picker / clipboard / window / menu ports | `pickDirectory()`, `copyText()`, `windowCommands`, `menuCommands` | Flutter |

`agent_management_repository.validateConfiguration()` is a **pure domain method** on the Repository, but
the UI **may only invoke it through a Bloc event**, never directly from a widget
([step 24](./migration_tasks.md)).

---

## 6. `app_ui`

```dart
export 'src/theme/app_theme.dart';
export 'src/theme/app_colors.dart';
export 'src/theme/app_spacing.dart';
export 'src/theme/app_typography.dart';
export 'src/components/...';        // one public component per file
export 'src/workbench/...';
export 'src/virtualization/...';
```

| Allowed dependencies | Forbidden dependencies |
| --- | --- |
| Flutter, `shadcn_flutter` (always imported `as sf`), pure UI utilities | any `*_repository`, any `*_client`, `AppLocalizations` |

**All copy is passed via constructor parameters.** No component may embed a string that needs
localization ([step 27](./migration_tasks.md)). Tokens go through `ThemeExtension`.

Accessibility baseline WCAG 2.2 AA: normal text contrast ≥4.5:1, large text ≥3:1, UI and focus
indicators ≥3:1; interactive targets have an AA floor of 24×24 dp with a 48×48 dp design goal.

---

## 7. Freeze and change process

### 7.1 Preconditions for parallel P2 work

The three vendor clients may proceed in parallel if and only if **all** of the following are done:

- [x] The 21 port signatures in `agent_provider_contracts` are frozen (§1.2).
- [x] The fields of the 35 `AgentEvent` subtypes are frozen (§1.5).
- [x] The 27 `AgentProviderCapabilities` flags are frozen (§1.3).
- [x] `ProcessStarter` and `TransportException` in `json_rpc_transport` are frozen (§2.1).
- [x] The bundle factory constructor signature is frozen (§3.1).
- [x] `ResolvedCliProcessCommand` is frozen (§3.3).

Parallelizing before that means three mutually incompatible adapter layers.

### 7.2 Change process

1. Edit the signature in this document and state which packages it affects.
2. Notify the owners of every affected package.
3. Update this document, the contract package and all implementations in the same PR.
4. Update both language versions together ([engineering standards](./migration_topology.md)).

**Not accepted**: changing code first and documenting later; or changing one client's implementation
without changing the contract.

### 7.3 Gates

| # | Assertion |
| ---: | --- |
| 1 | Every package has `lib/<name>.dart` and external code imports only that |
| 2 | External imports of `packages/*/lib/src/**` = 0 |
| 3 | The three vendor clients' `pubspec.yaml` files cannot see one another |
| 4 | Imports between `packages/*_repository/` = 0 |
| 5 | No Data / Repository package's `pubspec.yaml` depends on `flutter` |
| 6 | `app_ui` does not depend on Repository / Data / `AppLocalizations` |
| 7 | The §1.4 capability matrix matches the three clients' declarations bit for bit |
| 8 | Each of the 21 ports has a widget test asserting "no entry point renders when the port is null" |
