import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Claude Code secure storage 的只读窄接口。
///
/// 返回值只在调用栈内存活；null 仅代表缺失，失败抛脱敏异常。
/// 实现不得记录、缓存或持久化凭据正文。
abstract interface class ClaudeCodeSecureCredentialsSource {
  Future<String?> read();
}

/// Writes only the already-selected Keychain item; no migration or deletion.
abstract interface class ClaudeCodeSecureCredentialsWriter {
  void validateWrite(String contents);
  Future<void> write(String contents);
}

/// 统一入口将其映射为 unreadable；不携带 stderr、路径或凭据。
base class ClaudeCodeSecureCredentialsUnavailable implements Exception {
  const ClaudeCodeSecureCredentialsUnavailable();

  @override
  String toString() => 'ClaudeCodeSecureCredentialsUnavailable';
}

/// Only allow-listed diagnostics; never retain command text or stderr.
enum ClaudeCodeCredentialPersistenceStage { preflight, write, verify }

enum ClaudeCodeCredentialPersistenceReason {
  writerUnavailable,
  invalidIdentity,
  payloadTooLarge,
  processUnavailable,
  timeout,
  interactionNotAllowed,
  userCanceled,
  authenticationFailed,
  keychainUnavailable,
  commandFailed,
  fileWriteFailed,
  readbackUnavailable,
  readbackMismatch,
}

