# Provider 插件化拆包 · 总索引与开发记录

> 任务日期：2026-09-04
> 状态：待开发
> 前置：会话 UI 渲染改造（2026-09-03 计划，WP-1/2/3/4/6/7 已完成，WP-5 显式跳过）已收尾，本计划与其无代码依赖。

## 1. 目标（用户验收口径）

1. **项目只对接接口层**：根 app 只依赖契约包 `zeta_agent_provider_api`，厂商协议、CLI 细节、会话文件格式全部下沉到各 Provider 插件包。
2. **新增 Provider = 只增加一个插件包**：不动 `zeta_agent_core` / `provider_api` / `provider_sdk` / 其他插件 / app 业务代码。允许的唯一存量改动是编译期 manifest 的一行 import + 三行登记（definitions / settings / factories，见决策 D1 的诚实边界）。
3. **每个插件包可以单独测试**：`flutter test packages/zeta_agent_provider_<x>` 独立绿；中立契约由可复用契约测试套件固化，各插件一行接入。

## 2. 现状盘点（2026-09-04 事实）

### 2.1 已有资产（不重新发明）

| 资产 | 位置 | 说明 |
|---|---|---|
| 通用可信插件微内核 | `packages/zeta_plugin_kernel` | descriptor / apiVersion / 拓扑激活 / 贡献快照 / fail-closed / 反序关闭，零 Agent 语义 |
| Provider 贡献类型 | `zeta_agent_providers/lib/src/agent_provider_plugin_contribution.dart` | `AgentProviderPluginContribution` = definition + bundleFactory |
| 静态元数据目录 | 同包 `agent_provider_definition.dart` | `AgentProviderDefinitionCatalog`：id/type 唯一、默认项唯一、宽容 decode、`ensureDefaultProviders` |
| 聚合 bundle 工厂 | 同包 | `AgentProviderPluginBundleFactory`：按开放 `AgentProviderTypeId`（字符串，无枚举）路由，未知 type 抛 `UnsupportedError` |
| 唯一注册点 | `lib/src/app/plugins/zeta_plugin_catalog.dart` | 编译期目录，不扫描、不下载、不反射 |
| 每 Provider 插件入口类 | `codex_plugin.dart` / `grok_plugin.dart` / `claude_code_plugin.dart` | 同步激活，`essential: true` |

### 2.2 本计划要消除的耦合点

| # | 耦合点 | 位置 | 性质 |
|---|---|---|---|
| C1 | 三个 Provider 实现与共享机制混居单包 | `packages/zeta_agent_providers` | 物理 |
| C2 | 编译期清单硬编码在 providers 包 | `built_in_agent_provider_plugins.dart` | 新增 Provider 要改存量文件 |
| C3 | 指标标签按 providerId 硬编码 switch | `src/agent_metric_labels.dart` | 厂商身份白名单 |
| C4 | management repository 在 app 层按三厂商拼装 | `lib/src/app/composition/ide_workbench_composition.dart:47-61` | 旁路插件机制 |
| C5 | usage source registry 硬编码三厂商 switch | `lib/src/features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart:26-43` | 旁路插件机制 |
| C6 | `AgentDefinition.codex/grok/claudeCode` 静态目录 | `agent_management/domain/agent_management_models.dart:73-137` | UI 元数据硬编码 |
| C7 | `claudeCodeAccountDataEnrichmentKey` 被 app 组合层直接读 | `agent_management_slice_composition.dart:95`、`agent_management_slice_runner.dart:217-219` | Claude 私有 key 上漏 |
| C8 | Provider 测试住在根 test 树 | `test/src/features/agent/data/{mappers,datasources}/...` | 插件包不可独立测试 |
| C9 | 启动前静态元数据逃生口 | `zeta_store_providers.dart:77` 用 `builtInAgentProviderDefinitionCatalog` | 拆包后需同源替代 |
| C10 | presentation 按 providerId 分支 | `agent_management_page.dart:451`（setup guide）/`:664`（测试连接确认弹窗） | UI 厂商分支 |

