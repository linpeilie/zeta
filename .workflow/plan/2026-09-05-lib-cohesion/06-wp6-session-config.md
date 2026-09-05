# WP-6 · Session config 显式失败与结果契约

> 对应问题：问题 6（缺能力静默成功）。工作包：WP-6。状态：已完成；实现与验收见 §6.7。
> 前置：无，可独立先行修复；后续由 [WP-2](02-wp2-conversation-actions.md) 接入统一命令入口。返回 [开发总入口](00-index.md)。
> §6.1–6.6 保留开发设计与伪代码；具体落地差异与验证证据记录在 §6.7。既有 Provider 能力、权限与生命周期门禁仍有效。


### 6.1 事实与固定目标

设计基线中，`agent_conversation_runtime_controller.dart:1401-1437` 为 `Future<void>`：无 thread 时 return；`sessionConfiguration == null` 时 return；catch 把错误写进 header/composer 后 Future 仍正常完成。`agent_pane_sections.dart:1048` 接给 `agent_pane_composer.dart` 的 void 回调，控件不能知道是否生效。

`AgentConversationBinding.currentRuntime` 每次读取新建一个 context（core binding:259），因此下面比较其 typed `runtimeIdentity`，不能对 context 本身使用 identical，否则正常请求全被误判 stale。

当前 `AgentProviderCapabilities` **没有** `supportsSessionConfiguration` 字段。执行能力以 `AgentProviderBundle.sessionConfiguration` 端口为真源，不能在计划里引用一个不存在的 bool，更不能为了修复凭空加第二套能力位。现有 `AgentSessionConfigurationPort.setSessionConfigOption` 返回 `Future<void>`，其正常完成代表该端口确认请求完成；application 仍需要确认 callback 确实执行、目标未失效。`_runCurrentBundle<T>` 返回 `Future<T?>`，无 runtime 时 callback 可能未执行，不能把 null 当成功。

本 WP 可不等 [WP-3](03-wp3-state-ownership.md)/[WP-2](02-wp2-conversation-actions.md) 独立实施：先修 executor 方法和当前控件回调。WP2 后续只替换调用入口，不改变此 WP 的结果分类与测试。

### 6.2 文件清单与完整签名（拟调整/拟新增）

下表路径相对仓库根；`...` 统一表示 `lib/src/features/agent`。所有新增路径明确标注“拟新增”。

| 文件 | 改动 |
|---|---|
| `lib/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart` | 改 typed 返回；端口缺失抛 UnsupportedError；同 configId 队列；校验 old target；不再吞失败为正常 void |
| `.../application/conversation_slice/agent_conversation_slice_ports.dart` | 增加方法声明 `Future<AgentCommandOutcome> selectSessionConfigOption(String configId, Object value);` |
| `.../presentation/widgets/agent_pane_composer.dart` | 回调改 `Future<AgentCommandOutcome> Function(String configId,Object value)`；配置控件等待、禁重复、显示局部错误 |
| `.../presentation/widgets/agent_pane_sections.dart` | WP6 阶段注入结果翻译回调；WP2 完成后读取 Actions；不得用 Future<void> 桥接 |
| `.../presentation/agent_presentation_l10n.dart` + 两份 ARB（确无可复用 key 才新增） | 分类到本地化文案；禁止显示 exception.toString |
| `test/src/features/agent/presentation/agent_pane_composer_toolbar_test.dart` | 真实配置控件成功/失败/关闭/换代测试 |
| `test/src/features/agent/application/conversation_slice/agent_session_config_command_test.dart`（拟新增） | executor 缺端口、无 runtime、排队、迟到、失败不伪成功 |

