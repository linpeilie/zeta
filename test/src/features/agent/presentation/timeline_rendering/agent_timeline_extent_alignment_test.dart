import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderers.dart';

/// renderer 的 kind / estimateExtent 必须与迁移前的 descriptor 工厂逐条对齐：
/// 估算与真实高度脱节会让长会话滚动出现跳动。测试直接拿工厂当基线对比，
/// 而不是写死快照值——工厂公式后续调整时两侧不会悄悄分叉。
void main() {
  final registry = buildAgentTimelineRendererRegistry();

  const layout = AgentTimelineLayoutContext(
    crossAxisExtent: 720,
    devicePixelRatio: 1,
    textScale: 1,
    localeKey: 'zh',
  );
  const expansion = (
    isCommandGroupExpanded: _alwaysExpanded,
    isFileEditItemExpanded: _alwaysExpanded,
    isPlanMessageInteractive: _neverExpanded,
  );
  const collapsed = (
    isCommandGroupExpanded: _neverExpanded,
    isFileEditItemExpanded: _neverExpanded,
    isPlanMessageInteractive: _neverExpanded,
  );

  /// 与工厂对齐：kind 与估算高度都必须一致。
  void expectAligned(
    String label,
    AgentTimelineRenderBlock block, {
    AgentTimelineExpansionLookup lookup = collapsed,
    bool precededByOperationGroup = false,
    bool followedByOperationGroup = false,
  }) {
    final item = AgentBlockViewportItem(
      turn: _turn(<AgentTimelineEntry>[]),
      block: block,
      isLive: false,
    );
    final previous = precededByOperationGroup ? _operationGroupItem() : null;
    final next = followedByOperationGroup ? _operationGroupItem() : null;
    final descriptor = AgentTimelineExtentDescriptorFactory().describe(
      item,
      previousItem: previous,
      nextItem: next,
      expansion: lookup,
      layoutContext: layout,
    );
    final renderer = registry.resolve(block);
    final payload = AgentTimelineRendererRegistry.payloadOf(block);

    expect(renderer.kindOf(payload), descriptor.kind, reason: '$label kind');
    expect(
      renderer.estimateExtent(
        payload,
        crossAxisExtent: layout.crossAxisExtent,
        textScale: layout.textScale,
        expansion: lookup,
        precededByOperationGroup: precededByOperationGroup,
        followedByOperationGroup: followedByOperationGroup,
      ),
      descriptor.estimatedExtent,
      reason: '$label extent',
    );
  }

  group('extent 对齐', () {
    test('commandGroup 折叠 / 展开 / 邻接操作组三种情形均与工厂一致', () {
      final block = _commandGroupBlock();
      expectAligned('commandGroup collapsed', block);
      expectAligned('commandGroup expanded', block, lookup: expansion);
      expectAligned(
        'commandGroup adjacent',
        block,
        precededByOperationGroup: true,
        followedByOperationGroup: true,
      );
    });

    test('fileEditGroup 折叠 / 展开 / 邻接操作组三种情形均与工厂一致', () {
      final block = _fileEditGroupBlock();
      expectAligned('fileEditGroup collapsed', block);
      expectAligned('fileEditGroup expanded', block, lookup: expansion);
      expectAligned(
        'fileEditGroup adjacent',
        block,
        precededByOperationGroup: true,
        followedByOperationGroup: true,
      );
    });

    test('四类消息（user / agent / plan / system）与空正文均与工厂一致', () {
      expectAligned(
        'user',
        _messageBlock(role: AgentMessageRole.user, text: 'hello\nworld'),
      );
      expectAligned(
        'agent',
        _messageBlock(
          role: AgentMessageRole.agent,
          text: List<String>.filled(40, '正文很长' * 20).join('\n'),
        ),
      );
      expectAligned(
        'system',
        _messageBlock(role: AgentMessageRole.system, text: 'system note'),
      );
      expectAligned(
        'empty',
        _messageBlock(role: AgentMessageRole.agent, text: '   '),
      );
    });

    test('交互态 plan 消息与工厂一致（含底部输入 chrome）', () {
      const interactive = (
        isCommandGroupExpanded: _neverExpanded,
        isFileEditItemExpanded: _neverExpanded,
        isPlanMessageInteractive: _alwaysExpanded,
      );
      final block = _messageBlock(
        role: AgentMessageRole.agent,
        text: '# 计划\n- 步骤一\n- 步骤二',
        kind: AgentMessageKind.plan,
      );
      expectAligned('plan collapsed', block);
      expectAligned('plan interactive', block, lookup: interactive);
      expectAligned(
        'plan interactive empty',
        _messageBlock(
          role: AgentMessageRole.agent,
          text: '',
          kind: AgentMessageKind.plan,
        ),
        lookup: interactive,
      );
    });

    test('toolCall / planApproval / historyEvent 与工厂一致', () {
      expectAligned('toolCall', _toolCallBlock());
      expectAligned('planApproval', _planApprovalBlock());
      expectAligned('historyEvent', _historyEventBlock());
    });
  });

  group('零高度条目', () {
    // 迁移前这三类落在 _estimateEntry 的 48px 兜底（turnFileChanges 走 80px），
    // 而 sections 实际渲染 SizedBox.shrink()——估算与实测差一整项，虚拟化锚点
    // 会漂。renderer 按实际渲染结果登记 hidden + 0，这是本 WP 顺带修正的行为。
    test('permission / question / turnFileChanges 报 hidden 且估算 0', () {
      for (final block in <AgentTimelineRenderBlock>[
        _entryBlock(
          AgentPermissionTimelineEntry(
            request: const AgentPermissionRequest(
              id: 'p1',
              title: '执行命令',
              kind: AgentPermissionKind.commandExecution,
            ),
          ),
        ),
        _entryBlock(
          AgentQuestionTimelineEntry(
            request: const AgentQuestionRequest(
              id: 'q1',
              title: '选一个',
              questions: <AgentUserInputQaPair>[],
            ),
          ),
        ),
        _entryBlock(_turnFileChangesEntry()),
      ]) {
        final renderer = registry.resolve(block);
        final payload = AgentTimelineRendererRegistry.payloadOf(block);
        expect(renderer.kindOf(payload), AgentTimelineExtentKinds.hidden);
        expect(
          renderer.estimateExtent(
            payload,
            crossAxisExtent: 720,
            textScale: 1,
            expansion: collapsed,
            precededByOperationGroup: false,
            followedByOperationGroup: false,
          ),
          0,
        );
        // 零高度项不能当导航锚点。
        expect(renderer.rendersInline, isFalse);
      }
    });

    test('可见条目都进导航目录', () {
      for (final block in <AgentTimelineRenderBlock>[
        _commandGroupBlock(),
        _fileEditGroupBlock(),
        _messageBlock(role: AgentMessageRole.user, text: 'hi'),
        _toolCallBlock(),
        _planApprovalBlock(),
        _historyEventBlock(),
      ]) {
        expect(registry.resolve(block).rendersInline, isTrue);
      }
    });
  });

  group('layoutRevision', () {
    test('命令集内条目内容变化会改变指纹', () {
      final before = _commandGroupBlock(toolStatus: AgentToolStatus.pending);
      final after = _commandGroupBlock(toolStatus: AgentToolStatus.completed);
      final renderer = registry.resolve(before);
      expect(
        renderer.layoutRevision(
          AgentTimelineRendererRegistry.payloadOf(before),
          collapsed,
        ),
        isNot(
          renderer.layoutRevision(
            AgentTimelineRendererRegistry.payloadOf(after),
            collapsed,
          ),
        ),
      );
    });

    test('展开态变化会改变指纹（命令集 / 文件编辑组 / 交互态 plan）', () {
      const interactive = (
        isCommandGroupExpanded: _neverExpanded,
        isFileEditItemExpanded: _neverExpanded,
        isPlanMessageInteractive: _alwaysExpanded,
      );
      final cases = <(AgentTimelineRenderBlock, AgentTimelineExpansionLookup)>[
        (_commandGroupBlock(), expansion),
        (_fileEditGroupBlock(), expansion),
        (
          _messageBlock(
            role: AgentMessageRole.agent,
            text: '# 计划',
            kind: AgentMessageKind.plan,
          ),
          interactive,
        ),
      ];
      for (final (block, changed) in cases) {
        final renderer = registry.resolve(block);
        final payload = AgentTimelineRendererRegistry.payloadOf(block);
        expect(
          renderer.layoutRevision(payload, collapsed),
          isNot(renderer.layoutRevision(payload, changed)),
        );
      }
    });

    test('同一 payload 与同一展开态得到相等指纹', () {
      final block = _fileEditGroupBlock();
      final renderer = registry.resolve(block);
      final payload = AgentTimelineRendererRegistry.payloadOf(block);
      expect(
        renderer.layoutRevision(payload, collapsed),
        renderer.layoutRevision(payload, collapsed),
      );
    });
  });

  test('默认清单登记 9 条：entry 级 7 + block 级 2', () {
    expect(registry.registeredPayloadTypes.length, 9);
  });
}

