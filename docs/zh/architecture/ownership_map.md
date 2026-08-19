# 归属映射表（ownership map）

中文 ｜ [English](../../en/architecture/ownership_map.md)

本表执行[迁移任务清单 步骤 2](./migration_tasks.md)：把旧仓库的每个 Controller / Store /
Service / Notifier 逐个裁决到 Data、Repository、Bloc/Cubit 或 Presentation。

[迁移拓扑 §5](./migration_topology.md) 只给了原则；本表给答案。原则用于处理本表未覆盖的新情况，
**冲突时以本表为准**——本表的每条裁决都基于对源文件的实际阅读，而不是按目录名推断。

---

## 1. 判定程序

对每个旧类，按顺序回答，第一个 `是` 决定归属：

| # | 问题 | 归属 | 依据 |
| --- | --- | --- | --- |
| 1 | 它是否直接做进程、stdio、文件、平台通道或协议 IO？ | **Data** | [拓扑 §3.1](./migration_topology.md) |
| 2 | 它持有的状态，在没有任何 UI 打开时是否仍然必须存在且正确？ | **Repository** | 外部数据与外部资源生命周期 |
| 3 | 它的状态是否只描述"用户此刻看到/选中/展开了什么"？ | **Bloc/Cubit** | 交互状态 |
| 4 | 它是否只把已有状态变形为像素、缓存渲染结果或调度帧？ | **Presentation** | [拓扑 §5](./migration_topology.md) |

**第 2 问是关键判据。** 举例：

- Provider 进程还在跑、事件还在到达 → 即使 UI 全关也必须继续归并 → `AgentConversationReducer` 属 **Repository**。
- 用户展开了哪个工具卡 → UI 全关后这个事实无意义 → `expandedEntryIds` 属 **Bloc**。
- 模型目录的 TTL 缓存 → 与 UI 无关，是外部数据的缓存 → **Repository**。
- 模型下拉框当前选中项 → **Bloc**（持久化的默认值仍走 Repository）。

### 1.1 `ChangeNotifier` 不能机械替换

[拓扑 §5](./migration_topology.md) 已警告这点。具体做法：

| 原 `ChangeNotifier` 表示 | 新形态 |
| --- | --- |
| 外部数据变化（进程状态、文件内容、目录刷新） | Repository 暴露 `Stream<T>` + 同步 `T get snapshot` |
| 交互状态（选中、展开、加载中、错误提示） | Bloc/Cubit 的 `State` 字段 |
| 两者混合 | **必须拆分**，见 §5 |

Repository **不得**依赖 Flutter，因此 `ChangeNotifier` / `ValueNotifier` / `Listenable`
在 `packages/*_repository/` 中出现即门禁失败（[步骤 26](./migration_tasks.md)）。

---

## 2. `ChangeNotifier` / `Listenable` 全量清单（24）

旧仓库 `lib/src` 共 24 处声明。**每一处都必须在本表有去向**，这是 P4 的客观出口之一。

