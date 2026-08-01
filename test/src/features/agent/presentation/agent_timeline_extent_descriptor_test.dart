import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_item.dart';

void main() {
  final factory = AgentTimelineExtentDescriptorFactory();
  const layout = AgentTimelineLayoutContext(
    crossAxisExtent: 720,
    devicePixelRatio: 1,
    textScale: 1,
    localeKey: 'zh',
  );
  const expansion = (
    isCommandGroupExpanded: _neverExpanded,
    isFileEditItemExpanded: _neverExpanded,
  );

  test('footer / activity / user message kinds 与 estimate 合理', () {
    final footer = AgentTurnFooterViewportItem(
      turn: AgentConversationTurnGroup(
        id: 't1',
        status: AgentHistoryTurnStatus.completed,
        isStandby: false,
        entries: const <AgentTimelineEntry>[],
        renderRevision: 3,
      ),
      isLive: false,
    );
    final activity = AgentLiveActivityViewportItem(
      turn: AgentConversationTurnGroup(
        id: 't2',
        status: AgentHistoryTurnStatus.running,
        isStandby: false,
        entries: const <AgentTimelineEntry>[],
        renderRevision: 1,
      ),
    );
    final user = AgentBlockViewportItem(
      turn: AgentConversationTurnGroup(
        id: 't3',
        status: AgentHistoryTurnStatus.completed,
        isStandby: false,
        entries: const <AgentTimelineEntry>[],
        renderRevision: 2,
      ),
      block: AgentTimelineEntryRenderBlock(
        entry: AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'm1',
            role: AgentMessageRole.user,
            text: 'hello\nworld',
          ),
        ),
      ),
      isLive: false,
    );

    final dFooter = factory.describe(
      footer,
      expansion: expansion,
      layoutContext: layout,
    );
    final dActivity = factory.describe(
      activity,
      expansion: expansion,
      layoutContext: layout,
    );
    final dUser = factory.describe(
      user,
      expansion: expansion,
      layoutContext: layout,
    );

    expect(dFooter.kind, AgentTimelineExtentKinds.turnFooter);
    expect(dActivity.kind, AgentTimelineExtentKinds.liveActivity);
    expect(dUser.kind, AgentTimelineExtentKinds.userMessage);
    expect(dFooter.estimatedExtent, greaterThan(0));
    expect(dUser.estimatedExtent, greaterThan(dFooter.estimatedExtent));
    expect(dFooter.id, footer.id);
  });

  test('layout epoch 按 physical pixel 量化宽度', () {
    final a = const AgentTimelineLayoutContext(
      crossAxisExtent: 100.4,
      devicePixelRatio: 2,
      textScale: 1.0,
      localeKey: 'en',
    ).toEpoch();
    final b = const AgentTimelineLayoutContext(
      crossAxisExtent: 100.6,
      devicePixelRatio: 2,
      textScale: 1.0,
      localeKey: 'en',
    ).toEpoch();
    expect(a.crossAxisExtentInPhysicalPixels, 201);
    expect(a, b);
  });

  test('describeAll 保持顺序与 id', () {
    final items = <AgentTimelineViewportItem>[
      AgentTurnFooterViewportItem(
        turn: AgentConversationTurnGroup(
          id: 'a',
          status: AgentHistoryTurnStatus.completed,
          isStandby: false,
          entries: const <AgentTimelineEntry>[],
        ),
        isLive: false,
      ),
      AgentTurnFooterViewportItem(
        turn: AgentConversationTurnGroup(
          id: 'b',
          status: AgentHistoryTurnStatus.completed,
          isStandby: false,
          entries: const <AgentTimelineEntry>[],
        ),
        isLive: false,
      ),
    ];
    final descriptors = factory.describeAll(
      items,
      expansion: expansion,
      layoutContext: layout,
    );
    expect(descriptors.map((d) => d.id).toList(), [items[0].id, items[1].id]);
    expect(descriptors, everyElement(isA<IdeVirtualItemDescriptor>()));
  });

  test('长 Markdown 逐源行累计折行且估算不再截断到 4000', () {
    final longLine = List<String>.filled(180, '宽').join();
    final text = List<String>.filled(80, longLine).join('\n');
    final message = AgentConversationMessage(
      id: 'long-markdown',
      role: AgentMessageRole.agent,
      text: text,
    );
    final entry = AgentMessageTimelineEntry(message: message);
    final item = AgentBlockViewportItem(
      turn: AgentConversationTurnGroup(
        id: 'long-turn',
        status: AgentHistoryTurnStatus.completed,
        isStandby: false,
        entries: <AgentTimelineEntry>[entry],
      ),
      block: AgentTimelineEntryRenderBlock(entry: entry),
      isLive: false,
    );

    final descriptor = factory.describe(
      item,
      expansion: expansion,
      layoutContext: const AgentTimelineLayoutContext(
        crossAxisExtent: 360,
        devicePixelRatio: 1,
        textScale: 1,
        localeKey: 'zh',
      ),
    );

    expect(descriptor.estimatedExtent, greaterThan(4000));
  });
}

bool _neverExpanded(String _) => false;
