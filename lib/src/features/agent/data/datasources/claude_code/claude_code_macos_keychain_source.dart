import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Claude Code secure storage 的只读窄接口。
///
/// 返回值只在调用栈内存活；实现不得记录、缓存或持久化凭据正文。
abstract interface class ClaudeCodeSecureCredentialsSource {
  Future<String?> read();
}

/// 参数化 `security` 调用的白名单结果；刻意不保存 stderr。
final class ClaudeCodeKeychainProcessResult {
  const ClaudeCodeKeychainProcessResult({
    required this.exitCode,
    required this.stdout,
  });

  final int exitCode;
  final String stdout;

  @override
  String toString() {
    return 'ClaudeCodeKeychainProcessResult('
        'exitCode: $exitCode, hasOutput: ${stdout.trim().isNotEmpty})';
  }
}

typedef ClaudeCodeKeychainProcessRun =
    Future<ClaudeCodeKeychainProcessResult> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
    });

/// 只读访问 Claude Code 在 macOS Keychain 中的 OAuth secure storage。
///
/// 命令始终通过 executable + 参数数组启动，不经过 shell。任何缺失、拒绝、超时或
/// 损坏输出都折叠为 null，由上层 reader 再读取 `.credentials.json`。
final class ClaudeCodeMacOsKeychainSource
    implements ClaudeCodeSecureCredentialsSource {
  ClaudeCodeMacOsKeychainSource({
    Map<String, String>? environment,
    String? accountName,
    ClaudeCodeKeychainProcessRun? processRunner,
    this.timeout = const Duration(seconds: 10),
  }) : _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _accountName = _nonEmpty(accountName),
       _processRunner = processRunner ?? _runSecurity;

  final Map<String, String> _environment;
  final String? _accountName;
  final ClaudeCodeKeychainProcessRun _processRunner;
  final Duration timeout;

  /// Claude Code 当前环境对应的 service 名；不含用户身份或凭据。
  String get serviceName => claudeCodeMacOsKeychainServiceName(_environment);

  /// Keychain generic password 的 account 参数。
  String get accountName {
    return _accountName ??
        _nonEmpty(_environment['USER']) ??
        _nonEmpty(_environment['LOGNAME']) ??
        'claude-code-user';
  }

  @override
  Future<String?> read() async {
    try {
      final result = await _processRunner('security', <String>[
        'find-generic-password',
        '-a',
        accountName,
        '-w',
        '-s',
        serviceName,
      ], timeout: timeout);
      if (result.exitCode != 0) {
        return null;
      }
      return _nonEmpty(result.stdout);
    } catch (_) {
      return null;
    }
  }
}

/// 复现 Claude Code 的 Keychain service 命名规则。
///
/// production 默认目录使用 `Claude Code-credentials`；显式
/// `CLAUDE_CONFIG_DIR` 会附加目录字符串 SHA-256 的前八个十六进制字符。
String claudeCodeMacOsKeychainServiceName(Map<String, String> environment) {
  final configDirectory = _nonEmpty(environment['CLAUDE_CONFIG_DIR']);
  // Claude Code 的 getClaudeConfigHomeDir() 会先做 NFC；否则 macOS 上视觉
  // 相同但码点组合不同的目录会落到另一个 Keychain service。
  final normalizedConfigDirectory = configDirectory == null
      ? null
      : unorm.nfc(configDirectory);
  final directorySuffix = configDirectory == null
      ? ''
      : '-${sha256.convert(utf8.encode(normalizedConfigDirectory!)).toString().substring(0, 8)}';
  return 'Claude Code${_oauthEnvironmentSuffix(environment)}'
      '-credentials$directorySuffix';
}

String _oauthEnvironmentSuffix(Map<String, String> environment) {
  if (_nonEmpty(environment['CLAUDE_CODE_CUSTOM_OAUTH_URL']) != null) {
    return '-custom-oauth';
  }
  if (environment['USER_TYPE'] == 'ant') {
    if (_isTruthy(environment['USE_LOCAL_OAUTH'])) {
      return '-local-oauth';
    }
    if (_isTruthy(environment['USE_STAGING_OAUTH'])) {
      return '-staging-oauth';
    }
  }
  return '';
}

bool _isTruthy(String? value) {
  return const <String>{
    '1',
    'true',
    'yes',
    'on',
  }.contains(value?.trim().toLowerCase());
}

Future<ClaudeCodeKeychainProcessResult> _runSecurity(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  Process? process;
  try {
    process = await Process.start(executable, arguments, runInShell: false);
    final stdout = _readBounded(process.stdout);
    final stderrDone = process.stderr.drain<void>();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process?.kill();
        throw TimeoutException('Claude Code keychain read timed out', timeout);
      },
    );
    final output = await stdout;
    await stderrDone;
    return ClaudeCodeKeychainProcessResult(exitCode: exitCode, stdout: output);
  } catch (_) {
    process?.kill();
    rethrow;
  }
}

Future<String> _readBounded(
  Stream<List<int>> source, {
  int maxBytes = 1024 * 1024,
}) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in source) {
    length += chunk.length;
    if (length > maxBytes) {
      throw const FormatException('Claude Code keychain output is too large');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}

String? _nonEmpty(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
