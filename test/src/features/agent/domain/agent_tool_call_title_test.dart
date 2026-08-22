import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('buildAgentToolCallDisplayTitle', () {
    test('keeps explicit human titles', () {
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-1',
          kindLabel: const FallbackAgentUiTextCatalog().toolKindLabel,
          title: 'Read file',
          kind: AgentToolKind.read,
        ),
        'Read file',
      );
    });

    test('does not fall back to call- id when title is missing', () {
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-abc123',
          kindLabel: const FallbackAgentUiTextCatalog().toolKindLabel,
          title: null,
          kind: AgentToolKind.read,
          locations: const <String>[r'D:\repo\zeta\lib\main.dart'],
        ),
        '读取 · lib/main.dart',
      );
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-abc123',
          kindLabel: const FallbackAgentUiTextCatalog().toolKindLabel,
          title: 'call-abc123',
          kind: AgentToolKind.read,
          locations: const <String>[r'D:\repo\zeta\lib\main.dart'],
        ),
        '读取 · lib/main.dart',
      );
    });

    test('synthesizes execute titles from command rawInput', () {
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-9',
          kindLabel: const FallbackAgentUiTextCatalog().toolKindLabel,
          kind: AgentToolKind.execute,
          rawInput: const <String, Object?>{'command': 'flutter test'},
        ),
        '执行 · flutter test',
      );
    });

    test('uses kind label when no detail is available', () {
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-empty',
          kindLabel: const FallbackAgentUiTextCatalog().toolKindLabel,
          kind: AgentToolKind.search,
        ),
        '搜索',
      );
    });

    test('AgentToolCall.displayTitle recovers from opaque stored title', () {
      const tool = AgentToolCall(
        id: 'call-xyz',
        title: 'call-xyz',
        kind: AgentToolKind.edit,
        locations: <String>['/workspace/src/app.dart'],
      );
      expect(
        tool.displayTitle(const FallbackAgentUiTextCatalog()),
        '编辑 · src/app.dart',
      );
    });
  });

  group('isOpaqueAgentToolCallTitle', () {
    test('detects call- style ids', () {
      expect(isOpaqueAgentToolCallTitle('call-1a2b'), isTrue);
      expect(isOpaqueAgentToolCallTitle('Read file'), isFalse);
      expect(
        isOpaqueAgentToolCallTitle('call-1a2b', toolCallId: 'call-1a2b'),
        isTrue,
      );
    });

    test('detects generic titles from status-only updates', () {
      expect(isNonInformativeAgentToolCallTitle('操作'), isTrue);
      expect(isNonInformativeAgentToolCallTitle('Tool progress'), isTrue);
      expect(
        isNonInformativeAgentToolCallTitle('run_terminal_command'),
        isFalse,
      );
    });
  });
}
