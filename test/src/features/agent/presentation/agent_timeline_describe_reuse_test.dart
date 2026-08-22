import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';

void main() {
  const layout = AgentTimelineLayoutContext(
    crossAxisExtent: 720,
    devicePixelRatio: 1,
    textScale: 1,
    localeKey: 'zh',
  );
  const expansion = (
    isCommandGroupExpanded: _neverExpanded,
    isFileEditItemExpanded: _neverExpanded,
    isPlanMessageInteractive: _neverExpanded,
  );

  test('describeAll reuses unchanged prefix descriptors when tail grows', () {
    final factory = AgentTimelineExtentDescriptorFactory();
    final toolEntry = AgentToolTimelineEntry(
      toolCall: const AgentToolCall(
        id: 'tool-1',
        title: 'run',
        kind: AgentToolKind.execute,
        status: AgentToolStatus.completed,
        content: 'ok',
      ),
    );
    final msgV1 = AgentMessageTimelineEntry(
      message: const AgentConversationMessage(
        id: 'msg-1',
        role: AgentMessageRole.agent,
        text: 'Hi',
      ),
    );
    final msgV2 = AgentMessageTimelineEntry(
      message: const AgentConversationMessage(
        id: 'msg-1',
        role: AgentMessageRole.agent,
        text: 'Hi there',
      ),
    );

    final turnV1 = AgentConversationTurnGroup(
      id: 'live',
      status: AgentHistoryTurnStatus.running,
      isStandby: false,
      entries: <AgentTimelineEntry>[toolEntry, msgV1],
      renderRevision: 1,
    );
    final turnV2 = AgentConversationTurnGroup(
      id: 'live',
      status: AgentHistoryTurnStatus.running,
      isStandby: false,
      entries: <AgentTimelineEntry>[toolEntry, msgV2],
      renderRevision: 2,
    );

    final itemsV1 = <AgentTimelineViewportItem>[
      AgentBlockViewportItem(
        turn: turnV1,
        block: AgentTimelineEntryRenderBlock(entry: toolEntry),
        isLive: true,
      ),
      AgentBlockViewportItem(
        turn: turnV1,
        block: AgentTimelineEntryRenderBlock(entry: msgV1),
        isLive: true,
      ),
    ];
    final itemsV2 = <AgentTimelineViewportItem>[
      AgentBlockViewportItem(
        turn: turnV2,
        block: AgentTimelineEntryRenderBlock(entry: toolEntry),
        isLive: true,
      ),
      AgentBlockViewportItem(
        turn: turnV2,
        block: AgentTimelineEntryRenderBlock(entry: msgV2),
        isLive: true,
      ),
    ];

    final d1 = factory.describeAll(
      itemsV1,
      expansion: expansion,
      layoutContext: layout,
    );
    final d2 = factory.describeAll(
      itemsV2,
      expansion: expansion,
      layoutContext: layout,
    );

    expect(identical(d1[0], d2[0]), isTrue, reason: 'tool descriptor reused');
    expect(identical(d1[1], d2[1]), isFalse, reason: 'message rebuilt');
    expect(factory.debugReusedDescriptorCount, greaterThanOrEqualTo(1));
  });
}

bool _neverExpanded(String _) => false;
