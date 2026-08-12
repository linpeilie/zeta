import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart'
    show CodexCliLocator;
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.codex_process_starter');

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
}) {
  return (
    String _,
    List<String> _, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = await resolveCodexProcessCommand(config, locator: locator);
    _log.i('Codex CLI executable resolved');
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
