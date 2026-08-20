import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/mappers/claude_code_usage_quota_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('mapClaudeCodeUsageQuota', () {
    test('maps five-hour, weekly, plan, and extra usage fields', () {
      final result = mapClaudeCodeUsageQuota(
        <String, Object?>{
          'five_hour': <String, Object?>{
            'utilization': 12.6,
            'resets_at': '2026-08-12T09:30:00Z',
          },
          'seven_day': <String, Object?>{
            'utilization': 48,
            'resets_at': '2026-08-18T00:00:00Z',
          },
          'seven_day_sonnet': <String, Object?>{
            'utilization': 21,
            'resets_at': '2026-08-18T00:00:00Z',
          },
          'seven_day_opus': <String, Object?>{
            'utilization': 64,
            'resets_at': '2026-08-18T00:00:00Z',
          },
          'extra_usage': <String, Object?>{
            'is_enabled': true,
            'monthly_limit': 100,
            'used_credits': 25,
            'utilization': 25,
          },
          // REST 中即使出现相似字段，套餐名称仍只能来自 initialize metadata。
          'subscription_type': 'pro',
        },
        providerId: 'claude-personal',
        providerName: 'Claude Code',
        subscriptionType: ' max ',
      );

      expect(result, isNotNull);
      expect(result!.providerId, 'claude-personal');
      expect(result.providerName, 'Claude Code');
      expect(result.planType, 'Claude Max');
      expect(result.limitName, isNull);
      expect(
        result.limitNameCode,
        AgentUsageLimitNameCode.claudeCodeSubscriptionQuota,
      );
      expect(result.windows, hasLength(4));
      expect(result.windows.first.label, isNull);
      expect(result.windows.first.usedPercent, 13);
      expect(result.windows.first.windowDuration, const Duration(hours: 5));
      expect(
        result.windows.first.resetsAt,
        DateTime.parse('2026-08-12T09:30:00Z').toLocal(),
      );
      expect(result.windows.map((window) => window.labelCode), <Object?>[
        AgentUsageWindowLabelCode.fiveHours,
        AgentUsageWindowLabelCode.oneWeek,
        AgentUsageWindowLabelCode.sonnetOneWeek,
        AgentUsageWindowLabelCode.opusOneWeek,
      ]);
      expect(result.windows.map((window) => window.usedPercent), <int>[
        13,
        48,
        21,
        64,
      ]);
      expect(
        result.windows
            .skip(1)
            .every(
              (window) => window.windowDuration == const Duration(days: 7),
            ),
        isTrue,
      );
      expect(result.credits?.hasCredits, isTrue);
      expect(result.credits?.unlimited, isFalse);
      expect(result.credits?.balance, isNull);
    });

    test('keeps an active window when reset time is absent', () {
      final result = mapClaudeCodeUsageQuota(
        <String, Object?>{
          'five_hour': <String, Object?>{
            'utilization': '101.2',
            'resets_at': null,
          },
        },
        providerId: 'claude_code',
        providerName: 'Claude Code',
      );

      expect(result, isNotNull);
      expect(result!.windows, hasLength(1));
      expect(result.windows.single.usedPercent, 100);
      expect(result.windows.single.resetsAt, isNull);
    });

    test('uses provider units only to determine whether credits remain', () {
      final result = mapClaudeCodeUsageQuota(
        <String, Object?>{
          'extra_usage': <String, Object?>{
            'is_enabled': true,
            'monthly_limit': 100,
            'used_credits': 100,
          },
        },
        providerId: 'claude_code',
        providerName: 'Claude Code',
      );

      expect(result, isNotNull);
      expect(result!.credits?.hasCredits, isFalse);
      expect(result.credits?.unlimited, isFalse);
      expect(result.credits?.balance, isNull);
    });

    test('maps a null monthly limit as unlimited without guessing balance', () {
      final result = mapClaudeCodeUsageQuota(
        <String, Object?>{
          'extra_usage': <String, Object?>{
            'is_enabled': true,
            'monthly_limit': null,
            'used_credits': 12.5,
            'utilization': 99,
            'balance': 'must-not-be-projected',
          },
        },
        providerId: 'claude_code',
        providerName: 'Claude Code',
      );

      expect(result, isNotNull);
      expect(result!.credits?.hasCredits, isTrue);
      expect(result.credits?.unlimited, isTrue);
      expect(result.credits?.balance, isNull);
    });

    test('returns null for malformed or semantically empty payloads', () {
      expect(
        mapClaudeCodeUsageQuota(
          null,
          providerId: 'claude_code',
          providerName: 'Claude Code',
        ),
        isNull,
      );
      expect(
        mapClaudeCodeUsageQuota(
          <String, Object?>{
            'five_hour': <String, Object?>{'utilization': 'invalid'},
            'extra_usage': <String, Object?>{'is_enabled': false},
          },
          providerId: 'claude_code',
          providerName: 'Claude Code',
        ),
        isNull,
      );
    });

    test('keeps a plan-only snapshot when the REST payload is missing', () {
      final result = mapClaudeCodeUsageQuota(
        null,
        providerId: 'claude_code',
        providerName: 'Claude Code',
        subscriptionType: 'pro',
      );

      expect(result, isNotNull);
      expect(result!.planType, 'Claude Pro');
      expect(result.windows, isEmpty);
    });

    test('normalizes Claude subscription display names locally', () {
      const cases = <String, String>{
        'pro': 'Claude Pro',
        'MAX': 'Claude Max',
        ' team ': 'Claude Team',
        'enterprise': 'Claude Enterprise',
        'Claude Pro': 'Claude Pro',
        'future-plan': 'future-plan',
      };

      for (final entry in cases.entries) {
        final result = mapClaudeCodeUsageQuota(
          null,
          providerId: 'claude_code',
          providerName: 'Claude Code',
          subscriptionType: entry.key,
        );
        expect(result?.planType, entry.value, reason: entry.key);
        expect(result?.planType, isNot(startsWith('ChatGPT')));
      }
    });
  });
}
