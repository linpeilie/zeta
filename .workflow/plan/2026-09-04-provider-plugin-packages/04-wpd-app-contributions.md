# WP-D · app 层贡献化（management + usage statistics）

> 状态：已完成（2026-09-05，见 [验证记录](07-wpd-validation.md)）
> 规模：2–3 人天，建议 2 个 PR（management / usage 各一）
> 依赖：WP-C 完成（插件包与 manifest 就位）
> 性质：行为保持的重构（非纯搬移：构造签名换型 + 聚合逻辑改写）。每个 PR 全量绿为正确性证据；测试允许 import 改写，不允许断言改写。

## 1. 背景：app 层剩余的厂商硬编码（实测清单）

WP-C 后插件包已自治，但 app 层仍有六处认识具体厂商。以下行号均为 2026-09-04 实测：

| # | 位置 | 硬编码内容 |
|---|------|-----------|
| C1 | `lib/src/app/composition/ide_workbench_composition.dart:47-61` | management repository 注册表逐厂商 new：`AgentDefinition.codex.id: CodexAgentManagementRepository(...)` × 3 |
| C2 | `lib/src/features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart:26-42` | `switch (config.kind) { codexAgentProviderType => …; grokAgentProviderType => …; claudeCodeAgentProviderType => …; }` 逐厂商创建 source |
| C3 | `lib/src/app/agent_management_slice/agent_management_slice_composition.dart:94-95` | enrichment 读取闭包硬编码 `config.extra[claudeCodeAccountDataEnrichmentKey] != false` |
| C4 | `lib/src/app/agent_management_slice/agent_management_slice_runner.dart:217/219` | enrichment 写入直接 `extra.remove(claudeCodeAccountDataEnrichmentKey)` / `extra[key] = false` |
| C5 | `lib/src/app/agent_management_slice/agent_management_slice_runner.dart:186/382/431` + `agent_management_slice_composition.dart:54-64` | `AgentDefinition.byId(...)` / `AgentDefinition.all` 静态表查定义；`:427-433` 兜底用 `defaultCodexAgentProviderConfig.copyWith(...)` 给未知 agent 拼配置 |
| C6 | `lib/src/features/agent_management/presentation/agent_management_page.dart:451` | setup guide 卡片按 `agent.definition.id == AgentDefinition.claudeCode.id` 分支 |

另有两个**假象**先排除，避免过度设计：

- enrichment 的**能力门**已经是 G4 合规的：`AgentCliManagementCapabilities.supportsAccountDataEnrichment`（`agent_management_models.dart:61-70`）由各 repository 自声明（claude repo `:152-153` 声明 true），selector 走 `capabilitiesByAgentId`（`agent_management_slice_state.dart:214-218`）。**只有 key 字符串本身是硬编码**（C3/C4）。
- `page.dart:456` 的 `_ClaudeCodeAccountDataEnrichmentCard` 虽以 Claude 命名，但渲染由 supports 能力位门控，是通用 UI。保留不改（见 C6 处理）。

## 2. 目标

1. C1–C5 全部消灭：新增 Provider 时这些文件零改动。
2. 三个 management repository 与三个 usage source 迁入对应插件包，插件包对外只剩「contribution 声明」一个出口。
3. C6 保留为登记在册的单一例外（理由见 §3.6）。
4. 行为保持：持久化字节（D7）、文案、检测流水线步骤、enrichment 默认开全部不变。

## 3. 设计

### 3.1 总决策 D8：文案目录走 `AgentUiTextCatalog` 先例

实测：三个 management repository 对 `_textCatalog` 的调用点共 **50+ 处**（codex 30、grok 10+、claude 20），且 `AgentManagementTextCatalog` 本就是 `abstract interface class`（`agent_management/domain/agent_management_text_catalog.dart:4`），app 侧 ARB 实现在 `lib/src/app/localization/zeta_text_catalogs.dart:198`，fallback 在 feature domain。

这与 core 里 `AgentUiTextCatalog` 的模式完全一致（core 定义纯 Dart 接口 + Fallback，app 注入 ARB 实现）。因此**不做**「失败原因码 + app 侧映射」的间接层，直接：

- `AgentManagementTextCatalog` 接口与 `FallbackAgentManagementTextCatalog` **整体迁**入 `provider_api`（management 子库）。
- app 的 `LocalizedAgentManagementTextCatalog` 只改 import，`implements` 不变、实现零 diff。
- 接口里 vendor 命名的遗留成员（`runCodexLogin()`、`claudeInitializeTimeout()` 等约 10 个）**原样随迁**——它们是「Zeta 拥有的文案槽位」，不是 Provider 分支逻辑，不违反 G1 精神。规范化为通用成员的债记录在案，不在本计划（会牵动 ARB key，属行为面）。

usage 侧同理但收窄：实测三个 source 只用 **5 个成员**（`indexReadRescanned(String)`、`indexWriteFailed`、`sessionDirIncomplete(String)`、`sessionFilesUnreadable(...)`、`historyRowsCorrupt(String, String)`），而完整 `UsageStatisticsTextCatalog` 还有 UI 成员（`timeRangeLabel` 等）。故定义窄接口 `AgentUsageSourceTextCatalog`（5 成员签名逐字复制自现状），app 的 `LocalizedUsageStatisticsTextCatalog`（`zeta_text_catalogs.dart:82`）**同时 implements 两个接口**。

### 3.2 provider_api 的 management 子库

新增 `packages/zeta_agent_provider_api/lib/src/management.dart`（WP-A 的包内扩展，barrel 加一行 export）：