| 声明位置 | 表示什么 | 裁决 |
| --- | --- | --- |
| `app/shell/ide_shell_controller.dart:85` | 混合：布局 + 选中 + 会话恢复 | **Bloc** `IdeShellBloc` |
| `agent/application/agent_conversation_binding.dart:196` | 外部：会话运行时上下文 | **Repository** → Stream |
| `agent/application/agent_conversation_binding_manager.dart:33` | 外部：binding lease 与空闲回收 | **Repository** → Stream |
| `agent/application/agent_conversation_model_selection_controller.dart:53` | 混合：目录（外部）+ 选中/冲突/保存错误（交互） | **拆分**，见 §5.3 |
| `agent/application/agent_conversation_mode_controller.dart:85` | 混合：模式目录（外部）+ draft/选中（交互） | **拆分**，见 §5.3 |
| `agent/application/agent_conversation_permission_selection_controller.dart:43` | 混合：catalog/apply（外部）+ 选中/重试（交互） | **拆分**，见 §5.3 |
| `agent/application/agent_conversation_timeline_store.dart:1807` (`AgentConversationTurnState`) | 混合：turn 分组（外部）+ 展开态（交互） | **拆分**，见 §5.1 |
| `agent/application/agent_elapsed_ticker.dart:8` | 交互：1 秒刷新 elapsed 显示 | **Bloc** 的 timer |
| `agent/application/agent_provider_runtime_registry.dart:18` | 外部：runtime lease 注册表 | **Repository** → Stream |
| `agent/application/agent_provider_settings_controller.dart:18` | 外部：Provider 配置持久化 | **Repository** → Stream |
| `agent/application/agent_provider_settings_port.dart:10` | 端口，`implements Listenable` | **Repository 公共 API**，去掉 Listenable |
| `agent/application/agent_skills_catalog_controller.dart:58` | 混合：Skill 目录（外部）+ 加载状态（交互） | **拆分**，见 §5.4 |
| `agent/application/agent_thread_workspace_controller.dart:81,197` | 交互：常驻 thread/draft 与选中 | **Bloc** `IdeShellBloc` / `AgentChat` scope |
| `agent/presentation/widgets/agent_mention_file_picker.dart:7` | 交互：popover 列表游标（私有） | **Presentation** 局部 State |
| `agent/presentation/widgets/agent_skill_picker.dart:7` | 同上 | **Presentation** 局部 State |
| `agent/presentation/widgets/agent_slash_command_picker.dart:51` | 同上 | **Presentation** 局部 State |
| `agent_management/application/agent_management_controller.dart:21` | 混合 | **Bloc** `AgentManagementBloc` + Repository |
| `project_threads/presentation/project_threads_view_model.dart:11` | 交互 | **Bloc** `ProjectThreadsBloc` |
| `settings/application/appearance_settings_controller.dart:62` | 混合：字体目录（外部）+ 选中（交互） | **拆分**，见 §6 |
| `settings/application/general_settings_controller.dart:14` | 外部：设置持久化 | **Repository** + `SettingsCubit` |
| `usage_statistics/application/agent_usage_panel_controller.dart:36` | 交互：Tab + 按需加载状态 | **Cubit** `AgentUsagePanelCubit` |
| `usage_statistics/application/usage_statistics_controller.dart:14` | 交互：筛选 + 异步编排 | **Bloc** `UsageStatisticsBloc` |
| `workspace/application/workspace_file_index_controller.dart:36` | 混合：索引结果（外部）+ 索引进度（交互） | **拆分**，见 §6 |

`ValueNotifier` 出现在 8 个文件中，全部位于 `presentation/`，属 Widget 局部状态，随
Presentation 迁移，不进入 Bloc State。

> **三个 picker 的私有 `ChangeNotifier` 保留**：它们是 Widget 私有的列表游标，不跨 Widget 共享，
> 也不代表业务状态。VGV 不要求把所有 Widget 局部状态提升到 Bloc；提升反而会让高频键盘导航
> 走一遍 Bloc 事件循环。

---

## 3. `features/agent/application/`（35）— 逐个裁决

这是整个迁移风险最高的目录：35 个 `.dart` 文件、11,824 行（另有 1 个 `.gitkeep`），
同时包含真正的领域编排和伪装成 "application" 的 UI 状态。

### 3.1 → `agent_conversation_repository`（20）

判定第 2 问全部为"是"：Provider 进程在跑时，即使没有任何 UI，这些逻辑仍必须正确运行。