```dart
// 拟调整，加入现有 executor port：
Future<AgentCommandOutcome> selectSessionConfigOption(String configId, Object value);

// 拟调整，AgentComposer 的字段：
final Future<AgentCommandOutcome> Function(String configId, Object value)
    onSelectSessionConfigOption;

// 拟新增：只在 RuntimeController 作用域内使用，内存中的同 key 队列。
final Map<String, Future<void>> _sessionConfigTails = {};
final Set<_SessionConfigQueuedCommand> _sessionConfigPending = {};

// 拟新增 presentation helper（WP6 单独阶段）：
Future<AgentCommandOutcome> invokeSessionConfigCommand(
  Future<AgentCommandOutcome> Function() invoke,
);
```

`invokeSessionConfigCommand` 只翻译 executor 抛出的 UnsupportedError/意外异常为 typed failure；不包含状态 owner、重试、持久化或业务权限判断。WP2 的 Actions 边界已承担相同翻译后删除该独立 helper，控件 await Actions 结果即可。

### 6.3 结果矩阵

| 条件 | executor 方法 | UI Actions/控件最终收到 | Provider 调用次数 |
|---|---|---|---|
| 已关闭或发起后目标换代 | `failed(staleTarget)` | 同值，静默结束 | 尚未执行为 0，已发出为 1 |
| 草稿没有可配置 thread | `ignored(notAllowed)` | 同值 | 0 |
| 当前 entry 只读 | `ignored(notAllowed)` | 同值 | 0 |
| thread 存在但 runtime 未附着/callback 未运行 | `failed(providerUnavailable)` | 同值 | 0 |
| 当前 bundle 缺 sessionConfiguration | **抛 UnsupportedError**（在 callback 中） | `failed(unsupported)` | 0 |
| configId 已不在当前 port 的 options，或 kind 不支持该值 | `ignored(notAllowed)` | 同值；最新目录重建控件 | 0 |
| 新旧值等价 | `ignored(unchanged)` | 同值 | 0 |
| port 明确拒绝该能力 | 抛出的 UnsupportedError 透传 | `failed(unsupported)` | 1 |
| port 请求异常，目标仍有效 | `failed(requestFailed)` | 同值；局部错误 | 1 |
| await 完成且目标仍有效 | `succeeded()` | 同值；等既有 provider 事件刷新 currentValue | 1 |

成功只指 Provider 接受/完成配置请求，不伪造新的 currentValue。显示值仍来自 typed options/既有事件，禁止 UI 乐观更新一份独立业务真源。无 thread 是产品阶段不允许，不是“缺 capability”；两者不能混为 unsupported。

### 6.4 executor 与队列伪代码（拟调整）