```dart
// ── 模型闭包（自 agent_management/domain/agent_management_models.dart 原样迁移）──
enum AgentInstallationState { … }      // L4
enum AgentAccountState { … }           // L13
enum AgentRuntimeState { … }           // L24
enum AgentVersionState { … }           // L36
enum AgentDiagnosticStage { … }        // L45
enum AgentLogLevel { debug, info, warning, error }  // L58
class AgentCliManagementCapabilities {              // L61-70 + 两处改动
  const AgentCliManagementCapabilities({
    this.accountDataEnrichmentExtraKey,               // 改：bool → 可空 key（见 §3.6）
    this.requiresConnectionTestConfirmation = false,  // 新增：消灭 C6 的 664 分支（§3.6）
  });

  static const AgentCliManagementCapabilities none = AgentCliManagementCapabilities();

  /// 非 null = 支持 enrichment，且这就是它在 `config.extra` 里的键。
  final String? accountDataEnrichmentExtraKey;
  final bool requiresConnectionTestConfirmation;

  /// 派生 getter：UI 与 selector 的既有读取点零改动。
  bool get supportsAccountDataEnrichment =>
      accountDataEnrichmentExtraKey != null;
}
class AgentConnectionTestResult { … }  // L158-196 原样
class AgentConfigurationDocument { … } // L199-221 原样
class AgentConfigurationSaveResult { … }
class AgentLogEntry { … }
class AgentDetectionProgress { … }
class ManagedAgent { … }               // L264-450 原样，但删除 codex/grok/claudeCode
                                       // 三个厂商 factory（L291-312），保留 forDefinition
class AgentConfigurationConflictException { … }
class AgentConfigurationValidationException { … }

// ── AgentDefinition：删除静态表（enrichment key 不在这里，见能力位）──
class AgentDefinition {
  const AgentDefinition({
    required this.id,
    required this.displayName,
    required this.vendor,
    required this.commandName,
    required this.protocol,
    required this.transport,
    required this.configFormat,
    required this.defaultConfigRelativePath,
    required this.npmPackage,
    this.isBeta = false,                 // 现状 L85，逐字保留（初稿伪代码漏列）
  });
  // …字段原样，含 isBeta…
  // **不加** accountDataEnrichmentExtraKey：它挂在 AgentCliManagementCapabilities 上，
  // 与能力位合一，避免「声明了能力却没声明 key」的半状态（§3.6）。
  // 删除：static const codex/grok/claudeCode（L101-137）→ 字面量迁入各自插件包
  // 删除：static all / byId（L140-154）→ 由 contribution 聚合 map 取代
}

// ── 端口与回调（自 agent_cli_management_repository.dart 原样迁移）──
abstract class AgentCliManagementRepository { … }       // L7-53 十个成员原样
abstract interface class AgentCliManagementDescriptor { … }  // L59-67 原样
typedef AgentDetectionProgressCallback = …;

// ── 窄模型目录端口（新；实测 repositories 只用 load 一个方法，
//    见 codex repo:641-647 / grok repo:707-716）──
abstract interface class AgentManagementModelCatalogPort {
  Future<AgentModelCatalogLoadResult> load({
    required AgentProviderConfig config,
    required String source,
    required AgentModelCatalogLoader refreshLoader,
    bool forceRefresh = false,
  });
}
// AgentModelCatalogLoadResult / AgentModelCatalogLoader / fetchAgentProviderModels
// 自 agent/application/agent_model_catalog_repository.dart（L74-80 签名、L395 起函数）
// 迁入本文件——它们只依赖 core 类型，本就该在契约层。

// ── 文案端口（自 domain 整体迁移，成员零改动）──
abstract interface class AgentManagementTextCatalog { … }   // 45 成员原样
final class FallbackAgentManagementTextCatalog implements … { … }

// ── 宿主服务与贡献类型（新）──
final class AgentManagementHostServices {
  const AgentManagementHostServices({
    required this.textCatalog,
    required this.runtimeRegistry,
    this.modelCatalog,
  });
  final AgentManagementTextCatalog textCatalog;
  final AgentProviderRuntimeRegistry runtimeRegistry;   // core 类型，插件直接用
  final AgentManagementModelCatalogPort? modelCatalog;  // 可空语义同现状
}

final class AgentManagementContribution extends ZetaPluginContribution {
  const AgentManagementContribution({
    required this.providerId,
    required this.definition,
    required this.createRepository,
  });
  final String providerId;
  final AgentDefinition definition;
  final AgentCliManagementRepository Function(AgentManagementHostServices services)
      createRepository;

  // ZetaPluginContribution 是 abstract base class，contributionKind 是必须实现的成员
  // （进 ZetaPluginState.contributionKinds 诊断分组，属稳定标签，改动即破坏诊断口径）。
  @override
  String get contributionKind => 'zeta.agent.management-repository';
}
```

### 3.3 provider_api 的 usage 子库

新增 `lib/src/usage.dart`：