final class ClaudeCodeSecureCredentialsWriteException
    extends ClaudeCodeSecureCredentialsUnavailable {
  const ClaudeCodeSecureCredentialsWriteException(
    this.stage,
    this.reason, {
    this.exitCode,
  });
  final ClaudeCodeCredentialPersistenceStage stage;
  final ClaudeCodeCredentialPersistenceReason reason;
  final int? exitCode;

  @override
  String toString() =>
      'ClaudeCodeSecureCredentialsWriteException('
      'stage=${stage.name}, reason=${reason.name}'
      '${exitCode == null ? '' : ', exitCode=$exitCode'})';
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

typedef ClaudeCodeKeychainProcessStart =
    Future<Process> Function(String executable, List<String> arguments);

/// 访问 Claude Code 在 macOS Keychain 中的 OAuth secure storage。
///
/// 命令始终通过 executable + 参数数组启动，不经过 shell。任何缺失、拒绝、超时或
/// 失败都由统一 service 分类和回退；本层不保留底层错误。
final class ClaudeCodeMacOsKeychainSource
    implements
        ClaudeCodeSecureCredentialsSource,
        ClaudeCodeSecureCredentialsWriter {
  ClaudeCodeMacOsKeychainSource({
    Map<String, String>? environment,
    String? accountName,
    ClaudeCodeKeychainProcessRun? processRunner,
    ClaudeCodeKeychainProcessStart? processStarter,
    this.timeout = const Duration(seconds: 10),
  }) : _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _accountName = _nonEmpty(accountName),
       _processRunner = processRunner ?? _runSecurity,
       _processStarter = processStarter ?? _startSecurity;

  final Map<String, String> _environment;
  final String? _accountName;
  final ClaudeCodeKeychainProcessRun _processRunner;
  final ClaudeCodeKeychainProcessStart _processStarter;
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
  void validateWrite(String contents) {
    _writeCommand(contents);
  }

  String _writeCommand(String contents) {
    String quoted(String value) {
      if (value.contains(RegExp(r'[\r\n\x00]'))) {
        throw const ClaudeCodeSecureCredentialsWriteException(
          ClaudeCodeCredentialPersistenceStage.preflight,
          ClaudeCodeCredentialPersistenceReason.invalidIdentity,
        );
      }
      return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }

    final hex = utf8
        .encode(contents)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final command =
        'add-generic-password -U -a ${quoted(accountName)} '
        '-s ${quoted(serviceName)} -X "$hex"\n';
    // security -i has a bounded line buffer. Never fall back to secret argv.
    if (utf8.encode(command).length >= 4096) {
      throw const ClaudeCodeSecureCredentialsWriteException(
        ClaudeCodeCredentialPersistenceStage.preflight,
        ClaudeCodeCredentialPersistenceReason.payloadTooLarge,
      );
    }
    return command;
  }

  @override
  Future<void> write(String contents) async {
    final command = _writeCommand(contents);
    final Process process;
    try {
      process = await _processStarter('/usr/bin/security', ['-i']);
    } catch (_) {
      throw const ClaudeCodeSecureCredentialsWriteException(
        ClaudeCodeCredentialPersistenceStage.write,
        ClaudeCodeCredentialPersistenceReason.processUnavailable,
      );
    }
    try {
      // Bound stdin delivery and pipe draining as well as process exit.
      await (() async {
        final out = process.stdout.drain<void>().catchError((Object _) {});
        final err = _securityWriteFailure(process.stderr);
        process.stdin.write(command);
        await process.stdin.close();
        final exit = await process.exitCode;
        await out;
        final reason = await err;
        if (exit != 0 || reason != null) {
          throw ClaudeCodeSecureCredentialsWriteException(
            ClaudeCodeCredentialPersistenceStage.write,
            reason ?? ClaudeCodeCredentialPersistenceReason.commandFailed,
            exitCode: exit,
          );
        }
      })().timeout(timeout);
    } on ClaudeCodeSecureCredentialsWriteException {
      rethrow;
    } on TimeoutException {
      process.kill();
      throw const ClaudeCodeSecureCredentialsWriteException(
        ClaudeCodeCredentialPersistenceStage.write,
        ClaudeCodeCredentialPersistenceReason.timeout,
      );
    } catch (_) {
      process.kill();
      throw const ClaudeCodeSecureCredentialsWriteException(
        ClaudeCodeCredentialPersistenceStage.write,
        ClaudeCodeCredentialPersistenceReason.commandFailed,
      );
    }
    final String? saved;
    try {
      saved = await read();
    } catch (_) {
      throw const ClaudeCodeSecureCredentialsWriteException(
        ClaudeCodeCredentialPersistenceStage.verify,
        ClaudeCodeCredentialPersistenceReason.readbackUnavailable,
      );
    }
    if (saved != contents) {
      throw const ClaudeCodeSecureCredentialsWriteException(
        ClaudeCodeCredentialPersistenceStage.verify,
        ClaudeCodeCredentialPersistenceReason.readbackMismatch,
      );
    }
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
      if (result.exitCode == 44) return null;
      if (result.exitCode != 0) {
        throw const ClaudeCodeSecureCredentialsUnavailable();
      }
      return _nonEmpty(result.stdout);
    } catch (_) {
      throw const ClaudeCodeSecureCredentialsUnavailable();
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

Future<Process> _startSecurity(String executable, List<String> arguments) =>
    Process.start(executable, arguments, runInShell: false);

Future<ClaudeCodeCredentialPersistenceReason?> _securityWriteFailure(
  Stream<List<int>> stderr,
) async {
  // Keep a bounded private buffer, drain all input, emit only an enum.
  final bytes = <int>[];
  try {
    await for (final chunk in stderr) {
      final available = 16384 - bytes.length;
      if (available > 0) bytes.addAll(chunk.take(available));
    }
    final message = utf8.decode(bytes, allowMalformed: true).toLowerCase();
    if (message.contains('user interaction is not allowed')) {
      return ClaudeCodeCredentialPersistenceReason.interactionNotAllowed;
    }
    if (message.contains('user canceled') ||
        message.contains('user cancelled')) {
      return ClaudeCodeCredentialPersistenceReason.userCanceled;
    }
    if (message.contains('passphrase you entered is not correct') ||
        message.contains('authorization/authentication failed')) {
      return ClaudeCodeCredentialPersistenceReason.authenticationFailed;
    }
    if (message.contains('specified keychain could not be found') ||
        message.contains('no such keychain')) {
      return ClaudeCodeCredentialPersistenceReason.keychainUnavailable;
    }
    if (RegExp(
      r'add-generic-password: returned [1-9][0-9]*',
    ).hasMatch(message)) {
      return ClaudeCodeCredentialPersistenceReason.commandFailed;
    }
    return null;
  } catch (_) {
    return ClaudeCodeCredentialPersistenceReason.commandFailed;
  }
}
