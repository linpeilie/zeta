# Phase 3 第 2 批开工文档：Provider 配置、管理与模型目录

> ⚠️ **历史迁移证据（Phase 4 已完成）。**
> 本文记录的是当时的迁移过程与决策，**不描述当前架构**——其中提到的过渡层、
> 燃尽清单与中间态符号多数已在 Phase 4 删除。
> 当前架构以 [`AGENTS.md`](../../AGENTS.md) 与 [`overview.md`](overview.md) 为准；
> Phase 4 的删除边界见 [`phase4_transition_cleanup.md`](phase4_transition_cleanup.md)。

> 对应 [Phase 3 开工文档 §4](phase3_slice_expansion.md) 与 §9 模板。
> 本文件是第 2 批的字段级执行契约；框架文档只保留批次边界与顺序。
>
> 开工确认：2026-08-23。第 1 批仍在生产观察，第 2 批先完成 flag 默认 false 的
> “挂 flag / 对照验证”。同日经再次显式确认，接受两批观察窗口重叠的风险，生产入口
> 已翻至新路径；第 2 批按中高风险取至少 7 天观察期，最早于 2026-08-30 关批。

## 1. 范围与不迁清单

本批分三个小步，顺序固定：

1. **2a Provider settings**：以纯 Dart MVI store 替换
   `AgentProviderSettingsController` 的状态 owner；
   `AgentProviderSettingsPort` 的业务方法保持兼容，Riverpod 只做只读镜像；
2. **2b 模型目录投影**：保留 `AgentModelCatalogRepository` 的缓存与并发语义，
   只新增 Riverpod selector，不创建第二套目录缓存；
3. **2c Agent management**：把 `AgentManagementController` 拆成页面 scope 的
   state/reducer/effect runner；配置编辑器未提交草稿继续留在 presentation。

明确不迁：

- 不改 Codex / Grok / Claude Code 协议、transport、bundle、capability 定义；
- 不改 `AgentProviderRuntimeRegistry`、Binding 或 session runtime 生命周期；
- 不改 `providers.json` v2、V1→V2 权限迁移或模型目录缓存 schema；
- 不重写 `AgentModelCatalogRepository` 的 TTL、single-flight、generation 与
  stale-while-revalidate；
- 不改三套 `AgentCliManagementRepository` 的检测、配置冲突、备份、临时文件替换
  和日志脱敏规则；
- 不把 TOML / JSON 编辑器草稿、hover、popover、焦点或 composing 状态放进切片；
- 不做 Agent 管理页视觉重设计，不启动第 3 批，不触碰 G1 共享事件管线。

## 2. 字段与事实 owner 映射

### 2.1 Provider settings：18 个映射项

当前 `AgentProviderConfig` 有 **14 个存储字段**；Phase 3 框架文档所称“18 个字段”
按当前代码应理解为这 14 项，加 `AgentProviderSettings` 的 2 个外层项和 2 个只读
派生项。迁移不新增业务事实。

| # | 现状字段 / 投影 | 新位置 | 唯一事实 owner | 语义 |
| ---: | --- | --- | --- | --- |
| 1 | `AgentProviderConfig.id` | `state.settings.providers[].id` | Provider settings store | 稳定 Provider ID |
| 2 | `displayName` | 同名 | Provider settings store | Provider 返回/内置展示名，保持原文 |
| 3 | `kind` | 同名 | Provider settings store | 组合层静态能力查找键；UI 不按它分支 |
| 4 | `command` | 同名 | Provider settings store | CLI 启动命令 |
| 5 | `arguments` | 同名不可变列表 | Provider settings store | CLI 基础参数 |
| 6 | `environment` | 同名不可变 map | Provider settings store | 仅内存/配置文件；值不进日志与指纹 |
| 7 | `defaultModel` | 同名 | Provider settings store | CLI 默认模型覆盖 |
| 8 | `selectedModel` | 同名 | Provider settings store | Composer 已确认选择 |
| 9 | `selectedReasoningEffort` | 同名 | Provider settings store | 已确认推理档位 |
| 10 | `selectedServiceTier` | 同名 | Provider settings store | 已确认服务档位 ID |
| 11 | `modelPreferences` | 同名不可变 map | Provider settings store | 按模型的最近有效组合 |
| 12 | `selectedPermissionOptionId` | 同名 | Provider settings store | V2 唯一权限偏好真源 |
| 13 | `enabled` | 同名 | Provider settings store | 是否允许新建可写会话 |
| 14 | `extra` | 同名不可变 map | Provider settings store | Zeta 白名单扩展；不解释 raw payload |
| 15 | `AgentProviderSettings.providers` | `state.settings.providers` | Provider settings store | 规范化配置目录 |
| 16 | `activeProviderId` | `state.settings.activeProviderId` | Provider settings store | 新 thread 的默认 Provider |
| 17 | `resolvedPermissionOptionId` | selector | `selectedPermissionOptionId` 派生 | 去空白；不形成第二 owner |
| 18 | `activeProvider` | selector | `providers + activeProviderId` 派生 | 缺项保守回落内置 Codex，保持现状 |

