import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'claude_code_credentials_service.dart';
import 'claude_code_macos_keychain_source.dart';

/// Stable failures only. Never attach HTTP bodies, tokens, paths or IO errors.
enum ClaudeCodeCredentialRefreshFailure {
  unavailable,
  unsupportedIssuer,
  rejected,
  transport,
  invalidResponse,
  lockUnavailable,
  lockLost,
  sourceChanged,
  persistence,
}

final class ClaudeCodeCredentialRefreshException implements Exception {
  const ClaudeCodeCredentialRefreshException(
    this.failure, {
    this.source,
    this.persistenceStage,
    this.persistenceReason,
    this.refreshCompleted,
    this.exitCode,
  });
  final ClaudeCodeCredentialRefreshFailure failure;
  final ClaudeCodeCredentialsSource? source;
  final ClaudeCodeCredentialPersistenceStage? persistenceStage;
  final ClaudeCodeCredentialPersistenceReason? persistenceReason;
  final bool? refreshCompleted;
  final int? exitCode;
  @override
  String toString() => 'ClaudeCodeCredentialRefreshException('
      '${[
        failure.name,
        if (source != null) 'source=${source!.name}',
        if (persistenceStage != null) 'stage=${persistenceStage!.name}',
        if (persistenceReason != null) 'reason=${persistenceReason!.name}',
        if (refreshCompleted != null) 'refreshCompleted=$refreshCompleted',
        if (exitCode != null) 'exitCode=$exitCode',
      ].join(', ')})';
}

/// One coordinator is shared by all runtimes of a Claude plugin activation.
/// Futures (and their secrets) are removed immediately on settlement.
final class ClaudeCodeCredentialRefreshCoordinator {
  final _pending = <String, Future<ClaudeCodeCredentialsResult>>{};

  Future<ClaudeCodeCredentialsResult> run(
    String identity,
    Future<ClaudeCodeCredentialsResult> Function() operation,
  ) async {
    final existing = _pending[identity];
    if (existing != null) return existing;
    final future = Future<ClaudeCodeCredentialsResult>.sync(operation);
    _pending[identity] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[identity], future)) _pending.remove(identity);
    }
  }
}

abstract interface class ClaudeCodeOAuthRefreshClient {
  Future<ClaudeCodeOAuthCredentials> refresh(
    ClaudeCodeOAuthCredentials current,
  );
}

/// Production OAuth only. The service rejects custom issuers before reaching
/// this client, so credentials never silently cross an issuer boundary.
final class HttpClaudeCodeOAuthRefreshClient
    implements ClaudeCodeOAuthRefreshClient {
  HttpClaudeCodeOAuthRefreshClient({
    HttpClient Function()? clientFactory,
    DateTime Function()? clock,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now;

  final HttpClient Function() _clientFactory;
  final DateTime Function() _clock;
  static final tokenUri = Uri.parse(
    'https://platform.claude.com/v1/oauth/token',
  );
  static const clientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
  static const timeout = Duration(seconds: 15);

  @override
  Future<ClaudeCodeOAuthCredentials> refresh(
    ClaudeCodeOAuthCredentials current,
  ) async {
    final client = _clientFactory();
    try {
      return await _exchange(client, current).timeout(timeout);
    } on ClaudeCodeCredentialRefreshException {
      rethrow;
    } catch (_) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.transport,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ClaudeCodeOAuthCredentials> _exchange(
    HttpClient client,
    ClaudeCodeOAuthCredentials current,
  ) async {
    final request = await client.postUrl(tokenUri);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
        'client_id': clientId,
        // Preserve the granted scope set. Zeta does not request scope expansion.
        'scope': current.scopes.join(' '),
      }),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw ClaudeCodeCredentialRefreshException(
        response.statusCode == 400 ||
                response.statusCode == 401 ||
                response.statusCode == 403
            ? ClaudeCodeCredentialRefreshFailure.rejected
            : ClaudeCodeCredentialRefreshFailure.transport,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 65536) {
        throw const ClaudeCodeCredentialRefreshException(
          ClaudeCodeCredentialRefreshFailure.invalidResponse,
        );
      }
      bytes.addAll(chunk);
    }
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map) throw const FormatException();
      final token = data['access_token'];
      final refresh = data['refresh_token'] ?? current.refreshToken;
      final seconds = data['expires_in'];
      final scope = data['scope'];
      if (token is! String ||
          token.trim().isEmpty ||
          refresh is! String ||
          refresh.trim().isEmpty ||
          seconds is! num ||
          !seconds.isFinite ||
          seconds <= 0 ||
          seconds > 31536000 ||
          seconds != seconds.truncateToDouble() ||
          (scope != null && scope is! String)) {
        throw const FormatException();
      }
      return ClaudeCodeOAuthCredentials(
        accessToken: token,
        refreshToken: refresh,
        expiresAt: _clock().toUtc().add(Duration(seconds: seconds.toInt())),
        scopes: scope is String
            ? scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList()
            : current.scopes,
        subscriptionType: current.subscriptionType,
        rateLimitTier: current.rateLimitTier,
      );
    } catch (_) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.invalidResponse,
      );
    }
  }
}

