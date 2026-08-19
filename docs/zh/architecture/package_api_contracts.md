# 包 API 契约

中文 ｜ [English](../../en/architecture/package_api_contracts.md)

本文冻结每个包的 **barrel 导出**与**关键接口签名**，是 P2 三个 vendor client 并行开发的前提：
它们要实现同一套 capability port，契约必须先定，否则三方会各写各的。

配套文档：[迁移拓扑 §4 目标包拓扑](./migration_topology.md)、[归属映射表](./ownership_map.md)、
[逐文件清单](./migration_manifest.md)。

> **本文的约束力**：签名可以在实现中调整，但**任何调整必须先改本文再改代码**，且需通知
> 所有依赖该签名的包。P2 阶段三个 vendor client 并行时，这是唯一的协调机制。

---

## 0. 通用规则

### 0.1 barrel 是唯一公共入口

```text
packages/<name>/
├── lib/
│   ├── <name>.dart          ← 唯一 barrel，外部只能 import 这个
│   └── src/                 ← 实现，外部 import 即门禁失败
├── test/
└── pubspec.yaml
```

门禁：`外部 imports of package src/ = 0`（[任务清单 附表](./migration_tasks.md)）。

### 0.2 依赖方向

```text
app (lib/)
  └→ *_repository ──→ *_client ──→ agent_provider_contracts
                                    json_rpc_transport
                                    zeta_logging / zeta_storage
                                    desktop_platform_api
```

- Repository **之间**零依赖。
- vendor client **之间**零依赖。
- 任何 `packages/` **不得** import app 的 `lib/`。
- Data / Repository 包 **零 Flutter**。

### 0.3 失败表达

所有跨层失败使用 typed sealed family，**不抛裸 `Exception`，不返回本地化字符串**：

```dart
sealed class XxxFailure {
  const XxxFailure({this.cause, this.stackTrace});
  final Object? cause;
  final StackTrace? stackTrace;
}
```

`cause` / `stackTrace` 供日志使用；UI 只读 sealed 子类型，映射到 `lib/l10n/failure_messages.dart`。

### 0.4 Repository 暴露外部数据的标准形状

```dart
/// 每个 Repository 的外部数据出口统一为「Stream + 同步 snapshot」。
Stream<T> get changes;
T get snapshot;
Future<void> close();
```

**不使用** `ChangeNotifier` / `ValueNotifier` / `Listenable`（[归属映射表 §1.1](./ownership_map.md)）。
`close()` 必须释放全部 subscription、timer 与 lease，且可被测试证明。

---

## 1. `agent_provider_contracts`（ADR-001）

**唯一的模型归属例外。** 只允许不可变契约、typed code 和纯函数；不允许业务状态、vendor 字段、
IO 或 Flutter。

### 1.1 barrel

```dart
library agent_provider_contracts;

export 'src/bundle/agent_provider_bundle.dart';      // 21 个 port + bundle
export 'src/bundle/agent_provider_capabilities.dart';
export 'src/models/agent_event_models.dart';         // 35 个 AgentEvent 子类
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
export 'src/failures/agent_provider_failure.dart';   // typed code，取代 TextCatalog
export 'src/codecs/context_window_codec.dart';
export 'src/cli/resolved_cli_process_command.dart';
```

**不导出**：`AgentUiTextCatalog`、`FallbackAgentUiTextCatalog`、`ZetaTextCatalogs`、
`cursor_retirement_policy`、`AgentProviderErrorPresentation`——全部删除（[步骤 7 / 28](./migration_tasks.md)）。

`AgentTurnActivityPhase` / `AgentTurnActivitySnapshot` 同样不进入本包：它们是
`AgentConversationBloc` 持有的 live interaction state；耗时计算与格式化留在 app
Presentation/l10n。

### 1.2 端口计数：21 = 2 必需 + 19 可选

`AgentProviderBundle` 的字段就是端口清单。**操作是否存在，以端口是否非空为唯一真源**。