其余端口投影全部只读派生：`activeProviderName`、`activeProviderConfig`、
`enabledProviders`、`isProviderEnabled`、`providerConfigById` 与
`capabilitiesForProviderId`。Riverpod Provider 不复制这些事实。

### 2.2 模型目录

| 现状 | 迁移后 | owner |
| --- | --- | --- |
| `AgentModelCatalogRepository` snapshots / refreshes / generations | 原类原样保留 | app session 级 repository |
| `AgentModelCatalogLoadResult` | 脱敏的 `AgentModelCatalogProjectionState` | repository 结果的 autoDispose 只读投影 |
| Composer `AgentModelConfigUiState` | 原 selection controller，直到第 5 批并入 conversation composer | conversation model selection owner |
| 管理页连接测试返回的模型列表 | management state 的诊断快照 | management page store |

缓存四元组：

- `sourceOfTruth`：Provider bundle 的可选 `modelCatalog` port；
- `key`：`providerId + includeHidden + configFingerprint + providerGeneration`；
- `invalidation`：影响目录的 Provider 配置变化、环境值变化、显式 force refresh，
  或 Provider generation 推进；
- `budget`：fresh 1 小时、max-stale 7 天，每个 Provider/可见性槽只留最近一次
  last-known-good；single-flight 不形成长期缓存。

Riverpod family 自身只用 `providerId + includeHidden + configFingerprint` 作为安全
查询键，不把 `AgentProviderConfig`、环境变量值或原始异常放进 family 参数/state。
它同时监听 Provider settings 快照，因此仅环境变量**值**变化（安全指纹刻意不包含
值）也会重新查询；缓存是否可接受仍由 repository 的私有 provider/slot generation
裁决，Riverpod 不另造缓存 generation。

### 2.3 Agent management 页面状态

| 现状 controller 字段 / getter | 新 state / selector | owner / 备注 |
| --- | --- | --- |
| `_agents` + `agents` | `agentsById + orderedAgentIds` | management page store；规范化集合 |
| `_selectedAgentId` | `selectedAgentId` | management page store |
| `agent` | selector | 由 selected id 派生 |
| `_detectionProgress` | `detectionProgress` | management page store |
| `_configuration` | `confirmedConfiguration` | management page store；不落 Zeta 数据文件 |
| 编辑器未保存正文 | presentation draft | Widget/page scope，不进 store |
| `_logs` | `logs` | management page store；仅 data 层脱敏结果 |
| `_initialized` | `initialized` | management page store |
| `_detecting` | pending operation selector | management page store |
| `_testing` | pending operation selector | management page store |
| `_loadingConfiguration` | pending operation selector | management page store |
| `_savingConfiguration` | pending operation selector | management page store |
| `_loadingLogs` | pending operation selector | management page store |
| `_updatingAccountDataEnrichment` | pending operation selector | management page store |
| `_operationError` | typed failure + 文本目录投影 | 不保存 Provider 原始异常 |
| `availableThreadProviders` | selector | Provider settings slice + 已注册 management repository ID 交集 |
| `claudeCodeAccountDataEnrichmentEnabled` | typed management option selector | 由选中配置的白名单 extra 派生；presentation 不按 Provider 名称猜 |
| live runtime state | ingress snapshot | runtime registry/shell 仍是 owner；management 只投影 |

