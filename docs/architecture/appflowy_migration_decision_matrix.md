# AppFlowy 设计迁移决策矩阵

最后更新：2026-08-21

## 1. 结论

Zeta 不应进行一次“AppFlowy 化”重构。两者都是 Flutter 桌面应用，但核心问题不同：

- AppFlowy 是富文档、数据库、协作与多端工作区，Rust/FFI、Collab/Yrs、Rust 广播和大量子包服务于这些产品能力。
- Zeta 是本地 Agent CLI 壳层，核心约束是 Provider 协议隔离、会话生命周期、审批安全、可审计时间线和高吞吐流式渲染。

因此，AppFlowy 中真正适合 Zeta 的内容主要是**原则**：单向依赖、明确状态所有权、编译期显式装配、资源生命周期、按事件语义选择刷新策略、统一 UI 原语。Zeta 已经采用了其中大部分，并在 Provider 防腐层、能力协商、流式事件管线和工作台保活方面比 AppFlowy 的通用做法更贴合自身问题。

本轮建议汇总：

- **Adopt 5 项**：继续作为架构门禁，不做框架迁移。
- **Adapt 4 项**：只借鉴原则，落到 Zeta 现有端口、Binding、EffectRunner 和类型化事件上。
- **Avoid 6 项**：当前产品没有相应问题，引入只会制造第二套基础设施。
- **Defer 4 项**：设定明确触发条件，条件未满足前不建骨架、不预留空包。

最重要的即时判断：

1. 不执行共享会话中建议的“首期拆 8 个 package”。
2. 不把 AppFlowy 的 BLoC 经验翻译成 Zeta 的 Riverpod 全面迁移。当前 `flutter_riverpod` 只有根 `ProviderScope`，没有实际 Provider；没有明确试点前不继续扩张。
3. 不建立通用微内核、全局 EventBus、Rust 核心层或 CRDT。
4. 保留并强化 Zeta 已有的 `AgentProviderBundle`、Provider-local adapter/reducer、Binding 生命周期、纯 reducer + EffectRunner、Workbench slot、帧级 UI 合并和架构守卫。

后续用户明确选择在这些边界内试点 Riverpod、MVI、编译期微内核和多 Package，目标方案见
[Feature-First DDD / Riverpod / MVI / 微内核 / 多 Package 目标架构](./target_architecture_riverpod_mvi_plugins_packages.md)。该方案不推翻本矩阵对“全面迁移”和“一次拆很多包”的 Avoid 判断：Riverpod 只承载业务切片与 UI 订阅，微内核只承载可信编译期插件，Package 按 Phase 0–4 逐个建立。

## 2. 证据范围与判定口径

### 2.1 快照

