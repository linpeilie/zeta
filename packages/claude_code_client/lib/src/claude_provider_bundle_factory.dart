import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_agent_provider.dart';
import 'package:claude_code_client/src/datasources/claude_code/stream_json_peer.dart';
import 'package:clock/clock.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Creates one Claude Code stream-JSON peer.
typedef ClaudeStreamJsonPeerFactory = StreamJsonPeerBuilder;

/// Builds a complete Claude Code capability bundle.
final class ClaudeProviderBundleFactory implements AgentProviderBundleFactory {
  /// Creates a Claude Code bundle factory from injected infrastructure.
  ClaudeProviderBundleFactory({
    required this.peerFactory,
    required this.processStarter,
    required this.logger,
    this.clock = const Clock(),
  });

  /// Transport construction seam.
  final ClaudeStreamJsonPeerFactory peerFactory;

  /// Raw process-launch seam wrapped by the Claude CLI locator.
  final ProcessStarter processStarter;

  /// Sanitizing package logger.
  final AppLogger logger;

  /// Deterministic clock used by throttles and terminal timestamps.
  final Clock clock;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    final provider = ClaudeCodeAgentProvider(
      config: config,
      processStarter: processStarter,
      peerFactory: peerFactory,
      logger: logger,
      clock: clock,
    );
    return AgentProviderBundle(
      runtime: provider,
      conversation: provider,
      threadCatalog: provider,
      threadCompaction: provider,
      permissionResponses: provider,
      questions: provider,
      modelCatalog: provider,
      localThreadList: provider,
      planApproval: provider,
      permissionPolicy: provider.permissionPolicy,
      usageQuota: provider,
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

  /// Production peer constructor for composition roots.
  static StreamJsonPeer createPeer({
    required String command,
    required List<String> arguments,
    required String? workingDirectory,
    required Map<String, String> environment,
    required ProcessStarter processStarter,
    required AppLogger logger,
  }) {
    return StreamJsonPeer(
      command: command,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      processStarter: processStarter,
      logger: logger,
    );
  }
}
