# WP-A · 契约包 `zeta_agent_provider_api`

> 状态：未开始
> 规模：约 1 人天
> 依赖：无（本计划第一个 WP）
> 性质：纯搬移 + 一处语义等价迁移（metricLabel 入 definition）。行为零变化，全量绿为凭。

## 1. 背景与现状

插件契约三件套当前住在 `zeta_agent_providers`，但不含任何厂商语义：

- `lib/src/agent_provider_definition.dart` — `AgentProviderDefinition` + `AgentProviderDefinitionCatalog`（197 行）
- `lib/src/agent_provider_plugin_contribution.dart` — `AgentProviderPluginContribution` + `ResolvedAgentProviderPlugins` + `AgentProviderPluginBundleFactory`（119 行）

厂商身份白名单的残留是 `lib/src/agent_metric_labels.dart`（34 行，全文）：

```dart
abstract final class AgentMetricLabels {
  static const ZetaMetricLabel codex = ZetaMetricLabel.constant('codex');
  static const ZetaMetricLabel grok = ZetaMetricLabel.constant('grok');
  static const ZetaMetricLabel claudeCode = ZetaMetricLabel.constant('claude_code');

  static ZetaMetricLabel forProviderId(String providerId) {
    return switch (providerId) {
      defaultAgentProviderId => codex,
      grokAgentProviderId => grok,
      defaultClaudeCodeProviderId => claudeCode,
      _ => ZetaMetricLabel.hashed(providerId),
    };
  }
}
```

`providerMetricLabel` 参数的注入点（`AgentProviderRuntimeRegistry` 构造函数签名，`zeta_agent_core/.../agent_provider_runtime_registry.dart:19-23`）：

```dart
AgentProviderRuntimeRegistry({
  required this.providerFactory,
  this.metrics = noopZetaMetricsPort,
  this.providerMetricLabel = ZetaMetricLabel.hashed,  // 默认 hash；组合层注入可读常量
});
```

当前**两个**生产注入点 + 两个测试注入点：

| 位置 | 现状 |
|---|---|
| `lib/src/app/plugins/zeta_plugin_providers.dart:68` | `providerMetricLabel: AgentMetricLabels.forProviderId` |
| `lib/src/app/app.dart:135` | `providerMetricLabel: AgentMetricLabels.forProviderId`（传给 `IdeHome`） |
| `test/src/features/agent/presentation/agent_phase0_behavior_baseline_test.dart:145-199` | 同函数名 |
| `test/src/features/agent/application/agent_provider_runtime_registry_test.dart:556-602` | 同函数名 |

另有一处注释引用：`zeta_agent_core/.../agent_provider_runtime_registry.dart:33`（「组合层注入 `AgentMetricLabels.forProviderId`（data 层）后……」，改为指向 catalog）。

**本 WP 明确不搬**：`agent_provider_static_capabilities.dart`（86 行）是按厂商分常量（`codexAppServer` / `grokAcp` / `claudeCode`）的能力种子表，属厂商私产，WP-C 解散进各插件包。

## 2. 目标与非目标

目标：

- 新建 `packages/zeta_agent_provider_api`（纯 Dart 包，无 Flutter 依赖），契约两文件原样上移。
- `AgentProviderDefinition` 新增 `required ZetaMetricLabel metricLabel`；catalog 新增 `metricLabelFor`；删除 `AgentMetricLabels`，四个注入点全部切换。
- 全仓 import 切换完毕，`zeta_agent_providers` 不再导出契约两文件。

非目标：

- 不动 `zeta_agent_core` 的 `AgentProviderBundleFactory` / `AgentProviderCapabilities` / `AgentProviderTypeId` / registry 本体（只改一行注释）。
- 不建 re-export 兼容层：引用点全部在本仓，一次切完。
- 不迁 `agent_providers_contracts_test.dart`（它还测三内置插件，WP-C 随拆包消亡）。

## 3. 包设计

```
packages/zeta_agent_provider_api/
├── pubspec.yaml
└── lib/
    ├── zeta_agent_provider_api.dart        # barrel：只 export 下面两个 src 文件
    └── src/
        ├── agent_provider_definition.dart
        └── agent_provider_plugin_contribution.dart
```

