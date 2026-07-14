import 'dart:async';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.cursor_process_starter');

/// Windows 包装器进程树终止器；测试可注入，生产使用 `taskkill /T`。
typedef CursorProcessTreeKiller = Future<bool> Function(int processId);

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
  CursorProcessTreeKiller? windowsTreeKiller,
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
    final process = await (delegate ?? Process.start)(
      command.executable,
      command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    if (Platform.isWindows && _isWindowsWrapper(command.displayPath)) {
      return _WindowsCursorProcess(
        process,
        treeKiller: windowsTreeKiller ?? _killWindowsProcessTree,
      );
    }
    return process;
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

bool _isWindowsWrapper(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.cmd') ||
      lower.endsWith('.bat') ||
      lower.endsWith('.ps1');
}

Future<bool> _killWindowsProcessTree(int processId) async {
  try {
    final result = await Process.run('taskkill.exe', <String>[
      '/PID',
      '$processId',
      '/T',
      '/F',
    ]).timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } catch (error, stackTrace) {
    _log.warning(
      'Could not terminate Cursor wrapper process tree',
      error,
      stackTrace,
    );
    return false;
  }
}

/// Cursor 官方 Windows wrapper 会再启动 Node；只杀 wrapper 会留下占用 cwd 的子进程。
class _WindowsCursorProcess implements Process {
  _WindowsCursorProcess(this._delegate, {required this.treeKiller});

  final Process _delegate;
  final CursorProcessTreeKiller treeKiller;
  bool _killStarted = false;

  @override
  int get pid => _delegate.pid;

  @override
  IOSink get stdin => _delegate.stdin;

  @override
  Stream<List<int>> get stdout => _delegate.stdout;

  @override
  Stream<List<int>> get stderr => _delegate.stderr;

  @override
  Future<int> get exitCode => _delegate.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_killStarted) {
      return true;
    }
    _killStarted = true;
    unawaited(
      treeKiller(pid).then((killed) {
        if (!killed) {
          _delegate.kill(signal);
        }
      }),
    );
    return true;
  }
}
