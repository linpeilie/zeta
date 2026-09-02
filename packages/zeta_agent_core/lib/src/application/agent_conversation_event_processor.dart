import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect_runner.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/application/agent_event_observer.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_port.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final _log = zetaLoggerFor('zeta.agent.event_processor');

typedef AgentConversationReducerContextReader =
    AgentConversationReducerContext Function();

/// processor 与状态宿主之间的唯一边界。
abstract interface class AgentConversationStateSink {
  /// 当前会话状态。processor 每次 process 前读一次。
  AgentConversationSessionState get sessionState;

  /// 写回归约结果。宿主只做赋值，不得在此触发 Flutter 通知。
  void applyReducedState(AgentConversationSessionState next);

  /// 请求在下一次安全 UI 发布边界刷新 thread snapshot。
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
    required AgentConversationStateSink stateSink,
    required AgentUiUpdatePort uiUpdates,
    required AgentConversationEffectRunner effectRunner,
    Iterable<AgentEventObserver> observers = const <AgentEventObserver>[],
  }) => AgentConversationEventProcessor._(
    reducer,
    context,
    timeline,
    stateSink,
    uiUpdates,
    effectRunner,
    List<AgentEventObserver>.unmodifiable(observers),
  );

  AgentConversationEventProcessor._(
    this._reducer,
    this._context,
    this._timeline,
    this._stateSink,
    this._uiUpdates,
    this._effectRunner,
    this._observers,
  );

  final AgentConversationReducer _reducer;
  final AgentConversationReducerContextReader _context;
  final AgentConversationTimelineStore _timeline;
  final AgentConversationStateSink _stateSink;
  final AgentUiUpdatePort _uiUpdates;
  final AgentConversationEffectRunner _effectRunner;
  final List<AgentEventObserver> _observers;

  /// 处理一个规范化事件，并返回最终 reduction 结果供诊断/测试。
  AgentConversationReduction process(AgentEvent event) {
    final context = _context();
    final before = _stateSink.sessionState;
    final reduction = _reducer.reduce(event, before, context);
    _apply(reduction);
    _notifyObservers(event, reduction, context);
    return reduction;
  }

  /// 复用同步 mutation 收尾 provider-disconnected/thread-closed turn。
  AgentConversationReduction settleInterruptedTurn({
    required String fallbackTurnId,
  }) {
    final before = _stateSink.sessionState;
    final reduction = _reducer.settleInterruptedTurn(
      fallbackTurnId: fallbackTurnId,
      state: before,
      context: _context(),
    );
    _apply(reduction);
    return reduction;
  }

  void _notifyObservers(
    AgentEvent event,
    AgentConversationReduction reduction,
    AgentConversationReducerContext context,
  ) {
    for (final observer in _observers) {
      try {
        observer.onProcessed(event, reduction, context);
      } catch (error) {
        // 旁路失败不影响已接受事件；只记类型不记正文（G7）。
        _log.w('Agent event observer failed (${error.runtimeType})');
      }
    }
  }

  void _apply(AgentConversationReduction reduction) {
    _runEffects(reduction, AgentConversationEffectTiming.beforeMutation);
    if (!reduction.accepted) {
      _runEffects(reduction, AgentConversationEffectTiming.afterMutation);
      return;
    }

    _stateSink.applyReducedState(reduction.state);

    var activityChanged = false;
    for (final timelineMutation in reduction.timelineMutations) {
      timelineMutation.applyTo(_timeline);
      if (timelineMutation.trackActivityChange) {
        activityChanged = _timeline.takeActivityDirty() || activityChanged;
      }
    }

    if (reduction.threadSnapshot != null) {
      _stateSink.requestThreadSnapshotRefresh();
    }

    // afterMutation 必须在 UI 发布前执行：原 stateChanges 里的
    // setTurnRunning / bind mode 会同步触发 composer 刷新，若放在 publish
    // 之后会盖掉 reducer 声明的 region。TurnCompleted 等原 after 效果
    // 提前一拍不影响注意力回调语义。
    _runEffects(reduction, AgentConversationEffectTiming.afterMutation);

    final request = _resolveUiUpdate(
      reduction,
      activityChanged: activityChanged,
    );
    if (request != null) {
      _uiUpdates.publish(request);
    }
  }

  AgentUiUpdateRequest? _resolveUiUpdate(
    AgentConversationReduction reduction, {
    required bool activityChanged,
  }) {
    final base = reduction.uiUpdate;
    if (base == null) {
      return null;
    }
    final regions = <AgentUiRegion>{...base.regions};
    if (activityChanged &&
        reduction.uiResolution.includeHeaderWhenActivityChanges) {
      regions.add(AgentUiRegion.header);
    }
    if (reduction.uiResolution.includePendingInteractionWhenStateChanges) {
      regions.add(AgentUiRegion.pendingInteraction);
    }
    return AgentUiUpdateRequest(
      regions: regions,
      urgency: base.urgency,
      effects: base.effects,
    );
  }

  void _runEffects(
    AgentConversationReduction reduction,
    AgentConversationEffectTiming timing,
  ) {
    for (final effect in reduction.effects) {
      if (effect.timing == timing) {
        _effectRunner.run(effect);
      }
    }
  }
}
