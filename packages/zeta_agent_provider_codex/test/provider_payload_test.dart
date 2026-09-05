import 'package:test/test.dart';
import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex_testing.dart';

void main() {
  group('Provider-local envelope timestamp', () {
    test('Codex 只在明确的 envelope mapper 中选键', () {
      expect(
        codexProviderEnvelopeCapturedAt(const <String, Object?>{
          'timestamp': 1700000000,
        }),
        isNotNull,
      );
      expect(
        codexProviderEnvelopeCapturedAt(const <String, Object?>{
          'timestamp': 9223372036854775807,
        }),
        isNull,
      );
      expect(
        codexProviderEnvelopeCapturedAt(const <String, Object?>{
          'startedAtMs': 1,
        }),
        DateTime.fromMillisecondsSinceEpoch(1, isUtc: true).toLocal(),
      );
    });
  });
}
