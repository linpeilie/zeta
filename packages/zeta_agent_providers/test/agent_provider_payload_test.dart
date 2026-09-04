import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/src/mappers/codex_provider_payload.dart';
import 'package:zeta_agent_providers/src/mappers/grok_provider_payload.dart';

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