| 文件 | 行数 | 职责 | 迁移注意 |
| --- | ---: | --- | --- |
| `agent_conversation_binding.dart` | 647 | 会话稳定身份；draft → threadId 原子晋升 | 去 `ChangeNotifier`，改 Stream + 同步 snapshot |
| `agent_conversation_binding_manager.dart` | 276 | binding 唯一映射与空闲回收 | lease 释放必须在 Repository `close()` 可证明 |
| `agent_conversation_effect.dart` | 129 | reduction scope 枚举、effect 顺序 | `live/history/replay` 三个 scope 必须各自持有 reducer 实例 |
| `agent_conversation_effect_runner.dart` | 212 | effect 执行，带 generation/epoch 校验 | 只保留协议 effect；**UI effect 移出**，见 §5.2 |
| `agent_conversation_event_processor.dart` | 260 | 事件编排 | **拆分**：UI request 分支移出，见 §5.2 |
| `agent_conversation_mutation.dart` | 395 | typed state change sealed family | 直接迁移 |
| `agent_conversation_reducer.dart` | 1,160 | 确定性归并 + 本地 entryId 生成 | ADR-004 明确留 Repository |
| `agent_conversation_thread_snapshot.dart` | 57 | 轻量 thread 快照 | Shell 与线程列表的稳定契约 |
| `agent_event_coalescing_policy.dart` | 143 | 合并 key / merge / barrier | 高频事件性能关键路径 |
| `agent_event_pipeline.dart` | 349 | 事件管线与脱敏诊断 | 诊断只含计数，不含正文 |
| `agent_permission_request_resolver.dart` | 35 | 按优先级构造请求快照 | 纯函数 |
| `agent_provider_event_listener_gate.dart` | 103 | listener generation 隔离 | 防止旧 runtime 幽灵事件 |
| `agent_provider_runtime_identity.dart` | 30 | runtime 稳定身份 | 值类型；见 §3.5 关于放 contracts 的讨论 |
| `agent_provider_runtime_registry.dart` | 305 | runtime lease 注册表 | 去 `ChangeNotifier` |
| `agent_turn_context_overlay.dart` | 240 | 本地 turn context 覆盖历史快照 | 纯函数 |
| `agent_turn_context_recorder.dart` | 143 | turn context 旁路写入 | 失败只记诊断，不回抛 |
| `bounded_event_dispatcher.dart` | 183 | FIFO 有界分发 + 背压 | event-storm 验收依赖它 |
| `coalescing_event_buffer.dart` | 163 | 通用合并缓冲 | 与 policy 分离的泛型容器 |
| `agent_conversation_permission_state.dart` | 360 | 会话权限事实 | **部分**，见 §5.3 |
| `agent_conversation_timeline_store.dart` | 2,017 | 时间线聚合 | **部分**，见 §5.1 |

### 3.2 → `agent_provider_repository`（7）

| 文件 | 行数 | 职责 | 迁移注意 |
| --- | ---: | --- | --- |
| `agent_model_catalog_repository.dart` | 479 | 模型目录 TTL 缓存唯一真源 | 新鲜 1 小时 / stale 最多 7 天；见 [Claude 协议 §7](../protocols/claude_code_stream_json_protocol.md) |
| `agent_permission_catalog_controller.dart` | 101 | 权限目录加载与 stale retention | 目录是外部数据；**选中态不在这里** |
| `agent_provider_config_store.dart` | 8 | 配置持久化端口 | IO 实现下沉 `agent_config_client` |
| `agent_provider_global_runtime.dart` | 74 | 会话建立前的统一操作入口 | global scope 不参与空闲回收 |
| `agent_provider_settings_controller.dart` | 399 | Provider 配置/启停/默认值持久化 | 去 `ChangeNotifier` |
| `agent_provider_settings_port.dart` | 51 | 设置端口 | **去掉 `implements Listenable`**，改 Stream |
| `agent_skills_catalog_controller.dart` | 276 | Skill 目录 stale-while-revalidate | **部分**，见 §5.4 |

> **`agent_provider_repository` 与 `agent_conversation_repository` 之间零依赖。**
> `AgentConversationBloc` 先向前者取 `AgentProviderBundle`，再把 bundle 传给后者的
> `openConversation`（[拓扑 §4.4](./migration_topology.md)）。这条边界在 §3.1/§3.2 的划分中已经成立：
> 两组文件之间当前没有直接引用需要打断。

### 3.3 → Bloc / Cubit（5）

| 文件 | 行数 | 目标 | 理由 |
| --- | ---: | --- | --- |
| `agent_elapsed_ticker.dart` | 42 | `AgentConversationBloc` 的 timer | 纯 UI 刷新；`close()` 必须取消 |
| `agent_plan_execution_handoff_controller.dart` | 395 | `AgentConversationBloc` | 交接是本地业务规则；源文件已声明"不依赖 Widget、Store 或协议" |
| `agent_conversation_mode_controller.dart` | 629 | **拆分**，见 §5.3 | draft/选中/异步竞态是交互 |
| `agent_conversation_model_selection_controller.dart` | 782 | **拆分**，见 §5.3 | 冲突确认与保存失败是交互 |
| `agent_conversation_permission_selection_controller.dart` | 672 | **拆分**，见 §5.3 | catalog/apply 属外部数据，选中与重试属交互 |

### 3.4 → 其他包 / 删除（3）

