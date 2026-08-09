# 08 · Binding 端口与权限收敛

## 动机

Binding 重构完成后仍保留了两条兼容路径：Bundle/RuntimePort 可以取回原始
`AgentProvider`，权限状态则仍以跨 provider/runtime/thread 注册表建模。前者让 ViewModel
可能绕过能力端口，后者重复了 Binding 已经提供的会话唯一性和生命周期边界。

## 调整结果

本记录取代 02、05、06、07 中关于 `AgentPermissionStateStore`、active runtime map 和
跨 controller runtime broadcast 的目标态描述；历史执行事实保留，不覆盖原记录。

- 删除 `AgentProviderBundle.provider`、`AgentRuntimePort.provider` 与 Binding runtime context
  的原始 Provider getter；模型刷新、用量、Project Threads 与 ViewModel 改走中立 bundle
  端口。
- 删除 `AgentPermissionStateStore`，改为每个 Binding 独占一个不可变
  `AgentConversationPermissionState`。状态只保存本会话的 default、session、pending turn、
  runtime selection、scope/warning、持久化失败与精确 runtime identity。
- runtime scope 只影响拥有该 CLI runtime 的 Binding；不再遍历 thread map 或向其他
  controller 广播。精确 identity 只负责拒绝旧 generation 的迟到 apply。
- Binding Manager 继续禁止真实 thread 原地改绑；draft 晋升保留已有权限，兼容入口意外
  改绑时丢弃旧会话状态。runtime 回收时只清除 runtime-only 状态。
- 新增架构守卫，禁止 Bundle/Binding 向 ViewModel 重新暴露原始 Provider，并禁止权限状态
  重新引入跨会话注册表。

## 验证记录

2026-08-09 最终结果：

- `dart format .`：通过，439 个文件均已符合格式。
- `flutter analyze`：通过，0 issue。
- Binding、Registry、权限状态/协调器、ViewModel、Project Threads、Management、
  Usage、Settings、架构守卫与 pending interaction 定向回归：234 个测试通过。
- `flutter test`：全量完成，`+1313 ~1 -19`。影响路径的用例均通过；19 个失败
  仍属于前序记录的环境/基线问题，包括 `platform 3.0.0` 在当前 Dart SDK 下
  引用已移除的 `Platform.packageRoot`、字体资源与既有 Widget/日志断言。
- pending interaction Widget 用例已改为首次提交创建 session runtime 后再注入
  Provider 交互事件，并显式发送 turn 终态；6 个用例全部通过。

## 真实 CLI 验收

2026-08-09 已在 macOS x86_64、Grok `1.0.0` 上执行真实 ACP 冒烟，4/4 通过：

- 两个独立 CLI 进程分别建立会话并完成回合。
- 其中一个进程回收后，新进程成功恢复同一逻辑会话并继续完成回合。

记录未包含 prompt、回复正文、原始 payload、session/turn ID、CLI 私有路径、凭据或
stderr 原文。
