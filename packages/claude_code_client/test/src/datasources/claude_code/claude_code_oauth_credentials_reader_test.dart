import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_code_client/src/datasources/claude_code/claude_code_macos_keychain_source.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeCodeOAuthCredentialsReader', () {
    const credentialsPath = '/test-home/.claude/.credentials.json';
    final now = DateTime.utc(2026, 8, 11, 8);

    test(
      'reads a valid snapshot again on every call without side effects',
      () async {
        final source = _RecordingCredentialsFileSource(
          contents: <String?>[
            _credentialsJson(
              accessToken: 'oauth-token-first-secret',
              expiresAt: now.add(const Duration(hours: 1)),
              subscriptionType: 'max',
              scopes: const <String>['user:profile', 'user:inference'],
            ),
            _credentialsJson(
              accessToken: 'oauth-token-second-secret',
              expiresAt: now.add(const Duration(hours: 2)),
              subscriptionType: 'pro',
            ),
          ],
        );
        final reader = ClaudeCodeOAuthCredentialsReader(
          credentialsPath: credentialsPath,
          fileSource: source.read,
          isMacOS: false,
          clock: () => now,
        );

        final first = await reader.read();
        final second = await reader.read();

        expect(first?.accessToken, 'oauth-token-first-secret');
        expect(first?.expiresAt, now.add(const Duration(hours: 1)));
        expect(first?.subscriptionType, 'max');
        expect(first?.scopes, const <String>['user:profile', 'user:inference']);
        expect(second?.accessToken, 'oauth-token-second-secret');
        expect(second?.subscriptionType, 'pro');
        expect(source.operations, <String>[
          'read:$credentialsPath',
          'read:$credentialsPath',
        ]);
      },
    );

    test('returns null when the credentials file is missing', () async {
      final source = _RecordingCredentialsFileSource(
        contents: const <String?>[null],
      );
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: credentialsPath,
        fileSource: source.read,
        isMacOS: false,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
      expect(source.operations, <String>['read:$credentialsPath']);
    });

    test('returns null for an empty credentials file', () async {
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: credentialsPath,
        fileSource: _RecordingCredentialsFileSource(
          contents: const <String?>['   '],
        ).read,
        isMacOS: false,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
    });

    test('returns null for malformed or incomplete JSON', () async {
      for (final contents in <String>[
        '{malformed-json}',
        jsonEncode(<String, Object?>{'claudeAiOauth': <String, Object?>{}}),
        jsonEncode(<String, Object?>{
          'claudeAiOauth': <String, Object?>{
            'accessToken': 'secret',
            'expiresAt': <String, Object?>{'invalid': true},
          },
        }),
      ]) {
        final reader = ClaudeCodeOAuthCredentialsReader(
          credentialsPath: credentialsPath,
          fileSource: _RecordingCredentialsFileSource(
            contents: <String?>[contents],
          ).read,
          isMacOS: false,
          clock: () => now,
        );

        await expectLater(reader.read(), completion(isNull));
      }
    });

    test('returns null when the credentials are expired', () async {
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: credentialsPath,
        fileSource: _RecordingCredentialsFileSource(
          contents: <String?>[
            _credentialsJson(
              accessToken: 'expired-token-secret',
              expiresAt: now,
              subscriptionType: 'max',
            ),
          ],
        ).read,
        isMacOS: false,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
    });

    test('returns null when the read itself fails', () async {
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: credentialsPath,
        fileSource: _RecordingCredentialsFileSource(
          contents: const <String?>[],
          readError: const FormatException('redacted'),
        ).read,
        isMacOS: false,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
    });

    test('toString omits the token and its prefix', () {
      const token = 'oauth-sensitive-token-value';
      final credentials = ClaudeCodeOAuthCredentials(
        accessToken: token,
        expiresAt: now.add(const Duration(hours: 1)),
        subscriptionType: 'max',
        scopes: const <String>['user:profile'],
      );

      final description = credentials.toString();

      expect(description, contains('hasCredentials: true'));
      expect(description, isNot(contains(token)));
      expect(description, isNot(contains(token.substring(0, 8))));
      expect(description, isNot(contains('user:profile')));
    });

    test('does not read when no home can be resolved', () async {
      final source = _RecordingCredentialsFileSource(
        contents: const <String?>[],
      );
      final reader = ClaudeCodeOAuthCredentialsReader(
        environment: const <String, String>{},
        fileSource: source.read,
        isMacOS: false,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
      expect(source.operations, isEmpty);
    });

    test('resolves CLAUDE_CONFIG_DIR before the default home directory', () {
      final reader = ClaudeCodeOAuthCredentialsReader(
        environment: const <String, String>{
          'HOME': '/ignored-home',
          'CLAUDE_CONFIG_DIR': '/fixture/custom-claude',
        },
        isMacOS: false,
        clock: () => now,
      );

      expect(
        reader.resolveCredentialsPath(),
        '/fixture/custom-claude${Platform.pathSeparator}.credentials.json',
      );
    });

    for (final keychainCase
        in <
          ({
            String name,
            ClaudeCodeKeychainProcessResult? result,
            Exception? error,
          })
        >[
          (
            name: 'miss',
            result: const ClaudeCodeKeychainProcessResult(
              exitCode: 44,
              stdout: '',
            ),
            error: null,
          ),
          (
            name: 'denial',
            result: const ClaudeCodeKeychainProcessResult(
              exitCode: 36,
              stdout: '',
            ),
            error: null,
          ),
          (
            name: 'damaged JSON',
            result: const ClaudeCodeKeychainProcessResult(
              exitCode: 0,
              stdout: '{damaged',
            ),
            error: null,
          ),
          (name: 'timeout', result: null, error: TimeoutException('redacted')),
        ]) {
      test('macOS Keychain ${keychainCase.name} falls back to file', () async {
        final process = _RecordingKeychainProcess(
          result: keychainCase.result,
          error: keychainCase.error,
        );
        final fileSource = _RecordingCredentialsFileSource(
          contents: <String?>[
            _credentialsJson(
              accessToken: 'file-fallback-sensitive-token',
              expiresAt: now.add(const Duration(hours: 1)),
              subscriptionType: 'pro',
              scopes: const <String>['user:profile'],
            ),
          ],
        );
        final reader = ClaudeCodeOAuthCredentialsReader(
          credentialsPath: credentialsPath,
          fileSource: fileSource.read,
          secureSource: ClaudeCodeMacOsKeychainSource(
            environment: const <String, String>{'USER': 'fixture-user'},
            processRunner: process.call,
          ).read,
          isMacOS: true,
          clock: () => now,
        );

        final credentials = await reader.read();

        expect(credentials?.accessToken, 'file-fallback-sensitive-token');
        expect(credentials?.scopes, const <String>['user:profile']);
        expect(process.calls, 1);
        expect(fileSource.operations, <String>['read:$credentialsPath']);
      });
    }

    test(
      'macOS valid Keychain credentials win without reading the file',
      () async {
        final process = _RecordingKeychainProcess(
          result: ClaudeCodeKeychainProcessResult(
            exitCode: 0,
            stdout: _credentialsJson(
              accessToken: 'keychain-sensitive-token',
              expiresAt: now.add(const Duration(hours: 2)),
              subscriptionType: 'max',
              scopes: const <String>['user:profile', 'user:inference'],
            ),
          ),
        );
        final fileSource = _RecordingCredentialsFileSource(
          contents: const <String?>[],
        );
        final reader = ClaudeCodeOAuthCredentialsReader(
          credentialsPath: credentialsPath,
          fileSource: fileSource.read,
          secureSource: ClaudeCodeMacOsKeychainSource(
            environment: const <String, String>{'USER': 'fixture-user'},
            processRunner: process.call,
          ).read,
          isMacOS: true,
          clock: () => now,
        );

        final credentials = await reader.read();

        expect(credentials?.accessToken, 'keychain-sensitive-token');
        expect(credentials?.scopes, const <String>[
          'user:profile',
          'user:inference',
        ]);
        expect(fileSource.operations, isEmpty);
      },
    );

    test('expired Keychain credentials are never returned', () async {
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: credentialsPath,
        fileSource: _RecordingCredentialsFileSource(
          contents: const <String?>[null],
        ).read,
        secureSource: ClaudeCodeMacOsKeychainSource(
          environment: const <String, String>{'USER': 'fixture-user'},
          processRunner: _RecordingKeychainProcess(
            result: ClaudeCodeKeychainProcessResult(
              exitCode: 0,
              stdout: _credentialsJson(
                accessToken: 'expired-keychain-token',
                expiresAt: now,
                subscriptionType: 'max',
                scopes: const <String>['user:profile'],
              ),
            ),
          ).call,
        ).read,
        isMacOS: true,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
    });

    test('non-macOS keeps the file path and never starts security', () async {
      final process = _RecordingKeychainProcess(
        result: const ClaudeCodeKeychainProcessResult(
          exitCode: 0,
          stdout: 'must-not-be-read',
        ),
      );
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: credentialsPath,
        fileSource: _RecordingCredentialsFileSource(
          contents: <String?>[
            _credentialsJson(
              accessToken: 'file-sensitive-token',
              expiresAt: now.add(const Duration(hours: 1)),
              subscriptionType: 'pro',
            ),
          ],
        ).read,
        secureSource: ClaudeCodeMacOsKeychainSource(
          environment: const <String, String>{'USER': 'fixture-user'},
          processRunner: process.call,
        ).read,
        isMacOS: false,
        clock: () => now,
      );

      expect((await reader.read())?.accessToken, 'file-sensitive-token');
      expect(process.calls, 0);
    });
  });
}

String _credentialsJson({
  required String accessToken,
  required DateTime expiresAt,
  required String subscriptionType,
  List<String> scopes = const <String>[],
}) {
  return jsonEncode(<String, Object?>{
    'claudeAiOauth': <String, Object?>{
      'accessToken': accessToken,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'subscriptionType': subscriptionType,
      'scopes': scopes,
    },
  });
}

final class _RecordingKeychainProcess {
  _RecordingKeychainProcess({this.result, this.error});

  final ClaudeCodeKeychainProcessResult? result;
  final Exception? error;
  int calls = 0;

  Future<ClaudeCodeKeychainProcessResult> call(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    calls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result!;
  }
}

final class _RecordingCredentialsFileSource {
  _RecordingCredentialsFileSource({
    required List<String?> contents,
    this.readError,
  }) : _contents = List<String?>.of(contents);

  final List<String?> _contents;
  final Exception? readError;
  final List<String> operations = <String>[];

  Future<String?> read(String path) async {
    operations.add('read:$path');
    final error = readError;
    if (error != null) {
      throw error;
    }
    return _contents.removeAt(0);
  }

  Future<String?> call(String path) => read(path);
}