## 3. Intent、Effect 与结果意图

### 3.1 Provider settings

| Intent | Effect | Result intent |
| --- | --- | --- |
| `ProviderSettingsLoadRequested` | `ProviderSettingsLoadEffect` | `ProviderSettingsLoaded` / `ProviderSettingsLoadFailed` |
| `ProviderConfigUpdateRequested` | `ProviderSettingsPersistEffect` + 按需目录/runtime 失效 | `ProviderSettingsPersisted` / `ProviderSettingsPersistFailed` |
| `ProviderEnabledToggled` | 同上；禁用时 runtime 全 scope 失效 | 同上 |
| `ActiveProviderSelected` | `ProviderSettingsPersistEffect` | 同上 |
| `ProviderModelSelectionPersistRequested` | `ProviderSettingsPersistEffect` | 同上 |
| `ProviderPermissionOptionPersistRequested` | `ProviderSettingsPersistEffect` | 同上 |

现有 port 的 `Future` 只在对应 result intent 回流后完成；失败仍向调用方抛出原异常，
state 只保留稳定失败分类，不保存原始错误文本。配置写入由 runner 单写者串行，
模型目录与 runtime 失效保持 `Future.wait` 并行语义。

### 3.2 模型目录投影

`ModelCatalogRefreshRequested → ModelCatalogRefreshEffect →
ModelCatalogLoaded / ModelCatalogRefreshFailed`。已有 stale 快照时失败结果保留旧列表并
登记中立 refresh failure；无缓存时才显示首次加载错误。仓储内部 generation 仍是目录
结果是否可接受的唯一依据。

2b 落地形态是这个状态机的 Riverpod adapter：初次订阅与显式 `refresh()` 分别对应
普通读取/force refresh，repository 的 `onCacheHit` 先发布 last-known-good，完成后再
发布最终投影。投影只保留 `sourceUnavailable / invalidQuery / unsupported / load /
refresh` 五种稳定分类，不保存 `refreshError` 或抛出的原始异常。family autoDispose
只释放 UI 投影，不释放 repository、global runtime 或 registry。

### 3.3 Agent management

- Intent：`ManagementInitialized`、`AgentSelected`、`DetectionRequested`、
  `ProviderEnabledToggled`、`AccountDataEnrichmentToggled`、
  `ConnectionTestRequested`、`ConfigurationLoadRequested`、
  `ConfigurationSaveRequested`、`LogsLoadRequested`、`RuntimeSnapshotChanged`；
- Effect：检测、Provider 配置更新、连接测试、配置读/校验/保存、日志发现/读取；
- Result intent：对应的 `...Succeeded` / `...Failed`，检测进度使用
  `AgentDetectionProgressReported` typed result intent；
- 配置冲突仍以 `AgentConfigurationConflictException` 交给页面现有确认流程，不把
  overwrite 决策藏进 reducer。

## 4. 操作身份与迟到结果

| scope | identity | 接受条件 |
| --- | --- | --- |
| Provider settings load | `provider-settings/load` `OperationId` | 与当前 load id 相同且 store 未关闭 |
| Provider settings persist | `provider-settings/persist` `OperationId` | 与全局单写者当前 id 相同；旧回执只结算调用 Future，不覆盖新 state |
| Model catalog | repository 既有 provider/slot generation + fingerprint | 四项全部匹配；不在 Riverpod 层另造 generation |
| 全量检测 | `agent-management/detect` `OperationId` | id 相同；进度还须匹配检测中的 agent id |
| 选中 Agent 操作 | `<operation>/<agentId>` `OperationId` | id 与 agentId 都匹配；切换详情页后旧结果可更新对应实体，但不得覆盖新选中页临时状态 |
| 配置保存 | `configuration-save/<agentId>` `OperationId` + document signature | id、agentId、外部修改签名均匹配 |

