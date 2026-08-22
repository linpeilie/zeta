/// 一次用户命令的结果。
///
/// 存在的理由：Agent 的命令 port 历来用 `Future<void>` + 自己的通道表达失败
/// （回滚乐观状态、`_markError`、`AgentErrorEvent`、返回 `null`）。**"Future 正常
/// 结束"从来不等于"命令成功"**，调用方不能据此推断结果——切片就因为这么推断过，
/// 把真实失败记成了成功。
///
/// 纯 Dart：application 层不得 import Flutter（目标架构 §12.5）。
sealed class AgentCommandOutcome {
  const AgentCommandOutcome();

  /// 命令完成。
  const factory AgentCommandOutcome.succeeded() = AgentCommandSucceeded;

  /// 命令没做任何事，也没有可展示的错误。
  ///
  /// 例如输入为空、当前状态不允许、值没有变化。这些**不是失败**：让它们走失败
  /// 分支会在正常操作里弹出错误提示。
  const factory AgentCommandOutcome.ignored(AgentCommandIgnoreReason reason) =
      AgentCommandIgnored;

  /// 命令失败，且用户应当感知。
  const factory AgentCommandOutcome.failed(
    AgentCommandFailureKind kind, {
    String? diagnostic,
  }) = AgentCommandFailed;

  /// 是否成功完成。
  bool get isSuccess => this is AgentCommandSucceeded;

  /// 是否需要向用户报错。
  bool get isFailure => this is AgentCommandFailed;
}

/// 命令成功。
final class AgentCommandSucceeded extends AgentCommandOutcome {
  const AgentCommandSucceeded();

  @override
  String toString() => 'AgentCommandSucceeded()';
}

/// 命令被忽略的原因。
enum AgentCommandIgnoreReason {
  /// 输入为空或无效（空文本、空名字）。
  emptyInput,

  /// 当前状态或能力不允许（只读、能力缺失、没有可操作对象）。
  notAllowed,

  /// 值没有变化，无需执行。
  unchanged,
}

/// 命令没做任何事。
final class AgentCommandIgnored extends AgentCommandOutcome {
  const AgentCommandIgnored(this.reason);

  final AgentCommandIgnoreReason reason;

  @override
  String toString() => 'AgentCommandIgnored($reason)';
}

/// 命令失败的分类。
///
/// **只有分类，没有文案**：用户可见文字由 presentation 按 kind 从文本目录取，
/// 保证可本地化，也避免把原始错误文本当成 UI 内容（G7）。
enum AgentCommandFailureKind {
  /// Provider 进程拉不起来或已断开。
  providerUnavailable,

  /// 当前 Provider 不支持该能力。
  unsupported,

  /// 请求发出去了但失败了。
  requestFailed,

  /// 本地状态校验没过（例如迟到的目标已经不存在）。
  staleTarget,
}

/// 命令失败。
final class AgentCommandFailed extends AgentCommandOutcome {
  const AgentCommandFailed(this.kind, {this.diagnostic});

  final AgentCommandFailureKind kind;

  /// **只用于日志与诊断，不得进入 UI 文案。**
  ///
  /// 原始错误文本可能包含路径、命令行或 Provider 返回的原文。
  final String? diagnostic;

  @override
  String toString() => 'AgentCommandFailed($kind)';
}
