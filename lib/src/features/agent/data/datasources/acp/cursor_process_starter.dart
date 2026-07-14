import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.cursor_process_starter');

/// 实际传给 [Process.start] 的 Cursor ACP 启动参数。
class ResolvedCursorProcessCommand {
  const ResolvedCursorProcessCommand({
    required this.executable,
    required this.arguments,
    required this.displayPath,
    required this.identity,
  });

  final String executable;
  final List<String> arguments;
  final String displayPath;
  final CursorCliIdentity identity;
}

/// 在每次启动前重新执行 Cursor 身份探测，避免同名 `agent` 被替换后误启动。
Future<ResolvedCursorProcessCommand> resolveCursorProcessCommand(
  AgentProviderConfig config, {
  CursorCliLocator? locator,
}) async {
  final effectiveLocator =
      locator ??
      CursorCliLocator(
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
      '未找到通过身份校验且支持 ACP 的 Cursor CLI；可能存在同名 agent 命令冲突',
    );
  }
  return ResolvedCursorProcessCommand(
    executable: resolved.executable,
    arguments: resolved.argumentsFor(_protocolArguments(config.arguments)),
    displayPath: resolved.displayPath,
    identity: resolved.identity,
  );
}

/// 创建供 [JsonRpcStdioTransport] 使用的 Cursor 进程启动器。
ProcessStarter cursorProcessStarter(
  AgentProviderConfig config, {
  CursorCliLocator? locator,
  ProcessStarter? delegate,
}) {
  return (
    String _,
    List<String> _, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = await resolveCursorProcessCommand(config, locator: locator);
    _log.info(
      'Using verified Cursor CLI ${command.displayPath} '
      '(${command.identity.version ?? 'unknown version'})',
    );
    return (delegate ?? Process.start)(
      command.executable,
      command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  };
}

List<String> _protocolArguments(List<String> configuredArguments) {
  if (configuredArguments.contains('acp')) {
    return List<String>.from(configuredArguments);
  }
  if (configuredArguments.isEmpty) {
    return const <String>['acp'];
  }
  return <String>[...configuredArguments, 'acp'];
}
