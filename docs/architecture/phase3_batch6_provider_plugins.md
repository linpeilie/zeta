# Phase 3 第 6 批：显式 Provider 插件与开放 Provider 域

状态：✅ 2026-08-24 已直接切换并关批；无生产 flag、compatibility 或 default-factory
回退路径。Phase 3 阶段级准入结论见 §10。

> 对应 [Phase 3 开工文档 §8](phase3_slice_expansion.md) 与
> [目标架构 §9.3、§14、§15](target_architecture_riverpod_mvi_plugins_packages.md)。
> 本批按 2026-08-24 的明确要求直接进入目标态：不挂 flag、不保留 compatibility
> 双轨，回滚方式是整体 revert 本批提交。

## 1. 范围与不迁清单

本批一次完成两笔同源欠债：

1. Codex、Grok、Claude Code 分别成为显式 compile-time plugin contribution；
2. 清算 Phase 1 §8.1：从 `zeta_agent_core` 移除封闭的 `AgentProviderKind`、内置
   Provider ID/default config/display-name switch，以开放 `AgentProviderTypeId` 和插件
   definition catalog 取代。

范围内还包括配置 codec、静态 capability、legacy permission migration、usage source、
management 和 presentation 对旧枚举的消费改接。持久化 JSON 的 `kind` key 与三种既有
字符串值保持不变。

明确不迁：Provider 协议、wire 参数、CLI 启动参数、capability 内容、TimelineStore、
coalescing、Binding/runtime ownership、审批语义、持久化 schema、UI 视觉与路由。

## 2. 现状依赖图与目标依赖图

现状：

```text
MainApp
  -> DefaultAgentProviderFactory
  -> ZetaPluginCatalog.compatibility
  -> CompatibilityAgentProviderPlugin
  -> 单一 AgentProviderPluginContribution
  -> DefaultAgentProviderFactory.switch(config.kind)
  -> createCodexBundle / createGrokBundle / createClaudeCodeBundle
```

目标：

```text
MainApp
  -> ZetaPluginCatalog.builtIn
  -> CodexAgentProviderPlugin
     GrokAgentProviderPlugin
     ClaudeCodeAgentProviderPlugin
  -> 三个带 definition + 单域 factory 的 contribution
  -> ResolvedAgentProviderPlugins
     -> AgentProviderDefinitionCatalog
     -> AgentProviderPluginBundleFactory(typeId -> factory)
  -> AgentProviderRuntimeRegistry
```

Kernel 仍只负责登记、拓扑激活、typed contribution 汇总与反序关闭；runtime registry
仍是 bundle/runtime/CLI 的唯一 owner。

## 3. 字段与 owner 映射

| 现状 | 目标 | 唯一 owner | 说明 |
| --- | --- | --- | --- |
| `AgentProviderKind` enum | `AgentProviderTypeId(value)` | `zeta_agent_core` 中立值对象 | 开放值，不登记任何厂商常量 |
| 内置 ID/default config | 三个插件的 definition | 对应 Provider 插件 | 既有值与命令参数不变 |
| `normalizeDisplayName` switch | definition catalog | 激活后的插件 definition 集合 | 只规范化内置 definition 的稳定 ID |
| `AgentProviderStaticCapabilities.forKind` switch | definition 的 capability seed | 对应 Provider 插件 | runtime 握手后仍以 runtime 为准 |
| Claude 模型目录指纹 extra key | definition 的安全字段白名单 | Claude 插件 | application 仓储不认识 Provider 私有 key |
| permission migrator kind map | definition 的可选 migrator | 对应 Provider 插件 | 未声明时内容盲、fail-closed |
| `DefaultAgentProviderFactory` switch | type-id → 单域 factory map | resolved plugin catalog | 重复域、缺失域均抛错 |
| `config.id` | 不变 | Provider 配置实例 | 可自定义，不作为插件路由键 |
| JSON `kind` | 不变 | V2 codec | key/schema/value全部不变 |

新增业务事实为 0；新增的 definition 只是把既有分散常量归到其 Provider owner。

## 4. Intent / State / Effect / Result Intent

本批不引入新的 feature MVI 状态：插件激活仍是启动期同步组合，运行时业务状态仍由既有
feature slice 与 runtime registry 持有。

