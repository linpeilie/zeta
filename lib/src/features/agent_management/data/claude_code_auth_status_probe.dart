import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';

/// Claude Code `auth status --json` 的白名单投影。
///
/// 该快照不保存原始 JSON、email、organization、凭据来源明细或 stderr。
final class ClaudeCodeAuthStatusSnapshot {
  const ClaudeCodeAuthStatusSnapshot({
    required this.loggedIn,
    this.authMethod,
    this.apiProvider,
    this.subscriptionType,
  });

  final bool loggedIn;
  final String? authMethod;
  final String? apiProvider;
  final String? subscriptionType;
}

typedef ClaudeCodeAuthStatusLoader =
    Future<ClaudeCodeAuthStatusSnapshot?> Function(
      AgentProviderConfig providerConfig,
    );

typedef ClaudeCodeAuthStatusProcessRun =
    Future<CliProcessResult> Function(
      ResolvedCliCommand command,
      List<String> arguments, {
      Duration timeout,
      Map<String, String>? environment,
    });

/// 通过 Claude CLI 读取认证证据；不可用或响应损坏时返回 null。
///
/// null 只表示当前命令不能提供可靠证据；合法的 `loggedIn=false` 会作为明确结果返回。
final class ClaudeCodeAuthStatusProbe {
  ClaudeCodeAuthStatusProbe({
    ClaudeCodeCliLocator? locator,
    ClaudeCodeAuthStatusProcessRun? processRunner,
  }) : _locator = locator ?? const ClaudeCodeCliLocator(),
       _processRunner =
           processRunner ??
           ((command, arguments, {timeout = _timeout, environment}) {
             return const CliProcessRunner().run(
               command,
               arguments,
               timeout: timeout,
               environment: environment,
             );
           });

  static const Duration _timeout = Duration(seconds: 10);

  final ClaudeCodeCliLocator _locator;
  final ClaudeCodeAuthStatusProcessRun _processRunner;

  Future<ClaudeCodeAuthStatusSnapshot?> probe(
    AgentProviderConfig providerConfig,
  ) async {
    try {
      final command = await _locator.locate(providerConfig);
      if (command == null) {
        return null;
      }
      final result = await _processRunner(
        command,
        const <String>['auth', 'status', '--json'],
        timeout: _timeout,
        environment: providerConfig.environment,
      );
      // 当前 CLI 用 0/1 分别表达 logged-in/logged-out；其他退出码视为命令不可用。
      if (result.exitCode != 0 && result.exitCode != 1) {
        return null;
      }
      return _decode(result.stdout);
    } on TimeoutException {
      return null;
    } on ProcessException {
      return null;
    } on FileSystemException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

ClaudeCodeAuthStatusSnapshot? _decode(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final loggedIn = decoded['loggedIn'];
  if (loggedIn is! bool) {
    return null;
  }
  return ClaudeCodeAuthStatusSnapshot(
    loggedIn: loggedIn,
    authMethod: _nonEmptyString(decoded['authMethod']),
    apiProvider: _nonEmptyString(decoded['apiProvider']),
    subscriptionType: _nonEmptyString(decoded['subscriptionType']),
  );
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
