import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';

void main() {
  final now = DateTime.utc(2026, 9, 5);
  final expiry = now.add(const Duration(hours: 1));

  for (final platform in ClaudeCodeCredentialsPlatform.values) {
    group(platform.name, () {
      test('reads the full OAuth snapshot through the same entry', () async {
        final file = _FileSource(_json(expiresAt: expiry));
        final secure = _SecureSource(_json(expiresAt: expiry));
        final service = LocalClaudeCodeCredentialsService(
          platform: platform,
          environment: const {'HOME': '/fixture', 'USERPROFILE': r'C:\fixture'},
          fileSource: file,
          secureSource: secure,
        );
        final result = await service.read();
        expect(result.status, ClaudeCodeCredentialsStatus.available);
        final credentials = result.credentials!;
        expect(credentials.accessToken, 'fixture-access-secret');
        expect(credentials.refreshToken, 'fixture-refresh-secret');
        expect(credentials.expiresAt, expiry);
        expect(credentials.expiresAt!.isUtc, isTrue);
        expect(credentials.subscriptionType, 'max');
        expect(credentials.rateLimitTier, 'default_claude_max_5x');
        expect(credentials.scopes, ['user:inference', 'user:profile']);
        expect(() => credentials.scopes.add('other'), throwsUnsupportedError);
        if (platform == ClaudeCodeCredentialsPlatform.macOS) {
          expect(result.source, ClaudeCodeCredentialsSource.keychain);
          expect(file.paths, isEmpty);
          expect(secure.calls, 1);
        } else {
          expect(result.source, ClaudeCodeCredentialsSource.file);
          expect(secure.calls, 0);
          expect(file.paths, [
            platform == ClaudeCodeCredentialsPlatform.windows
                ? r'C:\fixture\.claude\.credentials.json'
                : '/fixture/.claude/.credentials.json',
          ]);
        }
      });

      test(
        'custom directory overrides home and isolates service instances',
        () async {
          final windows = platform == ClaudeCodeCredentialsPlatform.windows;
          final fileA = _FileSource(_json(accessToken: 'account-a'));
          final fileB = _FileSource(_json(accessToken: 'account-b'));
          final environment = <String, String>{
            'HOME': '/ignored',
            'USERPROFILE': r'C:\ignored',
            'CLAUDE_CONFIG_DIR': windows ? r'D:\a' : '/a',
          };
          final a = LocalClaudeCodeCredentialsService(
            platform: platform,
            environment: environment,
            fileSource: fileA,
            secureSource: _SecureSource(null),
          );
          environment['CLAUDE_CONFIG_DIR'] = windows ? 'D:\\b\\' : '/b/';
          final b = LocalClaudeCodeCredentialsService(
            platform: platform,
            environment: environment,
            fileSource: fileB,
            secureSource: _SecureSource(null),
          );
          expect((await a.read()).credentials!.accessToken, 'account-a');
          expect((await b.read()).credentials!.accessToken, 'account-b');
          expect(
            fileA.paths.single,
            windows ? r'D:\a\.credentials.json' : '/a/.credentials.json',
          );
          expect(
            fileB.paths.single,
            windows ? r'D:\b\.credentials.json' : '/b/.credentials.json',
          );
        },
      );

      test(
        'explicit environment token never mixes with stored credentials',
        () async {
          final file = _FileSource(_json(expiresAt: expiry));
          final secure = _SecureSource(_json(expiresAt: expiry));
          final service = LocalClaudeCodeCredentialsService(
            platform: platform,
            environment: const {'CLAUDE_CODE_OAUTH_TOKEN': 'env-secret'},
            fileSource: file,
            secureSource: secure,
          );
          final result = await service.read();
          expect(result.source, ClaudeCodeCredentialsSource.environment);
          expect(result.credentials!.accessToken, 'env-secret');
          expect(result.credentials!.refreshToken, isNull);
          expect(result.credentials!.expiresAt, isNull);
          expect(
            result.credentials!.expiryAt(now),
            ClaudeCodeCredentialExpiry.unknown,
          );
          expect(result.credentials!.scopes, ['user:inference']);
          expect(file.paths, isEmpty);
          expect(secure.calls, 0);
        },
      );

      test('re-reads external rotation and logout without caching', () async {
        final file = _FileSource(_json(accessToken: 'old'));
        final secure = _SecureSource(_json(accessToken: 'old'));
        final service = LocalClaudeCodeCredentialsService(
          platform: platform,
          environment: const {},
          credentialsPath: '/fixture',
          fileSource: file,
          secureSource: secure,
        );
        expect((await service.read()).credentials!.accessToken, 'old');
        file.contents = secure.contents = _json(
          accessToken: 'new',
          refreshToken: 'rotated',
        );
        final next = (await service.read()).credentials!;
        expect(next.accessToken, 'new');
        expect(next.refreshToken, 'rotated');
        file.contents = secure.contents = null;
        expect(
          (await service.read()).status,
          ClaudeCodeCredentialsStatus.missing,
        );
      });
    });
  }

  test(
    'expired Keychain snapshot wins over a different valid file account',
    () async {
      final file = _FileSource(
        _json(expiresAt: expiry, accessToken: 'other-account'),
      );
      final service = LocalClaudeCodeCredentialsService(
        platform: ClaudeCodeCredentialsPlatform.macOS,
        environment: const {},
        credentialsPath: '/fixture',
        fileSource: file,
        secureSource: _SecureSource(_json(expiresAt: now)),
      );
      final result = await service.read();
      expect(result.status, ClaudeCodeCredentialsStatus.available);
      expect(
        result.credentials!.expiryAt(now),
        ClaudeCodeCredentialExpiry.expired,
      );
      expect(result.credentials!.refreshToken, 'fixture-refresh-secret');
      expect(file.paths, isEmpty);
    },
  );

  for (final raw in [
    '{}',
    '{"claudeAiOauth":null}',
    '{"claudeAiOauth":{"accessToken":42}}',
  ]) {
    test('readable Keychain envelope does not fall through: $raw', () async {
      final file = _FileSource(_json());
      final result = await LocalClaudeCodeCredentialsService(
        platform: ClaudeCodeCredentialsPlatform.macOS,
        environment: const {},
        credentialsPath: '/fixture',
        fileSource: file,
        secureSource: _SecureSource(raw),
      ).read();
      expect(result.credentials, isNull);
      expect(result.source, ClaudeCodeCredentialsSource.keychain);
      expect(file.paths, isEmpty);
    });
  }

  for (final storageCase in [
    (
      name: 'missing',
      raw: null,
      error: null,
      status: ClaudeCodeCredentialsStatus.missing,
    ),
    (
      name: 'empty',
      raw: ' ',
      error: null,
      status: ClaudeCodeCredentialsStatus.missing,
    ),
    (
      name: 'damaged',
      raw: '{broken',
      error: null,
      status: ClaudeCodeCredentialsStatus.malformed,
    ),
    (
      name: 'denied',
      raw: null,
      error: const ClaudeCodeSecureCredentialsUnavailable(),
      status: ClaudeCodeCredentialsStatus.unreadable,
    ),
    (
      name: 'timeout',
      raw: null,
      error: TimeoutException('sensitive-error'),
      status: ClaudeCodeCredentialsStatus.unreadable,
    ),
  ]) {
    test('Keychain ${storageCase.name} permits a file fallback', () async {
      final secure = _SecureSource(storageCase.raw, error: storageCase.error);
      final file = _FileSource(_json());
      final service = LocalClaudeCodeCredentialsService(
        platform: ClaudeCodeCredentialsPlatform.macOS,
        environment: const {},
        credentialsPath: '/fixture',
        secureSource: secure,
        fileSource: file,
      );
      expect((await service.read()).source, ClaudeCodeCredentialsSource.file);
      file.contents = null;
      expect((await service.read()).status, storageCase.status);
    });
  }

  test(
    'missing optional fields are unknown, expired fields are preserved',
    () async {
      final file = _FileSource(
        '{"claudeAiOauth":{"accessToken":"access-only"}}',
      );
      final service = _fileService(file);
      final unknown = (await service.read()).credentials!;
      expect(unknown.refreshToken, isNull);
      expect(unknown.expiresAt, isNull);
      expect(unknown.subscriptionType, isNull);
      expect(unknown.rateLimitTier, isNull);
      expect(unknown.scopes, isEmpty);
      file.contents = _json(expiresAt: now.subtract(const Duration(days: 1)));
      expect(
        (await service.read()).credentials!.expiryAt(now),
        ClaudeCodeCredentialExpiry.expired,
      );
    },
  );

  for (final malformed in [
    '{broken',
    '[]',
    '{"claudeAiOauth":[]}',
    '{"claudeAiOauth":{"accessToken":""}}',
    '{"claudeAiOauth":{"accessToken":true}}',
    ...[{}, 1.5, 'not-a-date', 8640000000000001].map(
      (expiry) => jsonEncode({
        'claudeAiOauth': {'accessToken': 'secret', 'expiresAt': expiry},
      }),
    ),
  ]) {
    test('malformed input returns a sanitized result: $malformed', () async {
      final result = await _fileService(_FileSource(malformed)).read();
      expect(result.status, ClaudeCodeCredentialsStatus.malformed);
      expect(result.credentials, isNull);
      expect(result.toString(), isNot(contains('secret')));
    });
  }

  test('file absence and IO failure have different results', () async {
    expect(
      (await _fileService(_FileSource(null)).read()).status,
      ClaudeCodeCredentialsStatus.missing,
    );
    final result = await _fileService(
      _FileSource(null, error: FileSystemException('secret', '/private')),
    ).read();
    expect(result.status, ClaudeCodeCredentialsStatus.unreadable);
    expect(result.toString(), isNot(contains('secret')));
    expect(result.toString(), isNot(contains('/private')));
  });

  test('missing home skips IO', () async {
    final file = _FileSource(_json());
    final result = await LocalClaudeCodeCredentialsService(
      platform: ClaudeCodeCredentialsPlatform.linux,
      environment: const {},
      fileSource: file,
    ).read();
    expect(result.status, ClaudeCodeCredentialsStatus.missing);
    expect(file.paths, isEmpty);
  });

  test(
    'expiry boundaries distinguish unknown, expired and five minute buffer',
    () {
      for (final entry in [
        (at: null, state: ClaudeCodeCredentialExpiry.unknown),
        (at: now, state: ClaudeCodeCredentialExpiry.expired),
        (
          at: now.add(const Duration(milliseconds: 1)),
          state: ClaudeCodeCredentialExpiry.expiringSoon,
        ),
        (
          at: now.add(const Duration(minutes: 5)),
          state: ClaudeCodeCredentialExpiry.expiringSoon,
        ),
        (
          at: now.add(const Duration(minutes: 5, milliseconds: 1)),
          state: ClaudeCodeCredentialExpiry.valid,
        ),
      ]) {
        expect(
          ClaudeCodeOAuthCredentials(
            accessToken: 'secret',
            expiresAt: entry.at,
          ).expiryAt(now),
          entry.state,
        );
      }
    },
  );

  for (final environment in [
    {'ANTHROPIC_API_KEY': 'secret'},
    {'ANTHROPIC_AUTH_TOKEN': 'secret'},
    {'CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR': '7'},
    {'CLAUDE_CODE_USE_BEDROCK': '1'},
    {'CLAUDE_CODE_USE_VERTEX': 'true'},
    {'CLAUDE_CODE_USE_FOUNDRY': 'yes'},
  ]) {
    test(
      'other authentication never borrows stored OAuth: ${environment.keys.single}',
      () async {
        final file = _FileSource(_json());
        final secure = _SecureSource(_json());
        final result = await LocalClaudeCodeCredentialsService(
          environment: environment,
          fileSource: file,
          secureSource: secure,
        ).read();
        expect(result.status, ClaudeCodeCredentialsStatus.notApplicable);
        expect(file.paths, isEmpty);
        expect(secure.calls, 0);
      },
    );
  }

  test('disabled OAuth and unsupported FD do not read storage', () async {
    final file = _FileSource(_json());
    final disabled = LocalClaudeCodeCredentialsService(
      oauthEnabled: false,
      environment: const {'CLAUDE_CODE_OAUTH_TOKEN': 'secret'},
      fileSource: file,
    );
    expect(
      (await disabled.read()).status,
      ClaudeCodeCredentialsStatus.notApplicable,
    );
    final fd = LocalClaudeCodeCredentialsService(
      environment: const {'CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR': '7'},
      fileSource: file,
    );
    expect((await fd.read()).status, ClaudeCodeCredentialsStatus.unsupported);
    expect(file.paths, isEmpty);
  });

  test('diagnostics omit both tokens, account metadata and prefixes', () async {
    final result = await _fileService(_FileSource(_json())).read();
    final text = '${result.credentials} $result';
    for (final secret in [
      'fixture-access',
      'fixture-refresh',
      'user:profile',
      'default_claude_max_5x',
    ]) {
      expect(text, isNot(contains(secret)));
    }
  });

  test(
    'real host file IO reads rotation and absence using temporary fixtures',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'zeta-oauth-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}.credentials.json',
      );
      final service = LocalClaudeCodeCredentialsService(
        platform: ClaudeCodeCredentialsPlatform.linux,
        environment: const {},
        credentialsPath: file.path,
      );
      expect(
        (await service.read()).status,
        ClaudeCodeCredentialsStatus.missing,
      );
      await file.writeAsString(_json(accessToken: 'first'));
      expect((await service.read()).credentials!.accessToken, 'first');
      await file.writeAsString(
        _json(accessToken: 'second', refreshToken: 'new-refresh'),
      );
      expect((await service.read()).credentials!.refreshToken, 'new-refresh');
      await file.delete();
      expect(
        (await service.read()).status,
        ClaudeCodeCredentialsStatus.missing,
      );
    },
  );
}

LocalClaudeCodeCredentialsService _fileService(_FileSource file) =>
    LocalClaudeCodeCredentialsService(
      platform: ClaudeCodeCredentialsPlatform.linux,
      environment: const {},
      credentialsPath: '/fixture/.credentials.json',
      fileSource: file,
    );

String _json({
  String accessToken = 'fixture-access-secret',
  String refreshToken = 'fixture-refresh-secret',
  DateTime? expiresAt,
}) => jsonEncode({
  'claudeAiOauth': {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
    'scopes': ['user:inference', 'user:profile'],
    'subscriptionType': 'max',
    'rateLimitTier': 'default_claude_max_5x',
  },
});

final class _FileSource implements ClaudeCodeCredentialsFileSource {
  _FileSource(this.contents, {this.error});
  String? contents;
  final Object? error;
  final paths = <String>[];
  @override
  Future<String?> read(String path) async {
    paths.add(path);
    if (error != null) throw error!;
    return contents;
  }
}

final class _SecureSource implements ClaudeCodeSecureCredentialsSource {
  _SecureSource(this.contents, {this.error});
  String? contents;
  final Object? error;
  int calls = 0;
  @override
  Future<String?> read() async {
    calls++;
    if (error != null) throw error!;
    return contents;
  }
}