```dart
Future<AgentCommandOutcome> selectSessionConfigOption(String configId, Object value) {
  if (_disposed) return Future.value(failed(staleTarget));
  final cleanedId = configId.trim();
  if (cleanedId.isEmpty) return Future.value(ignored(notAllowed));
  final targetThread = _selectedThreadId;
  if (targetThread == null || isReadOnly) return Future.value(ignored(notAllowed));
  final issuedScope = currentCommandScope();
  // 必須在排队前拍下，不能轮到旧请求时重新认领新 runtime。
  final issuedRuntimeIdentity = conversationBinding.currentRuntime?.runtimeIdentity;
  if (issuedRuntimeIdentity == null) return Future.value(failed(providerUnavailable));
  final candidate = tryValidateSessionConfigScalar(value); // 拟新增 ({Object value})?。
  if (candidate == null) return Future.value(ignored(notAllowed));
  final frozenValue = candidate.value;

  return _enqueueSessionConfig(cleanedId, () async {
    bool targetMatches({bool beforeExecution = false}) => !_disposed &&
      _selectedThreadId == targetThread &&
      conversationBinding.currentRuntime?.runtimeIdentity == issuedRuntimeIdentity &&
      (beforeExecution ? issuedScope.matchesForExecution(currentCommandScope())
        : issuedScope.matchesForCommit(currentCommandScope()));
    if (!targetMatches(beforeExecution: true)) return failed(staleTarget);
    try {
      final outcome = await _runCurrentBundle<AgentCommandOutcome>((bundle) async {
        if (!targetMatches(beforeExecution: true)) return failed(staleTarget);
        final port = bundle.sessionConfiguration;
        if (port == null) {
          throw UnsupportedError('Session configuration is not supported');
        }
        final options = port.sessionConfigOptions(targetThread);
        final option = findOptionById(options, cleanedId);
        if (option == null || !acceptsTypedValue(option, frozenValue)) {
          return ignored(notAllowed);
        }
        if (sameTypedValue(option.currentValue, frozenValue)) return ignored(unchanged);
        await port.setSessionConfigOption(sessionId: targetThread,
          configId: cleanedId, value: frozenValue);
        if (!targetMatches()) return failed(staleTarget);
        return succeeded();
      });
      if (!targetMatches()) return failed(staleTarget);
      // callback 因 runtime 消失未执行时 outcome=null，不能伪造 succeeded。
      return outcome ?? failed(providerUnavailable);
    } on UnsupportedError {
      if (!targetMatches()) return failed(staleTarget);
      rethrow; // G4 执行层缺能力必须可观测，不被泛型 catch 吞掉。
    } on Object catch (error, stack) {
      if (!targetMatches()) return failed(staleTarget);
      recordNormalizedOperationFailure(operation: 'session_config',
        errorType: error.runtimeType); // 不输出 configId/value/raw error。
      return failed(requestFailed);
    }
  });
}

// 拟新增：同 key 串行；权限、取消、问题回答不进这条队列。
Future<AgentCommandOutcome> _enqueueSessionConfig(
    String configId, Future<AgentCommandOutcome> Function() execute) {
  final item = _SessionConfigQueuedCommand(execute);
  if (_disposed) { item.finish(failed(staleTarget)); return item.result.future; }
  _sessionConfigPending.add(item);
  final previous = _sessionConfigTails[configId] ?? Future<void>.value();
  late final Future<void> tail;
  tail = previous.then((_) async {
    // 关闭时可能已经给调用方返回 stale，排队项绝不能再执行。
    if (item.settled) return;
    final invoke = item.execute!;
    item.started = true;
    item.execute = null; // 队列项不再额外保留 value 捕获。
    try {
      item.finish(_disposed ? failed(staleTarget) : await invoke());
    } on Object catch (error, stack) {
      item.finishError(error, stack); // UnsupportedError 原样给 UI 边界翻译。
    }
  }).whenComplete(() {
    _sessionConfigPending.remove(item);
    if (identical(_sessionConfigTails[configId], tail)) _sessionConfigTails.remove(configId);
  });
  // tail 自身总是正常完成；request 的错误写入 result，不阻断后一项。
  _sessionConfigTails[configId] = tail;
  return item.result.future;
}

final class _SessionConfigQueuedCommand { // 拟新增，controller 文件私有。
  _SessionConfigQueuedCommand(this.execute);
  Future<AgentCommandOutcome> Function()? execute;
  final Completer<AgentCommandOutcome> result = Completer();
  bool started = false;
  bool settled = false;
  void finish(AgentCommandOutcome value) {
    if (settled) return;
    settled = true; execute = null; result.complete(value);
  }
  void finishError(Object error, StackTrace stack) {
    if (settled) return;
    settled = true; execute = null; result.completeError(error, stack);
  }
}

// 拟新增，RuntimeController.dispose 设置 _disposed=true 后、释放 runtime 前调用。
void _closeSessionConfigCommands() {
  for (final item in _sessionConfigPending.toList()) item.finish(failed(staleTarget));
  _sessionConfigPending.clear();
  _sessionConfigTails.clear();
  // 已发 Provider 请求仍可能结束；finish/finishError 幂等，不二次 complete。
  // 不 publish 已关闭 controller，不将队列清空声称为 Provider 请求已取消。
}
```

