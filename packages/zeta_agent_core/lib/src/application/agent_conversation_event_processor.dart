import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect_runner.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/application/agent_turn_context_recorder.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_port.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final _log = zetaLoggerFor('zeta.agent.turn_context');

typedef AgentConversationReducerContextReader =
    AgentConversationReducerContext Function();

/// typed state mutation 的 application/presentation facade 边界。
abstract interface class AgentConversationStateMutationTarget {
  AgentConversationStateMutationOutcome apply(
    AgentConversationStateChange change,
  );

  /// 请求 presentation 在下一次安全 UI 发布边界刷新 thread snapshot。
  ///
  /// 实现不得在这里同步通知 Flutter listener；build phase 延帧由 presentation
  /// 的 [AgentUiUpdatePort] 实现统一处理。
  void requestThreadSnapshotRefresh();
}

/// 已通过 gate、coalescing 与 bounded dispatch 的事件编排器。
///
/// Processor 不继承 ChangeNotifier，也不依赖 Widget。它按固定顺序应用 typed
/// state、Timeline、ThreadSnapshot、UI request 与 application effect。
final class AgentConversationEventProcessor {
  factory AgentConversationEventProcessor({
    required AgentConversationReducer reducer,
    required AgentConversationReducerContextReader context,
    required AgentConversationTimelineStore timeline,
    required AgentConversationStateMutationTarget stateTarget,
    required AgentUiUpdatePort uiUpdates,
    required AgentConversationEffectRunner effectRunner,
    AgentTurnContextRecorder? turnContextRecorder,
  }) => AgentConversationEventProcessor._(
    reducer,
    context,
    timeline,
    stateTarget,
    uiUpdates,
    effectRunner,
    turnContextRecorder,
  );

  AgentConversationEventProcessor._(
    this._reducer,
    this._context,
    this._timeline,
    this._stateTarget,
    this._uiUpdates,
    this._effectRunner,
    this._turnContextRecorder,
  );

  final AgentConversationReducer _reducer;
  final AgentConversationReducerContextReader _context;
  final AgentConversationTimelineStore _timeline;
  final AgentConversationStateMutationTarget _stateTarget;
  final AgentUiUpdatePort _uiUpdates;
  final AgentConversationEffectRunner _effectRunner;
  final AgentTurnContextRecorder? _turnContextRecorder;

  /// 处理一个规范化事件，并返回最终 reduction 结果供诊断/测试。
  AgentConversationMutation process(AgentEvent event) {
    final context = _context();
    final mutation = _reducer.reduce(event, context);
    _apply(mutation);
    _recordTurnContext(event, mutation, context);
    return mutation;
  }

  /// 复用同步 mutation 收尾 provider-disconnected/thread-closed turn。
  AgentConversationMutation settleInterruptedTurn({
    required String fallbackTurnId,
  }) {
    final mutation = _reducer.settleInterruptedTurn(
      fallbackTurnId: fallbackTurnId,
    );
    _apply(mutation);
    return mutation;
  }

  void _recordTurnContext(
    AgentEvent event,
    AgentConversationMutation mutation,
    AgentConversationReducerContext context,
  ) {
    if (!mutation.accepted ||
        context.scope != AgentConversationReductionScope.live) {
      return;
    }
    final recorder = _turnContextRecorder;
    if (recorder == null) {
      return;
    }
    final providerId = context.effectScope.providerId;
    try {
      switch (event) {
        case AgentTurnStartedEvent():
          recorder.recordStarted(providerId: providerId, event: event);
        case AgentTurnCompletedEvent():
          recorder.recordCompleted(providerId: providerId, event: event);
        default:
          break;
      }
    } catch (error) {
      _log.w('Could not record Agent turn context (${error.runtimeType})');
    }
  }

  void _apply(AgentConversationMutation mutation) {
    _runEffects(mutation, AgentConversationEffectTiming.beforeMutation);
    if (!mutation.accepted) {
      _runEffects(mutation, AgentConversationEffectTiming.afterMutation);
      return;
    }

    var stateOutcome = AgentConversationStateMutationOutcome.none;
    for (final change in mutation.stateChangesBeforeTimeline) {
      stateOutcome = stateOutcome.mergedWith(_stateTarget.apply(change));
    }

    var activityChanged = false;
    for (final timelineMutation in mutation.timelineMutations) {
      _applyTimelineMutation(timelineMutation);
      if (timelineMutation.trackActivityChange) {
        activityChanged = _timeline.takeActivityDirty() || activityChanged;
      }
    }

    for (final change in mutation.stateChanges) {
      stateOutcome = stateOutcome.mergedWith(_stateTarget.apply(change));
    }

    if (mutation.threadSnapshot != null) {
      _stateTarget.requestThreadSnapshotRefresh();
    }

    final request = _resolveUiUpdate(
      mutation,
      activityChanged: activityChanged,
      stateOutcome: stateOutcome,
    );
    if (request != null) {
      _uiUpdates.publish(request);
    }
    _runEffects(mutation, AgentConversationEffectTiming.afterMutation);
  }

