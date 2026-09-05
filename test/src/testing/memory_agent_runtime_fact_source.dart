import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';

export 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';

/// 外部事实端口的内存替身；Store/reducer/composition 仍使用生产实现。
final class MemoryAgentRuntimeFactSource
    implements AgentManagementRuntimeFactSource {
  MemoryAgentRuntimeFactSource([AgentManagementRuntimeFacts? facts])
    : current = facts ?? AgentManagementRuntimeFacts.empty;

  @override
  AgentManagementRuntimeFacts current;
  final _listeners = <void Function(AgentManagementRuntimeFacts)>[];
  int get listenerCount => _listeners.length;

  @override
  void Function() subscribe(
    void Function(AgentManagementRuntimeFacts) receive,
  ) {
    _listeners.add(receive);
    return () => _listeners.remove(receive);
  }

  void replace(AgentManagementRuntimeFacts facts) {
    current = facts;
    for (final receive in List.of(_listeners)) {
      receive(facts);
    }
  }
}
