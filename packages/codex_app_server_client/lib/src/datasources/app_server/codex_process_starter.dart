import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:codex_app_server_client/src/codex_cli_locator.dart'
    show CodexCliLocator;
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// 在每次启动前重新校验 CLI，避免持久化的旧路径阻断 Agent 初始化。
Future<ResolvedCliProcessCommand> resolveCodexProcessCommand(
  AgentProviderConfig config, {
  CodexCliLocator? locator,
}) async {
  final effectiveLocator =
      locator ??
      CodexCliLocator(
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
      'Codex executable was not found',
    );
  }

  final protocolArguments = _protocolArguments(config.arguments);
  return resolved.processCommandFor(protocolArguments);
}

/// 创建供 [JsonRpcStdioTransport] 使用的 Codex 进程启动器。
ProcessStarter codexProcessStarter(
  AgentProviderConfig config, {
  CodexCliLocator? locator,
  ProcessStarter? delegate,
  AppLogger? logger,
}) {
  final log = logger ?? loggerFor('zeta.agent.codex_process_starter');
  return (
    String _,
    List<String> _, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = await resolveCodexProcessCommand(config, locator: locator);
    log.i('Codex CLI executable resolved');
    return (delegate ?? Process.start)(
      command.executable,
      command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  };
}

List<String> _protocolArguments(List<String> configuredArguments) {
  final appServerIndex = configuredArguments.indexOf('app-server');
  if (appServerIndex >= 0) {
    // 旧配置可能在 app-server 之前保存了 PowerShell/cmd 包装参数。
    return configuredArguments.sublist(appServerIndex);
  }
  if (configuredArguments.isEmpty) {
    return const <String>['app-server'];
  }
  return List<String>.from(configuredArguments);
}
