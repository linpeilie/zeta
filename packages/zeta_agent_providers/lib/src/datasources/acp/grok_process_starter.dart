import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_providers/src/cli_command_locator.dart';
import 'package:zeta_agent_providers/src/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta_agent_providers/src/grok_cli_locator.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = zetaLoggerFor('zeta.agent.grok_process_starter');

/// 在每次启动前重新校验 CLI，避免持久化的旧路径阻断 Agent 初始化。
Future<ResolvedCliProcessCommand> resolveGrokProcessCommand(
  AgentProviderConfig config, {
  GrokCliLocator? locator,
  String? modelId,
  String? reasoningEffort,
}) async {
  final effectiveLocator =
      locator ??
      GrokCliLocator(
        environment: <String, String>{
          ...Platform.environment,
          ...config.environment,
        },
      );
  final resolved = await effectiveLocator.locate(config);
  if (resolved == null) {
    throw ProcessException(
      config.command,
      config.arguments,
      'Grok executable was not found',
    );
  }

  final protocolArguments = _protocolArguments(
    config.arguments,
    modelId: modelId ?? config.selectedModel ?? config.defaultModel,
    reasoningEffort: reasoningEffort ?? config.selectedReasoningEffort,
  );
  return resolved.processCommandFor(protocolArguments);
}

/// 创建供 [JsonRpcStdioTransport] 使用的 Grok 进程启动器。
ProcessStarter grokProcessStarter(
  AgentProviderConfig config, {
  GrokCliLocator? locator,
  ProcessStarter? delegate,
  String? Function()? modelIdResolver,
  String? Function()? reasoningEffortResolver,
}) {
  return (
    String _,
    List<String> _, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = await resolveGrokProcessCommand(
      config,
      locator: locator,
      modelId: modelIdResolver?.call(),
      reasoningEffort: reasoningEffortResolver?.call(),
    );
    _log.i('Grok CLI executable resolved');
    return (delegate ?? Process.start)(
      command.executable,
      command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  };
}

/// 规范化为 `agent [flags] stdio`，并注入模型/推理深度。
List<String> _protocolArguments(
  List<String> configuredArguments, {
  String? modelId,
  String? reasoningEffort,
}) {
  // 已含 agent + stdio 的完整配置：在 agent 与 stdio 之间注入可选 flags。
  final agentIndex = configuredArguments.indexOf('agent');
  final stdioIndex = configuredArguments.indexOf('stdio');
  if (agentIndex >= 0 && stdioIndex > agentIndex) {
    final prefix = configuredArguments.sublist(0, stdioIndex);
    final suffix = configuredArguments.sublist(stdioIndex);
    return <String>[
      ...prefix,
      ..._modelFlags(modelId: modelId, reasoningEffort: reasoningEffort),
      ...suffix,
    ];
  }
  if (configuredArguments.isEmpty) {
    return <String>[
      'agent',
      ..._modelFlags(modelId: modelId, reasoningEffort: reasoningEffort),
      'stdio',
    ];
  }
  // 其它自定义参数原样保留，调用方需自行保证可启动 ACP。
  return List<String>.from(configuredArguments);
}

List<String> _modelFlags({String? modelId, String? reasoningEffort}) {
  final flags = <String>[];
  final model = modelId?.trim();
  if (model != null && model.isNotEmpty) {
    flags.addAll(<String>['-m', model]);
  }
  final effort = reasoningEffort?.trim();
  if (effort != null && effort.isNotEmpty) {
    flags.addAll(<String>['--effort', effort]);
  }
  return flags;
}