| # | 端口 | 必需 | 关键方法 |
| ---: | --- | :---: | --- |
| 1 | `AgentRuntimePort` | ✅ | `config`、`capabilities`、`events`、`runtimeInfo`、`lifecycleState`、`runtimeScope`、`updateModelSelection()`、`initialize()`、`dispose()` |
| 2 | `AgentConversationPort` | ✅ | `startSession()`、`resumeSession()`、`sendMessage()`、`cancelTurn()` |
| 3 | `AgentThreadCatalogPort` | | `listThreads()`、`readThreadHistory()` |
| 4 | `AgentThreadSubscriptionPort` | | `unsubscribeThread()` |
| 5 | `AgentThreadNamingPort` | | `renameThread()` |
| 6 | `AgentThreadArchivalPort` | | `archiveThread()`、`unarchiveThread()` |
| 7 | `AgentThreadDeletionPort` | | `deleteThread()` |
| 8 | `AgentThreadCompactionPort` | | `compactThread()` |
| 9 | `AgentThreadBranchingPort` | | `forkThread()` |
| 10 | `AgentTurnSteeringPort` | | `steerTurn()` |
| 11 | `AgentPermissionResponsePort` | | `respondToPermission()` |
| 12 | `AgentQuestionResponsePort` | | `respondToQuestion()` |
| 13 | `AgentDeniedActionOverridePort` | | `approveDeniedAction()` |
| 14 | `AgentModelCatalogPort` | | `listModels()` |
| 15 | `AgentConversationModeCatalogPort` | | `listConversationModes()` |
| 16 | `AgentSkillsPort` | | `listSkills()`、`skillsChanged` |
| 17 | `AgentLocalThreadListPort` | | `removeThreadFromList()` |
| 18 | `AgentSessionConfigurationPort` | | `sessionConfigOptions()`、`setSessionConfigOption()` |
| 19 | `AgentPlanApprovalPort` | | `respondToPlanApproval()` |
| 20 | `AgentPermissionPolicyPort` | | `listPermissionOptions()`、`applyPermissionSelection()` |
| 21 | `AgentUsageQuotaProvider` | | `readUsageQuota()` |

外加 `AgentProviderBundleFactory.createBundle(AgentProviderConfig)`（工厂，不是能力端口）。

> **[步骤 33](./migration_tasks.md) 的"19 个 optional capability"指的就是第 3–21 号端口**，
> 每个都要有"端口为 null 时 UI 入口不出现"的 widget test。

### 1.3 端口 ≠ capability flag

两者是**不同的轴**，不要混用：

| | 端口（21） | capability flag（27） |
| --- | --- | --- |
| 定义位置 | `AgentProviderBundle` 字段 | `AgentProviderCapabilities` 的 `bool` 字段 |
| 语义 | 该操作**是否存在**实现 | 该操作在当前配置下**是否可用** |
| 判定时机 | 构造 bundle 时（编译期确定形状） | 握手前静态声明 + 握手后 runtime 覆盖 |
| UI 用途 | 入口是否渲染 | 入口是否可点击 |

27 个 flag 中 26 个默认 `false`，只有 `supportsTextInput` 默认 `true`。语义**保守**：只有能真实
完成操作时才为 `true`。

一个端口可能对应多个 flag（`AgentThreadArchivalPort` ↔ `canArchiveThread` + `canUnarchiveThread`），
也可能没有对应 flag（`AgentPermissionPolicyPort` 明确不使用 capability 位，见源码注释）。

### 1.4 三个 Provider 的能力矩阵（迁移基线）

| flag | Codex | Claude | Grok |
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
| `canForkThreadAtTurn` | 动态 | | |
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

`canForkThreadAtTurn` 静态为 `false`，握手后按 Codex 版本动态开启——这是唯一的动态位，
也是"静态声明保守、runtime 覆盖"模式的样板。

**迁移后此表必须与三个 client 的实际声明逐位相等**，由跨包测试断言。

### 1.5 `AgentEvent` sealed family（35 个子类）

