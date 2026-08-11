import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.claude_code.process_starter');

/// 实际传给 [Process.start] 的 Claude Code stream-json 启动参数。
class ResolvedClaudeCodeProcessCommand {
  const ResolvedClaudeCodeProcessCommand({
    required this.executable,
    required this.arguments,
    required this.displayPath,
  });

  final String executable;
  final List<String> arguments;
  final String displayPath;
}

/// 组装 Claude Code MVP 启动参数（顺序稳定，便于单测与冒烟 diff）。
///
/// 固定前缀：`--print --input-format stream-json --output-format stream-json
/// --verbose`；其后按固定顺序追加可选 flag。
List<String> buildClaudeCodeProcessArguments({
  String? sessionId,
  String? resumeSessionId,
  String? model,
  String? permissionPromptTool = 'stdio',
  String? permissionMode,
  bool includePartialMessages = false,
  bool noSessionPersistence = false,
  List<String> extraArguments = const <String>[],
}) {
  final args = <String>[
    '--print',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
  ];

  final resume = resumeSessionId?.trim();
  if (resume != null && resume.isNotEmpty) {
    args
      ..add('--resume')
      ..add(resume);
  } else {
    final sid = sessionId?.trim();
    if (sid != null && sid.isNotEmpty) {
      args
        ..add('--session-id')
        ..add(sid);
    }
  }

  final modelId = model?.trim();
  if (modelId != null && modelId.isNotEmpty) {
    args
      ..add('--model')
      ..add(modelId);
  }

  final promptTool = permissionPromptTool?.trim();
  if (promptTool != null && promptTool.isNotEmpty) {
    args
      ..add('--permission-prompt-tool')
      ..add(promptTool);
  }

  final mode = permissionMode?.trim();
  if (mode != null && mode.isNotEmpty) {
    args
      ..add('--permission-mode')
      ..add(mode);
  }

  if (includePartialMessages) {
    args.add('--include-partial-messages');
  }
  if (noSessionPersistence) {
    args.add('--no-session-persistence');
  }

  args.addAll(extraArguments);
  return List<String>.unmodifiable(args);
}

/// 解析可执行路径；**不**预判可用性（找不到时仍返回 config.command 原值）。
///
/// Windows 尝试 `where.exe`；类 Unix 尝试 `command -v`。解析失败则原样使用
/// [AgentProviderConfig.command]（可能是 PATH 名或绝对路径）。
Future<ResolvedClaudeCodeProcessCommand> resolveClaudeCodeProcessCommand(
  AgentProviderConfig config, {
  String? sessionId,
  String? resumeSessionId,
  String? model,
  String? permissionPromptTool = 'stdio',
  String? permissionMode,
  bool includePartialMessages = false,
  bool noSessionPersistence = false,
  Future<String?> Function(String command)? whichLookup,
}) async {
  final configured = config.command.trim().isEmpty
      ? AgentProviderConfig.defaultClaudeCode.command
      : config.command.trim();
  final cliPath = config.extra['cliPath'];
  final preferred = cliPath is String && cliPath.trim().isNotEmpty
      ? cliPath.trim()
      : configured;

  final lookup = whichLookup ?? _defaultWhichLookup;
  final resolvedExecutable = await lookup(preferred) ?? preferred;

  final args = buildClaudeCodeProcessArguments(
    sessionId: sessionId,
    resumeSessionId: resumeSessionId,
    model: model ?? config.selectedModel ?? config.defaultModel,
    permissionPromptTool: permissionPromptTool,
    permissionMode: permissionMode,
    includePartialMessages: includePartialMessages,
    noSessionPersistence: noSessionPersistence,
    extraArguments: config.arguments,
  );

  return ResolvedClaudeCodeProcessCommand(
    executable: resolvedExecutable,
    arguments: args,
    displayPath: preferred,
  );
}

/// 创建 [StreamJsonPeer] / [Process.start] 使用的启动器。
ProcessStarter claudeCodeProcessStarter(
  AgentProviderConfig config, {
  String? sessionId,
  String? resumeSessionId,
  String? model,
  String? permissionPromptTool = 'stdio',
  String? permissionMode,
  bool includePartialMessages = false,
  bool noSessionPersistence = false,
  ProcessStarter? delegate,
  Future<String?> Function(String command)? whichLookup,
}) {
  return (
    String _,
    List<String> _, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = await resolveClaudeCodeProcessCommand(
      config,
      sessionId: sessionId,
      resumeSessionId: resumeSessionId,
      model: model,
      permissionPromptTool: permissionPromptTool,
      permissionMode: permissionMode,
      includePartialMessages: includePartialMessages,
      noSessionPersistence: noSessionPersistence,
      whichLookup: whichLookup,
    );
    _log.i('Claude Code CLI executable resolved');
    return (delegate ?? Process.start)(
      command.executable,
      command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  };
}

Future<String?> _defaultWhichLookup(String command) async {
  if (command.contains('/') ||
      command.contains('\\') ||
      command.contains(':')) {
    // 已是路径形态：不在 starter 内 stat/预判，原样返回。
    return command;
  }
  try {
    if (Platform.isWindows) {
      final result = await Process.run('where.exe', <String>[command]);
      if (result.exitCode != 0) {
        return null;
      }
      final stdout = result.stdout;
      if (stdout is! String) {
        return null;
      }
      final first = stdout
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      return first.isEmpty ? null : first;
    }
    final result = await Process.run('sh', <String>[
      '-c',
      'command -v ${shellQuote(command)}',
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final stdout = result.stdout;
    if (stdout is! String) {
      return null;
    }
    final path = stdout.trim();
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}

/// 单测可见的简易 shell 引号（仅用于 which 查询拼接）。
String shellQuote(String value) {
  if (!value.contains("'")) {
    return "'$value'";
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}
