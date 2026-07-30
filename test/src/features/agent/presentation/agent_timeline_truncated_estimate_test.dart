import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';

void main() {
  final descriptorFactory = AgentTimelineExtentDescriptorFactory();
  const layout = AgentTimelineLayoutContext(
    crossAxisExtent: 720,
    devicePixelRatio: 1,
    textScale: 1,
    localeKey: 'en',
  );
  const expansion = (
    isCommandGroupExpanded: _never,
    isFileEditItemExpanded: _never,
  );

  test('history and live long markdown share full-height estimates', () {
    final longText = List<String>.filled(
      20,
      'line of markdown content\n',
    ).join();

    final message = AgentConversationMessage(
      id: 'm1',
      role: AgentMessageRole.agent,
      text: longText,
    );
    final entry = AgentMessageTimelineEntry(message: message);
    final turn = AgentConversationTurnGroup(
      id: 't1',
      isStandby: false,
      entries: <AgentTimelineEntry>[entry],
      contentRevision: 1,
      renderRevision: 1,
    );
    final historyItem = AgentBlockViewportItem(
      turn: turn,
      block: AgentTimelineEntryRenderBlock(entry: entry),
      isLive: false,
    );
    final liveItem = AgentBlockViewportItem(
      turn: turn,
      block: AgentTimelineEntryRenderBlock(entry: entry),
      isLive: true,
    );

    final historyDesc = descriptorFactory.describe(
      historyItem,
      expansion: expansion,
      layoutContext: layout,
    );
    final liveDesc = descriptorFactory.describe(
      liveItem,
      expansion: expansion,
      layoutContext: layout,
    );

    // 禁止折叠后，历史与 live 使用同一全文估算，不再截断到预览高度。
    expect(historyDesc.estimatedExtent, liveDesc.estimatedExtent);
    expect(historyDesc.estimatedExtent, greaterThan(180));
  });
}

bool _never(String _) => false;
