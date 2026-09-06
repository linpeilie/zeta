import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'agent_conversation_owner_key.dart';
import 'agent_conversation_command_scope.dart';
import 'agent_conversation_slice_ports.dart';

/// 创建 owner 时冻结，关闭时清除的会话端口。不会读取 Shell 或 Widget。
final class AgentConversationSessionDependencies {
  const AgentConversationSessionDependencies({
    required this.ownerKey,
    required this.regions,
    required this.executor,
    required this.scopeSnapshot,
    required this.onProjectionUnobserved,
    this.runnerFactory,
    this.operationIdGeneratorFactory,
  });
  final AgentConversationOwnerKey ownerKey;
  final AgentConversationRegionSource regions;
  final AgentConversationCommandPort executor;
  final AgentConversationCommandScope Function() scopeSnapshot;
  final void Function(AgentConversationOwnerKey) onProjectionUnobserved;
  final AgentConversationSliceEffectRunner Function(
    AgentConversationResultSink,
  )?
  runnerFactory;
  final OperationIdGenerator Function(String)? operationIdGeneratorFactory;
}

final agentConversationSessionDependenciesProvider = Provider.autoDispose
    .family<AgentConversationSessionDependencies, AgentConversationOwnerKey>(
      (ref, key) => throw StateError(
        'Conversation session dependencies are not installed',
      ),
    );

final agentConversationOwnerResolutionProvider = Provider.autoDispose
    .family<AgentConversationOwnerResolution, AgentConversationBindingKey>(
      (ref, key) =>
          throw StateError('Conversation owner resolution is not installed'),
    );
