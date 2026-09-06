import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// Widget tests exercise production owners/runners, without starting a real CLI.
/// Keep contribution identity and typed capability metadata from the plugin.
AgentManagementContribution memoryManagementContribution(
  AgentManagementContribution contribution,
) => AgentManagementContribution(
  providerId: contribution.providerId,
  definition: contribution.definition,
  createRepository: (services) => _MemoryManagementRepository(
    contribution.definition,
    contribution.createRepository(services),
  ),
);

final class _MemoryManagementRepository
    implements AgentCliManagementRepository, AgentCliManagementDescriptor {
  _MemoryManagementRepository(
    this.definition,
    AgentCliManagementRepository repository,
  ) : descriptor = repository is AgentCliManagementDescriptor
          ? repository as AgentCliManagementDescriptor
          : null;
  final AgentDefinition definition;
  final AgentCliManagementDescriptor? descriptor;
  @override
  String get agentId => definition.id;
  @override
  AgentCliManagementCapabilities get managementCapabilities =>
      descriptor?.managementCapabilities ?? AgentCliManagementCapabilities.none;
  @override
  AgentProviderConfig get defaultProviderConfig =>
      descriptor!.defaultProviderConfig;
  @override
  bool acceptsExecutablePath(String path) => false;
  @override
  String get connectionModelSourceLabel => definition.displayName;
  @override
  String get configPath => '/test/config';
  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async => ManagedAgent.forDefinition(
    definition: definition,
    enabled: enabled,
  ).copyWith(installationState: AgentInstallationState.installed);
  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async => (
    AgentConnectionTestResult(
      success: false,
      testedAt: DateTime.utc(2026),
      elapsed: Duration.zero,
      cliCallable: false,
      accountValid: false,
      protocolReady: false,
    ),
    const <AgentModelInfo>[],
  );
  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async => current;
  @override
  Future<AgentConfigurationDocument> readConfiguration() async =>
      AgentConfigurationDocument(
        path: configPath,
        format: 'JSON',
        content: '{}',
        maskedContent: '{}',
        exists: false,
        loadedAt: DateTime.utc(2026),
        signature: 'memory',
      );
  @override
  String? validateConfiguration(String content) => null;
  @override
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  }) async => throw UnsupportedError(
    'Override the management repository to test configuration writes',
  );
  @override
  Future<List<String>> discoverLogPaths() async => const [];
  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async => const [];
}