> **编号口径**：WP-D 文档内部使用局部编号 C1–C6，与本表对照为——WP-D C1=本表 C4、C2=C5、C3/C4=C7、C5=C6、C6=C10。「C6 登记例外」「消灭 C1–C5」等表述在 WP-D/WP-E 内一律指 **WP-D 局部编号**。

## 3. 目标态

```
packages/
├── zeta_plugin_kernel                 # 不动：通用微内核
├── zeta_agent_core                    # 不动：中立内核（端口/管线/reducer）
├── zeta_agent_provider_api            # 新增：宿主侧契约（definition/catalog/contribution/聚合工厂/可选能力端口）
├── zeta_agent_provider_sdk            # 新增：插件作者侧共享机制（ACP codec、JSON-RPC transport、payload 工具、CLI locator、契约测试套件）
├── zeta_agent_provider_codex          # 新增：Codex 插件（实现 + 测试）
├── zeta_agent_provider_grok           # 新增：Grok 插件（实现 + 测试）
└── zeta_agent_provider_claude_code    # 新增：Claude Code 插件（实现 + 测试）
```

依赖方向（单向，WP-E 加守卫断言）：

```
provider_api  → {agent_core, plugin_kernel, foundation}
provider_sdk  → {provider_api, agent_core, plugin_kernel(testing), foundation, acp_sdk}
provider_<x>  → {provider_api, provider_sdk(按需), agent_core, plugin_kernel, foundation}
provider_<x> 之间互不可见；插件包纯 Dart（禁 Riverpod / package:flutter/，允许 dart:io）——
现状仅 3 处 foundation 引用，经三处一行等价替换消除（kReleaseMode→dart.vm.product，
@visibleForTesting→package:meta，语义逐字等价，见 WP-B §1.1 / WP-C §1）
根 app        → provider_api；仅 lib/src/app/plugins/agent_provider_manifest.dart 一个文件可 import provider_<x>
              （含 test/——根测试的厂商 fixture 统一经 manifest，见 WP-C §5.1）
api 与 core 同为中立契约层：application / domain / presentation import api 合法（WP-E 同步 G6 文本）
```

`packages/zeta_agent_providers` 在 WP-C 结束时删除。

## 4. 决策记录

### D1 · 「不改现有代码」的诚实边界

Dart 没有类加载器，包不被 import 就不进产物，物理零改动不可能。目标收敛为**唯一一处改动**：app 组合层新建 `lib/src/app/plugins/agent_provider_manifest.dart`，它是全仓库唯一 import 插件包的文件，持有四类成员——静态 definition 列表、激活前只读 catalog、插件工厂函数、插件专属宿主 store 的 Riverpod provider（如 Claude 的三个）；外加派生的启动 settings 快照（兼根测试 fixture 源，WP-C §5.1）；`ZetaPluginCatalog.builtIn` 随之改为厂商中立签名（只收工厂列表）。新增 Provider = 一行 import + 三行登记（definitions / settings / factories 各一，无宿主注入的 Provider 不需要第四类成员）（+ pubspec 一条依赖）。**不做**目录扫描/反射/自注册——`ZetaPluginCatalog` 的既定决策（编译期目录是评审与编译期检查的一部分）不变。

### D2 · 契约独立成包，不进 core、不进 kernel

kernel 注释明说不 import 具体贡献语义；core 当前不依赖 kernel 且职责是领域模型+事件管线，definition catalog 是装配关注点。独立 api 包还让 app 的 codec/store 连 ACP/JSON-RPC 机制都摸不到，机制泄漏面小于现状。

### D3 · 厂商指标标签收进 definition

`AgentMetricLabels.forProviderId` 的 switch 删除，`AgentProviderDefinition` 新增 `required ZetaMetricLabel metricLabel`（编译期常量，`ZetaMetricLabel.constant(...)` 可 const 构造）；catalog 提供 `metricLabelFor(String providerId)`：命中 definition 用声明值，未命中回落 `ZetaMetricLabel.hashed`（自定义配置行为与现状一致）。`AgentProviderRuntimeRegistry.providerMetricLabel` 的绑定从硬编码 switch 改为 catalog 查询。

