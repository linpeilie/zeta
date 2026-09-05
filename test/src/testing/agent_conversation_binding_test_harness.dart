import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';

/// 测试中为 ViewModel 提供与生产一致的 Binding + global runtime 组合。
final class AgentConversationBindingTestHarness {
  AgentConversationBindingTestHarness({
    required this.registry,
    required this.settings,
  }) : manager = AgentConversationBindingManager(runtimeRegistry: registry),
       globalRuntime = AgentProviderGlobalRuntime(runtimeRegistry: registry);

  final AgentProviderRuntimeRegistry registry;
  final AgentProviderSettingsPort settings;
  final AgentConversationBindingManager manager;
  final AgentProviderGlobalRuntime globalRuntime;

  final List<AgentConversationBindingLease> _leases =
      <AgentConversationBindingLease>[];
  int _nextEntryId = 0;

  AgentConversationBindingLease acquireDraft(AgentProviderConfig config) {
    final lease = manager.acquireDraft(
      providerId: config.id,
      entryId: 'test-binding-${_nextEntryId += 1}',
      resolveConfig: (providerId) {
        final current = settings.providerConfigById(providerId);
        if (current != null) {
          return current;
        }
        if (providerId == config.id) {
          return config;
        }
        throw StateError('No test config for provider $providerId');
      },
      persistPermissionOptionId: (optionId) =>
          settings.persistPermissionOptionIdForProvider(config.id, optionId),
    );
    _leases.add(lease);
    return lease;
  }

  AgentConversationBindingLease acquireThread({
    required AgentProviderConfig config,
    required String threadId,
  }) {
    final lease = manager.acquireThread(
      providerId: config.id,
      threadId: threadId,
      resolveConfig: (providerId) {
        final current = settings.providerConfigById(providerId);
        if (current != null) {
          return current;
        }
        if (providerId == config.id) {
          return config;
        }
        throw StateError('No test config for provider $providerId');
      },
      persistPermissionOptionId: (optionId) =>
          settings.persistPermissionOptionIdForProvider(config.id, optionId),
    );
    _leases.add(lease);
    return lease;
  }

  Future<void> close() async {
    for (final lease in _leases.reversed) {
      await lease.release();
    }
    _leases.clear();
    await manager.close();
  }
}