```dart
// ── 查询模型闭包（自 usage_statistics/domain 迁移，实测闭包）──
// AgentUsageQuery 实测只有 { DateTime earliest, bool forceRefresh } 两字段，
// 不引用 UsageDateWindow/UsageTimeRangePreset——这两个类型是 UI 侧时间窗模型，
// 留在 app（narrow source 目录不需要 timeRangeLabel 之外的成员，UI 目录本就留 app）。
// 实测迁移集合（按签名递归闭包）：
//   AgentUsageQuery、AgentTokenUsageSourceSnapshot（providerId/providerName/
//   historyPresence/records/refreshedAt/warnings，用 UnmodifiableListView，dart:collection
//   无碍）、AgentTokenHistoryPresence、AgentUsageWarning、AgentUsageRecord
//   （含 toJson/tryDecode 白名单——errorMessage 不落盘的 G7 行为随迁）、
//   UsageTokenBreakdown、UsageTaskStatus（+ UsageTaskStatusX 扩展）、UsageErrorCategory。
// 禁止把 panel/report 类型（UsageOverview/UsageStatisticsReport 等查询结果层）带下来。
abstract interface class AgentTokenUsageSource {           // 自 domain 原样
  String get providerId;
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query);
}
abstract interface class AgentTokenUsageSourceRegistry {   // 自 domain 原样
  AgentTokenUsageSource? createFor(AgentProviderConfig config);
}

// ── 分区端口（自 usage_statistics/data/usage_statistics_partition_store.dart 迁移）──
// UsageStatisticsIndexPartition 类（L11-48）原样迁：schemaVersion/payload 字段名、
// 冻结语义、tryDecode 宽容度全部不变（D7：索引根版本 4 与分区字节不变）。
abstract interface class AgentUsagePartitionPort {
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey);
  Future<void> writePartition(String sourceKey, UsageStatisticsIndexPartition partition);
}

// ── 窄文案端口（新，5 成员签名逐字复制自 UsageStatisticsTextCatalog 现状）──
abstract interface class AgentUsageSourceTextCatalog {
  String get indexWriteFailed;
  String indexReadRescanned(String providerName);
  String sessionDirIncomplete(String providerName);
  String sessionFilesUnreadable(/* 以现状签名为准 */);
  String historyRowsCorrupt(String count, String providerName);
}
final class FallbackAgentUsageSourceTextCatalog implements AgentUsageSourceTextCatalog {
  // 5 成员的英文保守默认，逐字复制自 FallbackUsageStatisticsTextCatalog 对应成员
}

// ── 宿主服务与贡献类型（新）──
final class AgentUsageHostServices {
  const AgentUsageHostServices({
    required this.partitionPort,
    this.textCatalog = const FallbackAgentUsageSourceTextCatalog(),
  });
  final AgentUsagePartitionPort partitionPort;
  final AgentUsageSourceTextCatalog textCatalog;
}

final class AgentUsageContribution extends ZetaPluginContribution {
  const AgentUsageContribution({
    required this.providerType,   // 现状 switch 按 config.kind 路由（C2），故键是 type
    required this.createSource,
  });
  final AgentProviderTypeId providerType;
  final AgentTokenUsageSource Function(
    AgentUsageHostServices services,
    AgentProviderConfig config,
  ) createSource;

  @override
  String get contributionKind => 'zeta.agent.token-usage-source';
}
```

> **行为保持注意**：现状组合点（`usage_statistics_slice_overrides.dart:40-42`）构造 registry 时**没有**注入本地化目录，source 内部落到 `FallbackUsageStatisticsTextCatalog`。因此 `AgentUsageHostServices.textCatalog` 的默认值保持 fallback，组合侧**不要**顺手改成本地化目录——那是行为变化，单独提 PR。

### 3.4 插件包内的 contribution 声明（以 codex 为例）

```dart
// packages/zeta_agent_provider_codex/lib/src/management_contribution.dart

/// 自 agent_management_models.dart:101-113 的 AgentDefinition.codex 字面量逐字迁入。
const AgentDefinition codexAgentManagementDefinition = AgentDefinition(
  id: 'codex', displayName: 'Codex', vendor: 'OpenAI', /* …逐字段照抄… */
);

AgentManagementContribution createCodexManagementContribution() =>
    AgentManagementContribution(
      providerId: defaultAgentProviderId,
      definition: codexAgentManagementDefinition,
      createRepository: (services) => CodexAgentManagementRepository(
        runtimeRegistry: services.runtimeRegistry,
        modelCatalogRepository: services.modelCatalog,   // 参数类型随 port 换
        textCatalog: services.textCatalog,
      ),
    );

AgentUsageContribution createCodexUsageContribution() => AgentUsageContribution(
  providerType: codexAgentProviderType,
  createSource: (services, config) => CodexTokenUsageSource(
    config: config,
    partitionStore: services.partitionPort,
    textCatalog: services.textCatalog,
  ),
);
```

插件类的 contribution 列表从 1 项变 3 项：

```dart
class CodexAgentProviderPlugin extends ZetaPlugin<…> {
  List<ZetaPluginContribution> get contributions => [
    AgentProviderPluginContribution(definition: …, bundleFactory: …),  // 已有
    createCodexManagementContribution(),                              // WP-D 新增
    createCodexUsageContribution(),                                   // WP-D 新增
  ];
}
```

迁入插件包的 app 侧文件（import 改写规则同 WP-C §3）：

| 迁入 codex 包 | 迁入 grok 包 | 迁入 claude 包 |
|---|---|---|
| `agent_management/data/codex_agent_management_repository.dart` | grok 同名 | claude 同名（内含 `ClaudeCodeConnectionProbe`/`ClaudeCodeMetadataFileSystem` 等私有类型，整体随迁） |
| `agent_management/data/codex_config_file.dart`、`codex_log_files.dart`、`codex_latest_version_service.dart`、`codex_cli_locator.dart`（shim，删除改用包内 locator） | grok locator shim 删除 | `claude_code_auth_status_probe.dart`、locator shim 删除 |
| `usage_statistics/data/providers/codex/**`（source + log_scanner + partition_codec + session parser/registry/extractor） | `providers/grok/**`（source + log_scanner + partition_codec） | `providers/claude_code/**`（source + partition_codec；**无本地 scanner**——实测 claude source 直接复用 `ClaudeCodeSessionHistoryReader`，该类型 WP-C 后已在 claude 包内，天然可用） |
| 对应 root 测试随迁包内 | 同 | 同 |

