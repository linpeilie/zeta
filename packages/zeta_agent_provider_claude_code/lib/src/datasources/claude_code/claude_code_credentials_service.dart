import 'dart:convert';
import 'dart:io';

import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:zeta_agent_core/zeta_agent_core.dart' show AgentProviderConfig;

import 'claude_code_macos_keychain_source.dart';
import 'claude_code_credentials_refresh.dart';

/// Claude data 层统一入口。read 只读；ensureFresh 按需刷新并更新 CLI 自有存储。
abstract interface class ClaudeCodeCredentialsService {
  Future<ClaudeCodeCredentialsResult> read();
  Future<ClaudeCodeCredentialsResult> ensureFresh();
}

enum ClaudeCodeCredentialsStatus {
  available,
  missing,
  unreadable,
  malformed,
  notApplicable,
  unsupported,
}

enum ClaudeCodeCredentialsSource { environment, keychain, file }

enum ClaudeCodeCredentialsPlatform { macOS, windows, linux }

enum ClaudeCodeCredentialExpiry { valid, expiringSoon, expired, unknown }

/// 一次读取的凭据快照。读取成功不代表服务器仍接受 token。
final class ClaudeCodeOAuthCredentials {
  ClaudeCodeOAuthCredentials({
    required this.accessToken,
    this.refreshToken,
    DateTime? expiresAt,
    this.subscriptionType,
    this.rateLimitTier,
    List<String> scopes = const <String>[],
  }) : expiresAt = expiresAt?.toUtc(),
       scopes = List<String>.unmodifiable(scopes);

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? subscriptionType;
  final String? rateLimitTier;
  final List<String> scopes;

  ClaudeCodeCredentialExpiry expiryAt(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return ClaudeCodeCredentialExpiry.unknown;
    final remaining = expiry.difference(now);
    if (remaining <= Duration.zero) return ClaudeCodeCredentialExpiry.expired;
    if (remaining <= const Duration(minutes: 5)) {
      return ClaudeCodeCredentialExpiry.expiringSoon;
    }
    return ClaudeCodeCredentialExpiry.valid;
  }

  @override
  String toString() => 'ClaudeCodeOAuthCredentials(hasCredentials: true)';
}

/// 不携带路径、底层异常或原始 JSON 的读取结果。
final class ClaudeCodeCredentialsResult {
  const ClaudeCodeCredentialsResult.available(
    ClaudeCodeOAuthCredentials this.credentials, {
    required ClaudeCodeCredentialsSource this.source,
  }) : status = ClaudeCodeCredentialsStatus.available;

  const ClaudeCodeCredentialsResult.missing({this.source})
    : status = ClaudeCodeCredentialsStatus.missing,
      credentials = null;

  const ClaudeCodeCredentialsResult.unreadable({this.source})
    : status = ClaudeCodeCredentialsStatus.unreadable,
      credentials = null;

  const ClaudeCodeCredentialsResult.malformed({this.source})
    : status = ClaudeCodeCredentialsStatus.malformed,
      credentials = null;

  const ClaudeCodeCredentialsResult.notApplicable()
    : status = ClaudeCodeCredentialsStatus.notApplicable,
      credentials = null,
      source = null;

  const ClaudeCodeCredentialsResult.unsupported({this.source})
    : status = ClaudeCodeCredentialsStatus.unsupported,
      credentials = null;

  final ClaudeCodeCredentialsStatus status;
  final ClaudeCodeCredentialsSource? source;
  final ClaudeCodeOAuthCredentials? credentials;

  @override
  String toString() =>
      'ClaudeCodeCredentialsResult('
      'status: ${status.name}, source: ${source?.name})';
}

/// 内部文件读取边界；null 仅代表缺失，IO 异常由统一入口分类。
abstract interface class ClaudeCodeCredentialsFileSource {
  Future<String?> read(String path);
}

final class FileClaudeCodeCredentialsFileSource
    implements ClaudeCodeCredentialsFileSource {
  const FileClaudeCodeCredentialsFileSource();

  @override
  Future<String?> read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException catch (error) {
      // ENOENT / Windows ERROR_FILE_NOT_FOUND / ERROR_PATH_NOT_FOUND。
      if (error.osError?.errorCode == 2 ||
          (Platform.isWindows && error.osError?.errorCode == 3)) {
        return null;
      }
      rethrow;
    }
  }
}