> **预留扩展（本 WP 不做，WP-D T0 落地）**：api 包在 WP-D 会再长两个子库——
> `src/management.dart`（管理端口与模型闭包、`AgentManagementTextCatalog`、
> `AgentManagementContribution`）与 `src/usage.dart`（Token source 端口与查询模型、
> 窄分区端口、`AgentUsageContribution`）。建包时目录结构不必为它们预留空目录，
> 但 barrel 注释里写一句「契约面随贡献类型扩展」，避免后来者把两文件结构当成定案。

pubspec 逐字模板（对齐 `zeta_plugin_kernel` 的形态：纯 Dart、dev 用 `test` 而非 `flutter_test`）：

```yaml
name: zeta_agent_provider_api
description: Zeta Agent Provider 插件的宿主侧契约：definition/catalog/贡献类型/聚合 bundle 工厂。
publish_to: 'none'
version: 0.1.0
resolution: workspace

environment:
  sdk: ^3.12.2

dependencies:
  zeta_agent_core: ^0.1.0
  zeta_foundation: ^0.1.0
  zeta_plugin_kernel: ^0.1.0

dev_dependencies:
  test: ^1.25.0
```

`analysis_options.yaml`：与 `zeta_plugin_kernel` 对齐（有则复制，无则不建——workspace 根配置生效）。

根 `pubspec.yaml` 两处登记（列表按字典序，`zeta_agent_provider_api` 排在 `zeta_agent_core` 之后、`zeta_agent_providers` 之前——`_` 的码位小于字母）：

```yaml
workspace:
  - packages/zeta_agent_core
  - packages/zeta_agent_provider_api      # 新增
  - packages/zeta_agent_providers
  # ...
dependencies:
  zeta_agent_core: ^0.1.0
  zeta_agent_provider_api: ^0.1.0          # 新增
  zeta_agent_providers: ^0.1.0
  # ...
```

## 4. 任务

### T0 · 基线

`bash tool/test_full.sh` 确认起点全绿，记录耗时。

### T1 · 建包

1. 按 §3 建目录与 `pubspec.yaml`；根 `pubspec.yaml` 两处登记；`flutter pub get`。
2. 建 barrel 空壳：

```dart
/// Zeta Agent Provider 插件的宿主侧契约。
///
/// 这里只放**不含厂商语义**的装配契约；协议机制在 `zeta_agent_provider_sdk`，
/// 厂商实现在 `zeta_agent_provider_<x>`。依赖方向：本包只依赖
/// core / kernel / foundation。
library;

export 'src/agent_provider_definition.dart';
export 'src/agent_provider_plugin_contribution.dart';
```

验收：`flutter pub get` 与 `flutter analyze` 干净。

### T2 · definition/catalog 上移 + metricLabel 入 definition

1. `git mv`（或新建+删除）`zeta_agent_providers/lib/src/agent_provider_definition.dart` → api 包同相对路径。文件头注释保留；import 行不变（只引 `zeta_agent_core` + 新增 `zeta_foundation`——`ZetaMetricLabel` 来自 foundation，确认原文件是否已传递可用，否则显式 import）。
2. 应用设计变更（逐字段 diff）：

```dart
final class AgentProviderDefinition {
  const AgentProviderDefinition({
    required this.providerId,
    required this.providerType,
    required this.defaultConfig,
    required this.staticCapabilities,
    required this.modelCatalogSourceLabel,
    required this.metricLabel,                 // 新增
    this.modelCatalogFingerprintExtraKeys = const <String>{},
    this.isDefault = false,
  });

  // ...既有字段原样...

  /// 该 Provider 的指标标签，编译期常量。
  ///
  /// 内置插件声明 `ZetaMetricLabel.constant(...)`；指标维度只允许规范化标签（G7），
  /// 自定义配置 id 不经过这里，由 catalog 回落不可逆短 hash（见 [metricLabelFor]）。
  final ZetaMetricLabel metricLabel;
}
```

```dart
// AgentProviderDefinitionCatalog 追加方法（放在 staticCapabilitiesFor 附近）：
/// 指标标签查询：内置 id 用插件声明的常量，未知/自定义 id 回落不可逆短 hash。
/// 语义与退役的 `AgentMetricLabels.forProviderId` 逐分支一致。
ZetaMetricLabel metricLabelFor(String providerId) =>
    _byProviderId[providerId]?.metricLabel ?? ZetaMetricLabel.hashed(providerId);
```