以上是语义伪代码，`failed/ignored/succeeded` 是现有构造器的缩写；实际实现使用 `AgentCommandOutcome.*`。`tryValidateSessionConfigScalar/findOptionById/acceptsTypedValue/sameTypedValue/recordNormalizedOperationFailure` 是拟新增私有辅助函数。当前 runtime 的 `sessionConfigOptions`（:722）只给 UI 公开非空 select 与 boolean，WP6 保持这个支持面：select 按 `option.values` 的标量 typed id 接受，boolean 仅 bool；string/number/unknown 配置种类返回 notAllowed，不顺手新增控件。`tryValidateSessionConfigScalar` 不抛异常，只对 String/bool/finite num 返回 `({value:value})`，否则返回 null；用标量 `==` 比较新旧值。select 选项 id 可为 String/bool/finite num，但不能放大为任意 JSON。

队列对同 configId 按进入顺序执行，不用后来的值取消已经发出的旧 Provider 请求，避免 UI 的“最新选择”与远端真正接收顺序相反。关闭立即完成所有调用者为 staleTarget，包括排在挂起请求后的 B；未开始项释放 execute 捕获，迟到 A 只做 finally 清理。绝不把 queued Future 放进 JSON 或共享 region。

[WP-2](02-wp2-conversation-actions.md) 接入后，Actions waiter 与 executor queue waiter 是不同责任：前者是用户命令账本/跨动作结果，后者只负责同配置 key 的 Provider 请求顺序。不得再加第三份镜像业务状态；两层关闭都幂等并完成各自等待者。

### 6.5 UI 与可观测失败伪代码（拟调整）

```dart
// WP6 先行阶段；WP2 接入后 Actions runner 替代本 helper。
Future<AgentCommandOutcome> invokeSessionConfigCommand(
  Future<AgentCommandOutcome> Function() invoke,
) async {
  try { return await invoke(); }
  on UnsupportedError { return const AgentCommandOutcome.failed(AgentCommandFailureKind.unsupported); }
  on Object { return const AgentCommandOutcome.failed(AgentCommandFailureKind.requestFailed); }
}

// _SessionConfigOptionControl 改 StatefulWidget，temporary state 只含 pending/error kind。
// 当前设置值继续由 widget.option.currentValue 提供，不存第二份成功值。
Future<void> onChanged(Object value) async {
  if (_pending) return;
  final generation = ++_selectionGeneration;
  final identity = widget.commandContextId; // entry + option id；不含秘密 value。
  setState(() { _pending = true; _failure = null; });
  final outcome = await widget.onSelect(value);
  if (!mounted || generation != _selectionGeneration || identity != widget.commandContextId) return;
  setState(() {
    _pending = false;
    _failure = switch (outcome) {
      AgentCommandFailed(kind: AgentCommandFailureKind.staleTarget) => null,
      AgentCommandFailed(:final kind) => kind,
      _ => null,
    };
  });
}
// didUpdateWidget 发现 contextId/option.id 改变：generation++、pending/error 清空。
// dispose：generation++，不向 application 取消已发出操作。
```

控件等待期间只禁用自己的选择，不禁用整个 Composer 的取消/审批；错误文案由 `AgentCommandFailureKind` 映射到 l10n，采用原值继续显示并允许重试。同 value 的失败可再次尝试；无能力入口的正常渲染仍由 region/当前 options 控制，控件错误是防御性误调用反馈。

### 6.6 独立验收、接入 WP2 与回滚

**单元测试矩阵**：表 6.3 全覆盖；另补 runtime 变化发生在排队期间、Provider await 期间、catch 期间；same configId 的 A/B 请求实际调用顺序一致；不同 configId 可以并行；A 抛 UnsupportedError 不阻塞 B；dispose 前序挂起时 A/B 调用者都立即结算，迟到不再发布；callback 未调用返回 null 必须 providerUnavailable；不把异常原文写入 status.details/日志。