**跨家共享文件**：`usage_statistics/data/providers/usage_scan_cache.dart`（`usageFileFingerprint`/`findUsageCachedSession`/`usageCacheHit`，实测被三家引用：codex scanner:7、grok scanner:7、claude source:6）**不属于任何一家**——T4 时迁入 **sdk**（import `dart:io` 的 `FileStat`，与 sdk 依赖规则相容；api 是纯契约层不收 dart:io）。三个 scanner/source 的 import 指向 sdk barrel。

**Claude management 构造差异（实测）**：claude repository 构造**不含** `runtimeRegistry`/`modelCatalog` 参数（probes 自足），其 contribution 的 `createRepository` 忽略这两个 service 字段即可，端口设计不受影响。

repository/source 体改动仅四处：import 换包、`modelCatalogRepository`/`partitionStore`/`textCatalog` 参数类型换 api 端口、`ManagedAgent.codex(...)` 改 `ManagedAgent.forDefinition(definition: codexAgentManagementDefinition, ...)`（三家唯一调用点，实测 codex:74 / grok:94 / claude:172）、claude repository 的 `managementCapabilities` 声明追加 `requiresConnectionTestConfirmation: true`（§3.6 能力位，T0 落地字段，声明值可随 T2 随迁）。

### 3.5 app 侧聚合（消灭 C1/C2/C5）

> **接缝与 fail-closed 是硬要求（00-index D9）**。两条约束必须一起满足：
>
> 1. **不得让组合层直接问 `pluginRegistry`**。现状 `ide_workbench_composition.dart:47-61`
>    与 `built_in_agent_token_usage_source_registry.dart:26-42` 都不认识插件内核，所以
>    12 个文件、20+ 处覆盖 `agentProviderBundleFactoryProvider` 的测试压根不建插件目录
>    （`zeta_app_composition.dart:180` 明文依赖这一点）。直接查 registry 会让这些用例
>    要么开始真激活插件、要么拿到空贡献导致管理页零卡片——两条都会逼着改断言，
>    违反本 WP 纪律。
> 2. **空贡献表必须抛**。`ZetaPluginRegistry.contributions<T>()` 在内核关闭后返回
>    `const []`（`plugin_registry.dart:112-115`），静默降级会让管理页少 Provider、
>    用量面板报「无数据」——正是 G4 禁止的静默成功。
>
> 落法：新建 `lib/src/app/plugins/agent_contribution_providers.dart`
>
> ```dart
> final agentManagementContributionsProvider =
>     Provider<List<AgentManagementContribution>>(
>       (ref) => ref
>           .watch(zetaPluginCatalogProvider)
>           .registry
>           .contributions<AgentManagementContribution>(),
>       name: 'agentManagementContributions',
>     );
>
> final agentUsageContributionsProvider =
>     Provider<List<AgentUsageContribution>>(
>       (ref) => ref
>           .watch(zetaPluginCatalogProvider)
>           .registry
>           .contributions<AgentUsageContribution>(),
>       name: 'agentUsageContributions',
>     );
> ```
>
> 受影响用例加一行 `agentManagementContributionsProvider.overrideWithValue([...])`
> 即恢复原行为，**断言零修改**。组合层只读接缝。

```dart
// lib/src/app/composition/ide_workbench_composition.dart —— C1 替换
// 贡献列表由调用方经接缝读入并传进来（container.read(agentManagementContributionsProvider)），
// 本类不认识 pluginRegistry。
if (contributions.isEmpty) {
  throw StateError(
    'No plugin contributed agent management repositories; '
    'the workbench cannot assemble the management slice',
  );  // fail-closed，与 zeta_plugin_catalog.dart:113-118 的既有做法对齐
}
final managementContributions = <String, AgentManagementContribution>{
  for (final c in contributions) c.providerId: c,
};
final managementHostServices = AgentManagementHostServices(
  textCatalog: textCatalog,                       // LocalizedAgentManagementTextCatalog
  runtimeRegistry: runtimeRegistry,
  modelCatalog: AgentManagementModelCatalogPortAdapter(modelCatalogRepository),
);
final repositories = <String, AgentCliManagementRepository>{
  for (final c in managementContributions.values)
    c.providerId: c.createRepository(managementHostServices),
};
final managementDefinitions = <String, AgentDefinition>{
  for (final c in managementContributions.values) c.providerId: c.definition,
};
// managementDefinitions 传给 AgentManagementSliceComposition，取代 AgentDefinition.all/byId
```

```dart
// agent_management_slice_composition.dart —— C5 替换
// :54-64 原：for (final definition in AgentDefinition.all) … AgentDefinition.byId(id) ?? …
// 改为遍历注入的 definitions map；未知 id 的兜底 AgentDefinition('Unknown'…) 保留
// （runner:384-394 的兜底构造原样保留，只是查表来源换成注入 map）。
```

```dart
// runner:427-433 —— C5 的 codex 兜底替换
return _descriptor(repository)?.defaultProviderConfig ??
    AgentProviderConfig(
      id: repository.agentId,
      displayName:
          _definitions[repository.agentId]?.displayName ?? repository.agentId,
      kind: zetaAgentProviderDefinitionCatalog.byId(repository.agentId)
              ?.providerType ??
          const AgentProviderTypeId('unknown'),   // 中性兜底，不再是 codex 形状
      // 其余字段按 AgentProviderConfig 必填项的最小中性值
    );
// 注：三个内置 repository 都实现 descriptor（codex:57、grok:78、claude:156），
// 该兜底对内置 Provider 不可达，仅护住第三方/fake repository。
```

