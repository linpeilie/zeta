import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

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
        // 与 credentials.subscriptionType 故意不同，证明套餐名只来自 initialize。
        metadataLoader: () async => _metadata('team'),
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
      expect(first!.planType, 'Claude Team');
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
      test('${mode.name} returns plan without reading credentials', () async {
        var metadataCalls = 0;
        var credentialReads = 0;
        var remoteCalls = 0;
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          accountDataEnrichmentEnabled: mode.enabled,
          usesApiKey: mode.usesApiKey,
          metadataLoader: () async {
            metadataCalls += 1;
            return _metadata('team');
          },
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

        final result = await adapter.readUsageQuota();
        expect(result?.planType, 'Claude Team');
        expect(result?.windows, isEmpty);
        expect(metadataCalls, 1);
        expect(credentialReads, 0);
        expect(remoteCalls, 0);
      });
    }

    test('disabled enhancement never starts macOS security', () async {
      var securityCalls = 0;
      final reader = ClaudeCodeOAuthCredentialsReader(
        environment: const <String, String>{
          'HOME': '/fixture/home',
          'USER': 'fixture-user',
        },
        secureSource: ClaudeCodeMacOsKeychainSource(
          environment: const <String, String>{'USER': 'fixture-user'},
          processRunner: (executable, arguments, {required timeout}) async {
            securityCalls += 1;
            return const ClaudeCodeKeychainProcessResult(
              exitCode: 0,
              stdout: 'sensitive-value-must-not-be-read',
            );
          },
        ),
        isMacOS: true,
      );
      final adapter = ClaudeCodeUsageQuotaAdapter(
        providerId: 'claude_code',
        providerName: 'Claude Code',
        accountDataEnrichmentEnabled: false,
        metadataLoader: () async => _metadata('pro'),
        credentialsLoader: reader.read,
      );

      final result = await adapter.readUsageQuota();

      expect(result?.planType, 'Claude Pro');
      expect(securityCalls, 0);
    });

    test(
      'unauthenticated state returns plan-only without a remote request',
      () async {
        var remoteCalls = 0;
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          metadataLoader: () async => _metadata('Claude Pro'),
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

        final result = await adapter.readUsageQuota();
        expect(result?.planType, 'Claude Pro');
        expect(result?.windows, isEmpty);
        expect(remoteCalls, 0);
      },
    );

    for (final credentialsCase
        in <({String name, ClaudeCodeOAuthCredentials credentials})>[
          (
            name: 'missing profile scope',
            credentials: ClaudeCodeOAuthCredentials(
              accessToken: 'missing-profile-sensitive-token',
              expiresAt: DateTime.utc(2099),
              subscriptionType: 'pro',
              scopes: const <String>['user:inference'],
            ),
          ),
          (
            name: 'non-subscriber scope set',
            credentials: ClaudeCodeOAuthCredentials(
              accessToken: 'non-subscriber-sensitive-token',
              expiresAt: DateTime.utc(2099),
              subscriptionType: null,
              scopes: const <String>['user:profile'],
            ),
          ),
          (
            name: 'expired token',
            credentials: ClaudeCodeOAuthCredentials(
              accessToken: 'expired-sensitive-token',
              expiresAt: DateTime.utc(2026, 8, 12, 8),
              subscriptionType: 'max',
              scopes: const <String>['user:inference', 'user:profile'],
            ),
          ),
        ]) {
      test(
        '${credentialsCase.name} returns plan-only with zero HTTP',
        () async {
          var remoteCalls = 0;
          final adapter = ClaudeCodeUsageQuotaAdapter(
            providerId: 'claude_code',
            providerName: 'Claude Code',
            clock: () => DateTime.utc(2026, 8, 12, 8),
            metadataLoader: () async => _metadata('pro'),
            credentialsLoader: () async => credentialsCase.credentials,
            remoteUsageLoader:
                ({
                  required String accessToken,
                  required String? claudeCodeVersion,
                }) async {
                  remoteCalls += 1;
                  return const <String, Object?>{};
                },
          );

          final result = await adapter.readUsageQuota();

          expect(result?.planType, 'Claude Pro');
          expect(result?.windows, isEmpty);
          expect(remoteCalls, 0);
        },
      );
    }

    for (final statusCode in <int>[401, 429]) {
      test('upstream $statusCode fallback preserves the CLI plan', () async {
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          metadataLoader: () async => _metadata('max'),
          credentialsLoader: () async => _credentials,
          // API client 将非 200 响应统一折叠为 null，adapter 不读取响应体。
          remoteUsageLoader:
              ({
                required String accessToken,
                required String? claudeCodeVersion,
              }) async => null,
        );

        final result = await adapter.readUsageQuota();
        expect(result?.planType, 'Claude Max');
        expect(result?.windows, isEmpty);
      });
    }

    test(
      'loader exceptions are contained and failed attempts are throttled',
      () async {
        var remoteCalls = 0;
        final adapter = ClaudeCodeUsageQuotaAdapter(
          providerId: 'claude_code',
          providerName: 'Claude Code',
          metadataLoader: () async => _metadata('enterprise'),
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

        final first = await adapter.readUsageQuota();
        final throttled = await adapter.readUsageQuota();
        expect(first?.planType, 'Claude Enterprise');
        expect(identical(throttled, first), isTrue);
        expect(remoteCalls, 1);
      },
    );

    test('concurrent callers share one request', () async {
      final response = Completer<Map<String, Object?>?>();
      var remoteCalls = 0;
      final adapter = ClaudeCodeUsageQuotaAdapter(
        providerId: 'claude_code',
        providerName: 'Claude Code',
        metadataLoader: () async => _metadata('Claude Pro'),
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

    test('metadata failure still allows the old usage windows', () async {
      final adapter = ClaudeCodeUsageQuotaAdapter(
        providerId: 'claude_code',
        providerName: 'Claude Code',
        metadataLoader: () async {
          throw StateError('redacted metadata failure');
        },
        credentialsLoader: () async => _credentials,
        remoteUsageLoader:
            ({
              required String accessToken,
              required String? claudeCodeVersion,
            }) async => <String, Object?>{
              'five_hour': <String, Object?>{'utilization': 30},
            },
      );

      final result = await adapter.readUsageQuota();

      expect(result?.planType, isNull);
      expect(result?.windows.single.usedPercent, 30);
    });

    test(
      'macOS Keychain and Windows file credentials map to the same snapshot',
      () async {
        final now = DateTime.utc(2026, 8, 12, 8);
        final credentialsJson = jsonEncode(<String, Object?>{
          'claudeAiOauth': <String, Object?>{
            'accessToken': 'cross-platform-sensitive-token',
            'expiresAt': DateTime.utc(2099).millisecondsSinceEpoch,
            'subscriptionType': 'team',
            'scopes': <String>['user:profile', 'user:inference'],
          },
        });
        final macReader = ClaudeCodeOAuthCredentialsReader(
          credentialsPath: '/fixture/mac/.credentials.json',
          secureSource: ClaudeCodeMacOsKeychainSource(
            environment: const <String, String>{'USER': 'fixture-user'},
            processRunner: (executable, arguments, {required timeout}) async {
              return ClaudeCodeKeychainProcessResult(
                exitCode: 0,
                stdout: credentialsJson,
              );
            },
          ),
          fileSource: const _StaticCredentialsFileSource(null),
          isMacOS: true,
          clock: () => now,
        );
        final windowsReader = ClaudeCodeOAuthCredentialsReader(
          credentialsPath: r'C:\fixture\.claude\.credentials.json',
          fileSource: _StaticCredentialsFileSource(credentialsJson),
          isMacOS: false,
          clock: () => now,
        );

        Future<Map<String, Object?>?> loadUsage({
          required String accessToken,
          required String? claudeCodeVersion,
        }) async {
          expect(accessToken, 'cross-platform-sensitive-token');
          return <String, Object?>{
            'five_hour': <String, Object?>{'utilization': 20},
            'seven_day_sonnet': <String, Object?>{'utilization': 35},
            'extra_usage': <String, Object?>{
              'is_enabled': true,
              'monthly_limit': null,
              'used_credits': 12.5,
            },
          };
        }

        ClaudeCodeUsageQuotaAdapter adapterFor(
          ClaudeCodeOAuthCredentialsReader reader,
        ) {
          return ClaudeCodeUsageQuotaAdapter(
            providerId: 'claude_code',
            providerName: 'Claude Code',
            clock: () => now,
            metadataLoader: () async => _metadata('team'),
            credentialsLoader: reader.read,
            remoteUsageLoader: loadUsage,
          );
        }

        final macSnapshot = await adapterFor(macReader).readUsageQuota();
        final windowsSnapshot = await adapterFor(
          windowsReader,
        ).readUsageQuota();

        expect(_snapshotShape(macSnapshot), _snapshotShape(windowsSnapshot));
        expect(macSnapshot?.planType, 'Claude Team');
        expect(macSnapshot?.credits?.unlimited, isTrue);
      },
    );
  });
}

ClaudeCodeCliMetadataSnapshot _metadata(String? subscriptionType) {
  return ClaudeCodeCliMetadataSnapshot(
    models: const AgentModelList(models: <AgentModelInfo>[]),
    subscriptionType: subscriptionType,
  );
}

final _credentials = ClaudeCodeOAuthCredentials(
  accessToken: 'sensitive-test-token',
  expiresAt: DateTime.utc(2099),
  subscriptionType: 'pro',
  scopes: const <String>['user:inference', 'user:profile'],
);

Map<String, Object?>? _snapshotShape(AgentUsageQuotaSnapshot? snapshot) {
  if (snapshot == null) {
    return null;
  }
  return <String, Object?>{
    'providerId': snapshot.providerId,
    'providerName': snapshot.providerName,
    'planType': snapshot.planType,
    'limitName': snapshot.limitName,
    'windows': <Object?>[
      for (final window in snapshot.windows)
        <String, Object?>{
          'label': window.label,
          'usedPercent': window.usedPercent,
          'resetsAt': window.resetsAt?.toIso8601String(),
          'durationSeconds': window.windowDuration?.inSeconds,
        },
    ],
    'credits': snapshot.credits == null
        ? null
        : <String, Object?>{
            'hasCredits': snapshot.credits!.hasCredits,
            'unlimited': snapshot.credits!.unlimited,
            'balance': snapshot.credits!.balance,
          },
  };
}

final class _StaticCredentialsFileSource
    implements ClaudeCodeCredentialsFileSource {
  const _StaticCredentialsFileSource(this.contents);

  final String? contents;

  @override
  Future<String?> read(String path) async => contents;
}
