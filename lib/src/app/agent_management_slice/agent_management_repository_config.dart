import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

/// 管理命令沿用既有配置解析；检测持久化另行只合并当前白名单。
final class AgentManagementRepositoryConfig {
  AgentManagementRepositoryConfig(Map<String, AgentDefinition> definitions)
    : _definitions = Map.unmodifiable(definitions);
  final Map<String, AgentDefinition> _definitions;
  AgentProviderConfig configFor(
    AgentProviderSettings settings,
    AgentCliManagementRepository repository,
  ) {
    for (final provider in settings.providers) {
      if (provider.id == repository.agentId) {
        return sanitize(provider, repository);
      }
    }
    return descriptor(repository)?.defaultProviderConfig ??
        AgentProviderConfig(
          kind:
              zetaAgentProviderDefinitionCatalog
                  .definitionForProviderId(repository.agentId)
                  ?.providerType ??
              const AgentProviderTypeId('unknown'),
          command: repository.agentId,
          id: repository.agentId,
          displayName:
              _definitions[repository.agentId]?.displayName ??
              repository.agentId,
        );
  }

  AgentProviderConfig sanitize(
    AgentProviderConfig config,
    AgentCliManagementRepository repository,
  ) {
    final descriptor = this.descriptor(repository);
    if (descriptor == null) {
      return config.copyWith(id: repository.agentId);
    }
    final defaults = descriptor.defaultProviderConfig;
    final extra = Map<String, Object?>.from(config.extra)
      ..remove('timeoutSeconds');
    final cliPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final commandIsPath = _looksLikeFilePath(config.command);
    final commandWrong =
        commandIsPath && !descriptor.acceptsExecutablePath(config.command);
    final cliPathWrong =
        cliPath != null && !descriptor.acceptsExecutablePath(cliPath);
    final kindWrong = config.kind != defaults.kind;
    if (cliPathWrong) {
      extra.remove('cliPath');
      extra.remove('detectedCurrentVersion');
      extra.remove('detectedLatestVersion');
    }
    final needsDefaultCommand =
        kindWrong ||
        commandWrong ||
        config.command.trim().isEmpty ||
        (cliPathWrong && config.command == cliPath);
    return config.copyWith(
      id: repository.agentId,
      displayName: defaults.displayName,
      kind: defaults.kind,
      command: needsDefaultCommand ? defaults.command : config.command,
      arguments: kindWrong || needsDefaultCommand
          ? defaults.arguments
          : config.arguments,
      extra: extra,
    );
  }

  AgentCliManagementDescriptor? descriptor(
    AgentCliManagementRepository repository,
  ) => repository is AgentCliManagementDescriptor
      ? repository as AgentCliManagementDescriptor
      : null;

  bool acceptsExecutablePath(
    AgentCliManagementRepository repository,
    String path,
  ) => descriptor(repository)?.acceptsExecutablePath(path) ?? true;
}

bool _looksLikeFilePath(String value) {
  return value.contains('/') ||
      value.contains('\\') ||
      value.contains(':') ||
      value.endsWith('.exe') ||
      value.endsWith('.cmd') ||
      value.endsWith('.bat') ||
      value.endsWith('.ps1');
}
