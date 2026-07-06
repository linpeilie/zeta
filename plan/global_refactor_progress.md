# Zeta Flutter 全局重构进度跟踪

关联规划文档：

- [global_refactor_plan.md](global_refactor_plan.md)
- [task_1_module_architecture.md](task_1_module_architecture.md)

更新时间：

- 2026-07-07

状态说明：

- `未开始`：任务尚未启动
- `进行中`：任务已开始但未满足验收标准
- `已完成`：任务已满足验收标准
- `阻塞`：任务因外部依赖或前置条件无法继续

总体进度：

- 已完成任务：`10 / 10`
- 当前阶段：T1-T10 已完成，全局重构计划已完成
- 当前重点：维护新的 feature 测试结构与完整回归基线

---

## 任务总览

| ID | 任务名称 | 状态 | 完成时间 | 验收结果 | 备注 |
| --- | --- | --- | --- | --- | --- |
| T1 | 建立新模块骨架与依赖规则 | 已完成 | 2026-07-06 | 通过 | 已建立骨架目录、迁移映射与依赖规则文档 |
| T2 | 拆分 Agent 领域模型 | 已完成 | 2026-07-06 | 通过 | 已拆分至 `lib/src/features/agent/domain/`，并保留旧路径兼容导出 |
| T3 | 拆分 Workspace 与文件树模块 | 已完成 | 2026-07-06 | 通过 | 已拆分目录扫描、领域节点与 TreeView 映射，并补充独立测试 |
| T4 | 下沉 IDE 会话恢复与持久化 | 已完成 | 2026-07-06 | 通过 | 已新增恢复/保存协调器、快照构建器与独立应用层测试 |
| T5 | 拆分 Codex App Server 基础设施层 | 已完成 | 2026-07-06 | 通过 | 已拆为 provider 协调入口、app_server client、notification/approval/model mapper 与 history reader/jsonl parser |
| T6 | 收敛 Project Threads 模块 | 已完成 | 2026-07-06 | 通过 | 已拆为 feature 级 controller、session snapshot codec 与独立测试入口 |
| T7 | 拆分 Agent Conversation 应用层 | 已完成 | 2026-07-06 | 通过 | 已拆为 timeline store、model selection controller 与 UI signals |
| T8 | 拆分 Agent Pane 视图层 | 已完成 | 2026-07-06 | 通过 | 已迁入 `features/agent/presentation/` 并拆为页面壳 + 组件树 |
| T9 | 收薄 IDE Shell 页面 | 已完成 | 2026-07-07 | 通过 | 已新增 `IdeShellController`，将 `IdeHome` 收缩为 shell 级容器 |
| T10 | 重整测试结构并建立回归基线 | 已完成 | 2026-07-07 | 通过 | 已拆分根级 widget test 并按 feature/app 对齐测试目录 |

---

## 当前状态明细

### T1. 建立新模块骨架与依赖规则

- 状态：`已完成`
- Definition of Done：
- [x] 新目录结构已创建
- [x] 每个现有模块都有明确迁移归属
- [x] 已形成书面依赖规则

### T2. 拆分 Agent 领域模型

- 状态：`已完成`
- Definition of Done：
- [x] `agent_models.dart` 不再是单一超大模型文件
- [x] provider、thread、session、history、message、permission、model、event 已拆分
- [x] 领域模型拆分后相关测试保持通过
- 验收备注：
- 新增 `lib/src/features/agent/domain/agent_*.dart` 细分模型文件，并建立 feature 级 barrel
- 旧 `lib/src/domain/agent/agent_models.dart` 已收缩为兼容导出层，降低后续迁移风险
- `flutter analyze` 通过；排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后，其余测试通过

### T3. 拆分 Workspace 与文件树模块

- 状态：`已完成`
- Definition of Done：
- [x] 目录扫描逻辑与 TreeView 表示分离
- [x] `data` 层不再依赖 Flutter UI 和主题
- [x] 文件树逻辑具备独立测试入口
- 验收备注：
- 新增 `features/workspace/domain` 下的领域节点与目录过滤规则
- 新增 `features/workspace/application/workspace_tree_builder.dart`，将目录扫描与排序下沉到应用层
- 新增 `features/workspace/presentation` 下的 `FileTreePane`、`FileNodeData` 与 `TreeView` 映射器
- 旧 `data/file_system/*` 与旧 `ui/features/ide/views/file_tree_pane.dart` 已收缩为兼容导出层
- 新增 `test/src/features/workspace/application/workspace_tree_builder_test.dart`，覆盖忽略规则、排序与懒加载
- `flutter analyze` 通过；排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后，其余测试通过

