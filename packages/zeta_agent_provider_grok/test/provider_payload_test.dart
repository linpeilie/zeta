import 'package:test/test.dart';
import 'package:zeta_agent_provider_grok/zeta_agent_provider_grok_testing.dart';

void main() {
  group('Provider-local envelope timestamp', () {
    test('Grok 明确按毫秒解析 _meta.agentTimestampMs', () {
      expect(
        grokProviderEnvelopeCapturedAt(const <String, Object?>{
          '_meta': <String, Object?>{'agentTimestampMs': 1700000000000},
        }),
        DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ).toLocal(),
      );
    });
  });
}