```dart
// usage_statistics_slice_overrides.dart:40 —— C2 替换
final class ContributedAgentTokenUsageSourceRegistry
    implements AgentTokenUsageSourceRegistry {
  ContributedAgentTokenUsageSourceRegistry(
    Iterable<AgentUsageContribution> contributions, {
    required AgentUsageHostServices services,
  }) : _byType = {for (final c in contributions) c.providerType: c},
       _services = services;

  final Map<AgentProviderTypeId, AgentUsageContribution> _byType;
  final AgentUsageHostServices _services;

  @override
  AgentTokenUsageSource? createFor(AgentProviderConfig config) =>
      _byType[config.kind]?.createSource(_services, config);  // null = unsupported，语义同现状

  // 构造体内：if (_byType.isEmpty) throw StateError('No plugin contributed token usage sources');
}
// 组合点（usage_statistics_slice_overrides.dart）：经接缝读，不碰 pluginRegistry。
// 空表是装配事故，抛；createFor 返回 null 仍是合法的 unsupported 语义，两者不要混。
ContributedAgentTokenUsageSourceRegistry(
  ref.watch(agentUsageContributionsProvider),
  services: AgentUsageHostServices(
    partitionPort: ref.watch(usageStatisticsPartitionStoreProvider),  // app store 直接 implements 端口
  ),
)
```

`FileUsageStatisticsPartitionStore`（`usage_statistics_partition_store.dart:61`）改 `implements AgentUsagePartitionPort`——签名本来一致；`UsageStatisticsPartitionStore` 旧接口若除三个 source 外无其他实现/引用（实施时 grep 确认）则删除，否则保留为继承端口的空子接口。

### 3.6 C3/C4/C6：enrichment key 声明化与 setup guide 例外

**key 与能力位合一（本轮设计修正）**：初稿把 key 放在 `AgentDefinition`、把「支持与否」放在
`AgentCliManagementCapabilities`——两个对象、两处声明，必须同真同假却没有任何机制保证，
于是 runner 里要留一句「理论上不可达但绝不静默」的 `UnsupportedError`，WP-E 还要再加一条
parity 守卫。改为**一个可空字段**后，「声明了能力却没声明 key」这个半状态不可表示：

```dart
// AgentCliManagementCapabilities（§3.2）
final String? accountDataEnrichmentExtraKey;             // 非 null 即支持
bool get supportsAccountDataEnrichment => accountDataEnrichmentExtraKey != null;
```

claude repository 的 `managementCapabilities`（现状 `:152-153` 声明 `supportsAccountDataEnrichment: true`）
改为一处声明：`accountDataEnrichmentExtraKey: claudeCodeAccountDataEnrichmentKey`（值
`'claudeCode.accountDataEnrichment'` 逐字不变，D7）。UI 与 selector 读 `supportsAccountDataEnrichment`
的地方**一行都不用改**（派生 getter 同名同义）。

```dart
// agent_management_slice_composition.dart:94-95 —— C3 替换
// capabilities map 已在 state（agent_management_slice_state.dart:214-218 的 capabilitiesByAgentId）
accountDataEnrichmentEnabledFor: (config) {
  final key = capabilitiesByAgentId[config.id]?.accountDataEnrichmentExtraKey;
  return key != null && config.extra[key] != false;
},
// 语义等价论证：读取口（store:138-143）先经 supportsAccountDataEnrichment 能力门，
// 而该 getter 现在就是 `key != null`，两处判据同源，行为不变。
```

```dart
// agent_management_slice_runner.dart:212-220 —— C4 替换
final key = _capabilities[effect.agentId]?.accountDataEnrichmentExtraKey;
if (key == null) {
  throw UnsupportedError(   // 保留：第三方 repository 谎报能力时仍要炸，不静默
    'Agent ${effect.agentId} does not declare accountDataEnrichmentExtraKey',
  );
}
final extra = Map<String, Object?>.from(current.extra);
if (effect.enabled) { extra.remove(key); } else { extra[key] = false; }
```

**C6 处理**：两处分支性质不同，分开处置——

- **`page.dart:664`（测试连接前的确认弹窗）→ 能力化，不留例外。** 实测该分支是 `_testConnection()` 前置的 Claude 确认弹窗（`mgmtTestClaudeTitle`/`mgmtTestClaudeBody`，警告测试连接对 Claude 的副作用）。处置：`AgentCliManagementCapabilities` 新增 `requiresConnectionTestConfirmation`（默认 false；claude repository 在 `managementCapabilities` 里声明 true），门改为：

```dart
// page.dart _testConnection() —— 664 分支替换
final caps = /* state.capabilitiesByAgentId[_operations.selectedAgentId] */;
if (caps?.requiresConnectionTestConfirmation == true) {
  // …确认弹窗原样（文案是 Zeta 持有的 ARB 槽位，同 D8 先例；
  //   Claude 品牌文案留作登记债，第二家声明该能力时再泛化文案）…
}
```

  语义等价论证：现状只有 Claude 进弹窗，改写后只有声明该能力的（=Claude）进弹窗；能力位已在 state（`capabilitiesByAgentId` selector，`agent_management_slice_state.dart:214-218`），page 只多读一个 map。

- **`page.dart:451`（setup guide 卡片）→ 登记例外，但形态必须改写。** 现状分支条件是 `agent.definition.id == AgentDefinition.claudeCode.id`——而 T0 删除静态表后 `AgentDefinition.claudeCode` **符号不复存在**，原样保留编译都过不了。目标形态：

```dart
// agent_management_page.dart（文件私有）
/// 登记例外（WP-D §3.6）：Claude 专属安装指引卡片的门。
/// 值逐字 = Claude 内置 providerId（D7 红线 'claude_code'）。
/// 第二家需要 setup guide 时再泛化（能力位 + 可泛化内容），届时删除本常量。
const String _setupGuideAgentId = 'claude_code';
// 451 处：agent.definition.id == _setupGuideAgentId ? const _ClaudeCodeSetupGuideCard() : null
```

  **为什么 451 不像 664 那样能力化**：664 的弹窗只是一句警告文案（Zeta 文案槽位，D8 先例成立）；451 的 setup guide 是**整卡多段 Claude 安装指引内容**，若挂在中性能力位后面，未来声明该能力的 Provider 会看到 Claude 品牌指引——能力化反而是误导性抽象。诚实的边界就是登记一个 id 字面量例外。插件包是纯 Dart 无法贡献 Widget；引入「UI 贡献」机制属于过度设计（YAGNI）。WP-E 守卫 5 相应改为：presentation 层 grep `'claude_code'` 字面量 + 全仓 grep `AgentDefinition.claudeCode`，命中只允许这一处。

