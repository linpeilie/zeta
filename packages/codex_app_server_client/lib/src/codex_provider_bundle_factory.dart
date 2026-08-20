import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:codex_app_server_client/src/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:codex_app_server_client/src/datasources/app_server/codex_process_starter.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Creates the transport peer used by one Codex runtime.
typedef JsonRpcPeerFactory = JsonRpcPeer Function({
  required AgentProviderConfig config,
  required ProcessStarter processStarter,
  required AppLogger logger,
  required Clock clock,
});

/// Builds a complete Codex capability bundle from injected infrastructure.
final class CodexProviderBundleFactory implements AgentProviderBundleFactory {
  /// Creates a Codex bundle factory.
  CodexProviderBundleFactory({
    required this.peerFactory,
    required this.processStarter,
    required this.logger,
    this.clock = const Clock(),
  });

  /// Transport construction seam.
  final JsonRpcPeerFactory peerFactory;

  /// Raw process-launch seam wrapped by the Codex CLI locator.
  final ProcessStarter processStarter;

  /// Sanitizing package logger.
  final AppLogger logger;

  /// Deterministic time source shared with the transport.
  final Clock clock;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    final peer = peerFactory(
      config: config,
      processStarter: codexProcessStarter(
        config,
        delegate: processStarter,
        logger: logger,
      ),
      logger: logger,
      clock: clock,
    );
    final provider = CodexAppServerAgentProvider(
      config: config,
      peer: peer,
      logger: logger,
    );
    return AgentProviderBundle(
      runtime: provider,
      conversation: provider,
      threadCatalog: provider,
      threadSubscription: provider,
      threadNaming: provider,
      threadArchival: provider,
      threadDeletion: provider,
      threadCompaction: provider,
      threadBranching: provider,
      turnSteering: provider,
      permissionResponses: provider,
      questions: provider,
      deniedActionOverride: provider,
      modelCatalog: provider,
      conversationModes: provider,
      skills: provider,
      permissionPolicy: provider.permissionPolicy,
      usageQuota: provider,
    );
  }

  /// Production peer constructor for composition roots.
  static JsonRpcStdioTransport createPeer({
    required AgentProviderConfig config,
    required ProcessStarter processStarter,
    required AppLogger logger,
    required Clock clock,
  }) {
    return JsonRpcStdioTransport(
      command: config.command,
      arguments: config.arguments,
      environment: config.environment,
      processStarter: processStarter,
      logger: logger,
      clock: clock,
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