| 文件 | 行数 | 裁决 | 理由 |
| --- | ---: | --- | --- |
| `agent_thread_workspace_controller.dart` | 516 | **Bloc**（`IdeShellBloc` + `AgentConversationBloc` scope） | 常驻线程/草稿是 IDE canvas 的交互状态；key 类型作为值对象进 contracts |
| `agent_ui_update_port.dart` | 23 | **删除** | Bloc State + `BlocSelector` 取代"UI 更新端口" |
| `agent_ui_update_request.dart` | 170 | **Presentation**（`lib/agent_chat/view/`） | `AgentUiRegion` / urgency 仍供帧调度器使用（[拓扑 §5](./migration_topology.md)：帧合并留 Presentation） |

### 3.5 `agent_provider_runtime_identity.dart` 的归属讨论

30 行的纯值类型，`agent_conversation_repository` 与 `agent_provider_repository` 都需要它。
**两个 Repository 之间零依赖**，所以它不能留在其中一个。

- **裁决**：放 `agent_provider_contracts`。它是不可变值对象、零 IO、零 vendor 字段，符合 ADR-001 的准入条件。
- **同类处理**：`AgentThreadWorkspaceKey`、`AgentConversationBindingKey` 等跨包共享的 sealed key 类型同理。
- **反例**：不要因为"两个包都要用"就把有行为的类塞进 contracts。只有**不可变值对象与纯函数**可以。
- **Turn activity 裁决**：`AgentAttentionSignal`、`AgentWorkspaceAttention`、
  `AgentTurnTerminalSignal` 是跨包共享的中立不可变信号，进入 contracts；
  `AgentTurnActivityPhase` / `AgentTurnActivitySnapshot` 留在 `AgentConversationBloc` State，
  耗时格式化留在 app Presentation/l10n。

---

## 4. 其他 feature 的 `application/`（22）

22 个 `.dart` 文件、5,263 行（另有 3 个 `.gitkeep`）。

| 文件 | 行数 | 裁决 | 理由 |
| --- | ---: | --- | --- |
| `agent_management/agent_management_controller.dart` | 785 | **拆分**：detect/test/config/log 调用 → `agent_management_repository`；selected agent、progress、validation、logs 视图状态 → `AgentManagementBloc` | 步骤 24 明确"不保存 selected agent、progress、loading" |
| `desktop_notifications/desktop_attention_controller.dart` | 302 | **Bloc** `DesktopNotificationsBloc` | 合并 attention/可见性/未读，是跨 Repository 编排 → 步骤 29 |
| `ide_session/ide_session_persistence_coordinator.dart` | 128 | **Cubit** `IdeSessionCubit` | 恢复/持久化时序与取消令牌是交互编排 |
| `ide_session/ide_session_restore_result.dart` | 29 | **Cubit** State 的字段 | 恢复结果 → 步骤 30 的 initial route input |
| `ide_session/ide_session_state_builder.dart` | 136 | **拆分**：快照构建 → Cubit；失效项清洗（项目/文件是否存在）→ `project_session_repository` | 存在性判断需要文件系统事实 |
| `project_threads/project_threads_controller.dart` | 1,122 | **拆分**：聚合分页/游标 → `project_session_repository`；搜索防抖、筛选、选中 → `ProjectThreadsBloc` | 搜索 `restartable()`、load more `droppable()` → 步骤 30 |
| `project_threads/project_threads_session_snapshot_codec.dart` | 124 | **Cubit** + `project_session_client` | codec 下沉 Data；恢复计划留 Bloc |
| `settings/app_language_resolver.dart` | 38 | **`settings_repository`** | 纯函数，已声明不接收 Flutter `Locale` |
| `settings/appearance_settings_controller.dart` | 360 | **拆分**，见 §6 | 字体目录是外部数据，选中是交互 |
| `settings/general_settings_controller.dart` | 147 | **拆分**：持久化 → `settings_repository`；发布/失败提示 → `SettingsCubit` | 持久化写按 `sequential()` |
| `settings/general_settings_update_result.dart` | 2 | **`settings_repository`** | typed 结果；"失败时不得把内存选择当成已生效"是领域规则 |
| `workspace/workspace_file_index_controller.dart` | 272 | **拆分**，见 §6 | isolate 遍历与文件系统事件流 → Data/Repository |
| `workspace/workspace_file_indexer.dart` | 121 | **`workspace_client`** | 递归扫描是 `dart:io`，必须下沉（步骤 19） |
| `workspace/workspace_tree_builder.dart` | 112 | **拆分**：读目录下一层 → `workspace_client`；`expandedPaths` 判定 → `WorkspaceCubit` | 源文件把展开态和 IO 耦合在一起，是典型必拆点 |
| `usage_statistics/agent_usage_panel_controller.dart` | 467 | **Cubit** `AgentUsagePanelCubit` | Tab、按需加载、局部错误全是交互 |
| `usage_statistics/agent_usage_query_service.dart` | 247 | **`usage_statistics_repository`** | 渐进式查询输出，乱序收敛属领域 |
| `usage_statistics/agent_usage_refresh_coordinator.dart` | 76 | **删除** | 手写 event-queue 调度被 `bloc_concurrency` 的 `droppable()`/`restartable()` 取代 |
| `usage_statistics/agent_usage_token_aggregation.dart` | 27 | **`usage_statistics_repository`** | 纯聚合函数 |
| `usage_statistics/query_agent_usage_panel_repository.dart` | 88 | **`usage_statistics_repository`** | 投影为面板契约 |
| `usage_statistics/query_usage_statistics_repository.dart` | 81 | **`usage_statistics_repository`** | 同上 |
| `usage_statistics/usage_statistics_controller.dart` | 219 | **Bloc** `UsageStatisticsBloc` | 筛选状态 + 异步编排 |
| `usage_statistics/usage_statistics_report_builder.dart` | 380 | **`usage_statistics_repository`** | 聚合为 report domain model |