dispose 后所有 result intent 丢弃；未完成的兼容 port Future 以关闭错误结算，不能永久悬挂。

## 5. capability 与入口门禁（G4）

| 入口 / 操作 | 唯一判断 | 缺失行为 |
| --- | --- | --- |
| 新建/恢复/列表/改名/归档/删除/fork/compact | `AgentProviderCapabilities` + bundle 对应可选 port | UI 不显示；误调用抛 `UnsupportedError` |
| Composer 模型选择 | `supportsModelSelection` + `bundle.modelCatalog` | 隐藏模型入口；不得伪造空成功 |
| reasoning / service tier | `supportsReasoningOptions` / `supportsServiceTierSelection` + 模型 typed 选项 | 隐藏对应控件 |
| mode / skill / permission / question / Plan | 对应 capability + 可选 port | 各语义独立，禁止 no-op |
| CLI 检测、配置、日志、连接测试 | 已注册的 `AgentCliManagementRepository` typed 支持 | 管理入口不出现或明确 unsupported |
| Claude 账号数据增强 | management typed option capability | presentation 不按 id/displayName 分支 |

静态 capability 仍由 data/组合层注入的 `AgentProviderStaticCapabilitiesFor` 提供；
slice、UI、共享 port 不新增 kind/name switch。

## 6. 消费方切换顺序

```text
MainApp (flag + composition owner)
  ├─ ProviderSettingsSliceStore ── AgentProviderSettingsPort
  │    ├─ IdeShellController / usage directory
  │    ├─ AgentThreadWorkspaceController / conversation ViewModel
  │    ├─ ProjectThreadsController
  │    └─ AgentManagement page store
  ├─ Riverpod mirror
  │    ├─ settings/management selectors
  │    └─ keyed model catalog async projection
  └─ EffectRunner
       ├─ AgentProviderConfigStore
       ├─ AgentModelCatalogRepository
       └─ AgentProviderRuntimeRegistry
```

切换顺序：

1. app 根创建 Provider settings store/runner，flag 默认 false；
2. store 实现现有 port，先让 shell 与 application 消费方在 flag true 下整体切换，
   flag false 继续旧 controller；
3. 加 Riverpod 镜像与只读 selectors，presentation 不持有第二份 settings；
4. 新 presentation 消费方改读模型目录 selector，仓储保持原样；现有 Composer
   selection owner 按 §2.2 留到第 5 批，不在 2b 双写模型选择状态；
5. management controller 迁成 page store，配置草稿留 Widget；
6. 双路径验证后生产翻旗；观察通过才执行删除清单。

## 7. 生命周期与 dispose

| 对象 | 创建者 | 生命周期 | dispose / close |
| --- | --- | --- | --- |
| Provider settings store/runner | `MainApp` app 组合层 | app session | `MainApp.dispose` 关闭 store；不关闭注入的 repository/registry |
| Riverpod mirror | 根 `ProviderScope` | app session / query subscription | Riverpod 取消 store subscription 与目录投影；不拥有 store/repository |
| `AgentModelCatalogRepository` | `MainApp` | app session | 无独立进程；runtime registry 关闭前停止新请求 |
| management page store/runner | `IdeHome` management page composition | 页面保活寿命 | 页面销毁时取消 ingress/关闭 store；repository 不归它所有 |
| old controllers | flag false 路径 owner | 观察期 | 仅创建者 dispose；flag true 时不得同时创建/双写 |
| runtime registry | `MainApp` | app session/runtime generation | 仍按 runtime registry → plugin catalog 反序关闭 |

## 8. §15 十问答卷

1. **唯一 owner**：Provider 配置是 Provider settings store；模型目录是既有
   repository；管理页运行态是 management page store；runtime 仍归 registry。
2. **Intent/State/Effect/Result**：见 §2–3，完成只经 result intent 回写。
3. **边界类型**：state 只含 typed domain/application 类型；raw Provider、文件 API、
   Flutter 与 Riverpod 不进入 reducer/store。