### D4 · usage/management 旁路全部贡献化（用户已拍板：做，一步到位）

- **management**：端口与模型闭包（`AgentCliManagementRepository` / `AgentCliManagementDescriptor` / `AgentCliManagementCapabilities` / `ManagedAgent` 及其枚举与异常）从 `agent_management/domain` 下移 `provider_api`；repository 实现迁进对应插件包；插件以新贡献类型 `AgentManagementContribution`（definition + 工厂）暴露。host 注入收敛为 `AgentManagementHostServices`：`textCatalog`（见 D8）+ `runtimeRegistry`（core 类型，直接用，**不需要**窄端口）+ `AgentManagementModelCatalogPort` 窄端口（实测 repository 只调 `load` 一个方法，见 codex repo:641-647）。
- **usage**：`AgentTokenUsageSource` 实现（scanner/codec/home 解析）迁进插件包，经 `AgentUsageContribution`（**键为 providerType**——现状 registry 按 `config.kind` switch，实测 `built_in_agent_token_usage_source_registry.dart:26`）暴露工厂；Zeta 持久化留在 app——插件只拿到窄 `AgentUsagePartitionPort`（read/write 不透明分区，签名与现状 `UsageStatisticsPartitionStore` 一致），v4 白名单内容约束由 codec 测试固化。插件绝不获得 `StorageService`（G7）。
- **元数据**：`AgentDefinition` 下沉 api 并**即管理元数据**——删除 `codex/grok/claudeCode/all/byId` 静态成员（字面量逐字迁入各自插件包的 contribution 声明），新增 `accountDataEnrichmentExtraKey` 字段承载 C7（enrichment 能力门本已 G4 合规，只有 key 字符串上漏）。`ManagedAgent` 删三个厂商 factory，保留 `forDefinition`。
- **C7**：key 字符串值 `'claudeCode.accountDataEnrichment'` 逐字保留（D7），由 Claude 插件在自己的 definition 里声明；composition 读取闭包与 runner 写入路径改为经 definition 查 key，app 不再认识这个 key。C10 两处分支分流：`:664`（测试连接确认弹窗）改经 `AgentCliManagementCapabilities.requiresConnectionTestConfirmation` 新增能力位消灭；`:451`（setup guide 卡片）保留为登记例外——形态为文件私有 `_setupGuideAgentId = 'claude_code'` 字面量（T0 删除静态表后原符号引用无法编译，必须同轮换形态）；不能力化的理由（整卡 Claude 品牌内容，能力位会误导未来 Provider）见 WP-D §3.6。

### D8 · 文案目录下沉走 `AgentUiTextCatalog` 先例

实测三个 management repository 对文案目录有 50+ 调用点，且两个目录本就是对标 core `AgentUiTextCatalog` 的 `abstract interface class` + app ARB 实现 + domain fallback 结构。因此**不做**失败原因码间接层：

- `AgentManagementTextCatalog` 接口 + Fallback **整体**迁 api（45 个成员零改动，含 `runCodexLogin()` 等约 10 个 vendor 命名遗留——它们是 Zeta 文案槽位不是分支逻辑；规范化成通用成员牵动 ARB key，记录为债不在本计划）。
- usage 侧实测只用 5 个成员，定义窄接口 `AgentUsageSourceTextCatalog`；app 的 `LocalizedUsageStatisticsTextCatalog` 同时 implements 宽窄两接口。
- **行为保持**：usage 组合点现状注入的是 fallback 目录（`usage_statistics_slice_overrides.dart:40-42` 未传 textCatalog），目标态保持 fallback，不顺手「优化」成本地化。

### D5 · 测试随迁 + 契约测试套件复用

每个插件包带自己的 `test/`（根 test 树的 provider 测试按归属迁入）。`provider_sdk` 提供 `lib` 内测试辅助子库（`zeta_agent_provider_sdk_testing.dart`），导出 `runAgentProviderContractTests(...)`：固化 definition/config 身份一致、静态 capability 与 bundle 端口一致、G5 三类 handler 未被覆盖、脱敏 fixture 回放合法等中立契约。共享纯度守卫（G1 grep、raw payload freeze）继续跑在 core/sdk，不依赖任何插件包。

