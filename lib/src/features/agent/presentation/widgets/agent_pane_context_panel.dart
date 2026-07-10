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
  /// 原始消息行展开态：按 messageId 记录，避免父级重建时丢失。
  final Set<String> _expandedRawMessageIds = <String>{};

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
                          messages: messages,
                          expandedIds: _expandedRawMessageIds,
                          onToggle: _toggleRawMessage,
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

/// 原始消息列表：展示每条消息的 ID、角色与时间，可展开查看 raw 原文。
class _AgentContextRawMessageList extends StatelessWidget {
  const _AgentContextRawMessageList({
    required this.messages,
    required this.expandedIds,
    required this.onToggle,
  });

  final List<AgentConversationMessage> messages;
  final Set<String> expandedIds;
  final void Function(String messageId) onToggle;

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
          child: Text(
            '原始消息',
            style: textStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        for (var index = 0; index < messages.length; index += 1) ...[
          if (index > 0) const SizedBox(height: IdeSpacing.space4),
          _AgentContextRawMessageRow(
            message: messages[index],
            expanded: expandedIds.contains(messages[index].id),
            onToggle: () => onToggle(messages[index].id),
          ),
        ],
      ],
    );
  }
}

/// 原始消息单行：ID + 角色 + 时间，展开后显示 raw 协议原文。
class _AgentContextRawMessageRow extends StatelessWidget {
  const _AgentContextRawMessageRow({
    required this.message,
    required this.expanded,
    required this.onToggle,
  });

  final AgentConversationMessage message;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final hasRaw = message.raw.isNotEmpty;
    return IdeCollapsibleCard(
      headerKey: ValueKey<String>('agent-context-raw-${message.id}'),
      bodyKey: ValueKey<String>('agent-context-raw-body-${message.id}'),
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
              message.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.codeSmall.copyWith(
                color: colors.textSecondary.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            _contextRoleLabel(message.role),
            style: textStyles.caption.copyWith(
              color: colors.accent.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            _extractRawTimestamp(message.raw),
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
                  code: _prettyJson(message.raw),
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

/// 消息角色转为中文标签。
String _contextRoleLabel(AgentMessageRole role) {
  return switch (role) {
    AgentMessageRole.user => '用户',
    AgentMessageRole.agent => '助手',
    AgentMessageRole.system => '系统',
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