语义等价论证（写进 PR 描述）：旧 switch 的三个命中分支是 `defaultAgentProviderId`（`'codex'`）/ `grokAgentProviderId`（`'grok'`）/ `defaultClaudeCodeProviderId`（`'claude_code'`），即三个 definition 的 `providerId`；`_byProviderId` 的键恰好是同一集合；未命中分支同为 `ZetaMetricLabel.hashed`。catalog 构造已 fail-closed 保证 providerId 唯一，无歧义。

3. 三个插件 definition 常量补字段（三个文件本 WP 内原地改，值逐字对齐旧常量）：

```dart
// codex_plugin.dart:
const AgentProviderDefinition codexAgentProviderDefinition = AgentProviderDefinition(
  // ...既有字段...
  metricLabel: ZetaMetricLabel.constant('codex'),
);
// grok_plugin.dart:      metricLabel: ZetaMetricLabel.constant('grok'),
// claude_code_plugin.dart: metricLabel: ZetaMetricLabel.constant('claude_code'),
```

（`ZetaMetricLabel.constant` 是 const 构造——现状 `agent_metric_labels.dart` 已这么用。）

### T3 · contribution/resolved/聚合工厂上移

`agent_provider_plugin_contribution.dart` 整文件移入 api 包 `src/`：

- `import 'package:zeta_agent_providers/src/agent_provider_definition.dart'` → 相对导入 `agent_provider_definition.dart`；
- 头部注释「它定义在 data 层（未来的 `zeta_agent_providers`）而不是内核里」改写为「它定义在宿主侧契约包 `zeta_agent_provider_api`」；
- 其余逐字不动（`ResolvedAgentProviderPlugins` / `AgentProviderPluginBundleFactory` 的 fail-closed 逻辑全部保留）。

### T4 · 删除 `AgentMetricLabels`，四个注入点切换

1. 删 `packages/zeta_agent_providers/lib/src/agent_metric_labels.dart`；barrel 移除 `export 'src/agent_metric_labels.dart';`。
2. 生产注入点：

```dart
// lib/src/app/plugins/zeta_plugin_providers.dart（agentProviderRuntimeRegistryProvider 体内）:
final agentProviderRuntimeRegistryProvider =
    Provider<AgentProviderRuntimeRegistry>(
      (ref) => AgentProviderRuntimeRegistry(
        providerFactory: ref.watch(agentProviderBundleFactoryProvider),
        metrics: ref.watch(zetaMetricsPortProvider),
        providerMetricLabel:
            ref.watch(agentProviderDefinitionCatalogProvider).metricLabelFor,
      ),
      name: 'agentProviderRuntimeRegistry',
    );
```

```dart
// lib/src/app/app.dart:135 —— IdeHome 参数。
// app.dart 不持有 Ref；经组合层容器读一次 catalog（写法以 app.dart 现有
// 容器访问方式为准，例如 composition 暴露的 container/read 通道）：
providerMetricLabel: <读 agentProviderDefinitionCatalogProvider>.metricLabelFor,
```

注意顺序约束：`agentProviderDefinitionCatalogProvider` 依赖插件激活（同步，首帧前完成），`app.dart:135` 所在分支本就发生在语言冻结与组合根就绪之后（见其上方注释「这一支只在语言冻结之后走到」），读取安全。

3. 测试注入点（两处）：把 `AgentMetricLabels.forProviderId` 换成 `builtInAgentProviderDefinitionCatalog.metricLabelFor`（该 catalog 在 WP-C 前仍由 providers barrel 导出，测试改动最小）。
4. `agent_provider_runtime_registry.dart:33` 注释改为「组合层按 `AgentProviderDefinitionCatalog.metricLabelFor` 注入后，内置 Provider 才会显示成可读常量」。

### T5 · 全仓 import 切换

