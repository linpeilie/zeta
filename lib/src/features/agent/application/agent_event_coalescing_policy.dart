import 'package:zeta/src/features/agent/application/coalescing_event_buffer.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 仅由规范化 Agent identity 组成的合并键。
typedef AgentEventKey = ({
  String kind,
  String? sessionId,
  String? turnId,
  String itemId,
  String? detail,
});

/// Agent 事件的规范化 key、merge 与 barrier 规则。
///
/// Provider raw sourceId 不参与 key 推断；identity 仍完全来自 data adapter/reducer
/// 已经规范化的字段。
final class AgentEventCoalescingPolicy
    implements EventCoalescingPolicy<AgentEvent, AgentEventKey> {
  const AgentEventCoalescingPolicy();

  @override
  AgentEventKey? keyOf(AgentEvent event) {
    return switch (event) {
      AgentMessageDeltaEvent() => (
        kind: 'messageDelta',
        sessionId: event.sessionId,
        turnId: event.turnId,
        itemId: event.messageId,
        detail: '${event.role.name}:${event.kind.name}:${event.phase?.name}',
      ),
      AgentReasoningDeltaEvent() => (
        kind: 'reasoningDelta',
        sessionId: event.sessionId,
        turnId: event.turnId,
        itemId: event.itemId,
        detail:
            '${event.kind.name}:${event.contentIndex}:${event.summaryIndex}',
      ),
      AgentTokenUsageEvent() => (
        kind: 'tokenSnapshot',
        sessionId: event.sessionId,
        turnId: event.turnId,
        itemId: '<turn>',
        detail: event.isSessionCumulative.toString(),
      ),
      AgentContextWindowUsageEvent() => (
        kind: 'contextWindowSnapshot',
        sessionId: event.sessionId,
        turnId: event.turnId,
        itemId: '<turn>',
        detail: null,
      ),
      AgentTurnFileChangesEvent() => (
        kind: 'diffSnapshot',
        sessionId: event.sessionId,
        turnId: event.turnId,
        itemId: '<turn>',
        detail: null,
      ),
      AgentToolCallEvent() when !event.toolCall.isTerminalStatus => (
        kind: 'toolProgress',
        sessionId: event.toolCall.sessionId,
        turnId: event.toolCall.turnId,
        itemId: event.toolCall.id,
        detail: null,
      ),
      _ => null,
    };
  }

  @override
  bool isBarrier(AgentEvent event) => keyOf(event) == null;

  @override
  AgentEvent merge(AgentEvent previous, AgentEvent next) {
    return switch ((previous, next)) {
      (AgentMessageDeltaEvent previous, AgentMessageDeltaEvent next) =>
        AgentMessageDeltaEvent(
          messageId: next.messageId,
          sourceMessageId: next.sourceMessageId ?? previous.sourceMessageId,
          kind: next.kind,
          delta: '${previous.delta}${next.delta}',
          role: next.role,
          phase: next.phase ?? previous.phase,
          status: next.status ?? previous.status,
          duration: next.duration ?? previous.duration,
          raw: next.raw,
          sessionId: next.sessionId ?? previous.sessionId,
          turnId: next.turnId ?? previous.turnId,
        ),
      (AgentReasoningDeltaEvent previous, AgentReasoningDeltaEvent next) =>
        AgentReasoningDeltaEvent(
          itemId: next.itemId,
          sourceItemId: next.sourceItemId ?? previous.sourceItemId,
          kind: next.kind,
          delta: '${previous.delta}${next.delta}',
          contentIndex: next.contentIndex ?? previous.contentIndex,
          summaryIndex: next.summaryIndex ?? previous.summaryIndex,
          sessionId: next.sessionId ?? previous.sessionId,
          turnId: next.turnId ?? previous.turnId,
          raw: next.raw,
        ),
      (AgentToolCallEvent previous, AgentToolCallEvent next) =>
        _mergeToolProgress(previous, next),
      _ => next,
    };
  }
}

AgentToolCallEvent _mergeToolProgress(
  AgentToolCallEvent previous,
  AgentToolCallEvent next,
) {
  final previousCall = previous.toolCall;
  final nextCall = next.toolCall;
  final shouldAppend =
      previousCall.raw['_progressAppend'] == true &&
      nextCall.raw['_progressAppend'] == true;
  if (!shouldAppend) {
    return next;
  }
  return AgentToolCallEvent(
    nextCall.copyWith(
      content: _appendProgress(previousCall.content, nextCall.content),
      raw: <String, Object?>{...previousCall.raw, ...nextCall.raw},
    ),
  );
}

String? _appendProgress(String? previous, String? next) {
  if (next == null || next.isEmpty) {
    return previous;
  }
  if (previous == null || previous.isEmpty) {
    return next;
  }
  if (previous == next ||
      previous.endsWith('\n$next') ||
      previous.endsWith(next)) {
    return previous;
  }
  return '$previous\n$next';
}