## 4. 任务分解

### T0 · provider_api 扩展（management + usage 子库）
**产出**：api 包新增 `src/management.dart`、`src/usage.dart` + barrel 两行 export
1. 按 §3.2/§3.3 迁移类型；`ManagedAgent` 删三个厂商 factory（同步改三处调用点所在的 repository——它们在 T2 才迁包，本任务先改调用为 `forDefinition`）。
2. `AgentDefinition` 删静态表（**不加** enrichment key 字段，它进能力位）；`AgentCliManagementCapabilities` 的 `supportsAccountDataEnrichment` 由 bool 改可空 key + 派生 getter；**所有引用点本轮编译错误即迁移清单**（实测清单已列 §1 C5 + 两个 presentation 点 + composition/runner），全部改为注入 map 查表。
3. **过渡形态**：三个 `AgentDefinition` 字面量与 contribution 声明暂写在一个新建的 app 过渡文件（建议 `lib/src/app/agent_management_slice/management_contributions.dart`）——此刻 repository 还在 app 层，插件包无法 import app，字面量只能先进过渡文件；T2 随 repository 一起迁入插件包。该文件挂注释「T2 后删除」，并**登记进 WP-C §2 过渡白名单**：claude 字面量的 `accountDataEnrichmentExtraKey: claudeCodeAccountDataEnrichmentKey` 需要 import claude 插件 barrel（该过渡导出正是为此保留，WP-C T3 已安排）；T2 迁入包内后改用包内私有常量，import 与白名单条目一起消除。
4. `page.dart:664` 在本任务内经 `requiresConnectionTestConfirmation` 能力位等价改写（§3.6，语义等价论证见该节）；`page.dart:451` 同步改写为 §3.6 的 `_setupGuideAgentId` 字面量形态——**不是可选项**：T0-2 删除静态表后 `AgentDefinition.claudeCode` 无法编译，登记例外的新形态必须同轮落地。
5. **根测试的字面量来源**：实测 4 个根测试文件引用静态表（`ide_shell_widget_test:2282-2284`、`ide_home_localization_test:97/120`、`agent_management_page_test:457`、`global_home_page_test:207`）。落点是 `test/src/testing/agent_management_test_definitions.dart`（双层边界下这层允许 import 插件包，见 00-index D10），四个引用点改指它。
   **T0 期只能持测试侧字面量**（逐字段照抄，含 `isBeta`）——此刻 definition 还在 T0-3 的 app 过渡文件里；**T2 后**该文件可直接从插件贡献取 definition，字面量副本随之删除。在副本存在的窗口期，WP-E 贡献完备性守卫附加 parity 断言：测试字面量与插件贡献的 definition 逐字段一致（防漂移）；副本删除后该断言同步移除。
6. app 侧 `zeta_text_catalogs.dart` 与两个 feature 的引用文件改 import 指向 api。
7. `flutter analyze` + `bash tool/test_full.sh`（import 图失真，走全量）。
**验收**：行为零变化；`grep -rn "AgentDefinition\.\(codex\|grok\|claudeCode\|all\|byId\)" lib/ test/` **零命中**（静态表已删，C6 例外以 `_setupGuideAgentId` 字符串字面量形态存在于 `page.dart`，由 WP-E 守卫 5 单独固化，不走本 grep）。

### T1 · management contribution 类型 + 聚合骨架
**产出**：`AgentManagementContribution`/`AgentManagementHostServices` 落地；composition 改聚合（C1 消灭）
1. api 加类型（若 T0 未含）；**新建 `lib/src/app/plugins/agent_contribution_providers.dart`** 落地两个接缝 provider（§3.5 的硬要求），组合层只读接缝，不直接碰 `pluginRegistry`；kernel 侧用现有类型化 API `ZetaPluginRegistry.contributions<T>()`（`plugin_registry.dart:109`）。
2. 组合层按 §3.5 改写（含空贡献 fail-closed）；`AgentManagementModelCatalogPortAdapter` 落地（单方法转发 `AgentModelCatalogRepository.load`，签名收窄到 §3.2 端口）。
   **回归自查**：12 个覆盖 `agentProviderBundleFactoryProvider` 的测试文件逐个确认仍不建插件目录（`ProviderContainer.exists(zetaPluginCatalogProvider)` 仍为 false）；需要贡献的用例加一行 `overrideWithValue`，不得改断言。
3. 三个 repository **暂留 app 层**但构造改经 contribution 工厂创建——此 PR 内 contribution 的 `createRepository` 与 `AgentDefinition` 字面量都写在 T0 的过渡文件里，T2 随 repository 迁入插件包。
4. **注意**：kernel 的 `contributions<T>()` 只来自激活插件；过渡期 management contribution 尚未挂到插件类（T2 才挂），组合层应直接消费过渡文件的常量列表而非查 kernel——T2 落地时再把来源切成 `contributions<AgentManagementContribution>()`。WP-E 的贡献完备性守卫同理在 T2 后才对 management/usage 生效。
**验收**：管理页三个 agent 卡片全绿测试；`test_full.sh` 绿。

