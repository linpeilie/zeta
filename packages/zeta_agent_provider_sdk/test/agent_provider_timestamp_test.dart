import 'package:test/test.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';

void main() {
  group('tryParseAgentProviderTimestamp', () {
    test('按 adapter 声明识别秒、毫秒与 ISO 字符串', () {
      final seconds = tryParseAgentProviderTimestamp(
        1700000000,
        unit: AgentProviderTimestampUnit.seconds,
      );
      final millis = tryParseAgentProviderTimestamp(
        1700000000000,
        unit: AgentProviderTimestampUnit.milliseconds,
      );

      expect(
        seconds,
        DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ).toLocal(),
      );
      expect(millis, seconds);
      expect(
        tryParseAgentProviderTimestamp('2026-08-21T10:30:00Z'),
        DateTime.utc(2026, 8, 21, 10, 30).toLocal(),
      );
    });

    test('损坏、非有限和越界数值全部 fail-closed', () {
      expect(tryParseAgentProviderTimestamp('not a date'), isNull);
      expect(tryParseAgentProviderTimestamp(double.nan), isNull);
      expect(tryParseAgentProviderTimestamp(double.infinity), isNull);
      expect(
        tryParseAgentProviderTimestamp(
          9223372036854775807,
          unit: AgentProviderTimestampUnit.milliseconds,
        ),
        isNull,
      );
    });
  });
}