所有 Provider 事件归一化为同一族。分组如下（完整列表见源码）：

| 分组 | 事件 |
| --- | --- |
| 运行时 | `AgentStatusEvent`、`AgentErrorEvent`、`AgentModelListEvent` |
| 会话 | `AgentSessionStartedEvent`、`AgentSessionConfigUpdatedEvent`、`AgentConversationModeUpdatedEvent` |
| Thread | `AgentThreadStatusChangedEvent`、`...NameUpdated`、`...PreviewUpdated`、`...Archived`、`...Unarchived`、`...Deleted`、`...Closed`、`...Compacted`、`...SettingsUpdated` |
| Turn | `AgentTurnStartedEvent`、`AgentTurnCompletedEvent`、`AgentTurnFileChangesEvent` |
| 正文 | `AgentMessageDeltaEvent`、`AgentReasoningDeltaEvent`、`AgentMessageUpdatedEvent`、`AgentSystemItemEvent` |
| 工具 | `AgentToolCallEvent` |
| 审批 | `AgentPermissionRequestedEvent` / `Resolved`、`AgentAutoApprovalReviewEvent` |
| 提问 | `AgentQuestionRequestedEvent` / `Resolved` |
| 计划 | `AgentPlanUpdatedEvent`、`AgentPlanApprovalRequestedEvent` / `Resolved` |
| 用量 | `AgentTokenUsageEvent`、`AgentContextWindowUsageEvent` |
| 其他 | `AgentModelReroutedEvent`、`AgentDeprecationNoticeEvent` |

**权限、提问、计划审批是三个独立事件对**，不得互相转换——这是安全语义隔离的基础
（[步骤 32](./migration_tasks.md)）。

### 1.6 准入检查

新增类型进入本包前，逐条确认：

- [ ] 不可变（所有字段 `final`，集合 `unmodifiable`）。
- [ ] 无 vendor 字段名（`session_id`、`tool_use_id`、`_x.ai/*` 等一律不得出现）。
- [ ] 无 IO、无 `dart:io`、无 Flutter。
- [ ] 无业务状态（无 `isLoading`、`selected`、`expanded`）。
- [ ] 有 `Equatable` 或等价的 `==`/`hashCode`。
- [ ] 至少两个 client 需要它——只有一个消费者的类型属于那个 client。

---

## 2. 基础设施包

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

构造必须可注入 `ProcessStarter`、`Clock`、`AppLogger`（[步骤 9](./migration_tasks.md)），测试不启动真实进程。

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

**redactor 与 logger 同包，且所有日志出口默认经过 redactor**——不提供绕过 redactor 的 API。
message、error 与 stack 在 log event 进入 console、listener 或 file sink 之前完成脱敏；error
只保留宽泛类别，structured prompt/content/payload/raw 字段整体遮挡。credential、prompt、
Provider content 不得进入结构化属性（[步骤 8](./migration_tasks.md)）。

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

只实现**当前 schema**的原子读写。不迁移 SharedPreferences bridge，不做历史版本升级，
也不保留 migration-marker 路径。写失败**不得**覆盖目标文件。canonical directory 只接受
存在的绝对目录，失败时以 typed path exception fail closed（[步骤 8](./migration_tasks.md)）。

### 2.4 `desktop_platform_api`

纯 Dart 端口，**零实现**。Flutter adapter 只在 `lib/app/platform/`。

