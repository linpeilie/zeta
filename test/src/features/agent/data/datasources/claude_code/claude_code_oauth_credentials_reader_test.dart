import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart';

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
          fileSource: source,
          clock: () => now,
        );

        final first = await reader.read();
        final second = await reader.read();

        expect(first?.accessToken, 'oauth-token-first-secret');
        expect(first?.expiresAt, now.add(const Duration(hours: 1)));
        expect(first?.subscriptionType, 'max');
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
        fileSource: source,
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
        ),
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
          ),
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
        ),
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
        ),
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
      );

      final description = credentials.toString();

      expect(description, contains('hasCredentials: true'));
      expect(description, isNot(contains(token)));
      expect(description, isNot(contains(token.substring(0, 8))));
    });

    test('does not read when no home can be resolved', () async {
      final source = _RecordingCredentialsFileSource(
        contents: const <String?>[],
      );
      final reader = ClaudeCodeOAuthCredentialsReader(
        environment: const <String, String>{},
        fileSource: source,
        clock: () => now,
      );

      await expectLater(reader.read(), completion(isNull));
      expect(source.operations, isEmpty);
    });
  });
}

String _credentialsJson({
  required String accessToken,
  required DateTime expiresAt,
  required String subscriptionType,
}) {
  return jsonEncode(<String, Object?>{
    'claudeAiOauth': <String, Object?>{
      'accessToken': accessToken,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'subscriptionType': subscriptionType,
    },
  });
}

final class _RecordingCredentialsFileSource
    implements ClaudeCodeCredentialsFileSource {
  _RecordingCredentialsFileSource({
    required List<String?> contents,
    this.readError,
  }) : _contents = List<String?>.of(contents);

  final List<String?> _contents;
  final Object? readError;
  final List<String> operations = <String>[];

  @override
  Future<String?> read(String path) async {
    operations.add('read:$path');
    final error = readError;
    if (error != null) {
      throw error;
    }
    return _contents.removeAt(0);
  }
}
