import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_macos_keychain_source.dart';

/// Claude Code 本机 OAuth 凭证的瞬时只读快照。
///
/// 该对象只在一次账号数据请求期间存活，不提供序列化或写回能力。
final class ClaudeCodeOAuthCredentials {
  ClaudeCodeOAuthCredentials({
    required this.accessToken,
    required this.expiresAt,
    required this.subscriptionType,
    List<String> scopes = const <String>[],
  }) : scopes = List<String>.unmodifiable(scopes);

  final String accessToken;
  final DateTime expiresAt;
  final String? subscriptionType;
  final List<String> scopes;

  @override
  String toString() {
    // 凭据对象可能出现在诊断上下文中，只暴露是否存在，不输出 token 或其前缀。
    return 'ClaudeCodeOAuthCredentials(hasCredentials: true)';
  }
}

/// Claude Code 凭据文件的最小只读边界。
///
/// 刻意不提供写文件或网络方法，避免读取器获得刷新、写回凭据的能力。
abstract interface class ClaudeCodeCredentialsFileSource {
  Future<String?> read(String path);
}

/// 从本机文件系统读取 Claude Code 凭据。
final class FileClaudeCodeCredentialsFileSource
    implements ClaudeCodeCredentialsFileSource {
  const FileClaudeCodeCredentialsFileSource();

  @override
  Future<String?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }
}

/// 只读解析 Claude Code CLI 的本机 OAuth 凭据。
///
/// macOS 优先读取 Keychain，缺失或损坏时回退凭据文件；其他平台只读文件。
/// 缺失、不可读、损坏或过期时统一返回 `null`。reader 不刷新 token、不写回
/// Claude Code 配置目录，也不缓存凭据。
final class ClaudeCodeOAuthCredentialsReader {
  ClaudeCodeOAuthCredentialsReader({
    this.credentialsPath,
    this.homeDirectory,
    Map<String, String>? environment,
    ClaudeCodeCredentialsFileSource? fileSource,
    ClaudeCodeSecureCredentialsSource? secureSource,
    bool? isMacOS,
    DateTime Function()? clock,
  }) : _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _fileSource = fileSource ?? const FileClaudeCodeCredentialsFileSource(),
       _secureSource =
           secureSource ??
           ClaudeCodeMacOsKeychainSource(environment: environment),
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _clock = clock ?? DateTime.now;

  /// 测试或宿主可注入的完整凭据路径。
  final String? credentialsPath;

  /// 测试或宿主可注入的用户 home；默认从当前进程环境解析。
  final String? homeDirectory;

  final Map<String, String> _environment;
  final ClaudeCodeCredentialsFileSource _fileSource;
  final ClaudeCodeSecureCredentialsSource _secureSource;
  final bool _isMacOS;
  final DateTime Function() _clock;

  /// 解析当前平台上的 Claude Code 凭据文件路径。
  String? resolveCredentialsPath() {
    final injectedPath = _nonEmpty(credentialsPath);
    if (injectedPath != null) {
      return injectedPath;
    }
    final configDirectory =
        _nonEmpty(_environment['CLAUDE_CONFIG_DIR']) ??
        _defaultClaudeConfigDirectory();
    if (configDirectory == null) {
      return null;
    }
    return '$configDirectory${Platform.pathSeparator}.credentials.json';
  }

  /// 读取一个有效的 OAuth 凭据快照；所有降级路径均不抛异常。
  Future<ClaudeCodeOAuthCredentials?> read() async {
    if (_isMacOS) {
      try {
        final source = await _secureSource.read();
        if (source != null && source.trim().isNotEmpty) {
          final credentials = _decodeCredentials(source);
          if (credentials != null) {
            return credentials;
          }
        }
      } catch (_) {
        // Keychain 缺失、拒绝、超时或损坏时继续读取兼容文件。
      }
    }

    final path = resolveCredentialsPath();
    if (path == null) {
      return null;
    }
    try {
      final source = await _fileSource.read(path);
      if (source == null || source.trim().isEmpty) {
        return null;
      }
      return _decodeCredentials(source);
    } catch (_) {
      // 凭据不可读或格式损坏只代表当前未登录，不能阻断 Provider。
      return null;
    }
  }

  String? _defaultClaudeConfigDirectory() {
    final home =
        _nonEmpty(homeDirectory) ??
        _nonEmpty(_environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']);
    return home == null ? null : '$home${Platform.pathSeparator}.claude';
  }

  ClaudeCodeOAuthCredentials? _decodeCredentials(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final oauth = decoded['claudeAiOauth'];
    if (oauth is! Map) {
      return null;
    }
    final accessToken = _nonEmpty(oauth['accessToken']);
    final expiresAtMillis = _unixMilliseconds(oauth['expiresAt']);
    if (accessToken == null || expiresAtMillis == null) {
      return null;
    }
    final now = _clock();
    if (expiresAtMillis <= now.millisecondsSinceEpoch) {
      return null;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtMillis,
      isUtc: true,
    );
    return ClaudeCodeOAuthCredentials(
      accessToken: accessToken,
      expiresAt: expiresAt,
      subscriptionType: _nonEmpty(oauth['subscriptionType']),
      scopes: _stringList(oauth['scopes']),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final result = <String>[];
  for (final item in value) {
    final normalized = _nonEmpty(item);
    if (normalized != null && !result.contains(normalized)) {
      result.add(normalized);
    }
  }
  return result;
}

String? _nonEmpty(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _unixMilliseconds(Object? value) {
  return switch (value) {
    int() => value,
    double() when value.isFinite && value == value.truncateToDouble() =>
      value.toInt(),
    String() => int.tryParse(value.trim()),
    _ => null,
  };
}