### T2 · management repository 迁入插件包
**产出**：三 repository + 私有助手入包；WP-C §2 白名单抹掉三行
1. 逐包迁移（§3.4 表）；contribution 声明（definition 字面量 + 工厂）从 T0 过渡文件迁入包内并挂上插件类的 `contributions`；过渡文件删除。
2. 组合层的来源从过渡常量切成 `pluginRegistry.contributions<AgentManagementContribution>()`（T1-4 的切换点在此落地）。
3. root 的 repository 测试随迁包内。
4. manifest 无需改动（contribution 由插件类携带，kernel 激活时自动汇入快照）。
**验收**：三包独立 `flutter test` 绿；白名单 grep 确认三行已消除；贡献完备性守卫（WP-E T1-4）对 management 生效。

### T3 · usage contribution 类型 + registry 替换
**产出**：`ContributedAgentTokenUsageSourceRegistry` 落地（C2 消灭）
1. 按 §3.5 实现；`BuiltInAgentTokenUsageSourceRegistry` 删除。
2. `FileUsageStatisticsPartitionStore` implements 端口；旧接口按 §3.5 规则处置。
3. 三个 source **暂留 app 层**，由 composition 处的过渡工厂创建（同 T1 形态）。
**验收**：usage 面板全量测试绿；`switch (config.kind)` 在 app 层绝迹（`grep -rn "codexAgentProviderType =>" lib/` 无输出）。

### T4 · usage source 迁入插件包
**产出**：三 source + 私有 codec/scanner 入包；白名单再抹三行
1. 逐包迁移（§3.4 表）；source 构造的 `partitionStore`/`textCatalog` 参数换 api 端口；包内 contribution 工厂就位。
2. root 的 source 测试随迁包内。
3. **D7 自查**：三个 partition codec 逐字节随迁（索引字节不变）；索引根版本常量 `usageStatisticsPartitionIndexVersion = 4` 留在 app（store 侧），不迁。
**验收**：同 T2。

### T5 · enrichment key 声明化（C3/C4/C6）
**产出**：`AgentCliManagementCapabilities.accountDataEnrichmentExtraKey` 全链路启用；claude repository 的 `managementCapabilities` 一处填入 `claudeCodeAccountDataEnrichmentKey`（值 `'claudeCode.accountDataEnrichment'` 不变，D7）
1. composition/runner 按 §3.6 替换（capabilities map 来自 state 既有的 `capabilitiesByAgentId`，不需要新通道）。
2. `page.dart:664` 已在 T0-4 经能力位改写；`page.dart:451` 已在 T0-4 以 `_setupGuideAgentId` 字面量形态登记为例外，本任务只需复核注释指向 §3.6。
3. 插件包 barrel 移除 `claudeCodeAccountDataEnrichmentKey` 的过渡导出（WP-C 白名单收口）。
**验收**：`claudeCodeAccountDataEnrichmentKey` 在 lib/test 无生产引用或测试 import；现有 `agent_provider_catalog_freeze_test.dart` 的禁用符号匹配字符串保留，以免削弱守卫（该常量与其唯一声明点都在 claude 插件包内）。

### T6 · 端到端假插件验证
**产出**：`test/src/app/plugins/fake_agent_provider_plugin_e2e_test.dart`
1. 内存假插件：definition + bundle + management contribution + usage contribution 四件套。
2. 断言链：激活 → definition catalog 可见 → 管理页出现第四张卡片（detect 走 fake repository）→ usage query 能路由到 fake source → 移除假插件 import 后全仓编译通过（该步为人工/CI 验证，非测试断言）。
**验收**：测试绿；这是「新增 Provider 只加一个包」的直接证据。

## 5. DoD

- [x] C1–C5 实测位置全部消灭，`grep` 自证（命令见各任务）
- [x] 三个 repository 与三个 source 物理位于插件包，构造只经 contribution
- [x] **WP-C §2 过渡白名单清零**（具体厂商包 `zeta_agent_provider_(codex|grok|claude_code)` 在 `lib/` 除 manifest 外无 import/export；api/sdk 属中立包）——WP-E 守卫 2 的启用前置
- [x] app 层（含 composition/runner/page）除 C6 登记例外（`page.dart` 的 `_setupGuideAgentId` 一处字符串字面量）外无厂商标识分支
- [x] 贡献消费经接缝 provider，且空贡献表 fail-closed：`grep -rn "pluginRegistry\|\.registry\.contributions" lib/src/app/composition lib/src/app/usage_statistics_slice` 零命中
- [x] 覆盖 bundle 工厂的既有测试仍不建插件目录（本轮实测 11 个匹配文件，含一份结构守卫；通过测试助手及贡献接缝覆盖保持原断言）
- [x] D7：enrichment key 值、索引版本与分区字节、definition 字段值逐字节不变
- [x] `AppAgentManagementTextCatalog` / `AppUsageStatisticsTextCatalog` 实现体零 diff（当前树的实际命名；仅 import 与 implements 列表变化）
- [x] T6 假插件 e2e 绿
- [x] 本次完整变更集 `test_full.sh` 绿

## 6. 风险

| 风险 | 缓解 |
|---|---|
| 50+ 处文案调用点在迁包时漏改 import | T2/T4 以编译器为清单；目录接口零改动使 diff 面最小 |
| `AgentDefinition` 删静态表波及面漏改 | T0 先改类型让编译器枚举全部引用点（实测已列出 10 处） |
| usage 组合点历史上注入的是 fallback 文案，误「优化」成本地化目录 | §3.3 显式标注保持 fallback；PR 描述重申 |
| 窄端口与真实 repository 方法签名漂移 | adapter 只做转发无逻辑；端口签名从现状调用点（codex:641-647）逐字段复制 |
| C6 例外扩散 | WP-E 守卫断言 presentation 厂商分支仅 `page.dart:451` 一处登记（664 已能力化） |
| 贡献化把 management/usage 绑上插件激活，冲掉测试逃生口 | §3.5 接缝 provider + T1-2 的 12 文件回归自查；这是本 WP 最容易静默破坏「断言零修改」的一条 |
| 内核关闭/降级时贡献表为空导致静默缺项 | 两个消费点均 fail-closed 抛 `StateError`（与 `zeta_plugin_catalog.dart:113-118` 对齐） |

