/// 已通过会话 scope 与 generation 校验的 Turn 终态身份。
///
/// 该信号只携带应用组合层所需的白名单字段，不暴露 Provider 原始正文或 payload。
final class AgentTurnTerminalSignal {
  const AgentTurnTerminalSignal({
    required this.providerId,
    required this.threadId,
    required this.turnId,
  });

  final String providerId;
  final String? threadId;
  final String turnId;
}
