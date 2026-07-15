part of '../agent_pane.dart';

/// 上下文详情面板的固定宽度。
const double _agentContextPanelWidth = 360;

/// Agent 面板右侧的上下文详情面板。
///
/// 由 thread 详情头栏「上下文」菜单触发，展示会话元信息（名称、消息数、
/// 提供商、上下文限制、token 占用、创建/活跃时间）与原始消息列表。
/// 原始消息列表展示消息 ID、角色与时间，点击可展开查看 raw 协议原文。
class _AgentContextPanel extends StatefulWidget {
  const _AgentContextPanel({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  State<_AgentContextPanel> createState() => _AgentContextPanelState();
}

class _AgentContextPanelState extends State<_AgentContextPanel> {
  /// 原始消息行展开态：按条目 id 记录，避免父级重建时丢失。
  final Set<String> _expandedRawMessageIds = <String>{};

  /// 默认开启：隐藏工具调用、审批、系统事件等非主对话条目。
  bool _filterNonChatMessages = true;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    // 监听 ViewModel 整体变更：token 用量、消息列表与标题都会随它刷新。
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = IdeColors.of(context);
        final usage = viewModel.currentThreadTokenUsage;
        final messages = viewModel.messages;
        final rawItems = _buildContextRawItems(
          timelineEntries: viewModel.timelineEntries,
          filterNonChat: _filterNonChatMessages,
        );
        return Container(
          key: const ValueKey('agent-context-panel'),
          width: _agentContextPanelWidth,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              left: BorderSide(color: colors.borderSubtle, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AgentContextPanelHeader(onClose: viewModel.hideContextPanel),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    IdeSpacing.space16,
                    IdeSpacing.space8,
                    IdeSpacing.space16,
                    IdeSpacing.space20,
                  ),
                  child: RepaintBoundary(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AgentContextSummaryCard(
                          title: viewModel.currentThreadTitle,
                          messageCount: messages.length,
                          providerName: viewModel.activeProviderName,
                          contextLimit: usage?.displayModelContextWindow,
                          totalTokens: usage?.displayTotalTokens,
                          inputTokens: usage?.displayInputTokens,
                          outputTokens: usage?.displayOutputTokens,
                          cachedTokens: usage?.displayCachedInputTokens,
                          createdAt: viewModel.threadCreatedAt,
                          lastActiveAt: viewModel.threadLastActiveAt,
                        ),
                        const SizedBox(height: IdeSpacing.space20),
                        _AgentContextRawMessageList(
                          items: rawItems,
                          filterNonChat: _filterNonChatMessages,
                          expandedIds: _expandedRawMessageIds,
                          onToggle: _toggleRawMessage,
                          onFilterChanged: (value) {
                            setState(() {
                              _filterNonChatMessages = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleRawMessage(String messageId) {
    setState(() {
      if (!_expandedRawMessageIds.add(messageId)) {
        _expandedRawMessageIds.remove(messageId);
      }
    });
  }
}

/// 上下文面板标题栏：图标 + 标题 + 关闭按钮。
class _AgentContextPanelHeader extends StatelessWidget {
  const _AgentContextPanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Container(
      key: const ValueKey('agent-context-panel-header'),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 15,
            color: colors.textSecondary,
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            '上下文',
            style: textStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IdeTooltip(
            message: '关闭',
            child: sf.IconButton.ghost(
              key: const ValueKey('agent-context-panel-close'),
              onPressed: onClose,
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.iconDense,
              icon: Icon(
                Icons.close_rounded,
                size: 15,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 上下文概览信息卡：会话名称、消息数、提供商、token 与时间等键值对。
class _AgentContextSummaryCard extends StatelessWidget {
  const _AgentContextSummaryCard({
    required this.title,
    required this.messageCount,
    required this.providerName,
    required this.contextLimit,
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    required this.createdAt,
    required this.lastActiveAt,
  });

  final String title;
  final int messageCount;
  final String providerName;
  final String? contextLimit;
  final String? totalTokens;
  final String? inputTokens;
  final String? outputTokens;
  final String? cachedTokens;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;

  @override
  Widget build(BuildContext context) {
    final rows = <_ContextSummaryRow>[
      _ContextSummaryRow('会话名称', title),
      _ContextSummaryRow('消息数', '$messageCount'),
      _ContextSummaryRow('提供商', providerName),
      _ContextSummaryRow('上下文限制', contextLimit ?? '—'),
      _ContextSummaryRow('总 Token', totalTokens ?? '—'),
      _ContextSummaryRow('输入 Token', inputTokens ?? '—'),
      _ContextSummaryRow('输出 Token', outputTokens ?? '—'),
      _ContextSummaryRow('缓存 Token', cachedTokens ?? '—'),
      _ContextSummaryRow('创建时间', _formatContextDateTime(createdAt)),
      _ContextSummaryRow('最后活跃时间', _formatContextDateTime(lastActiveAt)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final row in rows) row.build(context)],
    );
  }
}

/// 概览区的单行键值对。
class _ContextSummaryRow {
  const _ContextSummaryRow(this.label, this.value);

  final String label;
  final String value;

  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: textStyles.caption.copyWith(
                color: colors.textSecondary.withValues(alpha: 0.72),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 原始消息列表：标题右侧筛选项；默认过滤工具等非主对话条目。
class _AgentContextRawMessageList extends StatelessWidget {
  const _AgentContextRawMessageList({
    required this.items,
    required this.filterNonChat,
    required this.expandedIds,
    required this.onToggle,
    required this.onFilterChanged,
  });

  final List<_ContextRawItem> items;
  final bool filterNonChat;
  final Set<String> expandedIds;
  final void Function(String messageId) onToggle;
  final ValueChanged<bool> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '原始消息',
                  style: textStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              IdeTab(
                key: const ValueKey('agent-context-raw-filter'),
                label: filterNonChat ? '仅对话' : '全部',
                selected: filterNonChat,
                trailingIcon: Icons.filter_list_rounded,
                semanticLabel: filterNonChat
                    ? '当前仅显示对话消息，点击显示全部'
                    : '当前显示全部消息，点击仅显示对话',
                onPressed: () => onFilterChanged(!filterNonChat),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space8),
            child: Text(
              filterNonChat ? '暂无对话消息' : '暂无原始消息',
              style: textStyles.bodySmall.copyWith(
                color: colors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          )
        else
          for (var index = 0; index < items.length; index += 1) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space4),
            _AgentContextRawMessageRow(
              item: items[index],
              expanded: expandedIds.contains(items[index].id),
              onToggle: () => onToggle(items[index].id),
            ),
          ],
      ],
    );
  }
}

/// 原始消息单行：ID + 类型 + 时间，展开后显示 raw 协议原文。
class _AgentContextRawMessageRow extends StatelessWidget {
  const _AgentContextRawMessageRow({
    required this.item,
    required this.expanded,
    required this.onToggle,
  });

  final _ContextRawItem item;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final hasRaw = item.raw.isNotEmpty;
    return IdeCollapsibleCard(
      headerKey: ValueKey<String>('agent-context-raw-${item.id}'),
      bodyKey: ValueKey<String>('agent-context-raw-body-${item.id}'),
      expanded: expanded,
      canExpand: hasRaw,
      onToggle: onToggle,
      hoverBackgroundColor: _agentHoverBackground(context),
      padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
      bodyPadding: const EdgeInsets.only(top: IdeSpacing.space8),
      semanticLabel: '原始消息',
      titleWidget: Row(
        children: [
          Expanded(
            child: Text(
              item.displayId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.codeSmall.copyWith(
                color: colors.textSecondary.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            item.kindLabel,
            style: textStyles.caption.copyWith(
              color: colors.accent.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            _extractRawTimestamp(item.raw),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.caption.copyWith(
              color: colors.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      body: hasRaw
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: _AgentHighlightedCodeBlock(
                  code: _prettyJson(item.raw),
                  language: 'json',
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: IdeSpacing.space4),
              child: Text('（无原始数据）', style: _agentMetaTextStyle(context)),
            ),
    );
  }
}

/// 上下文面板「原始消息」统一条目。
class _ContextRawItem {
  const _ContextRawItem({
    required this.id,
    required this.displayId,
    required this.kindLabel,
    required this.raw,
  });

  /// 展开态与 ValueKey 使用的稳定 id。
  final String id;

  /// 列表中展示的 id 文案。
  final String displayId;

  /// 类型标签（用户 / 助手 / 工具 / …）。
  final String kindLabel;

  final Map<String, Object?> raw;
}

/// 从时间线构建原始消息列表；[filterNonChat] 为 true 时仅保留主对话。
List<_ContextRawItem> _buildContextRawItems({
  required List<AgentTimelineEntry> timelineEntries,
  required bool filterNonChat,
}) {
  final items = <_ContextRawItem>[];
  for (final entry in timelineEntries) {
    switch (entry) {
      case AgentMessageTimelineEntry(:final message):
        if (filterNonChat && !_isMainConversationMessage(message)) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: message.id,
            displayId: message.id,
            kindLabel: _contextMessageKindLabel(message),
            raw: message.raw,
          ),
        );
      case AgentToolTimelineEntry(:final toolCall):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: toolCall.id,
            displayId: toolCall.id,
            kindLabel: _contextToolKindLabel(toolCall),
            raw: _toolCallRawMap(toolCall),
          ),
        );
      case AgentPermissionTimelineEntry(:final request):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: request.id,
            displayId: request.id,
            kindLabel: '审批',
            raw: request.raw.isNotEmpty
                ? request.raw
                : <String, Object?>{
                    'id': request.id,
                    'title': request.title,
                    'kind': request.kind.name,
                    'description': ?request.description,
                    'command': ?request.command,
                  },
          ),
        );
      case AgentPlanApprovalTimelineEntry(:final request):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: request.id,
            displayId: request.id,
            kindLabel: '计划审批',
            raw: request.raw,
          ),
        );
      case AgentHistoryEventTimelineEntry(:final event):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: event.id,
            displayId: event.id,
            kindLabel: _contextHistoryEventLabel(event),
            raw: event.raw.isNotEmpty
                ? event.raw
                : <String, Object?>{
                    'id': event.id,
                    'kind': event.kind.name,
                    'title': event.title,
                    'description': ?event.description,
                    'content': ?event.content,
                  },
          ),
        );
      case AgentTurnDiffTimelineEntry(:final turnId, :final diff, :final raw):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: 'turn-diff-$turnId',
            displayId: turnId,
            kindLabel: 'Diff',
            raw: raw.isNotEmpty
                ? raw
                : <String, Object?>{'turnId': turnId, 'diff': diff},
          ),
        );
    }
  }
  return items;
}

/// 主对话：用户/助手普通消息（排除 welcome、计划、系统）。
bool _isMainConversationMessage(AgentConversationMessage message) {
  if (message.id == 'welcome' ||
      message.id == AgentConversationTimelineStore.welcomeMessage.id) {
    return false;
  }
  if (message.isPlan) {
    return false;
  }
  return message.role == AgentMessageRole.user ||
      message.role == AgentMessageRole.agent;
}

String _contextMessageKindLabel(AgentConversationMessage message) {
  if (message.isPlan) {
    return '计划';
  }
  return switch (message.role) {
    AgentMessageRole.user => '用户',
    AgentMessageRole.agent => '助手',
    AgentMessageRole.system => '系统',
  };
}

String _contextToolKindLabel(AgentToolCall toolCall) {
  return switch (toolCall.kind) {
    AgentToolKind.think => '思考',
    AgentToolKind.read => '读取',
    AgentToolKind.edit => '编辑',
    AgentToolKind.delete => '删除',
    AgentToolKind.move => '移动',
    AgentToolKind.search => '搜索',
    AgentToolKind.execute => '执行',
    AgentToolKind.fetch => '拉取',
    AgentToolKind.other => '工具',
  };
}

String _contextHistoryEventLabel(AgentHistoryEventEntry event) {
  return switch (event.kind) {
    AgentHistoryEventKind.permission => '审批',
    AgentHistoryEventKind.warning => '警告',
    AgentHistoryEventKind.search => '搜索',
    AgentHistoryEventKind.system => '系统',
  };
}

Map<String, Object?> _toolCallRawMap(AgentToolCall toolCall) {
  if (toolCall.raw.isNotEmpty) {
    return toolCall.raw;
  }
  return <String, Object?>{
    'id': toolCall.id,
    'title': toolCall.displayTitle,
    'kind': toolCall.kind.name,
    'status': toolCall.status.name,
    'content': ?toolCall.content,
    if (toolCall.locations.isNotEmpty) 'locations': toolCall.locations,
    if (toolCall.rawInput.isNotEmpty) 'rawInput': toolCall.rawInput,
    if (toolCall.rawOutput.isNotEmpty) 'rawOutput': toolCall.rawOutput,
  };
}

/// 上下文面板内的日期时间格式化（yyyy-MM-dd HH:mm）；缺失时返回占位符。
String _formatContextDateTime(DateTime? dateTime) {
  if (dateTime == null) {
    return '—';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}-'
      '${two(dateTime.month)}-'
      '${two(dateTime.day)} '
      '${two(dateTime.hour)}:'
      '${two(dateTime.minute)}';
}

/// 从 raw payload 宽容提取消息时间；兼容记录级 timestamp、started/createdAt
/// 以及内嵌 payload 内的同名字段。缺失时返回占位符。
String _extractRawTimestamp(Map<String, Object?> raw) {
  for (final key in const <String>[
    'timestamp',
    'startedAt',
    'started_at',
    'completedAt',
    'completed_at',
    'createdAt',
    'created_at',
  ]) {
    final parsed = _rawToDateTime(raw[key]);
    if (parsed != null) {
      return _formatContextDateTime(parsed);
    }
  }
  // 部分协议把时间戳放在内嵌 payload 中。
  final payload = raw['payload'];
  if (payload is Map<String, Object?>) {
    for (final key in const <String>[
      'timestamp',
      'started_at',
      'completed_at',
    ]) {
      final parsed = _rawToDateTime(payload[key]);
      if (parsed != null) {
        return _formatContextDateTime(parsed);
      }
    }
  }
  return '—';
}

/// 把 raw 中的时间字段解析为本地 DateTime；兼容秒/毫秒整数与 ISO 字符串。
DateTime? _rawToDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    // 小于 10^12 视为秒级时间戳，统一换算到毫秒。
    final millis = value < 1000000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

/// 把 raw Map 序列化为带缩进的 JSON 字符串；失败时回退到 toString。
String _prettyJson(Map<String, Object?> raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(raw);
  } catch (_) {
    return raw.toString();
  }
}
