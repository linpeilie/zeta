import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_usage_quota_adapter.dart';

void main() {
  group('ClaudeCodeUsageQuotaAdapter', () {
    test('maps a successful response and throttles for 60 seconds', () async {
      var now = DateTime.utc(2026, 8, 12, 8);
      var credentialReads = 0;
      var remoteCalls = 0;
      final adapter = ClaudeCodeUsageQuotaAdapter(
        providerId: 'claude_code',
        providerName: 'Claude Code',
        claudeCodeVersion: '2.1.227',
        clock: () => now,
        credentialsLoader: () async {
          credentialReads += 1;
          return _credentials;
        },
        remoteUsageLoader:
            ({
              required String accessToken,
              required String? claudeCodeVersion,
            }) async {
              remoteCalls += 1;
              expect(accessToken, 'sensitive-test-token');
              expect(claudeCodeVersion, '2.1.227');
              return <String, Object?>{
                'five_hour': <String, Object?>{
                  'utilization': 25,
                  'resets_at': '2026-08-12T12:00:00Z',
                },
              };
            },
      );

      final first = await adapter.readUsageQuota();
      now = now.add(const Duration(seconds: 59));
      final throttled = await adapter.readUsageQuota();

      expect(first, isNotNull);
      expect(first!.planType, 'pro');
      expect(identical(throttled, first), isTrue);
      expect(credentialReads, 1);
      expect(remoteCalls, 1);

      now = now.add(const Duration(seconds: 1));
      await adapter.readUsageQuota();
      expect(credentialReads, 2);
      expect(remoteCalls, 2);
    });

    for (final mode in <({String name, bool enabled, bool usesApiKey})>[
      (name: 'account enhancement off', enabled: false, usesApiKey: false),
      (name: 'API key mode', enabled: true, usesApiKey: true),
    ]) {
      test('${mode.name} returns null without reading credentials', () async {
        var credentialReads = 0;
        var remoteCalls = 0;
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          accountDataEnrichmentEnabled: mode.enabled,
          usesApiKey: mode.usesApiKey,
          credentialsLoader: () async {
            credentialReads += 1;
            return _credentials;
          },
          remoteUsageLoader:
              ({
                required String accessToken,
                required String? claudeCodeVersion,
              }) async {
                remoteCalls += 1;
                return const <String, Object?>{};
              },
        );

        await expectLater(adapter.readUsageQuota(), completion(isNull));
        expect(credentialReads, 0);
        expect(remoteCalls, 0);
      });
    }

    test(
      'unauthenticated state returns null without a remote request',
      () async {
        var remoteCalls = 0;
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          credentialsLoader: () async => null,
          remoteUsageLoader:
              ({
                required String accessToken,
                required String? claudeCodeVersion,
              }) async {
                remoteCalls += 1;
                return const <String, Object?>{};
              },
        );

        await expectLater(adapter.readUsageQuota(), completion(isNull));
        expect(remoteCalls, 0);
      },
    );

    for (final statusCode in <int>[401, 429]) {
      test('upstream $statusCode fallback returns null safely', () async {
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          credentialsLoader: () async => _credentials,
          // API client 将非 200 响应统一折叠为 null，adapter 不读取响应体。
          remoteUsageLoader:
              ({
                required String accessToken,
                required String? claudeCodeVersion,
              }) async => null,
        );

        await expectLater(adapter.readUsageQuota(), completion(isNull));
      });
    }

    test(
      'loader exceptions are contained and failed attempts are throttled',
      () async {
        var remoteCalls = 0;
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          credentialsLoader: () async => _credentials,
          remoteUsageLoader:
              ({
                required String accessToken,
                required String? claudeCodeVersion,
              }) async {
                remoteCalls += 1;
                throw StateError('redacted');
              },
        );

        await expectLater(adapter.readUsageQuota(), completion(isNull));
        await expectLater(adapter.readUsageQuota(), completion(isNull));
        expect(remoteCalls, 1);
      },
    );

    test('concurrent callers share one request', () async {
      final response = Completer<Map<String, Object?>?>();
      var remoteCalls = 0;
      final adapter = ClaudeCodeUsageQuotaAdapter(
        providerId: 'claude_code',
        providerName: 'Claude Code',
        credentialsLoader: () async => _credentials,
        remoteUsageLoader:
            ({
              required String accessToken,
              required String? claudeCodeVersion,
            }) {
              remoteCalls += 1;
              return response.future;
            },
      );

      final first = adapter.readUsageQuota();
      final second = adapter.readUsageQuota();
      await Future<void>.delayed(Duration.zero);
      expect(remoteCalls, 1);

      response.complete(<String, Object?>{
        'seven_day': <String, Object?>{'utilization': 10},
      });
      final results = await Future.wait([first, second]);
      expect(results.every((result) => result != null), isTrue);
      expect(remoteCalls, 1);
    });
  });
}

final _credentials = ClaudeCodeOAuthCredentials(
  accessToken: 'sensitive-test-token',
  expiresAt: DateTime.utc(2099),
  subscriptionType: 'pro',
);