### D6 · 重构纪律

WP-A/B/C 是纯搬移：行为零变化（WP-A 的 metricLabel 是语义等价迁移），**测试断言零修改 + 全量绿**是唯一正确性证据，收尾跑 `bash tool/test_full.sh`（不走 `test_affected.sh`——搬文件会让 import 图失真）。WP-D 触及装配行为，走受影响档 + 全量兜底。

### D7 · 持久化身份红线

Provider 的持久化身份**逐字冻结**，拆包只是物理搬移：

- `AgentProviderTypeId` 的协议域字符串（`'codexAppServer'` 等）写进了 `~/.zeta/config` 的 providers.json 与模型目录缓存指纹——**一个字符都不许改**；
- 内置 providerId（`codex` / `grok` / `claude_code`）、`AgentProviderSettings.currentVersion`、codec 字段名同理；
- Claude 的 `claudeCodeAccountDataEnrichmentKey` 字符串值在 WP-D 收口时逐字保留。

WP-C 把这条写进 DoD，WP-E 用 codec 回归测试固化（既有覆盖不得红，必要时补一条「持久化样本逐字解码」测试）。

## 5. WP 总表

| WP | 文档 | 内容 | 规模 | 依赖 | 状态 |
|---|---|---|---|---|---|
| WP-A | [01-wpa-provider-api.md](01-wpa-provider-api.md) | 契约包：definition/catalog/contribution/聚合工厂上移 + metricLabel 入 definition | 1 人天 | 无 | 未开始 |
| WP-B | [02-wpb-provider-sdk.md](02-wpb-provider-sdk.md) | 共享机制包：13+1 文件逐行 import 反查实证归属 + `cli_process_runner` 入 sdk + 契约测试套件骨架 | 0.5–1 人天 | A | 未开始 |
| WP-C | [03-wpc-provider-split.md](03-wpc-provider-split.md) | 三个 Provider 各自拆包（23/20/30 文件实测清单），manifest 落地（兼根测试 fixture 源），删旧包 | 每个 1–2 人天 | B | 未开始 |
| WP-D | [04-wpd-app-contributions.md](04-wpd-app-contributions.md) | usage/management 贡献化（D4+D8）：模型闭包下沉 api、文案目录下沉、窄端口 ×2、聚合改写，消除 app 侧耦合 C4/C5/C6/C7 与 C10 的一处（另一处登记例外） | 2–3 人天 | C | 未开始 |
| WP-E | [05-wpe-governance.md](05-wpe-governance.md) | 七类守卫测试、门禁文本与文档同步、全量收尾 | 1 人天 | D | 未开始 |

## 6. 新增 Provider 的目标流程（最终验收）

1. 新建 `packages/zeta_agent_provider_<new>`（结构抄任一现有插件包），实现端口 + definition 常量 + 插件入口；本包内 `flutter test` 绿（含契约测试套件一行接入）。
2. 根 `pubspec.yaml` 加一条依赖；`agent_provider_manifest.dart` 加一行 import + 三行登记（definitions / settings / factories）。
3. 完。core / sdk / 其他插件 / app 业务代码零改动；若有遗漏，WP-E 的一致性守卫测试应当拦下。

## 7. 收尾协议提醒

- 每个 WP 收尾按仓库协议：`dart format .` → `flutter analyze` → 测试（WP-A/B/C 全量，WP-D 受影响 + 全量）。
- 本计划动到包结构与 G1/G6 门禁文本，WP-E 必须按 `AGENTS.md` §6 整组同步文档。
- 每个 WP 完成后回写本文档状态列与 §8 开发记录。

## 8. 开发记录