### T4. 下沉 IDE 会话恢复与持久化

- 状态：`已完成`
- Definition of Done：
- [x] `IdeHome` 不再直接组装 `IdeSessionState`
- [x] restore/save 协调逻辑迁入 `ide_session/application`
- [x] 会话恢复相关行为具备独立测试
- 验收备注：
- 新增 `features/ide_session/domain/ide_session_state.dart` 作为会话快照领域模型
- 新增 `features/ide_session/data/ide_session_store.dart` 作为持久化边界
- 新增 `features/ide_session/application/ide_session_persistence_coordinator.dart`、`ide_session_state_builder.dart` 与 `ide_session_restore_result.dart`
- `IdeHome` 改为消费应用层恢复结果与保存协调器，不再持有 restore token、save timer 与快照组装逻辑
- 旧 `data/session/*` 已收缩为兼容导出层，降低同轮迁移风险
- 新增 `test/src/features/ide_session/application/ide_session_persistence_coordinator_test.dart`，覆盖快照组装、无效路径清理、恢复期间延迟保存与取消慢恢复
- `flutter analyze` 通过；排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后，其余测试通过

### T5. 拆分 Codex App Server 基础设施层

- 状态：`已完成`
- Definition of Done：
- [x] `codex_app_server_provider.dart` 被拆为多个职责明确的模块
- [x] JSON-RPC 请求、通知映射、审批映射、历史解析彼此分离
- [x] 原始 `Map<String, Object?>` 不跨越 data 层边界
- 验收备注：
- 新增 `features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart` 作为精简后的 provider 协调入口
- 新增 `codex_app_server_client.dart`、`codex_notification_mapper.dart`、`codex_approval_mapper.dart` 与 `codex_model_list_mapper.dart`，将 JSON-RPC 请求与事件映射从 provider 主文件中抽离
- 新增 `features/agent/data/datasources/local_history/codex_thread_history_reader.dart` 与 `codex_jsonl_history_parser.dart`，把 `thread/read` 解析和本地 session jsonl 恢复职责拆开
- 旧 `lib/src/data/agent/codex_app_server_provider.dart` 已收缩为兼容导出层，避免同轮重构引发大面积 import 变更
- `flutter analyze` 通过；排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后，其余测试通过

### T6. 收敛 Project Threads 模块

- 状态：`已完成`
- Definition of Done：
- [x] 线程分页、展开态、选择态边界清晰
- [x] 项目线程缓存和恢复策略不再由页面直接协调
- [x] 模块具备独立测试入口
- 验收备注：
- 新增 `features/project_threads/domain` 下的 `ProjectThreadListState` 与 `ProjectThreadsSessionSnapshot`
- 新增 `features/project_threads/application/project_threads_controller.dart` 与 `project_threads_session_snapshot_codec.dart`，将分页、恢复快照和缓存策略从页面层收拢到模块应用层
- 新增 `features/project_threads/presentation/project_threads_view_model.dart` 作为纯列表状态容器，页面不再直接编排 thread 恢复映射
- `IdeHome` 改为通过 Project Threads controller 恢复/保存线程快照，`buildIdeSessionState` 也改为接收模块快照对象
- 旧 `ui/features/ide/view_models/project_threads_view_model.dart` 已收缩为兼容导出层，降低同轮迁移风险
- 新增 `test/src/features/project_threads/application/project_threads_controller_test.dart`，覆盖恢复、分页、失败保留缓存与快照构建
- `flutter analyze` 通过；排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后，其余测试通过

### T7. 拆分 Agent Conversation 应用层

- 状态：`已完成`
- Definition of Done：
- [x] 不再存在单个 ViewModel 同时承载 session、timeline、selection、tick 管理
- [x] 实时事件处理、token 汇总、权限交互等职责已拆开
- [x] 拆分后仍能保持现有主要交互行为
- 验收备注：
- 新增 `features/agent/application/agent_conversation_timeline_store.dart`，将时间线聚合、turn 分组、历史分页、token 汇总和展开态从超大 ViewModel 中抽离
- 新增 `features/agent/application/agent_conversation_model_selection_controller.dart` 与 `agent_conversation_ui_signals.dart`，分别承接模型列表/选择持久化以及 header/history/composer/live turn 的局部刷新节流
- 新增 `features/agent/presentation/agent_conversation_view_model.dart` 作为收缩后的 provider/session 协调入口，旧 `ui/features/ide/view_models/agent_conversation_view_model.dart` 保留兼容导出
- 新增 `test/src/features/agent/application/agent_conversation_timeline_store_test.dart` 与 `agent_conversation_model_selection_controller_test.dart`，补齐 feature 级应用层测试入口
- `flutter analyze` 通过；`flutter test` 在排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后通过