/// 三个平台唯一的凭据来源路由与解码实现。
///
/// 环境变量来自所属 Provider 的有效环境。构造不做 IO；每次 read 重新读取，
/// 使外部 CLI 登录/轮换在下一次调用可见。原始数据仅在调用期间持有。
final class LocalClaudeCodeCredentialsService
    implements ClaudeCodeCredentialsService {
  LocalClaudeCodeCredentialsService({
    Map<String, String>? environment,
    this.oauthEnabled = true,
    ClaudeCodeCredentialsPlatform? platform,
    this.credentialsPath,
    this.homeDirectory,
    ClaudeCodeCredentialsFileSource? fileSource,
    ClaudeCodeSecureCredentialsSource? secureSource,
    this.secureWriter,
    ClaudeCodeOAuthRefreshClient? refreshClient,
    ClaudeCodeCredentialLock? refreshLock,
    ClaudeCodeCredentialRefreshCoordinator? refreshCoordinator,
    DateTime Function()? clock,
  }) : _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _platform = platform ?? _currentPlatform(),
       _refreshClient =
           refreshClient ?? HttpClaudeCodeOAuthRefreshClient(clock: clock),
       _refreshLock = refreshLock ?? const DirectoryClaudeCodeCredentialLock(),
       _refreshCoordinator =
           refreshCoordinator ?? ClaudeCodeCredentialRefreshCoordinator(),
       _clock = clock ?? DateTime.now,
       _fileSource = fileSource ?? const FileClaudeCodeCredentialsFileSource(),
       _secureSource =
           secureSource ??
           ClaudeCodeMacOsKeychainSource(environment: environment);

  factory LocalClaudeCodeCredentialsService.forProvider(
    AgentProviderConfig config, {
    ClaudeCodeCredentialRefreshCoordinator? refreshCoordinator,
  }) => LocalClaudeCodeCredentialsService(
    refreshCoordinator: refreshCoordinator,
    oauthEnabled:
        !config.arguments.contains('--bare') &&
        config.extra['hasApiKey'] != true,
    environment: {...Platform.environment, ...config.environment},
  );

  final ClaudeCodeSecureCredentialsWriter? secureWriter;
  final ClaudeCodeOAuthRefreshClient _refreshClient;
  final ClaudeCodeCredentialLock _refreshLock;
  final ClaudeCodeCredentialRefreshCoordinator _refreshCoordinator;
  final DateTime Function() _clock;
  final bool oauthEnabled;
  final Map<String, String> _environment;
  final ClaudeCodeCredentialsPlatform? _platform;
  final String? credentialsPath;
  final String? homeDirectory;
  final ClaudeCodeCredentialsFileSource _fileSource;
  final ClaudeCodeSecureCredentialsSource _secureSource;

  @override
  Future<ClaudeCodeCredentialsResult> read() async {
    if (!oauthEnabled || _usesOtherAuthentication) {
      return const ClaudeCodeCredentialsResult.notApplicable();
    }
    final token = _nonEmpty(_environment['CLAUDE_CODE_OAUTH_TOKEN']);
    if (token != null) {
      return ClaudeCodeCredentialsResult.available(
        ClaudeCodeOAuthCredentials(
          accessToken: token,
          scopes: const ['user:inference'],
        ),
        source: ClaudeCodeCredentialsSource.environment,
      );
    }
    // FD numbers refer to the owning process. Never borrow another account
    // from storage when the host has not supplied an FD credential contract.
    if (_nonEmpty(_environment['CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR']) !=
        null) {
      return const ClaudeCodeCredentialsResult.unsupported(
        source: ClaudeCodeCredentialsSource.environment,
      );
    }
    if (_platform == null) {
      return const ClaudeCodeCredentialsResult.unsupported();
    }

    ClaudeCodeCredentialsResult? keychainFailure;
    if (_platform == ClaudeCodeCredentialsPlatform.macOS) {
      String? raw;
      try {
        raw = await _secureSource.read();
      } catch (_) {
        keychainFailure = const ClaudeCodeCredentialsResult.unreadable(
          source: ClaudeCodeCredentialsSource.keychain,
        );
      }
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          // A readable storage object is authoritative, even when its OAuth
          // data is missing, invalid or expired. Never switch accounts for it.
          if (decoded is Map) {
            return _decodeOAuth(decoded, ClaudeCodeCredentialsSource.keychain);
          }
          keychainFailure = const ClaudeCodeCredentialsResult.malformed(
            source: ClaudeCodeCredentialsSource.keychain,
          );
        } catch (_) {
          keychainFailure = const ClaudeCodeCredentialsResult.malformed(
            source: ClaudeCodeCredentialsSource.keychain,
          );
        }
      }
    }

    final path = _resolveCredentialsPath();
    if (path == null) {
      return keychainFailure ?? const ClaudeCodeCredentialsResult.missing();
    }
    try {
      final result = _decode(
        await _fileSource.read(path),
        ClaudeCodeCredentialsSource.file,
      );
      if (result.status == ClaudeCodeCredentialsStatus.missing &&
          keychainFailure != null &&
          keychainFailure.status != ClaudeCodeCredentialsStatus.missing) {
        return keychainFailure;
      }
      return result;
    } catch (_) {
      return const ClaudeCodeCredentialsResult.unreadable(
        source: ClaudeCodeCredentialsSource.file,
      );
    }
  }

  @override
  Future<ClaudeCodeCredentialsResult> ensureFresh() async {
    try {
      return await _ensureFresh();
    } on ClaudeCodeCredentialRefreshException {
      rethrow;
    } catch (_) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.unavailable,
      );
    }
  }

  Future<ClaudeCodeCredentialsResult> _ensureFresh() async {
    final initial = await read();
    if (!_needsRefresh(initial)) return initial;
    final path = _resolveCredentialsPath();
    if (path == null ||
        initial.source == ClaudeCodeCredentialsSource.environment) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.unavailable,
      );
    }
    // Do not send custom/staging credentials to the production issuer.
    if (_nonEmpty(_environment['CLAUDE_CODE_CUSTOM_OAUTH_URL']) != null ||
        _nonEmpty(_environment['CLAUDE_CODE_OAUTH_CLIENT_ID']) != null ||
        (_environment['USER_TYPE'] == 'ant' &&
            ['USE_LOCAL_OAUTH', 'USE_STAGING_OAUTH'].any(
              (key) => [
                '1',
                'true',
                'yes',
                'on',
              ].contains(_environment[key]?.trim().toLowerCase()),
            ))) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.unsupportedIssuer,
      );
    }
    final String directory;
    try {
      directory = await File(path).parent.resolveSymbolicLinks();
    } catch (_) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.lockUnavailable,
      );
    }
    final identity =
        '$directory|${_platform?.name}|${_environment['USER'] ?? _environment['LOGNAME'] ?? ''}|${_environment['CLAUDE_CONFIG_DIR'] ?? ''}';
    return _refreshCoordinator.run(
      identity,
      () => _refreshLock.run(directory, (validate) async {
        final fresh = await read();
        if (!_needsRefresh(fresh)) return fresh;
        final source = fresh.source;
        final String? raw;
        if (source == ClaudeCodeCredentialsSource.keychain) {
          raw = await _secureSource.read();
        } else if (source == ClaudeCodeCredentialsSource.file) {
          // An unreadable/corrupt primary may later shadow a rotated file token.
          if (_platform == ClaudeCodeCredentialsPlatform.macOS) {
            try {
              if (await _secureSource.read() != null) {
                throw const ClaudeCodeCredentialRefreshException(
                  ClaudeCodeCredentialRefreshFailure.sourceChanged,
                );
              }
            } catch (_) {
              throw const ClaudeCodeCredentialRefreshException(
                ClaudeCodeCredentialRefreshFailure.sourceChanged,
              );
            }
          }
          if (await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.link) {
            throw const ClaudeCodeCredentialRefreshException(
              ClaudeCodeCredentialRefreshFailure.sourceChanged,
            );
          }
          raw = await _fileSource.read(path);
        } else {
          throw const ClaudeCodeCredentialRefreshException(
            ClaudeCodeCredentialRefreshFailure.unavailable,
          );
        }
        final current = _decode(raw, source!);
        if (!_needsRefresh(current)) return current;
        final credentials = current.credentials!;
        if (credentials.refreshToken == null ||
            !credentials.scopes.contains('user:inference')) {
          throw const ClaudeCodeCredentialRefreshException(
            ClaudeCodeCredentialRefreshFailure.unavailable,
          );
        }
        final writer = source == ClaudeCodeCredentialsSource.keychain
            ? secureWriter ??
                  (_secureSource is ClaudeCodeSecureCredentialsWriter
                      ? _secureSource as ClaudeCodeSecureCredentialsWriter
                      : null)
            : null;
        if (source == ClaudeCodeCredentialsSource.keychain) {
          try {
            if (writer == null) {
              throw const ClaudeCodeSecureCredentialsWriteException(
                ClaudeCodeCredentialPersistenceStage.preflight,
                ClaudeCodeCredentialPersistenceReason.writerUnavailable,
              );
            }
            writer.validateWrite(raw!);
          } catch (error) {
            throw _persistenceException(error,
              source: source,
              stage: ClaudeCodeCredentialPersistenceStage.preflight,
              refreshCompleted: false,
            );
          }
        }
        Future<void> validateSourceDirectory() async {
          if (await File(path).parent.resolveSymbolicLinks() != directory) {
            throw const ClaudeCodeCredentialRefreshException(
              ClaudeCodeCredentialRefreshFailure.sourceChanged,
            );
          }
        }

        await validateSourceDirectory();
        await validate();
        final next = await _refreshClient.refresh(credentials);
        if (next.accessToken.isEmpty ||
            next.refreshToken == null ||
            !(next.expiresAt?.isAfter(_clock()) ?? false)) {
          throw const ClaudeCodeCredentialRefreshException(
            ClaudeCodeCredentialRefreshFailure.invalidResponse,
          );
        }
        // Commit even when a requesting runtime was disposed during HTTP. The
        // server may have rotated the refresh token; callers guard publication.
        await validate();
        await validateSourceDirectory();
        final selected = await read();
        final latestRaw = source == ClaudeCodeCredentialsSource.keychain
            ? await _secureSource.read()
            : await _fileSource.read(path);
        if (selected.source != source || latestRaw != raw) {
          throw const ClaudeCodeCredentialRefreshException(
            ClaudeCodeCredentialRefreshFailure.sourceChanged,
          );
        }
        final envelope = jsonDecode(raw!) as Map<String, dynamic>;
        final oauth = Map<String, dynamic>.from(
          envelope['claudeAiOauth'] as Map,
        );
        oauth.addAll({
          'accessToken': next.accessToken,
          'refreshToken': next.refreshToken,
          'expiresAt': next.expiresAt!.millisecondsSinceEpoch,
          'scopes': next.scopes,
        });
        envelope['claudeAiOauth'] = oauth;
        final encoded = jsonEncode(envelope);
        try {
          await validate();
          if (source == ClaudeCodeCredentialsSource.keychain) {
            await writer!.write(encoded);
          } else {
            await writeClaudeCredentialFile(path, encoded);
          }
          final saved = await read();
          if (saved.status != ClaudeCodeCredentialsStatus.available) {
            throw const ClaudeCodeSecureCredentialsWriteException(
              ClaudeCodeCredentialPersistenceStage.verify,
              ClaudeCodeCredentialPersistenceReason.readbackUnavailable,
            );
          }
          if (saved.source != source ||
              saved.credentials?.accessToken != next.accessToken ||
              saved.credentials?.refreshToken != next.refreshToken ||
              saved.credentials?.expiresAt != next.expiresAt) {
            throw const ClaudeCodeSecureCredentialsWriteException(
              ClaudeCodeCredentialPersistenceStage.verify,
              ClaudeCodeCredentialPersistenceReason.readbackMismatch,
            );
          }
          return saved;
        } catch (error) {
          if (error is ClaudeCodeCredentialRefreshException &&
              error.failure != ClaudeCodeCredentialRefreshFailure.persistence) {
            rethrow;
          }
          throw _persistenceException(error,
            source: source,
            stage: ClaudeCodeCredentialPersistenceStage.write,
            refreshCompleted: true,
          );
        }
      }),
    );
  }

  bool _needsRefresh(ClaudeCodeCredentialsResult result) {
    if (result.status == ClaudeCodeCredentialsStatus.unreadable ||
        result.status == ClaudeCodeCredentialsStatus.malformed) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.unavailable,
      );
    }
    final expiry = result.credentials?.expiryAt(_clock());
    return expiry == ClaudeCodeCredentialExpiry.expired ||
        expiry == ClaudeCodeCredentialExpiry.expiringSoon;
  }

  bool get _usesOtherAuthentication =>
      _nonEmpty(_environment['ANTHROPIC_API_KEY']) != null ||
      _nonEmpty(_environment['ANTHROPIC_AUTH_TOKEN']) != null ||
      _nonEmpty(_environment['CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR']) != null ||
      const [
        'CLAUDE_CODE_USE_BEDROCK',
        'CLAUDE_CODE_USE_VERTEX',
        'CLAUDE_CODE_USE_FOUNDRY',
      ].any(
        (key) => const [
          '1',
          'true',
          'yes',
          'on',
        ].contains(_environment[key]?.trim().toLowerCase()),
      );

  String? _resolveCredentialsPath() {
    final injected = _nonEmpty(credentialsPath);
    if (injected != null) return injected;
    final windows = _platform == ClaudeCodeCredentialsPlatform.windows;
    final separator = windows ? r'\' : '/';
    final home =
        _nonEmpty(homeDirectory) ??
        _nonEmpty(_environment[windows ? 'USERPROFILE' : 'HOME']);
    final configured = _nonEmpty(_environment['CLAUDE_CONFIG_DIR']);
    final directory = configured != null
        ? unorm.nfc(configured)
        : home == null
        ? null
        : '$home$separator.claude';
    if (directory == null) return null;
    final trailingSeparator =
        directory.endsWith(separator) || (windows && directory.endsWith('/'));
    return '$directory${trailingSeparator ? '' : separator}.credentials.json';
  }
}

