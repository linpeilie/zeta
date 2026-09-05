import 'package:flutter/foundation.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 把中立内核的 [AgentListenable] 投影为 Flutter presentation 可消费的信号。
///
/// 适配器不拥有 [source]，不会改变其生命周期；Widget 取消订阅时只把同一回调
/// 转发给内核对象。相同 source 的适配器具有相同值语义，避免 build 中重建代理时
/// 触发无意义的退订/重订。
base class AgentFlutterListenableAdapter implements Listenable {
  const AgentFlutterListenableAdapter(this.source);

  final AgentListenable source;

  @override
  void addListener(VoidCallback listener) => source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is AgentFlutterListenableAdapter && identical(other.source, source);

  @override
  int get hashCode => identityHashCode(source);
}

/// 带同步快照的 [AgentValueListenable] Flutter 投影。
final class AgentFlutterValueListenableAdapter<T>
    extends AgentFlutterListenableAdapter
    implements ValueListenable<T> {
  const AgentFlutterValueListenableAdapter(this.valueSource)
    : super(valueSource);

  final AgentValueListenable<T> valueSource;

  @override
  T get value => valueSource.value;
}

/// Runtime 的中立 listenable 到 Flutter 投影。适配器是值语义，build 里重建无害。
extension AgentConversationFlutterListenables
    on AgentConversationRuntimeController {
  ValueListenable<AgentConversationTurnState?> get flutterLiveTurnListenable =>
      AgentFlutterValueListenableAdapter(liveTurnListenable);

  ValueListenable<AgentConversationThreadSnapshot>
  get flutterThreadSnapshotListenable =>
      AgentFlutterValueListenableAdapter(threadSnapshotListenable);

  Listenable get flutterElapsedClockListenable =>
      AgentFlutterListenableAdapter(elapsedClockListenable);
}
