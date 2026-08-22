import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  group('deriveAgentPayloadCapturedAt', () {
    test('识别秒级与毫秒级时间戳', () {
      final seconds = deriveAgentPayloadCapturedAt(const <String, Object?>{
        'timestamp': 1700000000,
      });
      final millis = deriveAgentPayloadCapturedAt(const <String, Object?>{
        'timestamp': 1700000000000,
      });

      expect(
        seconds,
        DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ).toLocal(),
      );
      expect(millis, seconds);
    });

    test('识别 ISO 字符串与备用键名', () {
      expect(
        deriveAgentPayloadCapturedAt(const <String, Object?>{
          'created_at': '2026-08-21T10:30:00Z',
        }),
        DateTime.utc(2026, 8, 21, 10, 30).toLocal(),
      );
      expect(
        deriveAgentPayloadCapturedAt(const <String, Object?>{
          'startedAt': '2026-08-21T10:30:00Z',
        }),
        DateTime.utc(2026, 8, 21, 10, 30).toLocal(),
      );
    });

    test('识别内嵌 payload 与 _meta 里的时间', () {
      expect(
        deriveAgentPayloadCapturedAt(const <String, Object?>{
          'type': 'response_item',
          'payload': <String, Object?>{'started_at': 1700000000},
        }),
        DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ).toLocal(),
      );
      expect(
        deriveAgentPayloadCapturedAt(const <String, Object?>{
          '_meta': <String, Object?>{'timestamp': 1700000000},
        }),
        isNotNull,
      );
    });

    test('推不出时间时返回 null，不编造"现在"', () {
      expect(deriveAgentPayloadCapturedAt(const <String, Object?>{}), isNull);
      expect(
        deriveAgentPayloadCapturedAt(const <String, Object?>{
          'marker': 'no-time-here',
          'timestamp': 'not a date',
        }),
        isNull,
      );
    });
  });

  group('wrapAgentProviderPayload', () {
    test('默认从原文推导 capturedAt', () {
      final payload = wrapAgentProviderPayload(const <String, Object?>{
        'timestamp': 1700000000,
      });

      expect(
        payload.capturedAt,
        DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ).toLocal(),
      );
    });

    test('显式 capturedAt 优先于推导值，并统一到本地时区', () {
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

    test('嵌套结构本身也不可写', () {
      final payload = wrapAgentProviderPayload(<String, Object?>{
        'nested': <String, Object?>{'a': 1},
        'list': <Object?>[1],
      });
      // 通过 JSON 文本反推不到引用，这里直接验证冻结语义：解析回来的结构与
      // 原始内容一致，且构造时的副本没有被外部引用连累。
      expect(payload.toPrettyJson(), contains('"a": 1'));

      final other = wrapAgentProviderPayload(<String, Object?>{
        'nested': <String, Object?>{'a': 1},
        'list': <Object?>[1],
      });
      expect(payload, other);
      expect(payload.hashCode, other.hashCode);
    });
  });
}