- 共享会话：[梳理 AppFlowy 全局架构 (2)](https://chatgpt.com/s/cx_6a885677a5e08191bfd72a3649f703c1)。会话用于提取候选主张，不作为最终事实源。
- AppFlowy 本地快照：`/Users/linpeilie/Development/Workspace/OpenSource/AppFlowy`，commit `5cf3a365dec0d59f64bad1ee4bb1050471a39b93`（2026-06-26）。
- Zeta 本地快照：本仓库 commit `115a35bf9537041588db8723ea028f4e91faca4d`（2026-08-21）。

源码位置均以对应 commit 为准。AppFlowy 使用 AGPL-3.0，Zeta 使用 GPL-3.0；本矩阵建议重用设计思想并在 Zeta 内重新实现，不建议直接复制源码。任何实质源码复用都应另做许可证评估。

### 2.2 分类含义

- **Adopt**：设计原则可原样接受；若 Zeta 已实现，则“采用”意味着保持并加固，不重复造轮子。
- **Adapt**：问题部分同构，但实现必须落到 Zeta 的领域模型、作用域和安全边界。
- **Avoid**：当前没有对应产品问题，或方案会破坏现有边界。
- **Defer**：可能有价值，但必须先满足可观测触发条件；未满足前不得搭空架子。

### 2.3 成本与复杂度

- 成本：`XS` ≤ 1 天，`S` 1–3 天，`M` 1–2 周，`L` 2–6 周，`XL` > 6 周或持续投入。
- 新增复杂度：`-1` 简化，`0` 不变，`+1` 局部机制，`+2` 跨模块机制，`+3` 新运行时/语言/平台。
- 风险：低 / 中 / 高 / 极高。

### 2.4 关键证据索引

| 编号 | 证据 |
| --- | --- |
| AF-01 | AppFlowy README 将产品定位为 AI collaborative workspace、跨平台与可扩展协作基础设施：`README.md:110-143`。 |
| AF-02 | Flutter 主应用引用 7 个本地 Dart package，并依赖 `flutter_bloc`、`get_it`、`provider`、`event_bus`：`frontend/appflowy_flutter/pubspec.yaml:16-136`。 |
| AF-03 | Rust workspace 有 31 个 member，依赖 Collab 系列 crate、`yrs` 和 AppFlowy Cloud：`frontend/rust-lib/Cargo.toml:1-115,150-157`。 |
| AF-04 | Flutter→Rust 请求走 `FFIRequest`、`async_event`；Rust→Flutter 通知走全局广播 `RustStreamReceiver`：`frontend/appflowy_flutter/packages/appflowy_backend/lib/dispatch/dispatch.dart:50-133`、`frontend/appflowy_flutter/packages/appflowy_backend/lib/rust_stream.dart:11-55`、`frontend/rust-lib/dart-ffi/src/lib.rs:173-218`。 |
| AF-05 | 侧栏状态由 `HomeSettingBloc` 统一保存、持久化并驱动 350ms 动画，不由按钮局部 `setState` 持有：`frontend/appflowy_flutter/lib/workspace/application/home/home_setting_bloc.dart:13-175`。 |
| AF-06 | 页面插件是封闭 enum + Builder + 生命周期 + 显式注册；`PluginContext` 很薄，注册表缺失时还会回落 Blank：`frontend/appflowy_flutter/lib/startup/plugin/plugin.dart:13-113`、`frontend/appflowy_flutter/lib/startup/plugin/src/sandbox.dart:9-58`、`frontend/appflowy_flutter/lib/startup/tasks/load_plugin.dart:12-43`。 |
| AF-07 | 插件并非严格微内核：页面类型、图标和实例创建仍按 `ViewLayoutPB` 多处 switch：`frontend/appflowy_flutter/lib/workspace/application/view/view_ext.dart:55-145`。 |
| AF-08 | 编辑器用 Transaction stream、选择 debounce、远端同步 throttle：`frontend/appflowy_flutter/lib/plugins/document/application/document_bloc.dart:94-100,259-375`；编辑器包来自独立仓库固定 revision：`frontend/appflowy_flutter/pubspec.yaml:185-194`。 |
| AF-09 | AppFlowy 抽出 `appflowy_ui`、`appflowy_popover`、`appflowy_result` 等可复用包，但 Flutter 主应用仍保留大量 `features/`、`plugins/`、`workspace/` 混合结构。 |
| Z-01 | Zeta 的产品边界明确为本地 Agent CLI 壳层，不实现编辑器、云同步、账号、完整插件系统或移动端：`docs/architecture/overview.md:9-15`、`README.md:165-169`。 |
| Z-02 | Zeta 已采用 feature-first 的 domain/application/data/presentation 分层和单向依赖：`docs/architecture/overview.md:17-49`。 |
| Z-03 | Zeta 已有 Provider-local adapter/reducer → 中立事件 → 合并 → 有界派发 → 纯 reducer → EffectRunner → 帧级 UI 的专用管线：`docs/architecture/overview.md:51-96`。 |
| Z-04 | `AgentProviderBundle` 通过必选/可选端口与 capability fail-closed；工厂只在 data 组合边界按 Provider kind switch：`lib/src/features/agent/domain/agent_provider_bundle.dart:3-64`、`lib/src/features/agent/data/default_agent_provider_factory.dart:1-65`。 |
| Z-05 | Provider runtime 只在 `AgentConversationBinding.beginTurn()` 惰性创建，带 generation、scope 和 10 分钟空闲回收：`docs/architecture/overview.md:133-156`。 |
| Z-06 | Workbench 已使用固定 Navigation/Canvas/Inspector slot、持久化布局意图与 `IdeRetainedPageView`：`docs/architecture/overview.md:180-203`、`lib/src/ui/core/workbench/ide_retained_page_view.dart:3-176`。 |
| Z-07 | Zeta 已有 `BoundedEventDispatcher`、`AgentUiUpdateScheduler`、Markdown LRU/租约和虚拟化原语，直接解决 Agent 流式热点。 |
| Z-08 | 仓库级搜索只发现 `flutter_riverpod` 位于 `pubspec.yaml:19`、`lib/main.dart:5,70`；当前没有 Consumer、Notifier 或业务 Provider。 |

## 3. 总览矩阵

| ID | AppFlowy 设计 | 决策 | 同类问题 | 预期收益 | 成本 | 复杂度 | 风险 | 最小方式 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | 分层、Repository、状态与副作用分离 | Adopt | 是 | 保护 Provider 隔离 | S | 0 | 低 | 保持现有门禁与契约测试 |
| A2 | 侧栏状态集中、持久化、动画由布局消费 | Adopt | 是 | 状态一致、跨页恢复 | XS | 0 | 低 | 继续使用 Workbench layout state |
| A3 | 插件 Builder/实例生命周期与显式注册 | Adopt | 是，但对象是 Provider | 资源可控、失败隔离 | S | 0 | 低 | 继续用 Bundle + Registry + Binding |
| A4 | 统一 UI 包、设计 token、共享控件 | Adopt | 是 | 视觉与交互一致 | S | 0 | 低 | 继续在 `ui/core` 收敛，不立刻拆包 |
| A5 | 按事件语义 debounce/throttle、懒构建、稳定 key | Adopt | 是，而且更高频 | 保持流畅与可预测 | M | 0 | 中 | 保持现有合并、限批、帧发布和虚拟化 |
| B1 | 编译期页面插件注册表 | Adapt | 部分 | 减少重复元数据 | M | +1 | 中 | 只为明确扩展点建 typed descriptor，不做通用插件 |
| B2 | 命令与已发生事实分离，后端通知驱动多视图 | Adapt | 是 | 多视图一致、避免直接引用 | M | 0/+1 | 中 | Provider-local typed signal + scope/generation |
| B3 | 多 package 形成物理依赖边界 | Adapt | 有边界需求，无多产物需求 | 更早发现越层依赖 | S | 0 | 低 | 先用架构测试和公开 API 清单 |
| B4 | 分阶段启动与插件懒激活 | Adapt | 是 | 首帧更快、局部失败 | M | 0/+1 | 中 | 测量启动链，只延后可延后的 I/O |
| C1 | Rust 业务核心 + Dart FFI + Protobuf | Avoid | 否 | 当前无净收益 | XL | +3 | 极高 | 不采用；继续 stdio CLI adapter |
| C2 | Collab/Yrs CRDT | Avoid | 否 | 当前无收益 | XL | +3 | 极高 | 不采用；不建抽象占位 |
| C3 | getIt、全局 EventBus、全局广播接收器 | Avoid | 否，且与 scope 冲突 | 无 | L | +2 | 高 | 继续构造注入与 scoped ports |
| C4 | BLoC/Riverpod 全面状态管理迁移 | Avoid | 没有框架造成的已证实缺陷 | 不确定 | L/XL | +2 | 高 | 停止扩张空 `ProviderScope`，先要具体试点 |
| C5 | 把 AppFlowy 页面插件当成完整微内核复制 | Avoid | 否 | 无 | L | +2 | 高 | 保留显式 app/data 组合和 sealed switch |
| C6 | 按 feature/团队一次拆很多 package | Avoid | 否 | 低 | L | +2 | 高 | 不执行 8 包方案 |
| D1 | 真正拆出 Dart workspace package | Defer | 可能逐渐出现 | 编译隔离、可复用 | L | +1 | 中 | 触发后一次只拆一个叶子包 |
| D2 | Block editor、Transaction、组件插件 | Defer | 当前无编辑器 | 若产品改向，可支持编辑内核 | XL | +3 | 极高 | 产品范围变更后另立 RFC |
| D3 | 第三方运行时插件 SDK/沙箱 | Defer | 当前无插件生态 | 可选模块生态 | XL | +3 | 极高 | 先出现真实第三方扩展需求 |
| D4 | 云同步、账号、移动端、多端一致性 | Defer | 当前无 | 扩大产品覆盖 | XL | +3 | 极高 | 产品与威胁模型改变后重新设计 |

## 4. Adopt：直接采用或继续保持

### A1. Feature-first 分层、Repository/Port 与副作用隔离

- **AppFlowy 中的设计及证据**：Flutter 侧大量功能按 application/domain/presentation 与 Repository/Backend Service 组织；`HomeSettingBloc` 统一处理状态转移，FFI 细节留在 `appflowy_backend`。见 AF-02、AF-04、AF-05。
- **解决的问题**：防止 Widget、业务规则、存储/协议互相渗透；让状态变更可测试。
- **Zeta 是否存在同类问题**：存在，而且 Provider 协议污染是 Zeta 的首要架构风险。
- **应用前提**：所有 Provider 差异在 data adapter/reducer 内结束；domain 纯 Dart；副作用经 EffectRunner。
- **预期收益**：新增 Provider 不改共享层；协议升级与 UI 变更互不拖累；安全语义可审计。
- **引入成本**：`S`，主要是继续维护守卫测试和评审清单。
- **新增复杂度**：`0`，现有结构已承担。
- **风险**：低；风险来自名义分层但实际越层，而不是该原则本身。
- **最小可行采用方式**：不迁目录、不换框架；每次新增能力继续走“中立契约 + Provider data 实现 + app 组合 + 契约测试”。
- **最终建议**：**Adopt，保持为最高优先级门禁。** Zeta 已经比共享会话建议的通用 Clean Architecture 更具体，不应退回抽象模板。

### A2. 集中持有 Workbench 布局意图，而不是侧栏局部 `setState`

- **AppFlowy 中的设计及证据**：`HomeSettingBloc` 持有 `MenuStatus`、保存折叠偏好、区分拖动与滑动并输出 350ms 动画时长。见 AF-05。
- **解决的问题**：折叠按钮、外层布局、快捷键、平台标题栏与重启恢复共享同一状态源。
- **Zeta 是否存在同类问题**：存在；左右栏由标题栏、Overlay、断点布局、会话恢复共同消费。
- **应用前提**：只持久化用户意图，不持久化响应式派生值和临时 Popover 状态。
- **预期收益**：多入口一致、跨页面不丢状态、窄屏/宽屏行为可测试。
- **引入成本**：`XS`，主要是保持现有测试。
- **新增复杂度**：`0`。
- **风险**：低；主要风险是把 hover、拖动中每像素或临时 Overlay 塞进全局状态。
- **最小可行采用方式**：继续使用 `IdeWorkbenchLayoutState` + persistence coordinator；拖动中状态留局部，结束时提交。
- **最终建议**：**Adopt，现状已经正确。** 不需要为了模仿 BLoC 再包一层 Riverpod Notifier。

### A3. 显式装配、能力声明和资源生命周期

- **AppFlowy 中的设计及证据**：`PluginBuilder` 描述插件，`Plugin` 有 `init/dispose`，启动任务显式注册。见 AF-06。
- **解决的问题**：模块如何创建、支持什么、何时初始化和释放不再散落在 Widget 中。
- **Zeta 是否存在同类问题**：存在，但 Zeta 的可替换单元是 Agent Provider runtime 和 conversation Binding，不是文档页面插件。
- **应用前提**：能力必须 fail-closed；session/global scope 分离；旧 generation 不得回写。
- **预期收益**：Provider 缺能力时 UI 不出现入口；进程、订阅、审批状态不会跨 Thread 串味。
- **引入成本**：`S`，继续补 Provider 契约测试。
- **新增复杂度**：`0`，已有 `AgentProviderBundle`、Registry、Binding Manager。
- **风险**：低；最大风险是照搬 AppFlowy 的缺失回落 Blank/no-op，这会违反 Zeta G4。
- **最小可行采用方式**：保持 `AgentProviderBundle` 的可选端口、`UnsupportedError` 二次校验和 `beginTurn()` 惰性生命周期。
- **最终建议**：**Adopt 原则，保留 Zeta 实现。** Zeta 的 capability port 比 AppFlowy 薄 `PluginContext` 更适合安全边界。

### A4. 设计 token、共享 UI 原语和单一 Workbench 组合边界

- **AppFlowy 中的设计及证据**：独立 `appflowy_ui`、`flowy_infra_ui`、`appflowy_popover` 统一主题和组件。见 AF-02、AF-09。
- **解决的问题**：重复控件、主题漂移、Overlay/Popover 行为分叉。
- **Zeta 是否存在同类问题**：存在；桌面多面板与高密度控件更需要统一尺寸、焦点和语义。
- **应用前提**：语义 token 是真源；feature 不绕过 `ui/core`；`IdeHome` 是唯一 Workbench 组合点。
- **预期收益**：一致的主题、控件高度、响应式行为和可访问性；减少 feature 私有样式。
- **引入成本**：`S`，按新增控件逐步收敛。
- **新增复杂度**：`0`。
- **风险**：低；风险是把 App 本地化、品牌资源和 feature 逻辑下沉进通用 UI 层。
- **最小可行采用方式**：继续扩充 `ui/core` 的 Ide 封装；暂不拆 `zeta_ui` package。
- **最终建议**：**Adopt。** 采用的是设计系统边界，不是 AppFlowy 组件源码或包数量。

### A5. 按事件语义优化热路径，并成对管理资源

- **AppFlowy 中的设计及证据**：本地编辑立即应用 Transaction，选区 250ms debounce，远端同步 250ms throttle；Widget/Bloc 释放订阅。见 AF-05、AF-08。
- **解决的问题**：避免所有事件使用同一 debounce，兼顾交互延迟、同步压力和资源泄漏。
- **Zeta 是否存在同类问题**：存在且更突出；Agent 会持续产生 delta、工具输出、终态和审批 barrier。
- **应用前提**：先按事件语义分类；终态/审批不能被丢弃；性能结论来自 Profile 数据。
- **预期收益**：长时间线、窗口 resize 和流式 Markdown 保持响应；顺序语义稳定。
- **引入成本**：`M`，持续性能测试与回归维护。
- **新增复杂度**：`0`，机制已经存在。
- **风险**：中；错误的 throttle/debounce 会吞掉终态或最后一段文本。
- **最小可行采用方式**：保留 CoalescingPolicy barrier、每 turn 64 条有界派发、frame 合并、LRU/lease、Sliver、稳定 key 与 `RepaintBoundary`。
- **最终建议**：**Adopt，禁止用 AppFlowy 的通用 Throttler 替换现有专用管线。** AppFlowy 的“按语义选择策略”值得采用，具体实现不适合复制。

## 5. Adapt：借鉴但按 Zeta 改造

### B1. 编译期插件注册表改造成“有限扩展点”，不建通用微内核

- **AppFlowy 中的设计及证据**：Builder/Config 注册可生成创建菜单，但插件类型是封闭 enum，页面创建和图标仍有静态 switch。见 AF-06、AF-07。
- **解决的问题**：统一描述、创建和排序有限种页面模块。
- **Zeta 是否存在同类问题**：部分存在；Provider 描述、能力、图标和工厂需要统一，但当前只有三个内建 Provider，且安全语义不同。
- **应用前提**：至少出现一处真实的重复元数据或新增 Provider 必须改多处的证据；扩展点仍是编译期、可信代码。
- **预期收益**：减少 Provider 展示元数据与工厂清单重复；测试可枚举所有内建 Provider。
- **引入成本**：`M`。
- **新增复杂度**：`+1`。
- **风险**：中；容易把 descriptor 发展成无边界 `PluginContext`、动态服务定位器或 no-op fallback。
- **最小可行采用方式**：若重复已证实，只增加一个 typed `AgentProviderDescriptor` 目录供 app/data 组合读取；协议实现、runtime 和 UI 仍通过现有 Bundle 端口。
- **最终建议**：**Adapt，但当前不急于实现。** `DefaultAgentProviderFactory` 中的 sealed switch 是明确且 fail-closed 的组合代码，不是需要消灭的坏味道。

### B2. “命令”与“事实”分离，通知必须作用域化

- **AppFlowy 中的设计及证据**：BLoC/Backend Service 发命令，Rust 修改后通过广播传播事实；多个视图按 source/id/type 过滤。见 AF-04。
- **解决的问题**：左侧面板不直接操纵右侧面板；本地、远端、协作者变化可统一传播。
- **Zeta 是否存在同类问题**：存在；Thread 终态、文件变更、权限、模型刷新可能被多个 UI 消费，但来源是 Provider runtime，不是协作文档数据库。
- **应用前提**：事件在 Provider 边界前具备完整 typed 语义；携带 thread/runtime generation；日志不含敏感正文。
- **预期收益**：跨面板不互持 Widget/Controller；迟到事件可丢弃；多 Thread 不串状态。
- **引入成本**：`M`。
- **新增复杂度**：`0/+1`，取决于是否已有对应 typed signal。
- **风险**：中；复制全局广播会让所有订阅者先收再过滤，扩大泄漏和串会话面。
- **最小可行采用方式**：继续由 Agent pipeline 发布 scoped typed mutation/attention signal；Shell 只协调低频意图，不接收原始 Provider 流。
- **最终建议**：**Adapt。** 采用“命令/事实分离”，拒绝 `RustStreamReceiver.shared` 式全局广播。

### B3. 先用可执行架构守卫获得 package 边界收益

- **AppFlowy 中的设计及证据**：本地 Dart package 隔离 backend、UI、popover、result 等能力；Rust Cargo workspace 进一步物理隔离。见 AF-02、AF-03、AF-09。
- **解决的问题**：依赖方向和公开 API 可由工具链而非约定约束。
- **Zeta 是否存在同类问题**：存在边界治理需求，但尚无第二个 App、SDK 消费者或独立发布单元。
- **应用前提**：先能描述每个候选包的稳定公开 API、唯一 owner 和禁止依赖。
- **预期收益**：在不搬文件的情况下提前发现 Provider 泄漏、Flutter/dart:io 下沉和跨 feature 私有引用。
- **引入成本**：`S`。
- **新增复杂度**：`0`。
- **风险**：低；守卫过度依赖字符串扫描时可能误报或漏报。
- **最小可行采用方式**：继续扩充 `test/src/features/agent/architecture/`；为 domain 无 Flutter/io、presentation 无 Provider data、共享层无厂商分支建立可执行检查。
- **最终建议**：**Adapt。** 先购买“边界可执行”收益，不购买“多 pubspec、多测试入口、多公开 API”成本。

### B4. 分阶段启动与按需初始化必须由指标驱动

- **AppFlowy 中的设计及证据**：启动由 LaunchTask 和 `PluginLoadTask` 显式编排，插件有 init/dispose。见 AF-06。
- **解决的问题**：重型初始化不阻塞全部功能，失败可局部化。
- **Zeta 是否存在同类问题**：存在；窗口、存储迁移、主题、Provider 探测、历史和模型目录启动成本不同。
- **应用前提**：先测量首帧、可交互时间和每个启动任务耗时；不能延后会导致首帧闪烁或覆盖旧数据的迁移/主题读取。
- **预期收益**：更快显示可用工作台；Provider/统计失败不阻塞应用。
- **引入成本**：`M`。
- **新增复杂度**：`0/+1`。
- **风险**：中；盲目 post-frame 会引入竞态、闪烁、旧结果回写和退出时未完成任务。
- **最小可行采用方式**：保留同步必要 bootstrap；Provider session 继续只在 `beginTurn()` 创建；仅把测得较慢且可独立失败的目录/统计预热改为异步。
- **最终建议**：**Adapt。** 不复制 AppFlowy 的 LaunchTask 组织结构；以 Zeta startup profile 决定是否需要更显式的任务模型。

## 6. Avoid：当前不适合

### C1. Rust 业务核心、Dart FFI 和 Protobuf 双栈

- **AppFlowy 中的设计及证据**：Dart 将 `FFIRequest` 序列化后调用 Rust `async_event`，Rust dispatcher 处理并通过 Dart Port 回传；Rust workspace 拆成 31 个 crate。见 AF-03、AF-04。
- **解决的问题**：复用高性能跨平台文档/数据库/同步核心，承载本地数据库与协作算法。
- **Zeta 是否存在同类问题**：不存在。Zeta 的业务核心是已有外部 Agent CLI，传输天然是 stdio JSON-RPC/JSONL/stream-json。
- **应用前提**：只有出现必须由 Zeta 自己实现、Dart 无法满足且需被多个前端复用的重型核心才成立。
- **预期收益**：当前几乎为零；不会改善 Provider 隔离或时间线语义。
- **引入成本**：`XL`，包括 Rust 工具链、FFI ABI、代码生成、跨平台构建、崩溃诊断与发布矩阵。
- **新增复杂度**：`+3`。
- **风险**：极高；双语言所有权、线程、内存、ABI 与安全日志边界都会增加。
- **最小可行采用方式**：无。性能热点先以 Profile 证明，再用 Dart isolate/算法优化；不要预建 Rust bridge。
- **最终建议**：**Avoid。** AppFlowy 的 FFI 是产品需求推导出的实现，不是 Flutter 大项目的通用升级路径。

### C2. 为不存在的协作需求引入 Collab/Yrs/CRDT

- **AppFlowy 中的设计及证据**：Rust workspace 依赖 `collab-*`、`yrs`、Cloud client；文档层同步远端状态和 awareness selection。见 AF-03、AF-08。
- **解决的问题**：多用户、多设备、离线编辑后的并发合并、远端光标与协作状态。
- **Zeta 是否存在同类问题**：不存在。Zeta 没有内置编辑器、账号、云同步或多人共享文档。
- **应用前提**：必须先有明确的并发编辑模型、冲突语义、服务器协议、身份模型、离线要求和数据保留策略。
- **预期收益**：当前为零。
- **引入成本**：`XL` 且持续。
- **新增复杂度**：`+3`。
- **风险**：极高；数据模型、持久化、同步、安全和测试空间会全面扩大。
- **最小可行采用方式**：无；Thread 历史恢复不是协同编辑，不能用 CRDT 解决。
- **最终建议**：**Avoid。** 若未来产品正式进入多人/多端编辑，应重新立项，不从今天的空抽象演进。

### C3. 全局 getIt、EventBus 或“所有订阅者先收再过滤”的广播

- **AppFlowy 中的设计及证据**：插件注册调用全局 `getIt<PluginSandbox>()`；`RustStreamReceiver.shared` 使用 broadcast stream；主应用还依赖 `event_bus`。见 AF-02、AF-04、AF-06。
- **解决的问题**：大型既有应用中让距离很远的模块快速获得服务或接收通知。
- **Zeta 是否存在同类问题**：没有必须靠全局总线解决的问题；反而有强烈的 Provider/thread/runtime scope 隔离需求。
- **应用前提**：只有真正进程级、无敏感 payload、无身份歧义、无更窄 owner 的信号才可能全局化。
- **预期收益**：短期少传几个构造参数，长期收益为负。
- **引入成本**：`L`，随后持续支付隐式依赖与测试清理成本。
- **新增复杂度**：`+2`。
- **风险**：高；串 Thread、迟到回写、订阅泄漏、无法审计数据流。
- **最小可行采用方式**：不采用；构造函数注入、Bundle port、Binding、Shell typed intent 已足够。
- **最终建议**：**Avoid。** AppFlowy 自身也只把 EventBus 用于少量临时 UI 事件，不能据此推广为 Zeta 骨干。

### C4. 为模仿 AppFlowy BLoC 而全面迁移 Riverpod

- **AppFlowy 中的设计及证据**：主应用依赖 `bloc`、`flutter_bloc`、`provider`、`get_it`，状态方案是多年演进后的混合体，而非单一最佳实践。见 AF-02、AF-05、AF-08。
- **解决的问题**：统一事件入口、不可变状态、局部订阅、对象作用域与异步加载。
- **Zeta 是否存在同类问题**：这些问题存在，但现有 Controller、ChangeNotifier、分区 ValueListenable、纯 reducer、EffectRunner 和构造注入已经覆盖。没有证据表明框架缺失导致当前缺陷。
- **应用前提**：必须先选一个具体 feature，证明样板、生命周期或重建范围是当前主要问题，并设定迁移前后指标。
- **预期收益**：未有试点数据；对 Agent 热路径可能是零或负收益。
- **引入成本**：全面迁移 `L/XL`。
- **新增复杂度**：`+2`，迁移期会同时存在两套状态模型。
- **风险**：高；原始 delta 进入 Provider、Reducer 被异步 Notifier 包裹、一次性 effect 重放、Provider family 生命周期与 Binding 冲突。
- **最小可行采用方式**：没有具体试点前，不新增业务 Provider。当前根 `ProviderScope` 是空壳；要么在单一低风险 feature 做可度量试点，要么移除依赖和 Scope。
- **最终建议**：**Avoid 全面迁移。** 采用 AppFlowy 的状态所有权原则，不复制其状态管理组织结构。当前建议优先移除空壳依赖，而不是继续为它寻找用途。

### C5. 把 AppFlowy 页面插件体系复制成“完整微内核”

- **AppFlowy 中的设计及证据**：插件必须源码 import、手工注册，类型为 enum；页面实例创建仍按 layout switch；`PluginContext` 只含少量字段。见 AF-06、AF-07。
- **解决的问题**：内部页面类型的统一创建、菜单生成和生命周期。
- **Zeta 是否存在同类问题**：不存在可运行时安装的第三方页面，也不需要 Document/Grid/Board 这类同构页面类型。
- **应用前提**：必须有稳定插件 ABI、隔离/权限模型、版本兼容、安装来源、故障域和卸载需求。
- **预期收益**：当前无；只会把 app 组合层间接化。
- **引入成本**：`L`。
- **新增复杂度**：`+2`。
- **风险**：高；容易伪造能力、绕开 G4、让插件拿到过宽服务、破坏 feature 单向依赖。
- **最小可行采用方式**：无。内建 Provider 与页面继续显式组合；sealed switch 在封闭集合中是优点。
- **最终建议**：**Avoid。** 共享会话中的 `PluginRegistry/PluginContext/AppEventBus` 示例是面向未来的提案，不是 AppFlowy 已验证的严格微内核，也不应成为 Zeta 当前目标。

### C6. 按 feature、团队或组织结构一次拆出大量 package

- **AppFlowy 中的设计及证据**：Dart 本地包与 31 个 Rust crate 同时存在，但主 Flutter app 内仍有大量交叉的 `features/plugins/workspace/shared`；包数量与产品、语言和团队演进共同相关。见 AF-02、AF-03、AF-09。
- **解决的问题**：独立构建/发布、跨语言工作区、多个产品复用、依赖冲突和 owner 边界。
- **Zeta 是否存在同类问题**：当前没有第二个 App、SDK、独立发布 Provider 或编译依赖冲突。
- **应用前提**：每个包必须有独立消费者或可观测的物理隔离收益，而不只是目录看起来整齐。
- **预期收益**：当前低；单次测试和 IDE 导航反而更碎。
- **引入成本**：执行共享会话 8 包方案至少 `L`，随后每次跨包变更持续增加成本。
- **新增复杂度**：`+2`。
- **风险**：高；公开 API 被过早冻结、循环依赖转成 `shared` 垃圾桶、本地化/资产/测试 fixture 被迫外泄。
- **最小可行采用方式**：不执行批量拆包；继续 feature-first 目录和架构守卫。
- **最终建议**：**Avoid 当前的 8 包方案。** 组织结构不是技术最佳实践，AppFlowy 的规模也不是 Zeta 的目标函数。

## 7. Defer：满足条件后再评估

### D1. 真正建立 Pub Workspace 并提取 package

- **AppFlowy 中的设计及证据**：backend、UI、popover、result、infra 是独立本地包；部分包有 example 与平台接口。见 AF-02、AF-09。
- **解决的问题**：独立复用、测试、发布、平台实现或依赖集合。
- **Zeta 是否存在同类问题**：可能逐渐出现，但当前只有一个源代码 pub package；`ui/core`、Agent core/provider 尚无第二消费者。
- **应用前提**：满足至少两项：第二个真实消费者；独立发布/版本需求；第三方依赖冲突；编译耗时热点；架构守卫频繁失效；明确稳定 API。
- **预期收益**：物理依赖隔离、独立测试、潜在增量编译收益。
- **引入成本**：每个包 `M/L`，取决于本地化、资产和 fixture 耦合。
- **新增复杂度**：`+1`。
- **风险**：中；拆错边界后跨包 API 和 shared 包会膨胀。
- **最小可行采用方式**：触发后一次只拆一个叶子包。优先候选是无 App 本地化/资产依赖的纯 Dart core；`zeta_ui` 必须等第二个 Flutter 消费者。
- **最终建议**：**Defer。** 每季度用触发条件复查，不按文件数或 AppFlowy 包数启动。

### D2. Block editor、Transaction/Operation 和组件插件

- **AppFlowy 中的设计及证据**：独立 `appflowy_editor` 使用块模型与 Transaction；主应用监听 transaction stream 并同步到协作后端。见 AF-08。
- **解决的问题**：富文本块级编辑、局部重绘、撤销重做、输入法、协作增量与可扩展块组件。
- **Zeta 是否存在同类问题**：当前不存在。Zeta 明确不实现编辑器，也不读取/编辑文件正文。
- **应用前提**：产品范围正式加入内置编辑器，并定义文本模型、保存语义、撤销、外部文件变化、Agent patch 冲突和平台输入法要求。
- **预期收益**：只有届时才可能成立。
- **引入成本**：`XL`。
- **新增复杂度**：`+3`。
- **风险**：极高；编辑器本身会成为与 Agent 壳层同等级的产品。
- **最小可行采用方式**：范围改变后先做独立 RFC 和技术选型；不要现在创建 `code_editor` feature、transaction 抽象或空 package。
- **最终建议**：**Defer。** AppFlowy 编辑器实现细节不能作为当前 Agent 时间线 renderer registry 的理由；sealed timeline entry switch 更简单且具穷尽检查。

### D3. 第三方运行时插件 SDK、安装与沙箱

- **AppFlowy 中的设计及证据**：现有页面插件是编译期内部模块，不支持目录扫描或独立第三方安装，且仍依赖全局服务与静态 layout switch。见 AF-06、AF-07。
- **解决的问题**：未来让外部作者扩展面板、命令、Provider 或工具卡。
- **Zeta 是否存在同类问题**：当前不存在；README 明确“不包含完整插件系统”。
- **应用前提**：至少有两个无法通过内建 feature/Provider bundle 满足的真实第三方扩展；同时具备权限、签名/来源、版本 ABI、崩溃隔离和数据访问策略。
- **预期收益**：生态扩展、独立发布模块。
- **引入成本**：`XL` 且长期维护。
- **新增复杂度**：`+3`。
- **风险**：极高，尤其涉及项目文件、Prompt、CLI 与网络权限。
- **最小可行采用方式**：先收集扩展用例；如果只需新增 Agent Provider，继续用源码级 `AgentProviderBundleFactory`，不要升级为动态插件。
- **最终建议**：**Defer。** AppFlowy 不是可直接复用的沙箱范本。

### D4. 云同步、账号、移动端与多端一致性

- **AppFlowy 中的设计及证据**：产品明确覆盖移动端、自托管、协作工作区；Rust workspace 依赖 Cloud client 与 Collab 系列。见 AF-01、AF-03。
- **解决的问题**：跨设备访问、共享空间、远端事实同步、离线合并与账户权限。
- **Zeta 是否存在同类问题**：当前不存在；数据与 Agent CLI 均以本机为边界。
- **应用前提**：产品战略改变，并先完成账号、加密、服务端、同步冲突、数据驻留、通知与威胁模型设计。
- **预期收益**：扩大使用场景，但会改变“本地壳层”的核心承诺。
- **引入成本**：`XL` 且持续运营。
- **新增复杂度**：`+3`。
- **风险**：极高；隐私、安全、合规、成本与离线一致性都会成为新主轴。
- **最小可行采用方式**：如有需求，先做只读、显式导出/导入或用户自选备份的产品研究；不要从 CRDT 或跨语言 core 倒推需求。
- **最终建议**：**Defer。** 这是产品重定位，不是架构重构。

## 8. 推荐迁移路线

### 现在：不迁框架，只加固现有边界

1. 将 A1–A5 作为架构评审清单长期保留。
2. 不执行多 package、Rust、CRDT、微内核或状态管理大迁移。
3. 对 `flutter_riverpod` 做一次明确决策：若没有单一 feature 试点和量化验收，移除依赖与空根 Scope；不要让“已经加了依赖”成为继续迁移的理由。
4. 若新增跨面板交互，优先定义窄的 typed intent/signal，并绑定 workspace/thread/runtime generation；禁止全局原始事件总线。
5. 若新增 Provider，继续遵循现有 Bundle/capability/Binding 路径；不要为“插件化”改共享 Pipeline、TimelineStore 或 UI。

### 未来复查门槛

只有出现以下证据，才打开对应 Defer 项：

| 证据 | 可重新评估 |
| --- | --- |
| 第二个真实 App/SDK 消费者，或独立发布需求 | D1 Pub Workspace/package 提取 |
| 产品正式纳入内置编辑器 | D2 编辑器/Transaction |
| 两个以上真实外部扩展作者与明确权限需求 | D3 插件 SDK/沙箱 |
| 账号、云端、离线、多设备成为正式路线图 | D4 同步/多端；届时才重新评估 CRDT/Rust core |
| 启动 profile 显示某个可延后任务主导 TTI | B4 更显式的分阶段启动 |
| 某一 feature 的现有状态模型出现可重复缺陷，并有可量化试点 | 才可重新评估 Riverpod 局部使用，仍不代表全局迁移 |

## 9. 最终建议

参考 AppFlowy 的正确方式不是复制其目录、依赖或语言栈，而是追问每个结构背后的产品压力是否也存在于 Zeta。

当前答案是：

- 分层、状态所有权、生命周期、设计系统和性能策略的压力确实存在，Zeta 已经采用，继续加固。
- 文档协作、多端同步、富文本编辑、第三方插件生态和跨语言核心的压力不存在，拒绝提前设计。
- package 物理拆分可能未来有价值，但现在应先靠架构测试获得大部分收益。
- 当前最危险的迁移不是“做得不够多”，而是把 AppFlowy 的组织复杂度、协作复杂度和编辑器复杂度误当成 Zeta 的技术欠债。

最终方向：**保持单 Flutter package、保持 feature-first、保持 Provider capability bundle 与 scoped lifecycle；只对有证据的局部问题做小步 Adapt。**