```dart
abstract interface class SystemFontCatalogApi {
  Future<List<SystemFontFamily>> listFontFamilies({required String localeName});
}

abstract interface class DesktopNotificationApi {
  /// [title] / [body] 必须已本地化——本包不做 l10n。
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

`SystemFontFamily`、`FileTypeFilter`、`WindowSize`、`WindowBootstrapConfiguration`
与 `MenuConfiguration` 均为平台中立的不可变值，集合做防御性快照并具备 value equality。
结构化字体 payload 保留 canonical/display name、alias 与 monospace 标记；Flutter `XFile`、
`Size`、`Color` 及任何 plugin 类型均不得跨越此边界。

**平台端口由 app adapter 实现，并经 composition root 交给 Repository 消费。** Bloc /
Presentation 直接 import `desktop_platform_api` 是零容忍门禁（[步骤 10](./migration_tasks.md)）。

---

## 3. Provider Data clients

### 3.1 三方共同契约

每个 vendor client 的 barrel **必须**导出一个 bundle factory，且**只**导出它与自己的配置类型：

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

`claude_code_client` 与 `grok_acp_client` 结构完全相同，只换前缀。

**禁止导出**：mapper、codec、decoder、identity、tracker、peer 等实现细节。它们是 `src/` 内部。

### 3.2 静态能力声明

旧仓库的集中式 `AgentProviderStaticCapabilities.forKind(kind)` **拆掉**——它是一个跨 vendor 的
switch，违反"vendor client 互不依赖"。改为每个 client 各自声明：

```dart
// 每个 client 内部
abstract final class CodexStaticCapabilities {
  static const value = AgentProviderCapabilities(/* §1.4 的 Codex 列 */);
}
```

`agent_provider_repository` 持有 `Map<AgentProviderKind, AgentProviderBundleFactory>`，
由 `bootstrap.dart` 注入——kind→client 的映射只存在于 composition root。

### 3.3 CLI locator：每个 vendor 恰好一个

共享的**值类型**进 contracts，**行为**各 vendor 一份：

```dart
// agent_provider_contracts
final class ResolvedCliProcessCommand {
  const ResolvedCliProcessCommand({required this.executable, required this.arguments});
  final String executable;
  final List<String> arguments;
  ResolvedCliProcessCommand processCommandFor(List<String> protocolArguments);
}

// 各 vendor client 内部
final class CodexCliLocator {
  Future<ResolvedCliProcessCommand?> locate(AgentProviderConfig config);
}
```

`agent_config_client` 与任何 Repository **不得**重复实现 locator（[步骤 17](./migration_tasks.md)）。

### 3.4 `agent_history_client`

只保留 **Provider 无关**的 history merge / replay 输入与通用容错。vendor-specific parser
留在各自 client（[步骤 15](./migration_tasks.md)）。

```dart
export 'src/history_merge.dart';

final class HistoryMergeResult {
  final List<AgentHistoryTurn> turns;
  /// 单条损坏可跳过并计入 warning；整体 IO failure 必须抛出，不得吞掉。
  final List<HistoryDecodeWarning> warnings;
}
```

**不生成 UI timeline card / projection**——那是 Presentation 的事。

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

只支持当前 schema。未知或损坏文件返回 **typed decode failure**，不做历史升级，不静默清空。

### 3.6 `agent_management_client`

```dart
export 'src/agent_management_data_source.dart';
export 'src/cli_process_runner.dart';

abstract interface class AgentManagementDataSource {
  Future<DetectResponse> detect({required String executablePath});
  Future<ConnectionTestResponse> testConnection({required AgentProviderConfig config});
  Future<ConfigurationDocumentResponse> readConfiguration();
  Future<ConfigurationSaveResponse> saveConfiguration({required String contents});
  Future<List<String>> discoverLogPaths();
  Future<List<LogEntryResponse>> readLogs(String path, {int maxLines});
}
```

返回 **vendor-neutral response**，不依赖 `agent_provider_repository`，不保存选中 Agent 或
loading/progress UI 状态（[步骤 16](./migration_tasks.md)）。

---

## 4. 其余 Data clients

| 包 | barrel 关键导出 | 硬约束 |
| --- | --- | --- |
| `settings_client` | `GeneralSettingsStore`、`AppearanceSettingsStore`、对应 codec | **不含** system font 具体实现；用 `SystemFontCatalogApi` |
| `workspace_client` | `WorkspaceScanner`、`WorkspaceNodeResponse`、`GitignoreReader` | `WorkspaceNodeResponse` 只反映文件系统，**不含** `expanded`/`selected` |
| `project_session_client` | `ProjectSessionStore`、`SessionSnapshotCodec` | Data model 不引用 Bloc State；debounced write 可取消，close 时 flush |
| `usage_statistics_storage_client` | `UsagePartitionStore`、`UsageScanCache`、`UsageIndexCodec` | cache 是**可重建派生数据**，损坏时清空重算，不伪造成功 |

三个 vendor client 提供 Provider 原始用量数据；`usage_statistics_storage_client` 只做缓存与派生索引
（[步骤 21](./migration_tasks.md)）。

---

## 5. Repository 公共 API

### 5.1 `agent_provider_repository`

```dart
final class AgentProviderRepository {
  AgentProviderRepository({
    required ProviderConfigStore configStore,
    required ModelCatalogCacheStore modelCatalogCache,
    required Map<AgentProviderKind, AgentProviderBundleFactory> bundleFactories,
    required AppLogger logger,
  });