bool _neverExpanded(String id) => false;

bool _alwaysExpanded(String id) => true;

AgentConversationTurnGroup _turn(List<AgentTimelineEntry> entries) {
  return AgentConversationTurnGroup(
    id: 'turn-1',
    status: AgentHistoryTurnStatus.completed,
    isStandby: false,
    entries: entries,
    contentRevision: 1,
  );
}

AgentBlockViewportItem _operationGroupItem() {
  return AgentBlockViewportItem(
    turn: _turn(<AgentTimelineEntry>[]),
    block: _commandGroupBlock(),
    isLive: false,
  );
}

AgentTimelineEntryRenderBlock _entryBlock(AgentTimelineEntry entry) {
  return AgentTimelineEntryRenderBlock(entry: entry);
}

AgentTimelineCommandGroupRenderBlock _commandGroupBlock({
  AgentToolStatus toolStatus = AgentToolStatus.completed,
}) {
  return AgentTimelineCommandGroupRenderBlock(
    group: AgentTimelineCommandGroup(
      id: 'command-group-1',
      items: <AgentTimelineCommandGroupItem>[
        AgentTimelineCommandGroupItem(
          id: 'item-1',
          kind: AgentToolKind.execute,
          title: 'ls -la',
          entry: AgentToolTimelineEntry(
            toolCall: AgentToolCall(
              id: 'tool-1',
              title: 'ls -la',
              kind: AgentToolKind.execute,
              status: toolStatus,
            ),
          ),
        ),
        AgentTimelineCommandGroupItem(
          id: 'item-2',
          kind: AgentToolKind.search,
          title: 'grep foo',
          entry: AgentHistoryEventTimelineEntry(
            event: AgentHistoryEventEntry(
              id: 'event-1',
              kind: AgentHistoryEventKind.search,
              title: 'grep foo',
            ),
          ),
        ),
      ],
    ),
  );
}