| 文件 | 改动 |
|---|---|
| `zeta_agent_providers/lib/{codex,grok,claude_code}_plugin.dart`、`lib/src/agent_provider_static_capabilities.dart`（若引用 definition 类型）、`lib/built_in_agent_provider_plugins.dart` | `src/agent_provider_definition.dart` / `src/agent_provider_plugin_contribution.dart` 的 import 改 `package:zeta_agent_provider_api/zeta_agent_provider_api.dart` |
| `zeta_agent_providers/lib/zeta_agent_providers.dart` | 移除两条契约 export（definition / contribution）与 metric_labels export；pubspec 加 `zeta_agent_provider_api: ^0.1.0` |
| `lib/src/features/agent/data/agent_provider_config_codec.dart:3` | barrel import 换 api 包（只用到 `AgentProviderDefinitionCatalog` 类型） |
| `lib/src/app/plugins/zeta_plugin_catalog.dart:7` | 契约类型换 api 包；Claude 三个 store/factory 类型继续走 providers barrel（WP-C 处理） |
| `lib/src/app/plugins/zeta_plugin_providers.dart:3` | 同上 |
| `lib/src/app/app.dart:4` | barrel import 换 api 包（`AgentMetricLabels` 已删，T4 后无 providers 符号残留） |
| `lib/src/app/storage/zeta_store_providers.dart:4` | **本 WP 不动**（`builtInAgentProviderDefinitionCatalog` 与 Claude store provider 留到 WP-C T4） |
| `test/src/app/plugins/zeta_plugin_catalog_test.dart` 等引用契约类型的测试 | import 换 api 包（符号不变） |
| 根 `pubspec.yaml` dependencies | 加 `zeta_agent_provider_api: ^0.1.0`（已在 T1 完成） |

收尾反查（应零命中）：`Grep` 全仓 `package:zeta_agent_providers/src/agent_provider_definition|package:zeta_agent_providers/src/agent_provider_plugin_contribution|AgentMetricLabels`。

### T6 · 测试与收尾

1. api 包新建 `test/agent_provider_definition_catalog_test.dart`，用例：
   - `metricLabelFor` 命中内置 id 返回声明常量（构造含两个 definition 的小 catalog 即可，不依赖真实插件）；
   - 未知 id / 空串回落 `ZetaMetricLabel.hashed` 且不抛；
   - 既有 catalog 行为回归如已在别处覆盖则不重复（先查根树 `agent_provider_static_capabilities_test.dart` 与 `zeta_plugin_catalog_test.dart` 的覆盖面）。
2. `bash tool/test_packages.sh` → `bash tool/test_full.sh` 全绿。
3. `dart format .` → `flutter analyze`。

## 5. DoD

- [ ] api 包建立，依赖只有 core/kernel/foundation（`flutter analyze` + pubspec 目检）
- [ ] 契约两文件物理位于 api 包；providers barrel 无相关 export；全仓无 `src/agent_provider_definition` 裸路径 import
- [ ] `AgentMetricLabels` 全仓零引用（含测试与注释，除历史文档外）
- [ ] 三个 definition 的 `metricLabel` 值与旧常量逐字一致（codex/grok/claude_code）
- [ ] `AgentProviderStaticCapabilities` 仍在 providers 包原位、值未动
- [ ] `bash tool/test_full.sh` 全绿；测试断言零修改（除 import 与 T4-3 的函数名替换）

## 6. 风险

| 风险 | 缓解 |
|---|---|
| definition 加 required 字段漏改构造点 | 编译期必炸；构造点 = 三个插件入口 + 测试 fixture，analyze 即暴露 |
| 切换 import 漏掉裸 `src/` 路径引用 | T5 收尾反查三条 pattern |
| metricLabel 语义漂移（指标基数/标签变化） | §T2-2 的等价论证 + T6 单测固化两分支；指标标签值逐字比对 |
| `app.dart` 读取 catalog 的时机早于激活 | 激活是同步的且发生在组合根；该分支上方注释已保证顺序，PR 里截图/引用该注释说明 |

## 7. 开发记录

| 日期 | 内容 |
|---|---|
| 2026-09-04 | 文档加深到伪代码级：补全逐字现状（metric_labels 全文、registry 签名、四个注入点表）、pubspec 逐字模板、workspace 字典序插入位置、metricLabelFor 语义等价论证、T5 逐文件切换表。 |
| 2026-09-04 | 复审轮：§3 补 WP-D 扩展预留说明（management/usage 两个子库将在 WP-D T0 加入本包），防止两文件结构被当成定案。 |
