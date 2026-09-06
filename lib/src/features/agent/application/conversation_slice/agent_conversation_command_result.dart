import 'package:zeta_agent_core/zeta_agent_core.dart';
import '../agent_command_outcome.dart';

/// 已创建与已激活分别表达；产物仅随本次 Future 返回，不进入切片。
final class AgentForkCommandOutcome {
  const AgentForkCommandOutcome._(
    this.outcome,
    this.createdSession,
    this.activated,
  );
  factory AgentForkCommandOutcome.completed(AgentSession session) =>
      AgentForkCommandOutcome._(
        const AgentCommandOutcome.succeeded(),
        session,
        true,
      );
  factory AgentForkCommandOutcome.failed(
    AgentCommandFailureKind kind, {
    AgentSession? createdSession,
  }) => AgentForkCommandOutcome._(
    AgentCommandOutcome.failed(kind),
    createdSession,
    false,
  );
  factory AgentForkCommandOutcome.ignored(AgentCommandIgnoreReason reason) =>
      AgentForkCommandOutcome._(
        AgentCommandOutcome.ignored(reason),
        null,
        false,
      );
  factory AgentForkCommandOutcome.fromRegularFailure(
    AgentCommandOutcome outcome,
  ) => switch (outcome) {
    AgentCommandFailed(:final kind) => AgentForkCommandOutcome.failed(kind),
    AgentCommandIgnored(:final reason) => AgentForkCommandOutcome.ignored(
      reason,
    ),
    AgentCommandSucceeded() => AgentForkCommandOutcome.failed(
      AgentCommandFailureKind.requestFailed,
    ),
  };
  final AgentCommandOutcome outcome;
  final AgentSession? createdSession;
  final bool activated;
}

final class AgentConversationCommandResult {
  const AgentConversationCommandResult.regular(this.outcome) : fork = null;
  AgentConversationCommandResult.fork(AgentForkCommandOutcome value)
    : outcome = value.outcome,
      fork = value;
  final AgentCommandOutcome outcome;
  final AgentForkCommandOutcome? fork;
  AgentCommandFailureKind? get failureKind => switch (outcome) {
    AgentCommandFailed(:final kind) => kind,
    _ => null,
  };
  AgentConversationCommandResult withoutDiagnostic() => fork != null
      ? this
      : AgentConversationCommandResult.regular(switch (outcome) {
          AgentCommandFailed(:final kind) => AgentCommandOutcome.failed(kind),
          _ => outcome,
        });
  AgentConversationCommandResult asStaleKeepingCreatedSession() => fork == null
      ? const AgentConversationCommandResult.regular(
          AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
        )
      : AgentConversationCommandResult.fork(
          AgentForkCommandOutcome.failed(
            AgentCommandFailureKind.staleTarget,
            createdSession: fork!.createdSession,
          ),
        );
}