> **`agent_usage_refresh_coordinator.dart` 的删除是有意的。** 它存在的原因是"避免持续动画时
> idle 任务无法执行"。Bloc 的 event transformer 不依赖 Flutter Scheduler，这个问题不存在。
> 保留它等于在 Bloc 之外再造一套并发控制，违反[任务清单 §1.3](./migration_tasks.md)
> "每个异步事件显式选择 transformer"。

---

## 5. 必须拆分的文件（详细切分）

§8 统计的 16 个需拆分文件中，agent 会话相关的 8 个在本节给出字段级切分；workspace / settings
的 3 个见 §6；`ide_session_state_builder`、`project_threads_controller`、
`project_threads_session_snapshot_codec`、`general_settings_controller`、
`agent_management_controller` 这 5 个的切法已在 §4 表中逐条写明。

这些文件同时包含外部数据与交互状态，**不能整体搬到任何一层**。

### 5.1 `agent_conversation_timeline_store.dart`（2,017 行）

源文件自述职责三项，正好横跨两层：

| 源职责 | 归属 | 目标 |
| --- | --- | --- |
| 消息、工具调用、审批/提问卡片、历史事件的统一时间线 | Repository | `agent_conversation_repository` 的 timeline aggregate |
| live / history / standby turn 分组 | Repository | 同上；分组是 Provider 事件的确定性结果 |
| token 汇总 | Repository | 同上 |
| **UI 展开态** | **Bloc** | `AgentConversationState.expansion` slice |
| `AgentConversationTurnState extends ChangeNotifier`（:1807） | **拆分** | 数据字段 → Repository 的不可变 turn snapshot；展开/选中 → Bloc State |

字段级切分见[会话状态设计 §4](./agent_conversation_state_design.md)。

### 5.2 `agent_conversation_event_processor.dart` + `agent_conversation_effect_runner.dart`

Processor 源码自述按固定顺序应用五类结果：**typed state、Timeline、ThreadSnapshot、UI request、application effect**。
前三项是 Repository，第四项是 Bloc，第五项要看 effect 种类。

| 应用顺序 | 归属 |
| --- | --- |
| typed state mutation | Repository |
| Timeline 更新 | Repository |
| ThreadSnapshot 更新 | Repository |
| **UI request 发布** | **删除**——Repository 发出新的 domain snapshot，Bloc 订阅后自行决定 State 变化 |
| application effect | **按种类拆**，见下表 |

| effect 种类 | 归属 | 理由 |
| --- | --- | --- |
| 向 Provider 回写（权限、提问、Plan、steer、cancel） | Repository | 协议 effect |
| 持久化 turn context | Repository | 外部存储 |
| 释放 lease / 关闭 runtime | Repository | 外部资源生命周期 |
| 滚动到底部、聚焦 composer、展开某卡片 | **Bloc → `BlocListener`** | Flutter side effect |
| 弹 dialog / snackbar / 导航 | **Presentation `BlocListener`** | [任务清单 §1.4](./migration_tasks.md) |

**`AgentConversationStateMutationTarget`（processor 的 facade 接口）删除**：它的存在是为了让
application 层回调 presentation。Bloc 架构下这个方向的调用不存在。