- Intent：既有 `activate()`、`createBundle(config)`、`close()` 调用；
- State：kernel 的 `ZetaPluginState` 与不可变 contribution/definition catalog；
- Effect：插件 handle 激活/关闭；不执行 IO、不创建 CLI；
- Result intent：无。同步激活直接冻结 contribution snapshot；runtime 异步生命周期不变。

## 5. 身份、迟到结果与 fail-closed 规则

- 配置实例身份是 `config.id`；插件路由身份是 `config.kind: AgentProviderTypeId`，二者不得
  混用。
- contribution 的 Provider type 与默认 config ID 都必须唯一；重复构造/resolve 即抛。
- definition 的 ID/type 必须非空、无首尾空白；校验在 catalog 构造期执行，不依赖
  release 中失效的 `assert`，保证注册值与 JSON 归一化值一致。
- 未激活、已 degraded、全局零贡献、任一 active essential 插件不是恰好一个 Provider
  contribution，或运行期未知 type，均拒绝 resolve/create；禁止返回部分目录或回落 Codex。
- 单域 factory 收到其他 type 时立即抛，不创建 runtime。
- activate 或 resolve 任一步失败，catalog 都会回收已经激活的 handle，不留下半激活 owner。
- 激活为同步、无异步 result intent，因此没有新增 `OperationId`；kernel 既有 generation
  与 close/activation race 规则原样保留。

## 6. 生命周期与 dispose

| 对象 | 创建者 | 释放者 | 所有权边界 |
| --- | --- | --- | --- |
| 三个 plugin factory | `ZetaPluginCatalog.builtIn` | registry | 只持有构造依赖 |
| plugin handle | kernel registry | kernel 反序关闭 | 不创建/关闭 runtime |
| resolved definition/factory | app catalog resolve | 随 catalog 丢弃 | 不持有 IO 资源 |
| runtime registry | `MainApp` 或宿主注入 | `MainApp`/宿主 | 唯一 CLI/runtime owner |
| bundle/runtime | runtime registry | runtime registry | 规则不变 |

关闭顺序保持 runtime registry → plugin catalog；插件关闭顺序保持 Claude → Grok → Codex。
启动期 essential/de-duplicate/零贡献校验失败时没有 runtime，catalog 仍立即触发 kernel
反序关闭，避免成功激活的前序插件失去 owner。

## 7. §15 十问答卷

1. 唯一 owner：Provider definition 与单域 bundle factory 归各自插件；聚合关系归 app
   plugin catalog；runtime 仍归 runtime registry。
2. Intent/State/Effect/Result：见 §4；没有新增 feature 状态或异步回流。
3. 边界类型：core 只新增中立开放 type-id；raw/wire、Flutter、Riverpod 均不越界。
4. 生命周期：见 §6；插件 handle 不接管 Binding/runtime。
5. 迟到判定：没有新增异步 operation；沿用 kernel generation 与 runtime scope。
6. 正文/发布频率：不复制 prompt/tool/raw，不触碰 streaming publish/rebuild。
7. 缓存：无新缓存。definition catalog 是激活时冻结的进程内只读快照。
8. 持久化：白名单与 schema version 不变；`kind` key/旧字符串原样读写。
9. 回滚/双写：不设 flag、不双写；旧 compatibility 与 default factory 当批删除；整体 revert。
10. 证据：三插件/聚合/kernel lifecycle 契约、custom config id 路由、V1/V2 codec、静态
    capability、native bundle、架构守卫、完整 analyze/full test。

## 8. 验收测试清单

- 三个 descriptor 稳定、essential、同步激活，各自产出一个单域 contribution；
- 三插件同时激活，顺序稳定，关闭反序；单 essential 失败进入 degraded 且 resolve 拒绝；
- essential/resolve 失败后已激活 handle 仍会关闭；essential 零/多 Provider 贡献与非
  canonical ID/type 注册均被拒绝；
- custom config id 按 type 路由；重复 type、未知 type、错误单域 factory 全部 fail-closed；
- 三类 native bundle 端口矩阵、Claude 注入、runtime ownership 不变；
- V1/V2 Provider JSON 旧 fixture 正常解码，重新编码仍为 V2 且 `kind` 值不变；
- core 不再出现内置 ID、默认 CLI、厂商显示名或 `AgentProviderKind`；
- compatibility/default factory/旧 catalog 入口全仓为零；
- `dart format .`、`flutter analyze`、`bash tool/test_affected.sh`、`bash tool/test_full.sh`。