### T8. 拆分 Agent Pane 视图层

- 状态：`已完成`
- Definition of Done：
- [x] `AgentPane` 仅保留布局与组合职责
- [x] Markdown、Diff、命令组、文件编辑组、审批卡片等已拆分独立组件
- [x] 展开/收起状态归属统一
- 验收备注：
- `AgentPane` 与 `agent_timeline_grouping.dart` 已迁入 `lib/src/features/agent/presentation/`，旧 `ui/features/ide/views/*` 路径收缩为兼容导出层
- 新增 `widgets/agent_pane_*.dart` 组件文件，按 header、composer、timeline section、message cards、tool/history cards 与样式辅助函数拆分原超大视图文件
- `AgentConversationViewModel` / `AgentConversationUiSignals` 新增 expansion 刷新信号，plan、command group、tool call 与 file edit item 的展开状态统一回到 ViewModel，不再与 Widget 本地状态重复持有
- 新增/更新 `agent_pane_pr3_test.dart` 与 `agent_conversation_view_model_test.dart`，验证计划卡片和文件详情展开仍不会误触发 history version 刷新

### T9. 收薄 IDE Shell 页面

- 状态：`已完成`
- Definition of Done：
- [x] `IdeHome` 只负责三栏布局与事件转发
- [x] 项目加载、会话恢复、Agent 联动等逻辑迁出页面层
- [x] 页面结构显著简化
- 验收备注：
- 新增 `lib/src/app/shell/ide_shell_controller.dart`，集中承接项目打开、文件树状态、会话恢复/保存、Agent thread 映射与 Project Threads 同步
- `IdeHome` 不再直接扫描目录、构建会话快照或维护 Agent thread 恢复策略，只保留 split layout、原生菜单入口注册、三栏组件组合和状态提示
- 更新 `widget_test.dart` 中仓库文件树断言，使其验证 offstage 文件树内容，避免当前仓库顶层条目增多时误判首屏可见性
- `flutter analyze` 通过；排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后，其余测试通过

### T10. 重整测试结构并建立回归基线

- 状态：`已完成`
- Definition of Done：
- [x] 测试目录与 feature 结构一致
- [x] 关键行为具备模块级测试
- [x] 超大集成型测试职责被合理拆分
- 验收备注：
- 删除根级 `test/widget_test.dart`，将原 31 个 widget 回归用例拆分到 `test/src/app/`、`test/src/features/workspace/`、`test/src/features/project_threads/`、`test/src/features/agent/` 与 `test/src/features/ide_session/`
- 新增 `test/src/testing/ide_test_harness.dart`，集中复用 fake provider、内存 session store、文件树 finder 和 Agent timeline 辅助函数
- 旧 `test/src/data/*`、`test/src/domain/*` 与 `test/src/ui/features/ide/*` 测试已迁移到对应 feature 层级
- `flutter analyze` 通过；完整 `flutter test` 通过，当前回归基线为 126 个测试

---

## 变更记录

### 2026-07-07

- 完成 T10：按 app 与 feature 结构重整测试目录，移除根级超大 `widget_test.dart`
- 将 IDE shell、Workspace 文件树、Project Threads、Agent Conversation、IDE Session 恢复等 widget 回归用例拆为独立测试文件
- 新增共享测试 harness，集中维护 fake agent provider、内存 session store 和常用 finder/helper，减少拆分后重复代码
- 将旧 `data/domain/ui` 测试路径迁移到 `features/agent`、`features/ide_session` 等目标结构下
- 验证通过 `flutter analyze` 与完整 `flutter test`，建立 126 个测试的回归基线
- 总体进度更新为 `10 / 10`
- 完成 T9：新增 `app/shell/IdeShellController`，将项目打开、文件树交互、会话恢复/保存和 Agent thread 同步从 `IdeHome` 迁出
- `IdeHome` 收缩为三栏布局与事件转发容器，继续负责原生菜单打开项目入口和简单状态提示
- 调整仓库文件树 widget 测试断言，避免受顶层文件数量和首屏滚动位置影响
- 验证通过 `flutter analyze`；`flutter test` 在排除既有 `json_rpc_stdio_transport_test.dart` 环境依赖后通过
- 总体进度更新为 `9 / 10`

