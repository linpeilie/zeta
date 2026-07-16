import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 单条 thread/draft 运行时对外暴露的轻量快照。
///
/// Shell 与项目线程列表只依赖这组稳定字段来同步选中、运行中与等待态，
/// 不直接读取完整时间线或 provider 原始事件。
@immutable
class AgentConversationThreadSnapshot {
  const AgentConversationThreadSnapshot({
    required this.sessionId,
    required this.providerId,
    required this.threadTitle,
    required this.isTurnRunning,
    required this.runtimeStatus,
    required this.waitingOnApproval,
    required this.waitingOnUserInput,
  });

  final String? sessionId;
  final String providerId;
  final String threadTitle;
  final bool isTurnRunning;
  final AgentThreadRuntimeStatus? runtimeStatus;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;

  @override
  bool operator ==(Object other) {
    return other is AgentConversationThreadSnapshot &&
        other.sessionId == sessionId &&
        other.providerId == providerId &&
        other.threadTitle == threadTitle &&
        other.isTurnRunning == isTurnRunning &&
        other.runtimeStatus == runtimeStatus &&
        other.waitingOnApproval == waitingOnApproval &&
        other.waitingOnUserInput == waitingOnUserInput;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    providerId,
    threadTitle,
    isTurnRunning,
    runtimeStatus,
    waitingOnApproval,
    waitingOnUserInput,
  );
}