2026-08-24 实际验收结果：`dart format .` 零改动，`flutter analyze` 零问题；
第 6 批提交时，`tool/test_affected.sh` 与 `tool/test_full.sh` 均通过根测试 2383 条及全部内部 Package
analyze/test。独立复审没有剩余 P1/P2。

门禁过程还捕获并修复了一个开放 core 默认值带来的启动边界：模型目录查询源先于 Provider
settings 装载时，投影现在返回不可用而不是读取空目录的 active config；回归测试同时固定
“配置到达后正常查询”和“配置缺席时安全等待”两条路径。

## 9. 删除清单与回滚

删除：

- `compatibility_agent_provider_plugin.dart`；
- `default_agent_provider_factory.dart`；
- `ZetaPluginCatalog.compatibility`；
- core 内置 Provider enum/ID/default config/display-name switch；
- freeze test 的旧封闭目录断言及相关 barrel 欠债注释。

回滚只允许整体 revert 本批提交，不恢复生产双轨或运行时 fallback。

## 10. Phase 3 / Phase 4 关系

第 6 批完成后又按明确要求修复原审计阻塞 1、3、4。2026-08-24 最新复核结论：
**六批代码均已关批，但 Phase 3 阶段证据尚未全部完成，当前仍不能进入 Phase 4**。

| 阶段门禁 | 状态 | 当前证据 / 下一动作 |
| --- | --- | --- |
| 第 6 批 + Phase 1 §8.1 | ✅ | 三插件、开放 type、零 compatibility/default factory/core 内置目录 |
| 第 1 批关批 | ✅ | 用户明确接受不等待原定日期；两个 settings controller、ingress、flag 与 false-path 已删除，固定为 slice 单一路径 |
| 第 2 批关批 | ✅ | 用户明确接受不等待原定日期；settings/management 旧 controller、Flutter Listenable port、flag 与 false-path 已删除 |
| Phase 2 长时间真实使用证据 | ❌ | [Phase 3 §0](phase3_slice_expansion.md) 要求从 2026-08-23 起连续 14 天，最早约 2026-09-06；期间若发生需修复的 slice bug 要按规则重新计时 |
| application Flutter 燃尽 | ✅ | `knownApplicationFlutterImports` 已从 5 清零，application 层 Flutter import 现在零容忍 |
| 开放目录跨层贯通 | ✅ | application/domain 对 `zeta_agent_providers` 的 import 已清零并新增守卫；厂商 identity/extra-key/指标标签映射留在 data/app 组合层；Provider settings/模型目录根接线均 non-null、缺失时 fail-closed |
| root snapshot 必选关系 | ✅ | appearance/general/provider settings 与 agent management 四个节点均为 required 非空投影 |
| `zeta_agent_core` 纯 Dart | ✅ | 11 个 Flutter import 与 manifest 的 Flutter SDK/flutter_test 依赖清零；纯 Dart listenable + presentation adapter 替代，守卫改为零容忍 |
| Phase 4 发布/平台证据 | ❌ | 旧格式迁移窗口结束、可构建回退 tag/分支、三桌面平台构建与真实 Codex/Grok/Claude 冒烟尚未形成同一目标态证据；Phase 1 仍明列三平台构建待执行，第 5 批也明确没有用自动化测试推断真实 CLI 通过 |
| 性能与完整门禁 | ❌ | 本批自动化门禁在 §8/工作流记录；最近一份已跟踪 Windows Profile（2026-08-11）Raster p95 26.927/26.200ms、慢帧率 11.409%/9.396%，明确未过 16.7ms/5% 门槛，且尚无最终目标态同构复测；Phase 4 前必须复测关闭，并补真实 CLI 证据 |

剩余准入顺序：完成 Phase 2 连续 14 天证据 → 明确旧格式迁移窗口和可构建回退锚 →
三平台构建、三 Provider 真实 smoke、Windows Profile 与最终完整门禁。Phase 4 可以删除
剩余通用 facade/barrel并统一权威文档，但不能把这些未执行证据推断为通过。
