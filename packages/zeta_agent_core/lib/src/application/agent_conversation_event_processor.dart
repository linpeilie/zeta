import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect_runner.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/application/agent_event_observer.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_port.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final _log = zetaLoggerFor('zeta.agent.event_processor');

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
    Iterable<AgentEventObserver> observers = const <AgentEventObserver>[],
  }) => AgentConversationEventProcessor._(
    reducer,
    context,
    timeline,
    stateTarget,
    uiUpdates,
    effectRunner,
    List<AgentEventObserver>.unmodifiable(observers),
  );

  AgentConversationEventProcessor._(
    this._reducer,
    this._context,
    this._timeline,
    this._stateTarget,
    this._uiUpdates,
    this._effectRunner,
    this._observers,
  );

  final AgentConversationReducer _reducer;
  final AgentConversationReducerContextReader _context;
  final AgentConversationTimelineStore _timeline;
  final AgentConversationStateMutationTarget _stateTarget;
  final AgentUiUpdatePort _uiUpdates;
  final AgentConversationEffectRunner _effectRunner;
  final List<AgentEventObserver> _observers;

  /// 处理一个规范化事件，并返回最终 reduction 结果供诊断/测试。
  AgentConversationMutation process(AgentEvent event) {
    final context = _context();
    final mutation = _reducer.reduce(event, context);
    _apply(mutation);
    _notifyObservers(event, mutation, context);
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

  void _notifyObservers(
    AgentEvent event,
    AgentConversationMutation mutation,
    AgentConversationReducerContext context,
  ) {
    for (final observer in _observers) {
      try {
        observer.onProcessed(event, mutation, context);
      } catch (error) {
        // 旁路失败不影响已接受事件；只记类型不记正文（G7）。
        _log.w('Agent event observer failed (${error.runtimeType})');
      }
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
      timelineMutation.applyTo(_timeline);
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
}
