# WP-2 · 原断言迁移审计

基线：`2a6d956e`，比对本轮改动过且基线已存在的 Dart 测试文件。使用 Dart analyzer AST 按 `test` / `testWidgets` 声明匹配，提取 `expect` / `expectLater`，仅忽略格式空白和尾逗号；参数化成功/失败的两项测试按原成功名称匹配，另将 G5 和同步展开的两个新标题映射回原标题。

扫描 **281 个原测试声明、1,526 条原断言**，没有删除原测试。**1,497 条原断言保留；29 条调整分布在 18 个测试声明**，逐项如下。263 个测试声明的全部原断言保持。这里计数是 AST 声明，参数化/循环的实际执行数以完整门禁报告为准。

29 条分为：typed 结果迁移 16 条、信封/接线与守卫结构迁移 8 条、同步命令账本时序 3 条、G5 保守权限修正 2 条。没有把它们包装成“断言零修改”的纯搬迁；保存、回滚、运行中禁用、原线程不变、lease/owner 生命周期等业务不变量仍由原断言和全量回归验证。

| 测试与文件 | 调整断言数 | 原因与保留边界 |
|---|---:|---|
| [ide_shell_controller_test.dart](../../../test/src/app/ide_shell_controller_test.dart)：fork 将 Provider 新建的 thread 登记并选中，后续操作只作用于新 thread | 1 | 读取 typed result.createdSession.id；新增 activated=true，原新旧 Binding 断言保留 |
| [agent_conversation_model_selection_controller_test.dart](../../../test/src/features/agent/application/agent_conversation_model_selection_controller_test.dart)：requires explicit atomic resolution for xhigh and Fast | 4 | bool → succeeded / ignored(unchanged, notAllowed, requiresConfirmation, superseded) / failed；保存与回滚字段断言保留 |
| [agent_conversation_model_selection_controller_test.dart](../../../test/src/features/agent/application/agent_conversation_model_selection_controller_test.dart)：rolls back a failed save and retries the full snapshot | 2 | bool → succeeded / ignored(unchanged, notAllowed, requiresConfirmation, superseded) / failed；保存与回滚字段断言保留 |
| [agent_conversation_model_selection_controller_test.dart](../../../test/src/features/agent/application/agent_conversation_model_selection_controller_test.dart)：coalesces rapid changes and persists the latest snapshot last | 3 | bool → succeeded / ignored(unchanged, notAllowed, requiresConfirmation, superseded) / failed；保存与回滚字段断言保留 |
| [agent_conversation_model_selection_controller_test.dart](../../../test/src/features/agent/application/agent_conversation_model_selection_controller_test.dart)：selecting the current model does not persist again | 1 | bool → succeeded / ignored(unchanged, notAllowed, requiresConfirmation, superseded) / failed；保存与回滚字段断言保留 |
| [agent_conversation_model_selection_controller_test.dart](../../../test/src/features/agent/application/agent_conversation_model_selection_controller_test.dart)：rejects a disabled model without changing or persisting | 1 | bool → succeeded / ignored(unchanged, notAllowed, requiresConfirmation, superseded) / failed；保存与回滚字段断言保留 |
| [agent_plan_execution_handoff_controller_test.dart](../../../test/src/features/agent/application/agent_plan_execution_handoff_controller_test.dart)：falls back to first executable option when catalog default is planningOnly | 2 | G5 行为修正：无可执行 catalog 默认时保持 null；新增用户显式选择后的 userOverride 断言 |
| [agent_conversation_slice_reducer_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_conversation_slice_reducer_test.dart)：命令登记在途身份并产出 effect，但不直接改 region | 1 | typed command envelope 替代各命令的重复 effect 壳；scope / epoch / region 原预期保留 |
| [agent_conversation_slice_reducer_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_conversation_slice_reducer_test.dart)：展开态切换只发 effect，不占用在途身份 | 3 | 同步命令同样先登记；runner 当栈结算另有测试，不再断言 reducer 不登记 |
| [agent_conversation_slice_store_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_conversation_slice_store_test.dart)：命令带上发起时的作用域快照 | 1 | typed command envelope 替代各命令的重复 effect 壳；scope / epoch / region 原预期保留 |
| [agent_conversation_slice_store_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_conversation_slice_store_test.dart)：作用域变化后发起的命令带的是新快照 | 3 | typed command envelope 替代各命令的重复 effect 壳；scope / epoch / region 原预期保留 |
| [agent_conversation_slice_store_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_conversation_slice_store_test.dart)：dispose 后拒绝一切写入 | 1 | 关闭后 Future 完成 staleTarget，替代同步抛 StateError；不执行 effect 的断言保留 |
| [agent_conversation_slice_store_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_conversation_slice_store_test.dart)：dispose 其一不影响另一个 | 1 | typed command envelope 替代各命令的重复 effect 壳；scope / epoch / region 原预期保留 |
| [agent_session_config_command_test.dart](../../../test/src/features/agent/application/conversation_slice/agent_session_config_command_test.dart)：missing port throws at executor and becomes unsupported at UI boundary | 1 | 删除 presentation 翻译器；通过真实 owner Actions 得到同样的 unsupported |
| [agent_conversation_slice_scope_guard_test.dart](../../../test/src/features/agent/architecture/agent_conversation_slice_scope_guard_test.dart)：命令 effect 必须携带作用域快照 | 1 | typed command envelope 替代各命令的重复 effect 壳；scope / epoch / region 原预期保留 |
| [agent_conversation_view_model_test.dart](../../../test/src/features/agent/presentation/agent_conversation_view_model_test.dart)：new session freezes dormant permission before runtime creation | 1 | 成功由 null → succeeded；冻结的权限快照、次数、hint 断言保留 |
| [agent_conversation_view_model_test.dart](../../../test/src/features/agent/presentation/agent_conversation_view_model_test.dart)：history resume freezes dormant permission before runtime creation | 1 | 成功由 null → succeeded；冻结的权限快照、次数、hint 断言保留 |
| [agent_pane_composer_toolbar_test.dart](../../../test/src/features/agent/presentation/agent_pane_composer_toolbar_test.dart)：permission policy is disabled while a turn is running | 1 | 运行中拒绝改为 ignored(notAllowed)；按钮禁用和零 apply 断言保留 |

新增回归另见 [验收记录](00-validation.md)：真实按钮两 Canvas/晋升/关闭/旧 epoch、四类审批、冻结参数、逐 waiter 结果、fork 产物与编辑对话框的新 entry 失败、异常结算及 AST 负例。未调整 packages 测试或放宽跨层/权限门禁。
