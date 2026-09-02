import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// runtime detach 后仍允许交付的事件白名单。
///
/// 这是**管线级**策略，不是归约逻辑：Pipeline 用它决定是否放行，
/// 因此不能依附于 reducer 的生命周期。
abstract final class AgentDetachedEventPolicy {
  /// detached runtime 仍可交付的精确 critical allowlist。
  ///
  /// [AgentThreadNameUpdatedEvent] / [AgentThreadPreviewUpdatedEvent] 纳入：
  /// Grok 在 turn 结束后异步下发标题或 `last_turn_summary`，事件可能略晚于
  /// runtime detach 边界，仍需更新列表展示。
  static bool isCritical(AgentEvent event) {
    return event is AgentStatusEvent ||
        event is AgentErrorEvent ||
        event is AgentTurnCompletedEvent ||
        event is AgentThreadClosedEvent ||
        event is AgentThreadNameUpdatedEvent ||
        event is AgentThreadPreviewUpdatedEvent ||
        event is AgentPermissionRequestedEvent ||
        event is AgentPermissionResolvedEvent ||
        event is AgentPlanApprovalRequestedEvent ||
        event is AgentPlanApprovalResolvedEvent;
  }
}
