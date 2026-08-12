import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.claude_code.process_starter');

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

/// 组装无 Prompt 的 Claude Code metadata 探测参数。
///
/// 该进程只接受 `control_request.initialize`，不创建会话、不选择模型，也不加载
/// project/local settings。参数保持封闭，避免用户会话参数改变探测语义。
List<String> buildClaudeCodeMetadataProbeArguments() {
  return const <String>[
    '--print',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
    '--no-session-persistence',
    '--setting-sources',
    'user',
  ];
}

/// 在每次启动前重新校验 CLI，并统一解析 Windows 脚本包装器。
Future<ResolvedCliProcessCommand> resolveClaudeCodeProcessCommand(
  AgentProviderConfig config, {
  String? sessionId,
  String? resumeSessionId,
  String? model,
  String? permissionPromptTool = 'stdio',
  String? permissionMode,
  bool includePartialMessages = false,
  bool noSessionPersistence = false,
  ClaudeCodeCliLocator? locator,
}) async {
  final resolved = await (locator ?? const ClaudeCodeCliLocator()).locate(
    config,
  );
  if (resolved == null) {
    throw ProcessException(
      config.command,
      config.arguments,
      'Claude Code executable was not found',
    );
  }

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

  return resolved.processCommandFor(args);
}

/// 定位 Claude Code CLI，并生成 metadata 专用启动命令。
Future<ResolvedCliProcessCommand> resolveClaudeCodeMetadataProbeCommand(
  AgentProviderConfig config, {
  ClaudeCodeCliLocator? locator,
}) async {
  final resolved = await (locator ?? const ClaudeCodeCliLocator()).locate(
    config,
  );
  if (resolved == null) {
    throw ProcessException(
      config.command,
      const <String>[],
      'Claude Code executable was not found',
    );
  }
  return resolved.processCommandFor(buildClaudeCodeMetadataProbeArguments());
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
  ClaudeCodeCliLocator? locator,
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
      locator: locator,
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