abstract interface class ClaudeCodeCredentialLock {
  Future<T> run<T>(
    String directory,
    Future<T> Function(Future<void> Function() validate) operation,
  );
}

/// Interoperates with proper-lockfile's realpath + atomic mkdir + mtime lease.
/// Does not steal stale locks: uncertain ownership fails closed.
final class DirectoryClaudeCodeCredentialLock
    implements ClaudeCodeCredentialLock {
  const DirectoryClaudeCodeCredentialLock({
    this.waitLimit = const Duration(seconds: 12),
  });
  final Duration waitLimit;

  @override
  Future<T> run<T>(
    String directory,
    Future<T> Function(Future<void> Function()) operation,
  ) async {
    final String canonical;
    try {
      canonical = await Directory(directory).resolveSymbolicLinks();
    } catch (_) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.lockUnavailable,
      );
    }
    final lockPath = '$canonical.lock';
    final deadline = Stopwatch()..start();
    while (!await _makeLock(lockPath)) {
      if (deadline.elapsed >= waitLimit) {
        throw const ClaudeCodeCredentialRefreshException(
          ClaudeCodeCredentialRefreshFailure.lockUnavailable,
        );
      }
      await Future<void>.delayed(
        Duration(milliseconds: 200 + Random().nextInt(200)),
      );
    }
    DateTime lastModified = (await Directory(lockPath).stat()).modified;
    var lost = false;
    Future<void> heartbeat = Future<void>.value();
    Future<void> validate() async {
      await heartbeat;
      final stat = await Directory(lockPath).stat();
      if (lost ||
          stat.type != FileSystemEntityType.directory ||
          stat.modified != lastModified ||
          DateTime.now().difference(lastModified) >=
              const Duration(seconds: 8)) {
        lost = true;
        throw const ClaudeCodeCredentialRefreshException(
          ClaudeCodeCredentialRefreshFailure.lockLost,
        );
      }
    }

    var heartbeatRunning = false;
    final timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (heartbeatRunning || lost) return;
      heartbeatRunning = true;
      heartbeat = heartbeat
          .then((_) async {
            if (lost) return;
            final stat = await Directory(lockPath).stat();
            if (stat.type != FileSystemEntityType.directory ||
                stat.modified != lastModified ||
                DateTime.now().difference(lastModified) >=
                    const Duration(seconds: 8)) {
              lost = true;
              return;
            }
            if (Platform.isWindows) {
              await claudeCredentialsWindowsOperation('touch', lockPath);
            } else {
              final touch = await Process.run('/usr/bin/touch', [
                '-m',
                lockPath,
              ], runInShell: false);
              if (touch.exitCode != 0) {
                lost = true;
                return;
              }
            }
            lastModified = (await Directory(lockPath).stat()).modified;
          })
          .catchError((Object _) {
            lost = true;
          })
          .whenComplete(() {
            heartbeatRunning = false;
          });
    });
    try {
      await validate();
      return await operation(validate);
    } finally {
      timer.cancel();
      await heartbeat;
      // A replaced/lost lock belongs to somebody else. Never remove it.
      final stat = await Directory(lockPath).stat();
      if (!lost &&
          stat.type == FileSystemEntityType.directory &&
          stat.modified == lastModified) {
        try {
          await Directory(lockPath).delete();
        } catch (_) {
          /* CLI can reclaim a stale empty lock. */
        }
      }
    }
  }
}

