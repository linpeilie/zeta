import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_acp_agent_provider.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Builds a complete Grok ACP capability bundle.
final class GrokProviderBundleFactory implements AgentProviderBundleFactory {
  /// Creates a Grok bundle factory from injected infrastructure.
  GrokProviderBundleFactory({
    required this.processStarter,
    required this.logger,
  });

  /// Raw process-launch seam wrapped by the Grok CLI locator.
  final ProcessStarter processStarter;

  /// Sanitizing package logger.
  final AppLogger logger;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    return nativeBundleFromGrok(
      GrokAcpAgentProvider(
        config: config,
        processStarter: processStarter,
        logger: logger,
      ),
    );
  }

  /// Production raw process starter for composition roots.
  static Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

/// Assembles the neutral capability bundle around an existing Grok provider.
AgentProviderBundle nativeBundleFromGrok(GrokAcpAgentProvider provider) {
  return AgentProviderBundle(
    runtime: provider,
    conversation: provider,
    threadCatalog: provider,
    threadNaming: provider,
    threadDeletion: provider,
    permissionResponses: provider,
    questions: provider,
    modelCatalog: provider,
    conversationModes: provider,
    skills: provider,
    planApproval: provider,
    permissionPolicy: provider.permissionPolicy,
    usageQuota: provider,
  );
}
