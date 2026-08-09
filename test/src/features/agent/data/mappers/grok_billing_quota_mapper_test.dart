import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_billing_quota_mapper.dart';

import '../../../../testing/fixture_reader.dart';

void main() {
  group('mapGrokBillingQuota', () {
    test('maps weekly SuperGrok billing window and reset time', () {
      final raw = readFixtureJsonMap(
        'grok/acp/xai_billing_response_redacted.json',
      );

      final quota = mapGrokBillingQuota(
        raw,
        providerId: 'grok-personal',
        providerName: 'Grok',
      );

      expect(quota, isNotNull);
      expect(quota!.providerId, 'grok-personal');
      expect(quota.providerName, 'Grok');
      expect(quota.planType, 'SuperGrok');
      expect(quota.limitName, 'SuperGrok');
      expect(quota.windows, hasLength(1));
      expect(quota.windows.single.label, '1 周');
      expect(quota.windows.single.usedPercent, 35);
      expect(
        quota.windows.single.resetsAt,
        DateTime.parse('2026-08-01T08:38:01.643958+00:00').toLocal(),
      );
      expect(
        quota.windows.single.windowDuration,
        DateTime.parse(
          '2026-08-01T08:38:01.643958+00:00',
        ).difference(DateTime.parse('2026-07-25T08:38:01.643958+00:00')),
      );
      expect(quota.credits?.hasCredits, isFalse);
      expect(quota.credits?.balance, '0');
    });

    test('maps on-demand window when cap is positive', () {
      final quota = mapGrokBillingQuota(
        <String, Object?>{
          'subscription_tier': 'SuperGrok',
          'config': <String, Object?>{
            'creditUsagePercent': 10,
            'currentPeriod': <String, Object?>{
              'type': 'USAGE_PERIOD_TYPE_MONTHLY',
              'start': '2026-07-01T00:00:00Z',
              'end': '2026-08-01T00:00:00Z',
            },
            'onDemandCap': <String, Object?>{'val': 20},
            'onDemandUsed': <String, Object?>{'val': 5},
            'prepaidBalance': <String, Object?>{'val': 12.5},
          },
        },
        providerId: 'grok',
        providerName: 'Grok',
      );

      expect(quota, isNotNull);
      expect(quota!.windows, hasLength(2));
      // 月周期按 start/end 时长对齐 Codex：「31 天」类标签，而非「月额度」。
      expect(quota.windows.first.label, '31 天');
      expect(quota.windows.first.usedPercent, 10);
      expect(quota.windows.last.label, '按需额度');
      expect(quota.windows.last.usedPercent, 25);
      expect(quota.credits?.hasCredits, isTrue);
      expect(quota.credits?.balance, '12.5');
    });

    test('returns null for empty or malformed payloads', () {
      expect(
        mapGrokBillingQuota(null, providerId: 'grok', providerName: 'Grok'),
        isNull,
      );
      expect(
        mapGrokBillingQuota(
          <String, Object?>{},
          providerId: 'grok',
          providerName: 'Grok',
        ),
        isNull,
      );
    });

    test('keeps plan-only snapshot when usage percent is absent', () {
      final quota = mapGrokBillingQuota(
        <String, Object?>{'subscription_tier': 'SuperGrok'},
        providerId: 'grok',
        providerName: 'Grok',
      );

      expect(quota, isNotNull);
      expect(quota!.planType, 'SuperGrok');
      expect(quota.windows, isEmpty);
      expect(quota.credits, isNull);
    });

    test(
      'treats omitted weekly creditUsagePercent as 0% and keeps reset time',
      () {
        // 周额度刚重置时后端常省略 proto3 默认的 0 百分比，但仍返回周期边界。
        final quota = mapGrokBillingQuota(
          <String, Object?>{
            'subscription_tier': 'SuperGrok',
            'config': <String, Object?>{
              'currentPeriod': <String, Object?>{
                'type': 'USAGE_PERIOD_TYPE_WEEKLY',
                'start': '2026-08-01T08:38:01.643958+00:00',
                'end': '2026-08-08T08:38:01.643958+00:00',
              },
            },
          },
          providerId: 'grok',
          providerName: 'Grok',
        );

        expect(quota, isNotNull);
        expect(quota!.limitName, 'SuperGrok');
        expect(quota.windows, hasLength(1));
        expect(quota.windows.single.label, '1 周');
        expect(quota.windows.single.usedPercent, 0);
        expect(
          quota.windows.single.resetsAt,
          DateTime.parse('2026-08-08T08:38:01.643958+00:00').toLocal(),
        );
      },
    );

    test('does not invent a zero window when period end is also missing', () {
      final quota = mapGrokBillingQuota(
        <String, Object?>{
          'subscription_tier': 'SuperGrok',
          'config': <String, Object?>{
            'currentPeriod': <String, Object?>{
              'type': 'USAGE_PERIOD_TYPE_WEEKLY',
            },
          },
        },
        providerId: 'grok',
        providerName: 'Grok',
      );

      expect(quota, isNotNull);
      expect(quota!.limitName, 'SuperGrok');
      expect(quota.windows, isEmpty);
    });
  });
}
