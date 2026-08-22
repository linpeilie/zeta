import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

/// wire 形状启发式的归属测试。
///
/// 这段逻辑原先住在中立 domain（`agent_tool_models.dart` 直接翻 `rawInput` 猜
/// 二十来个键名），属于 G2 违规：从 Provider 原文推导展示摘要是适配层的职责。
/// 搬到这里之后，中立层只消费算好的 `AgentToolCall.inputDetail`。
void main() {
  group('deriveAgentToolInputDetail', () {
    test('优先取命令类键', () {
      expect(
        deriveAgentToolInputDetail(const <String, Object?>{
          'command': 'flutter test',
        }),
        'flutter test',
      );
    });

    test('路径类键会被缩短', () {
      final detail = deriveAgentToolInputDetail(const <String, Object?>{
        'file_path': '/Users/someone/project/lib/src/feature/widget.dart',
      });

      expect(detail, isNotNull);
      expect(detail, contains('widget.dart'));
      expect(detail!.length, lessThan(60));
    });

    test('支持嵌套 arguments / input / params', () {
      expect(
        deriveAgentToolInputDetail(const <String, Object?>{
          'arguments': <String, Object?>{'query': 'needle'},
        }),
        'needle',
      );
    });

    test('空 payload 与无信息 payload 返回 null', () {
      expect(deriveAgentToolInputDetail(const <String, Object?>{}), isNull);
      expect(
        deriveAgentToolInputDetail(const <String, Object?>{'unknown': 42}),
        isNull,
      );
    });
  });
}
