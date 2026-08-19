import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  String kindLabel(AgentToolKind kind) => kind.name;

  group('buildAgentToolCallDisplayTitle', () {
    test('keeps explicit human titles', () {
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-1',
          kindLabel: kindLabel,
          title: 'Read file',
          kind: AgentToolKind.read,
        ),
        'Read file',
      );
    });

    test('synthesizes titles without exposing opaque ids', () {
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-abc123',
          kindLabel: kindLabel,
          title: 'call-abc123',
          kind: AgentToolKind.read,
          locations: const <String>[r'D:\repo\zeta\lib\main.dart'],
        ),
        'read · lib/main.dart',
      );
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-9',
          kindLabel: kindLabel,
          kind: AgentToolKind.execute,
          rawInput: const <String, Object?>{'command': 'flutter test'},
        ),
        'execute · flutter test',
      );
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call-empty',
          kindLabel: kindLabel,
          kind: AgentToolKind.search,
        ),
        'search',
      );
    });
  });

  test('opaque and generic tool titles are detected', () {
    expect(isOpaqueAgentToolCallTitle('call-1a2b'), isTrue);
    expect(isOpaqueAgentToolCallTitle('Read file'), isFalse);
    expect(isOpaqueAgentToolCallTitle('tc_123'), isTrue);
    expect(
      isOpaqueAgentToolCallTitle(
        '01234567-89ab-cdef-0123-456789abcdef',
      ),
      isTrue,
    );
    expect(isNonInformativeAgentToolCallTitle('Tool progress'), isTrue);
    expect(isNonInformativeAgentToolCallTitle('run_terminal_command'), isFalse);
  });
}