| 日期 | 记录 |
|---|---|
| 2026-09-04 | 初版方案经用户确认（范围：WP-D 一步到位；落档：是）。建立索引与五份 WP 文档。 |
| 2026-09-04 | 复审+细化轮：① 逐行 review 修正 4 处（WP-A barrel 数、D7 持久化红线新增、WP-E 的 CI 覆盖确认、DoD 计数）。② 基于三路并行事实采集（插件结构/pubspec/测试清单、13 个共享文件 import 反查、management/usage 接口与调用点实测）把 WP-A/B/C/D 全部重写到伪代码级。关键设计修正：**D8 新增**（文案目录下沉取代失败原因码映射，依据 50+ 实测调用点与 AgentUiTextCatalog 先例）；`AgentDefinition` 与管理元数据合并并加 `accountDataEnrichmentExtraKey` 字段（enrichment 能力门本已合规，实测只有 key 字符串上漏）；usage 贡献键改 providerType（现状按 config.kind switch）；`runtimeRegistry` 无需窄端口（core 类型）；唯一窄端口是模型目录单方法；WP-C 新增 §5.1「manifest 即根测试 fixture 源」（约 25 个测试文件纯 import 改写）；`stream_json_peer` 实证归 Claude 私有；`AcpSessionConfigMapper` 标注无生产引用。WP-E 守卫扩到七类（新增 D7 红线、贡献完备性、C6 登记例外、test/ 全域隔离、TypeId 字面量禁令）。 |
| 2026-09-04 | 完整勘察报告对账轮（三份逐字报告 vs 已写文档）：① **Flutter 依赖实测**——全 providers 包仅 3 个文件 import foundation（logger 的 kReleaseMode + 两个 adapter 的 @visibleForTesting），定三处一行等价替换（dart.vm.product / package:meta），sdk 与三插件包「纯 Dart」论断由此成立并写入 WP-B/WP-C。② **WP-D 664 分支纠错**——实测是测试连接确认弹窗（非 enrichment 编辑），新增 `requiresConnectionTestConfirmation` 能力位消灭之，C6 登记例外收敛为 `page.dart:451` 一处。③ usage 闭包精确化（query 仅 earliest/forceRefresh；`UsageDateWindow`/`UsageTimeRangePreset` 不下沉；补 `UsageErrorCategory`）；`usage_scan_cache.dart` 三家共用实测，T4 迁 sdk；claude 两处构造差异（无本地 scanner、management 无 runtimeRegistry/modelCatalog）落档。④ **字符串引用守卫点名**（WP-E 守卫 6）：`agent_core_raw_payload_freeze_test`、`agent_provider_catalog_freeze_test`、`agent_provider_bundle_contract_test` 三处以字符串引用将被静默绕过，列入逐条核对清单。⑤ 根测试 definition 字面量 fixture（4 个引用点）+ WP-E parity 断言联动。⑥ 行数/文件数校订（bundles 129 行、static 86 行、测试 59 文件、part 文件随迁）。 |
| 2026-09-04 | 终审轮（全文重读 + 关键点实测复核）：① **编号冲突消解**——§2.2 新增 C10（page 厂商分支）并给出 WP-D 局部编号 C1–C6 的对照表，D4/WP 表改用无歧义表述（此前索引 C6=静态目录与 WP-D C6=page 分支同号不同义）。② **WP-C 白名单漏 runner**——实测 `agent_management_slice_runner.dart:4` import providers barrel，已补行。③ **WP-D C6 内部矛盾修正**——T0 删静态表后 451 的原符号引用编译即失效，例外形态改为 `_setupGuideAgentId` 字面量并同轮落地；WP-E 守卫 5 改双 grep 形态。④ **sdk testing 独立 barrel**——契约套件 import `package:test`，主 barrel 导出会把 test 污染进生产编译面；定为独立 entrypoint + test 列常规依赖，WP-B/WP-C 同步。⑤ manifest 补成员五（类型常量 show 再导出，根测试 fixture 通道）与生产 textCatalog 注入注意。⑥ barrel 升格点名：`agent_provider_timestamp` 由包内私有升为 sdk barrel 导出。⑦ WP-E 守卫 2 补启用前置（白名单清零先行）。⑧ 实测复核：`ZetaMetricLabel` 在 foundation（WP-A 假设成立）；三家 usage source 构造签名恰好 `(config, partitionStore, textCatalog)`（`AgentUsageHostServices` 无缺口）；契约两文件行数 197/119 复核无误。 |
