import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry.dart';

void main() {
  final commandBlock = AgentTimelineCommandGroupRenderBlock(
    group: const AgentTimelineCommandGroup(
      id: 'cg1',
      items: <AgentTimelineCommandGroupItem>[],
    ),
  );
  final messageBlock = AgentTimelineEntryRenderBlock(
    entry: AgentMessageTimelineEntry(
      message: const AgentConversationMessage(
        id: 'm1',
        role: AgentMessageRole.agent,
        text: 'hi',
      ),
    ),
  );

  test('resolve 按 payload 类型命中；entry 级 block 先解包', () {
    const commandRenderer = _FakeRenderer<AgentTimelineCommandGroupRenderBlock>(
      payloadType: AgentTimelineCommandGroupRenderBlock,
      kind: AgentTimelineExtentKinds.commandGroup,
    );
    const messageRenderer = _FakeRenderer<AgentMessageTimelineEntry>(
      payloadType: AgentMessageTimelineEntry,
      kind: AgentTimelineExtentKinds.agentMarkdown,
    );
    final registry = AgentTimelineRendererRegistry(
      <AgentTimelineRenderer<Object>>[commandRenderer, messageRenderer],
    );

    expect(registry.resolve(commandBlock), same(commandRenderer));
    // 注册的是 entry 类型而非 AgentTimelineEntryRenderBlock：解包必须发生。
    expect(registry.resolve(messageBlock), same(messageRenderer));
    expect(
      AgentTimelineRendererRegistry.payloadOf(messageBlock),
      same(messageBlock.entry),
    );
    expect(
      AgentTimelineRendererRegistry.payloadOf(commandBlock),
      same(commandBlock),
    );
  });

  test('未注册类型抛 UnsupportedError，不静默回退', () {
    final registry =
        AgentTimelineRendererRegistry(<AgentTimelineRenderer<Object>>[
          const _FakeRenderer<AgentTimelineCommandGroupRenderBlock>(
            payloadType: AgentTimelineCommandGroupRenderBlock,
            kind: AgentTimelineExtentKinds.commandGroup,
          ),
        ]);

    expect(
      () => registry.resolve(messageBlock),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('AgentMessageTimelineEntry'),
        ),
      ),
    );
  });

  test('同一 payload 类型重复注册直接抛错', () {
    expect(
      () => AgentTimelineRendererRegistry(<AgentTimelineRenderer<Object>>[
        const _FakeRenderer<AgentTimelineCommandGroupRenderBlock>(
          payloadType: AgentTimelineCommandGroupRenderBlock,
          kind: AgentTimelineExtentKinds.commandGroup,
        ),
        const _FakeRenderer<AgentTimelineCommandGroupRenderBlock>(
          payloadType: AgentTimelineCommandGroupRenderBlock,
          kind: AgentTimelineExtentKinds.commandGroup,
        ),
      ]),
      throwsArgumentError,
    );
  });
}

/// 只登记类型的最小 renderer：本文件只验证分发，不验证渲染。
final class _FakeRenderer<P extends Object>
    extends AgentTimelineRendererBase<P> {
  const _FakeRenderer({required this.payloadType, required this.kind});

  @override
  final Type payloadType;

  final String kind;

  @override
  String kindOf(P payload) => kind;

  @override
  Widget build(
    BuildContext context,
    P payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) => const SizedBox.shrink();

  @override
  double estimateExtent(
    P payload, {
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    required bool precededByOperationGroup,
    required bool followedByOperationGroup,
  }) => 0;

  @override
  Object layoutRevision(P payload, AgentTimelineExpansionLookup expansion) => 0;
}