AgentTimelineFileEditGroupRenderBlock _fileEditGroupBlock() {
  return AgentTimelineFileEditGroupRenderBlock(
    group: AgentTimelineFileEditGroup(
      id: 'file-edit-group-1',
      items: <AgentTimelineFileEditItem>[
        AgentTimelineFileEditItem(
          id: 'edit-1',
          title: 'lib/main.dart',
          status: AgentToolStatus.completed,
          projection: _projection('edit-1', 'lib/main.dart'),
        ),
        AgentTimelineFileEditItem(
          id: 'edit-2',
          title: 'lib/app.dart',
          status: AgentToolStatus.completed,
          projection: _projection('edit-2', 'lib/app.dart'),
        ),
      ],
    ),
  );
}

AgentFileChangeItemProjection _projection(String ownerEntryId, String path) {
  return AgentFileChangeItemProjection(
    ownerEntryId: ownerEntryId,
    snapshotRevision: 1,
    replayability: AgentFileChangeReplayability.replayable,
    changeId: 'change-$ownerEntryId',
    path: path,
    destinationPath: null,
    kind: AgentFileChangeKind.modified,
    statistics: null,
    detail: null,
  );
}

AgentTimelineEntryRenderBlock _messageBlock({
  required AgentMessageRole role,
  required String text,
  AgentMessageKind kind = AgentMessageKind.regular,
}) {
  return _entryBlock(
    AgentMessageTimelineEntry(
      message: AgentConversationMessage(
        id: 'm-${role.name}-$kind',
        role: role,
        text: text,
        kind: kind,
      ),
    ),
  );
}

AgentTimelineEntryRenderBlock _toolCallBlock() {
  return _entryBlock(
    AgentToolTimelineEntry(
      toolCall: const AgentToolCall(
        id: 'tool-9',
        title: 'read file',
        kind: AgentToolKind.read,
      ),
    ),
  );
}

AgentTimelineEntryRenderBlock _planApprovalBlock() {
  return _entryBlock(
    AgentPlanApprovalTimelineEntry(
      request: const AgentPlanApprovalRequest(
        id: 'plan-1',
        title: '实施计划',
        markdown: '# 计划\n\n- 第一步\n- 第二步\n',
      ),
    ),
  );
}

AgentTimelineEntryRenderBlock _historyEventBlock() {
  return _entryBlock(
    AgentHistoryEventTimelineEntry(
      event: const AgentHistoryEventEntry(
        id: 'event-9',
        kind: AgentHistoryEventKind.system,
        title: '会话已压缩',
      ),
    ),
  );
}

AgentTurnFileChangesTimelineEntry _turnFileChangesEntry() {
  return AgentTurnFileChangesTimelineEntry(
    turnId: 'turn-1',
    snapshot: AgentFileChangeSnapshot(
      revision: 1,
      replayability: AgentFileChangeReplayability.replayable,
      changes: <AgentFileChange>[],
    ),
  );
}