## 7. 开发记录

| 日期 | 内容 |
|---|---|
| 2026-09-04 | 初稿 |
| 2026-09-04 | 重写：硬编码清单全部换成实测 file:line（C1-C6 + 两个假象排除）；文案方案从「失败原因码映射」改为 D8「目录接口下沉」（AgentUiTextCatalog 先例，50+ 调用点实测为依据）；usage 侧收窄为 5 成员窄端口 + fallback 保持现状的实测发现落档；`AgentDefinition` 与元数据合并并新增 `accountDataEnrichmentExtraKey`（enrichment 能力门本已 G4 合规的实测结论）；`runtimeRegistry` 为 core 类型无需窄端口、真正窄端口只有模型目录（单方法，签名实测）；usage registry 现状是 `switch (config.kind)` 故 contribution 键为 providerType；C6 登记为例外并给出语义等价论证 |
| 2026-09-04 | 完整勘察报告对账：usage 闭包精确化（query 实测仅 earliest/forceRefresh，`UsageDateWindow`/`UsageTimeRangePreset` 不下沉；补 `UsageErrorCategory`）；`usage_scan_cache.dart` 三家共用实测落档（T4 迁 sdk）；claude source 无本地 scanner、claude management 构造无 runtimeRegistry/modelCatalog 两处差异落档；**664 分支实测为测试连接确认弹窗**（非 enrichment 编辑），改经新增能力位 `requiresConnectionTestConfirmation` 消灭，C6 登记例外收敛为 451 一处；T0 补根测试字面量 fixture（4 个引用点实测）与 WP-E parity 守卫联动 |
| 2026-09-04 | 实证复核轮：① **§3.5 新增接缝与 fail-closed（00-index D9）**——实测现状两个装配点都不认识插件内核，12 个文件 20+ 处用例靠覆盖 `agentProviderBundleFactoryProvider` 来不建插件目录（`zeta_app_composition.dart:180` 明文依赖），直接查 registry 会逼着改断言；改为 `agentManagementContributionsProvider` / `agentUsageContributionsProvider` 两个可覆盖 provider，且空贡献表抛 `StateError`（`contributions<T>()` 在内核关闭后返回 `const []`，静默降级违反 G4）。② **enrichment key 折叠进能力位**——`String? accountDataEnrichmentExtraKey` + 派生 getter 取代「definition 持 key + capabilities 持 bool」，半状态不可表示，UI 读取点零改动，省掉一条 WP-E parity 守卫。③ 两个新贡献类型补 `contributionKind` 实现（`ZetaPluginContribution` 是 abstract base class，该成员必须实现且进诊断口径）。④ `AgentDefinition` 伪代码补回实测存在的 `isBeta` 字段。 |
| 2026-09-04 | 终审轮：① **C6 内部矛盾修正**——T0 删除静态表后 `AgentDefinition.claudeCode` 符号不复存在，451 例外原样保留会编译失效；目标形态定为文件私有 `_setupGuideAgentId = 'claude_code'` 字面量（T0-4 同轮落地，非可选），并补「为什么不能力化 451」的论证（整卡 Claude 品牌内容 vs 664 的一句警告文案）；T0 验收 grep 与 WP-E 守卫 5 同步改为新形态。② T0-3 过渡文件的 claude key 来源写明（import claude barrel 过渡导出，加入 WP-C §2 白名单，T2 后消除）。③ DoD 新增「WP-C §2 过渡白名单清零」（WP-E 守卫 2 的启用前置）。④ usage source 构造签名实测核验：三家恰好只收 `(config, partitionStore, textCatalog)`，`AgentUsageHostServices` 不需要 home 解析字段（claude 的 homeDirectory 参数是可选自解析），设计无缺口。 |

## 8. 本轮实测修正（2026-09-05）

- 当前实际迁移为 4 个 management 生产文件、8 个 usage 生产文件、9 个测试文件；计划中的独立 config/log/version/locator shim 文件在 WP-C 完成树中不存在，不创建额外壳文件。
- Grok 仍从 Codex repository 借用版本比较、配置遮挡、日志清洗。它们是中立机制，整体移到 sdk；纯文本脱敏及显式环境 HOME 解析由 foundation 承载，宿主日志与插件共用，避免跨插件 import 和重复实现。
- 用量 fallback 实际为中文；保留原 5 个方法逐字文本，不按早期伪代码改成英文。`usageProjectName` 的默认“未知项目”亦保持原值。管理文本目录整体迁移，ARB 实现体不变。
- Grok 管理实现已有 toml 依赖，从根移动后在 Grok pubspec 声明同一约束 `^0.18.0`；没有新增第三方版本。
- 各插件实际是 `ZetaSynchronousPluginFactory`，贡献来自 activate 返回的 handle。宿主先解析 Provider，再校验每个插件自己拥有的三类贡献，避免伪代码直接读取未激活 registry 的空表。
- T0–T5 在一个变更集中完成；不落地随后即删除的临时 app contribution 文件。完整验证及审计见 [WP-D 验证记录](07-wpd-validation.md)。

- 最终验收：`dart format .`、`flutter analyze`、`bash tool/test_affected.sh` 和 `bash tool/test_full.sh` 全部通过；两个测试门禁各 2854 条，退出码均为 0。WP-D 完成，下一项 WP-E。
