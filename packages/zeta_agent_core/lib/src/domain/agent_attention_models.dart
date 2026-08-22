/// Agent 运行时需要用户注意的原因。
enum AgentAttentionKind {
  turnCompleted,
  turnFailed,
  turnInterrupted,
  permissionRequired,
  questionRequired,
  planApprovalRequired,
  planExecutionRequired,
}

/// 一条提醒信号是新产生，还是已经失效。
enum AgentAttentionPhase { raised, resolved }

/// Provider 中立的用户注意力信号。
///
/// 这里只携带定位与去重所需的标识，不携带命令、文件路径、问题答案、错误原文
/// 或 Provider raw payload，避免后续系统通知意外泄露敏感内容。
final class AgentAttentionSignal {
  const AgentAttentionSignal({
    required this.kind,
    required this.phase,
    required this.sourceId,
    this.threadId,
    this.turnId,
  });

  final AgentAttentionKind kind;
  final AgentAttentionPhase phase;

  /// turnId 或服务端 requestId，用于幂等去重和精确清除。
  final String sourceId;
  final String? threadId;
  final String? turnId;

  String identityFor(String providerId, String resolvedThreadId) =>
      '${kind.name}:$providerId:$resolvedThreadId:$sourceId';

  AgentAttentionSignal withThreadId(String value) {
    if (threadId == value) {
      return this;
    }
    return AgentAttentionSignal(
      kind: kind,
      phase: phase,
      sourceId: sourceId,
      threadId: value,
      turnId: turnId,
    );
  }
}

/// 常驻 Agent workspace 为提醒信号补齐的安全展示上下文。
final class AgentWorkspaceAttention {
  const AgentWorkspaceAttention({
    required this.signal,
    required this.providerId,
    required this.threadId,
    required this.projectPath,
  });

  final AgentAttentionSignal signal;
  final String providerId;
  final String threadId;
  final String projectPath;

  String get identity => signal.identityFor(providerId, threadId);
}
