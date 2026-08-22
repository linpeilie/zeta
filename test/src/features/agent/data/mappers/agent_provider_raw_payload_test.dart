import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  group('wrapAgentProviderPayload', () {
    test('保持内容盲，不把工具参数里的 timestamp 当报文时间', () {
      final payload = wrapAgentProviderPayload(const <String, Object?>{
        'timestamp': 1700000000,
        'query': 'business timestamp',
      });

      expect(payload.capturedAt, isNull);
      expect(payload.toPrettyJson(), contains('business timestamp'));
    });

    test('只携带 adapter 显式传入的 capturedAt', () {
      final explicit = DateTime.utc(2030, 1, 1);
      final payload = wrapAgentProviderPayload(const <String, Object?>{
        'timestamp': 1700000000,
      }, capturedAt: explicit);

      expect(payload.capturedAt, explicit.toLocal());
      expect(payload.capturedAt!.isUtc, isFalse);
    });
  });

  group('AgentProviderRawPayload 不可变', () {
    test('包装后修改原 Map 不影响已展示内容', () {
      final source = <String, Object?>{
        'command': 'git status',
        'nested': <String, Object?>{'path': 'lib/main.dart'},
        'list': <Object?>[1, 2],
      };
      final payload = wrapAgentProviderPayload(source);
      final before = payload.toPrettyJson();

      source['command'] = 'rm -rf /';
      source['injected'] = 'late';
      (source['nested']! as Map<String, Object?>)['path'] = 'changed';
      (source['list']! as List<Object?>).add(3);

      expect(payload.toPrettyJson(), before);
      expect(payload.entryCount, 3);
    });

    test('相同嵌套 JSON 快照保持值相等', () {
      final payload = wrapAgentProviderPayload(<String, Object?>{
        'nested': <String, Object?>{'a': 1},
        'list': <Object?>[1],
      });
      final other = wrapAgentProviderPayload(<String, Object?>{
        'nested': <String, Object?>{'a': 1},
        'list': <Object?>[1],
      });

      expect(payload, other);
      expect(payload.hashCode, other.hashCode);
    });
  });
}
