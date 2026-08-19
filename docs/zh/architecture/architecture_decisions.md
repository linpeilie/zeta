# 架构决策记录（ADR-001—ADR-004）

中文 ｜ [English](../../en/architecture/architecture_decisions.md)

状态：**全部已接受**。决策日期：2026-08-19。适用基线：旧仓库
`b5c2f3e8a9ac544e9832866e86ff633661c46053`。

本文冻结迁移 P-1 的四项架构决策。机器可判定部分同步写入仓库根目录
`.architecture.yaml`；详细 API 以[包 API 契约](./package_api_contracts.md)为准，类与字段归属以
[ownership map](./ownership_map.md)为准。

## ADR-001：`agent_provider_contracts` 模型例外

### 背景

三个互不依赖的 Provider Data client 必须实现同一套中立能力端口，并交换完全相同的事件、
会话、权限、计划与用量值对象。把这些模型放进任一 Repository 会迫使其他 Repository 或 Data
client 反向依赖它，违反 VGV 的单向依赖与 Repository 零互依规则。

### 决策

建立纯 Dart 叶子包 `agent_provider_contracts`，作为唯一的模型归属例外：

- 允许 21 个 capability port、`AgentProviderBundle`、不可变中立值对象、typed failure/code、
  纯函数 codec 和 `ResolvedCliProcessCommand`。
- 只允许 Dart SDK、`collection`、`equatable`、`meta` 依赖；不得依赖任何本地 package。
- 禁止 Flutter、`dart:io`、平台插件、日志/存储实现、业务状态、本地化字符串与 vendor wire 字段。
- 类型必须不可变，集合必须冻结，并提供稳定值相等语义。
- 新类型必须至少有两个独立 client 消费；单一消费者类型留在对应 vendor client。
- 端口是否存在由 bundle 字段是否非空决定；capability flag 只表示当前配置下是否可用。

### 后果与复核条件

优点是三个 vendor client 可并行实现同一契约，代价是 contracts 容易变成“共享杂物包”。出现
以下任一情况必须重新评审 ADR-001：新增本地 package 依赖、加入 IO/Flutter、出现 vendor 字段、
出现 `selected`/`expanded`/`isLoading` 等交互状态、只有一个消费者，或端口数/事件 sealed family
发生变化。复核必须先更新中英文 API 契约与 `.architecture.yaml`，再修改实现。

## ADR-002：Flutter platform adapter 边界

### 背景

系统字体、通知、attention、目录选择、剪贴板、窗口和菜单需要 Flutter plugin 或
`MethodChannel`，但 Data/Repository package 必须保持纯 Dart。

### 决策

- 中立端口位于纯 Dart package `desktop_platform_api`。
- Flutter concrete adapter 只位于 `lib/app/platform/**`。
- adapter 只可依赖 `desktop_platform_api`、Flutter services 与对应 plugin；不得依赖业务 Data
  client、Repository、Bloc 或 Presentation。
- Repository 只依赖纯 Dart port；Bloc 不直接调用 platform port，必须经过对应 Repository。
- `lib/bootstrap.dart` 构造 adapter 并注入 Repository，是唯一可同时看见两者的 composition root。
- native Runner/MethodChannel 只负责 transport，不拥有业务规则、选择状态或本地化文案。

### 后果与复核条件

平台实现留在 app，纯 Dart package 可独立测试。新增 plugin、channel 或新的平台能力时必须复核
端口是否仍然中立，并同步 `.architecture.yaml` 的 plugin allowlist。任何在 Bloc、Widget 或
Repository 中直接出现 `MethodChannel`/plugin import 的方案都否决。

## ADR-003：Router 是导航标识唯一真源

### 背景

旧 `IdeShellController` 同时保存页面、project/thread 标识与恢复状态，会与 GoRouter location
形成双真源，导致启动恢复、back、菜单导航和无效 ID 处理互相覆盖。

### 决策

- typed hierarchical GoRouter route 是当前页面、projectId、threadId 的唯一真源。
- route 只携带稳定 ID；禁止 `extra:`、裸路径拼接和文件路径对象。
- session restore 只产出 initial location 或 redirect 输入，不保存或回写持续导航状态。
- `IdeShellBloc` 只保存布局、面板可见性和选择等非导航交互状态，不镜像 router location。
- Bloc 不依赖 GoRouter；导航、dialog/snackbar 与 back side effect 由 Presentation 的
  `BlocListener` 执行。
- 无效或失效 ID 的 redirect 必须 fail closed 到可恢复的父 route。

### 后果与复核条件

导航状态可由 URL/location 重建，恢复逻辑不再和 Shell 状态竞争。引入外部 deep link、多个窗口、
可并存 flavor 安装或需要跨窗口共享导航时必须重新评审；当前迁移明确不支持 OS 外部 deep link。

## ADR-004：Conversation reducer/effect 与 Bloc 边界

### 背景

Provider 事件即使没有 UI 也必须继续按顺序归并；同时旧 conversation application/presentation
代码混有展开、选中、加载、草稿、滚动和导航等 UI 状态。整体搬到 Repository 或 Bloc 都会跨层。

### 决策

- Repository 持有 runtime lease、listener generation、事件管线、确定性 reducer、timeline/domain
  snapshot、history/live/replay scope，以及 Provider/存储/资源生命周期 effect。
- Repository 通过 `Stream<T> changes` + 同步 `snapshot` 发布外部事实，不依赖 Flutter。
- Bloc 持有选择、草稿、展开、loading/failure、冲突确认和跨 Repository 业务编排；每个异步事件
  显式选择 transformer。
- 滚动、聚焦、dialog/snackbar、导航等 Flutter side effect 由 Presentation `BlocListener` 执行。
- UI request 回调端口删除；Repository 不回调 Presentation，也不保存 UI slice。
- 发送时由 Bloc 冻结不可变 turn configuration，再作为参数交给 Repository。

### 后果与复核条件

Provider 顺序与资源生命周期不受 Widget 生命周期影响，UI State 保持廉价且可比较。修改 reducer
输入/输出、effect 顺序、scope、lease 所有权、snapshot 发布形状，或需要 Repository 保存任何
交互字段时必须重新评审 ADR-004，并同步会话状态设计、ownership map 与事件风暴测试。

## Open-decision register

**当前开放项：0。** 新问题必须先登记为 `OPEN`，明确 owner、截止步骤和阻塞范围；未清零不得
离开 P-1。

| 决策 | 最终结论 | 状态 |
| --- | --- | --- |
| 桌面平台 | macOS、Windows、Linux 都是一等目标；三平台统一 `cn.easii.zeta` / `Zeta` | RESOLVED |
| 无障碍 | 固定 WCAG 2.2 AA；macOS 用 VoiceOver，Windows 用 Narrator/NVDA，Linux 用 Orca，并执行纯键盘 smoke | RESOLVED |
| Linux 限制 | Flutter/Orca 已知限制必须记录，但不能用来跳过阻塞性 AA 问题或手工验证 | RESOLVED |
| 动效 | reduce-motion 是额外 VGV 平台门禁，不冒充 WCAG AA 条款 | RESOLVED |
| flavor 身份 | 三个 flavor 共用应用 ID 与 `~/.zeta`，不支持并存安装 | RESOLVED |
| 旧仓库覆盖率 | 只记录 83.97%，不作为 Step 0 门禁；新 VGV workspace 仍要求人工代码 100% | RESOLVED |
| Codex schema/tool | stable schema pin 与必要 smoke/gate 工具迁入；旧 packaging 与 updater 不迁入 | RESOLVED |