### 2026-07-06

- 初始化进度跟踪文档
- 建立 10 个任务的统一状态位
- 完成 T1：建立 `app / core / shared / features/*` 目标骨架
- 新增 `task_1_module_architecture.md`，明确迁移归属与依赖规则
- 总体进度更新为 `1 / 10`
- 完成 T2：将 Agent 领域模型拆分到 `lib/src/features/agent/domain/`
- 保留旧 `agent_models.dart` 作为兼容导出，避免同轮重构大面积改 import
- 验证通过 `flutter analyze` 与除 `json_rpc_stdio_transport_test.dart` 外的测试集
- 总体进度更新为 `2 / 10`
- 完成 T3：将 Workspace 文件树拆分为 domain/application/presentation 三层
- 目录扫描逻辑不再直接依赖 `TreeView`、Flutter 图标或主题色
- 新增文件树构建独立测试，验证忽略规则、排序与按需展开行为
- 总体进度更新为 `3 / 10`
- 完成 T4：将 IDE 会话恢复与持久化逻辑下沉到 `features/ide_session`
- `IdeHome` 不再直接维护恢复 token、延迟保存 timer 或快照组装逻辑
- 新增会话恢复协调器与独立应用层测试，覆盖清洗无效路径和恢复期保存时序
- 总体进度更新为 `4 / 10`
- 完成 T5：将 Codex App Server 基础设施层拆为 provider 协调入口、app server client、notification/approval/model mapper 与 local history reader/parser
- `codex_app_server_provider.dart` 不再同时承载 JSON-RPC 请求、通知映射、审批映射与 jsonl 历史恢复逻辑
- 旧 provider 路径保留兼容导出，降低后续 Task 6/7 继续迁移的阻力
- 验证通过 `flutter analyze` 与除 `json_rpc_stdio_transport_test.dart` 外的测试集
- 总体进度更新为 `5 / 10`
- 完成 T6：将 Project Threads 收敛为 feature 级 controller、view model 与 session snapshot 模块
- `IdeHome` 不再直接拼装项目 thread 展开态、缓存线程列表和选中 thread 映射
- 新增 Project Threads 独立应用层测试，并把原 view model 级测试迁到 feature 结构下
- 验证通过 `flutter analyze` 与除 `json_rpc_stdio_transport_test.dart` 外的测试集
- 总体进度更新为 `6 / 10`
- 完成 T7：将 Agent Conversation 拆为 timeline store、模型选择控制器与 UI signals 三个 feature 级应用模块
- `AgentConversationViewModel` 收缩为 provider/session 协调入口，不再同时承载 turn 聚合、token 汇总与局部刷新节流
- 保留旧 ViewModel 路径兼容导出，并新增 Agent Conversation 应用层独立测试
- 验证通过 `flutter analyze` 与除 `json_rpc_stdio_transport_test.dart` 外的测试集
- 总体进度更新为 `7 / 10`
- 完成 T8：将 Agent Pane 迁入 `features/agent/presentation/`，拆为页面壳、timeline 分段、header/composer 与独立卡片组件文件
- 统一 plan、command group、tool call 和 file edit item 的展开状态归属，新增 expansion UI signal，避免与 Widget 本地状态双份维护
- 保留旧 `ui/features/ide/views/agent_pane.dart` 与 `agent_timeline_grouping.dart` 兼容导出，并补充 plan/file edit 展开回归测试
- 验证通过 `flutter analyze`；`flutter test` 仍仅受既有 `json_rpc_stdio_transport_test.dart` 环境依赖影响，其余测试通过
- 总体进度更新为 `8 / 10`

---

## 后续更新约定

- 每当一个任务开始执行，先将对应状态改为 `进行中`
- 每当一个任务满足验收标准，将对应状态改为 `已完成`
- 若任务受阻，将状态改为 `阻塞`，并在备注中写明阻塞原因
- 每次更新后同步修改：
- `更新时间`
- `已完成任务数量`
- `当前重点`
- `变更记录`
