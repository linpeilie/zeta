import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('formatAgentUsageWindowLabelFromMinutes', () {
    test('matches Codex windowDurationMins labels', () {
      expect(formatAgentUsageWindowLabelFromMinutes(300), '5 小时');
      expect(formatAgentUsageWindowLabelFromMinutes(10080), '1 周');
      expect(formatAgentUsageWindowLabelFromMinutes(20160), '2 周');
      expect(formatAgentUsageWindowLabelFromMinutes(24 * 60), '1 天');
      expect(formatAgentUsageWindowLabelFromMinutes(31 * 24 * 60), '31 天');
      expect(formatAgentUsageWindowLabelFromMinutes(45), '45 分钟');
      expect(formatAgentUsageWindowLabelFromMinutes(null), isNull);
      expect(formatAgentUsageWindowLabelFromMinutes(0), isNull);
    });
  });

  group('formatAgentUsageWindowLabelFromPeriodType', () {
    test('maps Grok period enums to Codex-style duration labels', () {
      expect(
        formatAgentUsageWindowLabelFromPeriodType('USAGE_PERIOD_TYPE_WEEKLY'),
        '1 周',
      );
      expect(
        formatAgentUsageWindowLabelFromPeriodType('USAGE_PERIOD_TYPE_DAILY'),
        '1 天',
      );
      expect(
        formatAgentUsageWindowLabelFromPeriodType('USAGE_PERIOD_TYPE_MONTHLY'),
        isNull,
      );
    });
  });
}