### 5.3 三个 selection controller

`mode`（629）、`model_selection`（782）、`permission_selection`（672）+ `permission_state`（360）
结构相同：都是"目录加载 + 当前选择 + 持久化 + 异步竞态"。统一切法：

| 关注点 | 归属 | 说明 |
| --- | --- | --- |
| 目录读取与缓存（modes / models / permission options / skills） | `agent_provider_repository` | 外部数据 |
| 向 Provider apply 选择 | `agent_provider_repository` | 协议调用 |
| 默认偏好持久化 | `agent_provider_repository` | 外部存储 |
| **当前选中值** | **Bloc State** | 交互 |
| **thread draft（尚未发送的选择）** | **Bloc State** | 交互 |
| **加载/失败状态、保存错误、冲突待确认** | **Bloc State** | 交互，用 typed failure |
| **异步竞态守卫** | **Bloc 的 transformer** | `restartable()` 取代手写 generation 计数 |
| 发送时冻结的不可变快照 | Repository 的方法参数 | 由 Bloc 构造后传入 |

`AgentModelCompatibilityConflict`（Fast 与思考程度冲突后等待用户确认）是**纯交互状态**，
必须进 `AgentConversationState.composer`，不能留在 Repository。

`AgentConversationPermissionState`（360 行）切分：

| 成员 | 归属 |
| --- | --- |
| `AgentPermissionStateSource` 枚举、`AgentConversationPermissionValue` | contracts（值对象） |
| 已生效的权限事实、Provider apply 结果 | `agent_provider_repository` |
| `AgentPermissionPersistenceFailure`（可重试提示） | **Bloc State** |

### 5.4 `agent_skills_catalog_controller.dart`（276 行）

| 成员 | 归属 |
| --- | --- |
| stale-while-revalidate 目录读取、失效刷新订阅 | `agent_provider_repository` |
| `AgentSkillsLoadStatus` 枚举 | **Bloc State**（loading/failure 是交互状态） |
| `AgentSkillsCatalogState` 不可变目录内容 | Repository 的 domain model，Bloc State 引用它 |

---

## 6. 其他必拆文件

### 6.1 `settings/appearance_settings_controller.dart`（360 行）

| 成员 | 归属 |
| --- | --- |
| 系统字体目录读取 | `settings_repository`（经 `SystemFontCatalogApi` 端口） |
| 外观设置持久化 | `settings_repository` |
| `AppearanceFontOption`（弹窗展示选项） | **`SettingsCubit` State**——它是为 UI 构造的展示模型 |
| 当前选中字体/主题 | **`SettingsCubit` State**（持久化后的默认值仍在 Repository） |

### 6.2 `workspace/workspace_file_index_controller.dart`（272 行）

| 成员 | 归属 |
| --- | --- |
| 后台 isolate 遍历、文件系统事件流创建 | `workspace_client`（`dart:io`，步骤 19） |
| 索引结果与查询 | `workspace_repository` |
| 索引进度、取消、失败提示 | **`WorkspaceCubit` State** |
| 注入 fake 以绕过真实 IO 的能力 | 保留——Data 包测试不得启动真实 IO（[拓扑 §3.1](./migration_topology.md)） |

### 6.3 `workspace/workspace_tree_builder.dart`（112 行）

源文件把"目录是否展开"与"是否继续读下一层"耦合在一起，这是最典型的分层违规：

```text
旧：if (expanded || expandedPaths.contains(path)) { readChildren(); }
新：WorkspaceCubit 持有 expandedPaths
    → 派发 WorkspaceNodeExpanded(path)
    → Cubit 调 workspace_repository.loadChildren(path)
    → Repository 调 workspace_client 读目录
```

Repository **不保存** `expandedPaths`（[步骤 25](./migration_tasks.md)）。

### 6.4 `app/shell/ide_shell_controller.dart`（1,467 行）

| 成员 | 归属 |
| --- | --- |
| 当前页面、projectId、threadId | **GoRouter**（[拓扑 §6](./migration_topology.md)：Router 是唯一真源） |
| 布局尺寸、面板可见性、选中项 | **`IdeShellBloc` State** |
| 会话恢复触发 | **`IdeSessionCubit`** → 产出 initial location，由 router redirect 消费 |
| 项目/线程数据读取 | `workspace_repository` / `project_session_repository` |
| 原生菜单命令分发 | `desktop_platform_repository` + typed route |