  Stream<ProviderConfigSnapshot> get configChanges;
  ProviderConfigSnapshot get configSnapshot;

  /// Bloc 先调这个拿 bundle，再传给 conversation repository。
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

**不接收** `AgentConversationRepository` 或 `AgentManagementRepository`。
**不保存** model / permission / mode 的当前选中值——那些在 Bloc State
（[步骤 22](./migration_tasks.md)）。

模型目录 TTL 由本包持有：新鲜 1 小时，失败时最多保留 7 天 stale；刷新成功才覆盖缓存文件。
首次读取失败或返回空目录时**不写空缓存**。

### 5.2 `agent_conversation_repository`

```dart
final class AgentConversationRepository {
  AgentConversationRepository({
    required AgentHistoryClient historyClient,
    required TurnContextStore turnContextStore,
    required AppLogger logger,
    Clock clock = const Clock(),
  });

  /// bundle 由 Bloc 从 provider repository 取得后传入——
  /// 本包**不依赖** agent_provider_repository。
  Future<ConversationHandle> openConversation({
    required AgentProviderBundle bundle,
    required ConversationKey key,
    required AgentContext context,
  });

  /// 只暴露 domain timeline snapshot，不含任何 UI slice。
  Stream<ConversationSnapshot> snapshots(ConversationKey key);
  ConversationSnapshot? snapshotOf(ConversationKey key);

  Future<AgentTurn> submit({required ConversationKey key, required TurnRequest request});
  Future<void> cancel(ConversationKey key);
  Future<void> steer({required ConversationKey key, required SteerRequest request});

  // 四种安全语义各自独立的方法——不得合并
  Future<void> respondToPermission(ConversationKey key, AgentPermissionDecision decision);
  Future<void> respondToQuestion(ConversationKey key, AgentQuestionResponse response);
  Future<void> respondToPlanApproval(ConversationKey key, AgentPlanApprovalDecision decision);

  Future<void> closeConversation(ConversationKey key);
  Future<void> close();
}
```

> **Plan 执行交接不在此列。** 它是 Zeta 本地工作流（新建 Default 回合），由
> `AgentConversationBloc` 发起，走 `submit()`。把它做成 repository 方法会让"批准计划"
> 看起来像一次协议调用，模糊安全边界（[Codex 协议 §8.2](../protocols/codex_app_server_protocol.md)）。

live / history / replay **必须使用独立 reducer 实例**（[步骤 23](./migration_tasks.md)）。

### 5.3 其余 Repository

| 包 | 构造依赖 | 关键方法 | 禁止 |
| --- | --- | --- | --- |
| `agent_management_repository` | management client、config client | `detect()`、`testConnection()`、`readConfiguration()`、`saveConfiguration()`、`discoverLogPaths()`、`readLogs()`、`validateConfiguration()` | selected agent、progress、loading、本地化 message |
| `settings_repository` | settings client、`SystemFontCatalogApi` | `settings` / `settingsChanges`、`persist()`、`fontFamilies()` | UI 展示选项模型 |
| `workspace_repository` | workspace client | `index()`、`query()`、`loadChildren(path)`、`treeChanges` | `expanded` / `selected` |
| `project_session_repository` | project session client、vendor thread ports | `restore()`、`save()`、`threadCatalog()`、`threadPage(query)` | 搜索词、选中、加载状态 |
| `usage_statistics_repository` | 三个 vendor client、usage storage client | `report(query)`、`quotaSnapshots()` | filter selection |
| `desktop_notifications_repository` | `DesktopNotificationApi`、`DesktopAttentionApi` | `notify(NotificationRequest)`、`setBadge(int)` | **不依赖** `settings_repository`；只接受已本地化 copy |
| `desktop_platform_repository` | picker / clipboard / window / menu ports | `pickDirectory()`、`copyText()`、`windowCommands`、`menuCommands` | 零 Flutter |

`agent_management_repository.validateConfiguration()` 是 Repository 的**纯 domain 方法**，
但 UI **只能通过 Bloc event 调用**，不得由 Widget 直接调（[步骤 24](./migration_tasks.md)）。

---

## 6. `app_ui`

```dart
export 'src/theme/app_theme.dart';
export 'src/theme/app_colors.dart';
export 'src/theme/app_spacing.dart';
export 'src/theme/app_typography.dart';
export 'src/components/...';        // 一文件一公开组件
export 'src/workbench/...';
export 'src/virtualization/...';
```

| 允许依赖 | 禁止依赖 |
| --- | --- |
| Flutter、`shadcn_flutter`（统一 `as sf`）、纯 UI 工具 | 任何 `*_repository`、任何 `*_client`、`AppLocalizations` |

**全部文案由构造参数传入。** 组件不得内置任何需要本地化的字符串
（[步骤 27](./migration_tasks.md)）。token 走 `ThemeExtension`。

无障碍基线 WCAG 2.2 AA：普通文本对比度 ≥4.5:1、大文本 ≥3:1、UI/焦点指示 ≥3:1；
交互目标 AA 下限 24×24 dp，设计目标 48×48 dp。

---

## 7. 冻结与变更流程

### 7.1 P2 并行的前置条件

三个 vendor client 可以并行开发，当且仅当以下**全部**完成：

- [x] `agent_provider_contracts` 的 21 个端口签名冻结（§1.2）。
- [x] `AgentEvent` 的 35 个子类字段冻结（§1.5）。
- [x] `AgentProviderCapabilities` 的 27 个 flag 冻结（§1.3）。
- [x] `json_rpc_transport` 的 `ProcessStarter` 与 `TransportException` 冻结（§2.1）。
- [x] bundle factory 的构造签名冻结（§3.1）。
- [x] `ResolvedCliProcessCommand` 冻结（§3.3）。

在此之前并行 = 三方各写一套不兼容的适配层。

### 7.2 变更流程

1. 在本文修改签名，说明影响哪些包。
2. 通知所有受影响包的负责人。
3. 同一 PR 内更新本文、契约包和全部实现。
4. 中英文两版同步更新（[工程规范](./migration_topology.md)）。

**不接受**：先改代码再补文档；或只改一个 client 的实现而不改契约。

### 7.3 门禁

| # | 断言 |
| ---: | --- |
| 1 | 每个 package 的 `lib/<name>.dart` 存在，且外部只 import 它 |
| 2 | `packages/*/lib/src/**` 的外部 import = 0 |
| 3 | 三个 vendor client 的 `pubspec.yaml` 互不可见 |
| 4 | `packages/*_repository/` 之间 import = 0 |
| 5 | Data / Repository 包的 `pubspec.yaml` 无 `flutter` 依赖 |
| 6 | `app_ui` 不依赖 Repository / Data / `AppLocalizations` |
| 7 | §1.4 的能力矩阵与三个 client 的实际声明逐位相等 |
| 8 | 21 个端口各有一个"端口为 null 时入口不渲染"的 widget test |