**真实控件测试**：从 Composer 打开现有 session 配置控件并选值，fake Provider 延迟/成功/失败；确认只有该控件 pending、值由事件更新、失败保留旧值、可再次选择、控件换 entry 后旧结果无错误提示。用无 port 的 runtime 把旧控件回调模拟为迟到触发，验证 unsupported，不能仅单测 RuntimeController。

**实施顺序**：改 executor/port 签名和队列→迁移其 fake→改 current UI callback/helper 与本地 pending→补真实 UI→更新 l10n→运行 format/analyze/受影响测试。该 WP 是局部行为修复，默认不要求本地全量；若和 WP2/WP3 一起合并，以重构完整门禁为准。

**接入 WP2 的固定动作**：新增 `AgentSelectSessionConfigOptionCommand`→同一 CommandRequested/runner→调用已修复 executor；UI callback 改 Actions；删除 WP6 standalone helper，保留控件 pending/result行为与 executor 队列。不得保留 UI 既可调 helper/controller 又可调 Actions 的二选一开关。

**验收**：缺端口 executor 抛 UnsupportedError，UI typed failed(unsupported)；无执行不可能 succeeded；失败/关闭/迟到没有悬挂 Future；option currentValue 仍有唯一 owner；没有改 Provider 权限、凭据、持久化或 G5 语义。

**回滚**：WP6 可独立 revert，保留 WP2 时需同步将它从 Actions/executor/测试 API 表中完整恢复到前一版本，不允许仅退方法签名而保留 await 成功的 UI 假设。推荐在 WP2 落地后不单独回滚此安全边界修复；确需回滚按依赖顺序先回滚 WP2 的 session-config 接入，再回滚本提交。无数据迁移。

**与 WP-3 关闭解析一致**：WP-2 获取的 Actions 已捕获 ownerKey+lifetime；Closing/Closed 的旧 UI 得到空终止投影和拒绝动作，不能再次按 BindingKey 把配置请求解析到新 entry。WP-6 自身 executor 队列继续按原 runtimeIdentity/scope 校验，真实 owner 的依赖在 build 时 ref.read 冻结。


### 6.7 实施与验收记录（2026-09-05）

实现提交：待收尾登记。完整证据见 [阶段验收记录](../../fix/2026-09-05-session-config/00-validation.md)。

- [x] executor 与 CommandPort 使用 typed outcome；缺端口/明确拒绝能力的 UnsupportedError 透传，生产 Section helper 翻译。
- [x] 同 configId 队列、入队前冻结目标、执行前目录/只读检查、返回后 runtime/scope 校验与幂等关闭等待者。
- [x] 当前端口缺失时隐藏旧目录；真实旧控件快照迟到调用仍显示 typed unsupported。
- [x] pending 仅限制当前控件；错误图标/tooltip/语义提示保持单行工具栏，原值由 Provider 事件确认，失败可重试。
- [x] 双 Provider/双 thread、同 key 重开、排队/await/catch 换代、关闭时挂起请求与迟到异常均有回归。
- [x] `dart format .`、`flutter analyze`、54 条定向测试、925 条受影响测试和本地化字面量门禁通过。
- [x] AGENTS、开发/架构文档、双语总览/术语/贡献指南与 CHANGELOG 同步；依赖、Provider 包、协议和持久化格式无改动。

实现细节相对伪代码：队列项使用 settled 与可清空 execute 闭包，不额外保留无消费者的 started 标志；控件上下文由当前 controller 生命周期、Provider/thread 上下文与 typed runtime identity 组成。错误提示采用行内图标及 tooltip，避免在现有窄工具栏内新增一行导致溢出。禁用 Provider 会使已发起请求的 scope 失效，因此排队请求返回 stale；禁用后新发起的请求仍按只读返回 notAllowed。

本工作包按 §5.1 的行为修复门禁收尾，不要求本地全量；全量保留在最终整合。未执行真实 CLI 和 Windows/Linux 实机验收。后续执行 WP-1；WP-2 接入时删除 standalone helper，由 Actions runner 承担同一异常翻译，保留 executor 队列和控件结果契约。