4. **创建/释放**：见 §7；store 不创建 Binding/runtime/plugin。
5. **迟到结果**：见 §4；settings 用 `OperationId`，目录复用既有 generation。
6. **正文/频率**：Provider 配置低频；环境值不进日志/指标；配置编辑草稿留页面；
   不复制 conversation 正文，不增加流式 publish。
7. **缓存**：仅模型目录，四元组见 §2.2；不新增第二缓存。
8. **持久化**：`providers.json` v2 与模型缓存 schema 均不变；无新白名单字段。
9. **回滚**：`providerManagementSliceEnabled` 全局 bool，flag 二选一、无双写；
   关批删除 flag 后回滚依赖 revert 关批提交。
10. **证据**：纯 reducer/store/runner 单测、config/runtime/cache 竞态测试、
    MainApp/IdeHome flag 双路径 Widget 测试、management 交互测试、架构守卫与
    `test_affected`。

## 9. 验收测试

- Provider settings 14+4 映射与 selector 等价；
- load 幂等、写入单写者、迟到成功/失败不覆盖新 state、dispose 不悬挂 Future；
- 环境值/安全指纹变化使模型目录失效，普通选择更新不误失效；
- `restartProvider` 与禁用只回收目标 Provider，global-only 失效不终止 session；
- 禁用 active Provider 后选择首个 enabled fallback；未知/禁用 active 选择仍抛错；
- 权限只持久化规范化 V2 optionId；模型选择整体保存与失败传播等价；
- flag false/true 下 shell、thread、usage directory 与 management 渲染/行为等价；
- 模型目录 fresh/stale/force/single-flight/generation 既有测试保持全绿；
- 模型目录 safe key、cache-first、force refresh、stale 保留、typed failure、flag
  双路径根注入均有 Riverpod/runner 测试；
- management 检测、连接测试、启停、配置冲突、日志与账号增强 Widget 测试双路径；
- 关批时 `knownApplicationFlutterImports` −3，并删除对应燃尽条目；
- 本批无流式/resize 热路径变化，无需新增 Phase 0 帧预算；若实际改到热路径则补测。

## 10. 关批删除清单

- `agent_provider_settings_controller.dart`；
- `AgentProviderSettingsPort implements Listenable` 的 Flutter 继承，改为纯 Dart
  `subscribe`/取消订阅契约（业务方法保持）；
- `agent_management_controller.dart`；
- shell/management/workspace/project threads/conversation 中旧 controller
  listener 与具体类型引用；
- management presentation 对 controller 的参数与 `ListenableBuilder` 接缝；
- `providerManagementSliceEnabled` flag 与旧路径组合；
- `feature_layering_guard_test` 的三条 application Flutter import 基线。

`AgentModelCatalogRepository`、三个 management data repository、配置 codec/store、
模型缓存 store 都不删除。

## 11. 回滚与四步节奏

- 2026-08-24 关批后不再保留运行时 flag 或旧 controller 路径；
- 回滚只允许 revert 关批提交，从 git 历史恢复整个旧路径；
- 任何回滚不得恢复静默 capability 成功或改写 v2 配置。

四步状态：

1. **挂 flag**：✅ 2a Provider settings store/runner、2b keyed 模型目录投影与
   2c management page store/runner/Riverpod 接缝均已落地（2026-08-23）；旧/new
   owner 由同一 app flag 二选一；
2. **对照验证**：✅ 已覆盖 management 检测、连接测试、配置签名与冲突、日志、
   账号增强、迟到结果、dispose 结算和 MainApp/IdeHome flag 双路径；受影响测试与
   完整重构门禁均通过；
3. **翻 flag**：✅ 2026-08-23 生产启用；2026-08-24 用户明确接受不等待原定日期，
   缩短本批独立观察余量；
4. **关批**：✅ 2026-08-24 已执行 §10：settings/management 旧 controller、
   Flutter Listenable port、flag 与 false-path 删除，Provider settings/management 固定为
   slice 单一路径，对应 application Flutter 燃尽项清零。