Future<bool> _makeLock(String path) async {
  try {
    if (Platform.isWindows) {
      await claudeCredentialsWindowsOperation('mkdir', path);
    } else {
      final result = await Process.run('/bin/mkdir', [path], runInShell: false);
      if (result.exitCode != 0) {
        if (await Directory(path).exists()) return false;
        throw const ClaudeCodeCredentialRefreshException(
          ClaudeCodeCredentialRefreshFailure.lockUnavailable,
        );
      }
    }
    return true;
  } catch (_) {
    if (await Directory(path).exists()) return false;
    throw const ClaudeCodeCredentialRefreshException(
      ClaudeCodeCredentialRefreshFailure.lockUnavailable,
    );
  }
}

/// OS operations only; stdin contains paths, never tokens. The fixed PowerShell
/// script uses literal .NET path APIs, with an atomic Win32 directory create.
Future<void> claudeCredentialsWindowsOperation(
  String operation,
  String path, [
  String? otherPath,
]) async {
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final process = await Process.start(
    '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', _windowsScript],
    runInShell: false,
  );
  final out = process.stdout.drain<void>();
  final err = process.stderr.drain<void>();
  process.stdin.write(
    jsonEncode({'operation': operation, 'path': path, 'other': otherPath}),
  );
  await process.stdin.close();
  try {
    final exit = await process.exitCode.timeout(const Duration(seconds: 5));
    await Future.wait([out, err]);
    if (exit != 0) {
      throw const ClaudeCodeCredentialRefreshException(
        ClaudeCodeCredentialRefreshFailure.persistence,
      );
    }
  } catch (_) {
    process.kill();
    throw const ClaudeCodeCredentialRefreshException(
      ClaudeCodeCredentialRefreshFailure.persistence,
    );
  }
}

const _windowsScript = r'''
$ErrorActionPreference = 'Stop'
try {
  $inputData = [Console]::In.ReadToEnd() | ConvertFrom-Json
  switch ($inputData.operation) {
    'mkdir' {
      Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class ZetaCredentialNative { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool CreateDirectory(string path, IntPtr security); }'
      if (-not [ZetaCredentialNative]::CreateDirectory($inputData.path, [IntPtr]::Zero)) { exit 1 }
    }
    'touch' { [IO.Directory]::SetLastWriteTimeUtc($inputData.path, [DateTime]::UtcNow) }
    'create' {
      $acl = Get-Acl -LiteralPath $inputData.other
      $stream = [IO.File]::Create($inputData.path, 4096, [IO.FileOptions]::None, $acl)
      $stream.Dispose()
    }
    'replace' { [IO.File]::Replace($inputData.path, $inputData.other, $null) }
    default { exit 1 }
  }
  exit 0
} catch { exit 1 }
''';

/// Only updates an existing file. No migration, backup or external source copy.
Future<void> writeClaudeCredentialFile(String path, String contents) async {
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const ClaudeCodeCredentialRefreshException(
      ClaudeCodeCredentialRefreshFailure.sourceChanged,
    );
  }
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temporary = File('$path.zeta-$suffix.tmp');
  try {
    if (Platform.isWindows) {
      await claudeCredentialsWindowsOperation('create', temporary.path, path);
    } else {
      await temporary.create(exclusive: true);
      final permissions = await Process.run('/bin/chmod', [
        '600',
        temporary.path,
      ], runInShell: false);
      if (permissions.exitCode != 0) {
        throw const ClaudeCodeCredentialRefreshException(
          ClaudeCodeCredentialRefreshFailure.persistence,
        );
      }
    }
    await temporary.writeAsString(contents, flush: true);
    if (Platform.isWindows) {
      await claudeCredentialsWindowsOperation('replace', temporary.path, path);
    } else {
      await temporary.rename(file.path);
    }
  } catch (_) {
    throw const ClaudeCodeCredentialRefreshException(
      ClaudeCodeCredentialRefreshFailure.persistence,
    );
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