**`IdeShellBloc` 不得持有 router location**，否则会与 GoRouter 形成双真源
（[ADR-003](./architecture_decisions.md)）。

---

## 7. `presentation/` 的保留边界

[拓扑 §5](./migration_topology.md) 明确 Markdown/render/cache、frame coalescing、scroll controller
留 Presentation。具体到 `features/agent/presentation/` 的 16 个非 widget 文件：

| 文件 | 归属 | 理由 |
| --- | --- | --- |
| `agent_conversation_view_model.dart`（4,190） | **Bloc** | 见[会话状态设计](./agent_conversation_state_design.md) |
| `agent_conversation_ui_state.dart`（1,098） | **Bloc State** | 同上 |
| `agent_markdown_cache.dart` | **Presentation** | 渲染结果缓存，不进 State |
| `agent_timeline_projection.dart` / `_cache.dart` | **Presentation** | domain snapshot → UI slice 的投影 |
| `agent_file_change_projection.dart` / `_cache.dart` | **Presentation** | 同上 |
| `agent_timeline_grouping.dart` | **Presentation** | 视觉分组 |
| `agent_timeline_extent_descriptor.dart` | **Presentation** | 虚拟滚动尺寸 |
| `agent_ui_update_scheduler.dart` | **Presentation** | 帧合并 |
| `composer_document.dart` | **Presentation** | 富文本编辑器文档模型 |
| `model_config_ui_state.dart` | **Bloc State** | 是选择状态，不是渲染中间产物 |
| `agent_plan_revision_drafts.dart` | **Bloc State** | 未提交的草稿是交互状态 |
| `agent_conversation_navigation.dart` | **`lib/app/router/`** | typed route |
| `agent_presentation_l10n.dart` | **`lib/l10n/`** | typed code → ARB 映射 |

> **缓存不进 State 的原因**：`AgentConversationState` 必须是 `Equatable` 且比较廉价。把
> Markdown 渲染结果或投影缓存放进 State，会让每次 `state == state` 比较遍历大量对象，
> 在高频 delta 下直接毁掉性能。缓存由 Widget 持有，以 entryId 为 key，随 Widget 销毁释放。

---

## 8. 裁决汇总

| 目标层 | agent | 其他 feature | 合计 | 占比 |
| --- | ---: | ---: | ---: | ---: |
| Repository（全部包） | 22 | 7 | 29 | 51% |
| Bloc / Cubit | 3 | 5 | 8 | 14% |
| Data 包 | 0 | 1 | 1 | 2% |
| Presentation | 1 | 0 | 1 | 2% |
| **拆分（跨两层）** | 8 | 8 | **16** | **28%** |
| 删除 | 1 | 1 | 2 | 3% |
| **合计** | **35** | **22** | **57** | **100%** |

统计口径：`features/*/application/` 的 57 个 `.dart` 文件（agent 35 + 其他 22），不含 4 个 `.gitkeep`。
拆分文件只计入"拆分"一次，不在其他行重复计数。

**28% 的文件需要拆分**，这是本次迁移最重要的单一数字。它意味着近三分之一的 application 层
文件不能整体搬运——按目录批量迁移一定会把 UI 状态带进 Repository。§5 与 §6 给出了这 16 个
文件的字段级切分；其余 41 个可以整体迁移。

---

## 9. 门禁

本表的裁决必须由机器可判定，写入 `.architecture.yaml`：

1. `packages/*_repository/**` 中 `ChangeNotifier`、`ValueNotifier`、`Listenable` 出现次数 = 0。
2. `packages/*_repository/**` 中字段名匹配 `expanded|selected|isLoading|loadStatus|errorMessage` 的声明 = 0。
3. `packages/*_repository/` 之间 import = 0。
4. `lib/**/bloc/**` 与 `lib/**/cubit/**` 中 `BuildContext`、`GoRouter`、`package:flutter/widgets.dart` import = 0。
5. §2 的 24 处 `ChangeNotifier` 声明在新仓库全部消失，或只出现在 `presentation/widgets/` 的私有类中。
6. §3.4 与 §4 标记为"删除"的 3 个文件路径在新仓库不存在。

第 2 条是启发式，会有误报。允许在 `.architecture.yaml` 中登记例外，**但每个例外必须写明
为什么该字段代表外部数据而非 UI 状态**——这正是本表判定程序第 2 问的书面回答。
