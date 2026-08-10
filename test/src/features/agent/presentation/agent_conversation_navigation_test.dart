import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_navigation.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_item.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_list_controller.dart';

void main() {
  group('buildAgentConversationNavigationEntries', () {
    test('每个非 standby turn 对应一项，跳过 standby', () {
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 's', standby: true, userText: 'standby'),
          _turn(id: 't1', userText: '第一问'),
          _turn(id: 't2', userText: '第二问'),
        ],
        liveTurn: _turn(
          id: 'live',
          userText: '第三问',
          status: AgentHistoryTurnStatus.running,
        ),
      );

      expect(entries.map((e) => e.turnId).toList(), <String>[
        't1',
        't2',
        'live',
      ]);
      expect(entries.map((e) => e.ordinal).toList(), <int>[1, 2, 3]);
      expect(entries[0].label, '第一问');
      expect(entries[2].status, AgentConversationNavigationStatus.streaming);
    });

    test('history 与 live 同 id 时不重复', () {
      final turn = _turn(id: 't1', userText: '同一回合');
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[turn],
        liveTurn: turn,
      );
      expect(entries, hasLength(1));
      expect(entries.single.turnId, 't1');
    });

    test('工具调用不产生额外顶级导航项', () {
      final turn = AgentConversationTurnGroup(
        id: 't1',
        isStandby: false,
        status: AgentHistoryTurnStatus.completed,
        entries: <AgentTimelineEntry>[
          AgentMessageTimelineEntry(
            message: AgentConversationMessage(
              id: 'u1',
              role: AgentMessageRole.user,
              text: '请改代码',
            ),
          ),
          AgentToolTimelineEntry(
            toolCall: AgentToolCall(
              id: 'tool-1',
              kind: AgentToolKind.execute,
              title: 'run',
              status: AgentToolStatus.completed,
            ),
          ),
          AgentToolTimelineEntry(
            toolCall: AgentToolCall(
              id: 'tool-2',
              kind: AgentToolKind.edit,
              title: 'edit',
              status: AgentToolStatus.completed,
            ),
          ),
          AgentMessageTimelineEntry(
            message: AgentConversationMessage(
              id: 'a1',
              role: AgentMessageRole.agent,
              text: '完成',
            ),
          ),
        ],
      );
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[turn],
        liveTurn: null,
      );
      expect(entries, hasLength(1));
      expect(entries.single.hasTools, isTrue);
      expect(entries.single.hasFileEdits, isTrue);
      expect(entries.single.anchorViewportItemId, contains('message-u1'));
    });

    test('空可见块的 turn 不生成导航项', () {
      final empty = AgentConversationTurnGroup(
        id: 'empty',
        isStandby: false,
        entries: const <AgentTimelineEntry>[],
      );
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[empty],
        liveTurn: null,
      );
      expect(entries, isEmpty);
    });

    test('摘要截断到最大字符数', () {
      final long = '字' * 80;
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 't1', userText: long),
        ],
        liveTurn: null,
      );
      expect(
        entries.single.label.length,
        kAgentConversationNavigationLabelMaxChars + 1, // 含省略号
      );
      expect(entries.single.label.endsWith('…'), isTrue);
    });
  });

  group('shouldShowAgentConversationNavigation', () {
    test('短于阈值时隐藏', () {
      final two = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 't1', userText: 'a'),
          _turn(id: 't2', userText: 'b'),
        ],
        liveTurn: null,
      );
      expect(shouldShowAgentConversationNavigation(two), isFalse);

      final enough = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          for (var i = 0; i < kAgentConversationNavigationMinEntries; i++)
            _turn(id: 't$i', userText: 'q$i'),
        ],
        liveTurn: null,
      );
      expect(shouldShowAgentConversationNavigation(enough), isTrue);
    });
  });

  group('resolveActiveNavigationTurnId', () {
    test('按 extent 阅读线映射到 turn', () {
      final turns = <AgentConversationTurnGroup>[
        _turn(id: 't1', userText: 'one'),
        _turn(id: 't2', userText: 'two'),
        _turn(id: 't3', userText: 'three'),
      ];
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: turns,
        liveTurn: null,
      );
      final items = projectAgentTimelineViewportItems(
        standbyTurn: null,
        visibleHistoryTurns: turns,
        liveTurn: null,
        resolveBlocks: _blocks,
      );
      final controller = IdeVirtualListController()
        ..synchronizeNow(
          <IdeVirtualItemDescriptor>[
            for (final item in items)
              IdeVirtualItemDescriptor(
                id: item.id,
                kind: 'block',
                estimatedExtent: 100,
                layoutRevision: 0,
              ),
          ],
          epoch: const IdeLayoutEpoch(
            crossAxisExtentInPhysicalPixels: 800,
            textScaleKey: 1,
            localeKey: 'zh',
            typographyEpoch: 0,
          ),
        );

      // 每个 turn：user block + agent block + footer = 3 项 × 100。
      // t2 起点 300；阅读线 = scroll + viewport*0.12。
      final active = resolveActiveNavigationTurnId(
        entries: entries,
        items: items,
        controller: controller,
        scrollPixels: 320,
        contentTopInset: 0,
        viewportDimension: 400,
      );
      expect(active, 't2');
    });
  });

  group('resolveNavigationScrollOffset', () {
    test('锚点 offset 加上 contentTopInset', () {
      final turn = _turn(id: 't1', userText: 'hi');
      final entries = buildAgentConversationNavigationEntries(
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 'before', userText: 'before'),
          turn,
        ],
        liveTurn: null,
      );
      final items = projectAgentTimelineViewportItems(
        standbyTurn: null,
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 'before', userText: 'before'),
          turn,
        ],
        liveTurn: null,
        resolveBlocks: _blocks,
      );
      final controller = IdeVirtualListController()
        ..synchronizeNow(
          <IdeVirtualItemDescriptor>[
            for (final item in items)
              IdeVirtualItemDescriptor(
                id: item.id,
                kind: 'block',
                estimatedExtent: 50,
                layoutRevision: 0,
              ),
          ],
          epoch: const IdeLayoutEpoch(
            crossAxisExtentInPhysicalPixels: 800,
            textScaleKey: 1,
            localeKey: 'zh',
            typographyEpoch: 0,
          ),
        );

      final targetEntry = entries.firstWhere((e) => e.turnId == 't1');
      final offset = resolveNavigationScrollOffset(
        entry: targetEntry,
        controller: controller,
        contentTopInset: 16,
        maxScrollExtent: 1000,
      );
      expect(offset, isNotNull);
      // before turn 至少一个 block + footer（约 2 * 50）再加 inset。
      expect(offset! >= 16, isTrue);
    });
  });

  group('buildAgentConversationNavigationTooltip', () {
    test('包含序号、摘要与状态', () {
      final entry = AgentConversationNavigationEntry(
        entryId: 't1',
        turnId: 't1',
        ordinal: 6,
        label: '建立 Agent 权限架构契约测试',
        status: AgentConversationNavigationStatus.completed,
        anchorViewportItemId: 'turn-block-t1-message-u1',
        hasTools: true,
      );
      final text = buildAgentConversationNavigationTooltip(entry);
      expect(text, contains('第 6 个回合'));
      expect(text, contains('建立 Agent 权限架构契约测试'));
      expect(text, contains('已完成'));
      expect(text, contains('含工具'));
    });
  });
}

AgentConversationTurnGroup _turn({
  required String id,
  String userText = 'question',
  bool standby = false,
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed,
}) {
  return AgentConversationTurnGroup(
    id: id,
    status: status,
    isStandby: standby,
    entries: <AgentTimelineEntry>[
      AgentMessageTimelineEntry(
        message: AgentConversationMessage(
          id: '$id-user',
          role: AgentMessageRole.user,
          text: userText,
        ),
      ),
      AgentMessageTimelineEntry(
        message: AgentConversationMessage(
          id: '$id-agent',
          role: AgentMessageRole.agent,
          text: 'answer $id',
        ),
      ),
    ],
  );
}

List<AgentTimelineRenderBlock> _blocks(AgentConversationTurnGroup turn) {
  return buildAgentTimelineRenderBlocks(turnId: turn.id, entries: turn.entries);
}
