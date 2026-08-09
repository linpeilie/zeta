# 07 · Binding 重构执行记录

## 实现结果

- 新增 `AgentConversationBinding`、`AgentConversationBindingManager`、
  `AgentProviderGlobalRuntime` 与 application 层 settings 端口。
- Workspace entry 改持 Binding lease，共享同一个 settings controller；application 不再
  import UI controller。
- Registry 增加 identity 条件失效与 dispose barrier，删除公开 touch/pin/snapshot 和独立
  IdleReaper；session 不再覆盖 global permission identity。
- ViewModel 的生产路径只从 Binding 取得 session runtime，首次提交才 `beginTurn()`；历史和
  thread 操作走 global，短 session RPC 走 `runCurrent()`。
- Binding 内权限支持 dormant next-send、runtime detach/migration、旧 generation 丢弃和只重试
  持久化；Project Threads 优先使用已存在 Binding 快照。

## 自动化验证

- Binding：严格惰性、单实例、draft 晋升、两 thread 事件/权限隔离、turn/RPC 活跃保护、
  10 分钟 TTL、single-flight sweep、配置失效、global 不回收和晋升冲突。
- Registry：并发 acquire、identity ABA、dispose/acquire 屏障和 global/session 隔离。
- 架构守卫：factory 唯一调用者、application 零 UI 依赖、ViewModel 无 lease/scope/pin、
  Timer 只属于 BindingManager。

2026-08-09 最终结果：

- `dart format .`：通过。
- `flutter analyze`：通过，0 issue。
- Binding、Registry、Workspace、权限、ViewModel、Project Threads、Settings、Shell 与架构
  守卫定向回归：201 个测试通过。
- `flutter test`：全量运行完成，但被现有基线阻塞；`platform 3.0.0` 在当前 Dart SDK 下引用
  已移除的 `Platform.packageRoot`，相关 Widget 测试无法编译；另有字体选择 Widget 测试因
  持续动画导致 `pumpAndSettle` 超时。两项均可在未触及本重构的单文件测试中独立复现，
  本次不扩展范围修改依赖或 UI 动画。

## 真实 CLI 验收

2026-08-09 已在 macOS x86_64、Grok `1.0.0` 上执行
`tool/smoke_grok_acp.py`，结果 4/4 通过：

- 两个独立 Grok CLI 进程并发建立会话并各自完成一轮。
- 两个会话的终态均正常返回，未触发权限放行。
- 关闭其中一个旧进程后，新进程成功加载同一逻辑会话并继续完成一轮。

记录未包含 prompt、回复正文、原始 payload、session/turn ID、CLI 私有路径、凭据或 stderr
原文。