  AgentUiUpdateRequest? _resolveUiUpdate(
    AgentConversationMutation mutation, {
    required bool activityChanged,
    required AgentConversationStateMutationOutcome stateOutcome,
  }) {
    final base = mutation.uiUpdate;
    if (base == null) {
      return null;
    }
    final regions = <AgentUiRegion>{...base.regions};
    if (activityChanged &&
        mutation.uiResolution.includeHeaderWhenActivityChanges) {
      regions.add(AgentUiRegion.header);
    }
    if (stateOutcome.pendingInteractionChanged &&
        mutation.uiResolution.includePendingInteractionWhenStateChanges) {
      regions.add(AgentUiRegion.pendingInteraction);
    }
    return AgentUiUpdateRequest(
      regions: regions,
      urgency: base.urgency,
      effects: base.effects,
    );
  }

  void _runEffects(
    AgentConversationMutation mutation,
    AgentConversationEffectTiming timing,
  ) {
    for (final effect in mutation.effects) {
      if (effect.timing == timing) {
        _effectRunner.run(effect);
      }
    }
  }

  void _applyTimelineMutation(AgentTimelineMutation mutation) {
    switch (mutation) {
      case AgentBeginLiveTurnTimelineMutation():
        _timeline.beginLiveTurnGroup(mutation.turn);
      case AgentCompleteLiveTurnTimelineMutation():
        final event = mutation.event;
        _timeline.completeLiveTurnGroup(
          event.turnId,
          status: event.status,
          duration: event.duration,
        );
      case AgentSettleInterruptedTimelineMutation():
        if (_timeline.isTurnRunning) {
          _timeline.completeLiveTurnGroup(
            _timeline.selectedRunningTurnId ?? mutation.fallbackTurnId,
            status: AgentHistoryTurnStatus.interrupted,
          );
        }
      case AgentAddConversationMessageTimelineMutation():
        final message = mutation.message;
        _timeline.addConversationMessage(
          AgentConversationMessage(
            id: message.id,
            sourceMessageId: message.sourceMessageId,
            role: message.role,
            text: message.text,
            kind: message.kind,
            phase: message.phase,
            status: message.status,
            duration: message.duration,
            localImagePaths: message.localImagePaths,
            raw: message.raw,
          ),
        );
      case AgentAddHistoryEventTimelineMutation():
        _timeline.addHistoryEvent(mutation.event);
      case AgentUpdateTurnTokenUsageTimelineMutation():
        _timeline.updateTurnTokenUsage(mutation.event);
      case AgentUpdateContextWindowUsageTimelineMutation():
        _timeline.updateContextWindowUsage(mutation.event);
      case AgentAppendMessageDeltaTimelineMutation():
        _timeline.appendMessageDelta(mutation.event);
      case AgentAppendReasoningDeltaTimelineMutation():
        _timeline.appendReasoningDelta(mutation.event);
      case AgentUpdateMessageTimelineMutation():
        _timeline.updateMessage(mutation.event);
      case AgentReplaceActivePlanTimelineMutation():
        _timeline.replaceActivePlan(mutation.event);
      case AgentUpsertTurnFileChangesTimelineMutation():
        _timeline.upsertTurnFileChanges(mutation.event);
      case AgentUpsertToolCallTimelineMutation():
        _timeline.upsertToolCall(mutation.toolCall);
      case AgentAddPermissionRequestTimelineMutation():
        _timeline.addPermissionRequest(mutation.request);
      case AgentRemovePermissionRequestTimelineMutation():
        _timeline.removePermissionRequest(mutation.requestId);
      case AgentAddQuestionRequestTimelineMutation():
        _timeline.addQuestionRequest(mutation.request);
      case AgentRemoveQuestionRequestTimelineMutation():
        _timeline.removeQuestionRequest(mutation.requestId);
      case AgentAddPlanApprovalRequestTimelineMutation():
        _timeline.addPlanApprovalRequest(mutation.request);
      case AgentRemovePlanApprovalRequestTimelineMutation():
        _timeline.removePlanApprovalRequest(mutation.requestId);
    }
  }
}
