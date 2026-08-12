import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_usage_quota_mapper.dart';

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
          'extra_usage': <String, Object?>{
            'is_enabled': true,
            'has_credits': true,
            'balance': '42.50',
          },
        },
        providerId: 'claude-personal',
        providerName: 'Claude Code',
        subscriptionType: ' max ',
      );

      expect(result, isNotNull);
      expect(result!.providerId, 'claude-personal');
      expect(result.providerName, 'Claude Code');
      expect(result.planType, 'max');
      expect(result.limitName, 'Claude Code 订阅额度');
      expect(result.windows, hasLength(2));
      expect(result.windows.first.label, '五小时会话额度');
      expect(result.windows.first.usedPercent, 13);
      expect(result.windows.first.windowDuration, const Duration(hours: 5));
      expect(
        result.windows.first.resetsAt,
        DateTime.parse('2026-08-12T09:30:00Z').toLocal(),
      );
      expect(result.windows.last.label, '1 周');
      expect(result.windows.last.usedPercent, 48);
      expect(result.windows.last.windowDuration, const Duration(days: 7));
      expect(result.credits?.hasCredits, isTrue);
      expect(result.credits?.unlimited, isFalse);
      expect(result.credits?.balance, '42.50');
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

    test('keeps a plan-only snapshot', () {
      final result = mapClaudeCodeUsageQuota(
        const <String, Object?>{},
        providerId: 'claude_code',
        providerName: 'Claude Code',
        subscriptionType: 'pro',
      );

      expect(result, isNotNull);
      expect(result!.planType, 'pro');
      expect(result.windows, isEmpty);
    });
  });
}