ClaudeCodeCredentialsPlatform? _currentPlatform() {
  if (Platform.isMacOS) return ClaudeCodeCredentialsPlatform.macOS;
  if (Platform.isWindows) return ClaudeCodeCredentialsPlatform.windows;
  if (Platform.isLinux) return ClaudeCodeCredentialsPlatform.linux;
  return null;
}

ClaudeCodeCredentialsResult _decode(
  String? source,
  ClaudeCodeCredentialsSource origin,
) {
  if (source == null || source.trim().isEmpty) {
    return ClaudeCodeCredentialsResult.missing(source: origin);
  }
  try {
    return _decodeOAuth(jsonDecode(source), origin);
  } catch (_) {
    return ClaudeCodeCredentialsResult.malformed(source: origin);
  }
}

ClaudeCodeCredentialsResult _decodeOAuth(
  Object? decoded,
  ClaudeCodeCredentialsSource origin,
) {
  try {
    if (decoded is! Map) {
      return ClaudeCodeCredentialsResult.malformed(source: origin);
    }
    final oauth = decoded['claudeAiOauth'];
    if (oauth == null) {
      return ClaudeCodeCredentialsResult.missing(source: origin);
    }
    if (oauth is! Map || _nonEmpty(oauth['accessToken']) == null) {
      return ClaudeCodeCredentialsResult.malformed(source: origin);
    }
    final rawExpiry = oauth['expiresAt'];
    final milliseconds = _unixMilliseconds(rawExpiry);
    if (rawExpiry != null && milliseconds == null) {
      return ClaudeCodeCredentialsResult.malformed(source: origin);
    }
    return ClaudeCodeCredentialsResult.available(
      ClaudeCodeOAuthCredentials(
        accessToken: _nonEmpty(oauth['accessToken'])!,
        refreshToken: _nonEmpty(oauth['refreshToken']),
        expiresAt: milliseconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
        subscriptionType: _nonEmpty(oauth['subscriptionType']),
        rateLimitTier: _nonEmpty(oauth['rateLimitTier']),
        scopes: _stringList(oauth['scopes']),
      ),
      source: origin,
    );
  } catch (_) {
    return ClaudeCodeCredentialsResult.malformed(source: origin);
  }
}

List<String> _stringList(Object? value) => value is List
    ? value.map(_nonEmpty).whereType<String>().toSet().toList(growable: false)
    : const [];

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _unixMilliseconds(Object? value) => switch (value) {
  int() => value,
  double() when value.isFinite && value == value.truncateToDouble() =>
    value.toInt(),
  String() => int.tryParse(value.trim()),
  _ => null,
};

ClaudeCodeCredentialRefreshException _persistenceException(
  Object error, {
  required ClaudeCodeCredentialsSource? source,
  required ClaudeCodeCredentialPersistenceStage stage,
  required bool refreshCompleted,
}) {
  final detail = error is ClaudeCodeSecureCredentialsWriteException ? error : null;
  return ClaudeCodeCredentialRefreshException(
    ClaudeCodeCredentialRefreshFailure.persistence,
    source: source,
    persistenceStage: detail?.stage ?? stage,
    persistenceReason: detail?.reason ?? (source == ClaudeCodeCredentialsSource.file
        ? ClaudeCodeCredentialPersistenceReason.fileWriteFailed
        : ClaudeCodeCredentialPersistenceReason.commandFailed),
    refreshCompleted: refreshCompleted,
    exitCode: detail?.exitCode,
  );
}
