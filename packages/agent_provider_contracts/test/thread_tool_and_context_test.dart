import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  AgentThreadSummary summary({
    String id = 'thread-123456',
    String? title,
    String preview = '',
    AgentThreadRuntimeStatus status = AgentThreadRuntimeStatus.idle,
  }) => AgentThreadSummary(
    id: id,
    providerId: 'provider',
    projectPath: '/repo',
    title: title,
    preview: preview,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: status,
  );

  test(
    'thread values cover placeholder, persistence, copy, and paging rules',
    () {
      expect(const AgentForkThroughTurn('turn').turnId, 'turn');
      expect(const AgentForkCurrentHead(), isA<AgentForkBoundary>());
      expect(isAgentThreadTitlePlaceholder(null), isTrue);
      expect(isAgentThreadTitlePlaceholder(agentDefaultThreadTitle), isTrue);
      expect(isAgentThreadTitlePlaceholder(agentDefaultThreadTitleEn), isTrue);
      expect(
        isAgentThreadTitlePlaceholder(agentProviderPlaceholderThreadTitle),
        isTrue,
      );
      expect(isAgentThreadTitlePlaceholder('Real'), isFalse);

      final active = summary(status: AgentThreadRuntimeStatus.active);
      expect(active.isBusy, isTrue);
      expect(summary().isBusy, isFalse);
      expect(summary(title: 'Title').displayTitle, 'Title');
      expect(summary(id: 'short').displayName, 'short');
      final copied = active.copyWith(
        id: 'copy',
        providerId: 'p2',
        projectPath: '/copy',
        title: 'Copied',
        sessionPath: '/session',
        preview: 'preview',
        createdAt: DateTime.fromMillisecondsSinceEpoch(3),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(4),
        recencyAt: DateTime.fromMillisecondsSinceEpoch(5),
        status: AgentThreadRuntimeStatus.systemError,
        waitingOnApproval: true,
        waitingOnUserInput: true,
        raw: <String, Object?>{'x': 1},
      );
      expect(copied.id, 'copy');
      expect(copied.toJson(), containsPair('sessionPath', '/session'));
      expect(active.copyWith(title: null).title, isNull);
      expect(active.copyWith().id, active.id);
      expect(AgentThreadSummary.tryDecode(null), isNull);
      expect(
        AgentThreadSummary.tryDecode(<String, Object?>{'id': 'broken'}),
        isNull,
      );
      final decoded = AgentThreadSummary.tryDecode(<String, Object?>{
        'id': 'thread',
        'providerId': 'provider',
        'projectPath': '/repo',
        'createdAt': 1,
        'updatedAt': 2,
        'status': 'future-status',
      });
      expect(decoded?.status, AgentThreadRuntimeStatus.unknown);
      final sourceKinds = <String>['cli'];
      final query = AgentThreadListQuery(
        projectPath: '/repo',
        limit: 20,
        sourceKinds: sourceKinds,
      );
      sourceKinds.clear();
      expect(query.sourceKinds, <String>['cli']);
      expect(query.sourceKinds.clear, throwsUnsupportedError);
      final page = AgentThreadPage(
        threads: <AgentThreadSummary>[active],
        nextCursor: null,
      );
      expect(page.threads.single, active);
      expect(page.threads.clear, throwsUnsupportedError);
    },
  );

  test('turn context merges and upserts immutable records', () {
    final first = AgentTurnContextRecord(
      turnId: 'turn-1',
      modelId: 'model-a',
      startedAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    final merged = first.merge(
      const AgentTurnContextRecord(
        turnId: 'turn-1',
        reasoningEffort: 'high',
        explicitFast: true,
        status: AgentHistoryTurnStatus.completed,
      ),
    );
    expect(merged.modelId, 'model-a');
    expect(merged.reasoningEffort, 'high');
    final context = AgentThreadTurnContext(
      providerId: 'provider',
      threadId: 'thread',
      turns: <AgentTurnContextRecord>[first],
    );
    expect(context.turnById('turn-1'), first);
    expect(context.turnById('missing'), isNull);
    final replaced = context.upsertTurn(merged);
    expect(replaced.turns.single.reasoningEffort, 'high');
    final appended = replaced.upsertTurn(
      const AgentTurnContextRecord(turnId: 'turn-2'),
    );
    expect(appended.turns, hasLength(2));
    expect(appended.turns.clear, throwsUnsupportedError);
  });

  test('tool model handles lifecycle, parsing, copies, and title details', () {
    final tool = AgentToolCall(
      id: 'tool',
      title: 'Run',
      kind: AgentToolKind.execute,
      status: AgentToolStatus.inProgress,
      content: 'content',
      locations: <String>['/repo/lib/main.dart'],
      rawInput: <String, Object?>{
        'arguments': <String, Object?>{'path': '/repo/lib/main.dart'},
      },
      rawOutput: <String, Object?>{'ok': true},
      raw: <String, Object?>{'event': 'update'},
    );
    expect(tool.isActiveStatus, isTrue);
    expect(tool.isTerminalStatus, isFalse);
    expect(
      tool.copyWith(status: AgentToolStatus.completed).isTerminalStatus,
      isTrue,
    );
    expect(
      tool.copyWith(status: AgentToolStatus.failed).isTerminalStatus,
      isTrue,
    );
    expect(
      tool.copyWith(status: AgentToolStatus.cancelled).isTerminalStatus,
      isTrue,
    );
    final copy = tool.copyWith(
      id: 'copy',
      title: 'Copy',
      kind: AgentToolKind.read,
      content: 'new',
      locations: <String>['a'],
      sessionId: 'thread',
      turnId: 'turn',
      startedAt: DateTime.fromMillisecondsSinceEpoch(1),
      completedAt: DateTime.fromMillisecondsSinceEpoch(2),
      duration: const Duration(seconds: 1),
      rawInput: <String, Object?>{'x': 1},
      rawOutput: <String, Object?>{'y': 2},
      raw: <String, Object?>{'z': 3},
    );
    expect(copy.id, 'copy');
    expect(tool.copyWith(clearContent: true).content, isNull);
    expect(tool.locations.clear, throwsUnsupportedError);

    for (final entry in <String, AgentToolKind>{
      'read': AgentToolKind.read,
      'edit': AgentToolKind.edit,
      'delete': AgentToolKind.delete,
      'move': AgentToolKind.move,
      'search': AgentToolKind.search,
      'execute': AgentToolKind.execute,
      'think': AgentToolKind.think,
      'fetch': AgentToolKind.fetch,
      'unknown': AgentToolKind.other,
    }.entries) {
      expect(parseAgentToolKind(entry.key), entry.value);
    }
    String label(AgentToolKind kind) => kind.name;
    expect(
      buildAgentToolCallDisplayTitle(
        toolCallId: 'call-1',
        kindLabel: label,
        rawInput: <String, Object?>{
          'arguments': <String, Object?>{'path': '/repo/lib/main.dart'},
        },
      ),
      'lib/main.dart',
    );
    expect(
      buildAgentToolCallDisplayTitle(
        toolCallId: 'call-1',
        kindLabel: label,
        rawInput: const <String, Object?>{'arguments': 'a very useful command'},
      ),
      'a very useful command',
    );
    expect(
      buildAgentToolCallDisplayTitle(
        toolCallId: 'call-1',
        kindLabel: label,
        locations: const <String>['single'],
      ),
      'single',
    );
    expect(
      buildAgentToolCallDisplayTitle(
        toolCallId: 'call-1',
        kindLabel: label,
        rawInput: <String, Object?>{'command': List<String>.filled(20, 'long')},
      ).endsWith('…'),
      isTrue,
    );
  });
}
