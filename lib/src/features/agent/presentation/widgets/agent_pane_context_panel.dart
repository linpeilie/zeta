part of '../agent_pane.dart';

/// 上下文详情面板的固定宽度。
const double _agentContextPanelWidth = 360;

/// 元数据区字段名列宽。
///
/// 比通用的 [IdeMetrics.keyValueLabelWidth] 更窄：这里的字段名走 `caption`
/// （10px）而不是 `titleSmall`（12px），最长的「最后活跃时间」/「Context limit」
/// 在 76px 内排得下，同时把省下的横向空间还给等宽的值列。固定宽度是这一块的
/// 关键——所有行的值从同一条竖线起排，纵向扫视才能一眼比对。
const double _agentContextKeyColumnWidth = 76;

/// Agent 面板右侧的上下文详情面板。
///
/// 由 thread 详情头栏「上下文」菜单触发，展示会话元信息（名称、会话 ID、
/// 消息数、提供商、上下文限制、token 占用、创建/活跃时间）与原始消息列表。
/// 原始消息列表展示消息 ID、角色与时间，点击可展开查看 raw 协议原文。
/// 面板正文包在 [SelectionArea] 中，支持拖选文本与系统复制菜单。
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
    return ValueListenableBuilder<AgentConversationTurnState?>(
      valueListenable: viewModel.liveTurnListenable,
      builder: (context, liveTurnState, _) {
        // 上下文面板只组合已有 typed slice；live binding 改变时重绑稳定 turn
        // notifier，避免重新引入完整 ViewModel ChangeNotifier。
        return ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            viewModel.headerStateListenable,
            viewModel.historyStateListenable,
            viewModel.threadSnapshotListenable,
            viewModel.providerController,
            ?liveTurnState,
          ]),
          builder: (context, _) {
            final colors = IdeColors.of(context);
            final usage = viewModel.currentThreadTokenUsage;
            final messages = viewModel.messages;
            final rawItems = _buildContextRawItems(
              timelineEntries: viewModel.timelineEntries,
              filterNonChat: _filterNonChatMessages,
              catalog: viewModel.textCatalog,
              l10n: context.l10n,
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
                  // SelectionArea 覆盖概览与原始消息区，支持拖选 / 右键复制；
                  // 关闭按钮留在区外，避免与选择手势争用。
                  Expanded(
                    child: SelectionArea(
                      key: const ValueKey('agent-context-panel-selection'),
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
                                sessionId: viewModel.sessionId,
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
                              // 元数据区与原始消息之间不画线：靠一整段留白
                              // 把两个功能区分开，面板整体保持无框线。
                              const SizedBox(height: IdeSpacing.space32),
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
                  ),
                ],
              ),
            );
          },
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
///
/// 刻意不画底部分割线：面板已经有左侧边框与自身底色，横贯左右的线只会把
/// 标题从内容上「切」下来。标题与正文之间的层级由字重和留白表达。
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
      child: Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 15,
            color: colors.textSecondary,
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            context.l10n.agentContext,
            style: textStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IdeTooltip(
            message: context.l10n.agentClose,
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

/// 上下文概览信息卡：会话名称、会话 ID、消息数、提供商、token 与时间等键值对。
class _AgentContextSummaryCard extends StatelessWidget {
  const _AgentContextSummaryCard({
    required this.title,
    required this.sessionId,
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
  final String? sessionId;
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
    final l10n = context.l10n;
    final rows = <_ContextSummaryRow>[
      _ContextSummaryRow(l10n.agentSessionName, title),
      _ContextSummaryRow(l10n.agentSessionId, sessionId ?? '—'),
      _ContextSummaryRow(l10n.agentMessageCount, '$messageCount'),
      _ContextSummaryRow(l10n.agentProvider, providerName),
      _ContextSummaryRow(l10n.agentContextLimit, contextLimit ?? '—'),
      _ContextSummaryRow(l10n.agentTotalTokens, totalTokens ?? '—'),
      _ContextSummaryRow(l10n.agentInputTokens, inputTokens ?? '—'),
      _ContextSummaryRow(l10n.agentOutputTokens, outputTokens ?? '—'),
      _ContextSummaryRow(l10n.agentCachedTokens, cachedTokens ?? '—'),
      _ContextSummaryRow(
        l10n.agentCreatedAt,
        _formatContextDateTime(createdAt),
      ),
      _ContextSummaryRow(
        l10n.agentLastActive,
        _formatContextDateTime(lastActiveAt),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final row in rows) row.build(context)],
    );
  }
}

/// 概览区的单行键值对。
///
/// 排版分工按「仪表盘」来定：字段名走 UI 字体的次级浅灰小字，值一律走等宽
/// 字体的主色 + 等宽数字——面板里所有值都是可复制的机器数据（会话 ID、
/// Token 计数、时间戳），等宽让它们逐位对齐，也和字段名一眼分开。
/// 行高压到 [IdeSpacing.space2]，让十余行元数据读起来是一块密集数据，
/// 而不是十余个段落。
class _ContextSummaryRow {
  const _ContextSummaryRow(this.label, this.value);

  final String label;
  final String value;

  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
      child: Row(
        // 值可能折行，用首行基线对齐字段名，避免两列文字上下错开半个字。
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: _agentContextKeyColumnWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.caption.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textStyles.codeSmall.copyWith(
                color: colors.textPrimary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
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
                  context.l10n.agentRawMessages,
                  style: textStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _AgentContextRawFilterButton(
                filterNonChat: filterNonChat,
                onChanged: onFilterChanged,
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space8),
            child: Text(
              filterNonChat
                  ? context.l10n.agentNoChatMessages
                  : context.l10n.agentNoRawMessages,
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

/// 「原始消息」区的过滤控件：在「仅对话」与「全部」之间切换。
///
/// 刻意不用 [IdeTab]：那一档的选中态是换底色加 `bodySmall` 加粗标签，会和左边
/// 的区块标题抢主次。这里按**次级操作**来定型——`caption` 字号、次级色文字、
/// 极轻的灰底加 [IdeRadius.small]（6px）圆角、无边框，只在 hover / 按下时
/// 加深底色告诉用户它可点。
class _AgentContextRawFilterButton extends StatelessWidget {
  const _AgentContextRawFilterButton({
    required this.filterNonChat,
    required this.onChanged,
  });

  final bool filterNonChat;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PaneInteractiveSurface(
      key: const ValueKey('agent-context-raw-filter'),
      onPressed: () => onChanged(!filterNonChat),
      selected: filterNonChat,
      semanticLabel: filterNonChat
          ? context.l10n.agentShowChatOnly
          : context.l10n.agentShowAllMessages,
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space8,
        vertical: IdeSpacing.space4,
      ),
      borderRadius: IdeRadius.allSmall,
      backgroundColor: colors.border.withValues(alpha: 0.16),
      // 选中态（默认的「仅对话」）不另加高亮：当前档位已经写在标签上，
      // 再上一层底色只会让这个次级控件重新抢眼。
      selectedBackgroundColor: colors.border.withValues(alpha: 0.16),
      hoverBackgroundColor: colors.border.withValues(alpha: 0.28),
      selectedHoverBackgroundColor: colors.border.withValues(alpha: 0.28),
      pressedBackgroundColor: colors.border.withValues(alpha: 0.36),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            filterNonChat ? context.l10n.agentChatOnly : context.l10n.agentAll,
            style: textStyles.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: IdeSpacing.space4),
          Icon(Icons.filter_list_rounded, size: 12, color: colors.textTertiary),
        ],
      ),
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
    final rawText = hasRaw ? _prettyJson(item.raw) : '';
    return IdeCollapsibleCard(
      headerKey: ValueKey<String>('agent-context-raw-${item.id}'),
      bodyKey: ValueKey<String>('agent-context-raw-body-${item.id}'),
      expanded: expanded,
      canExpand: hasRaw,
      onToggle: onToggle,
      hoverBackgroundColor: _agentHoverBackground(context),
      padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
      bodyPadding: const EdgeInsets.only(top: IdeSpacing.space8),
      semanticLabel: context.l10n.agentRawMessages,
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
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    button: true,
                    label: context.l10n.agentCopyOriginal,
                    child: IdeTooltip(
                      message: context.l10n.agentCopyOriginal,
                      child: sf.IconButton.ghost(
                        key: ValueKey<String>(
                          'agent-context-raw-copy-${item.id}',
                        ),
                        onPressed: () => _copyContextRaw(context, rawText),
                        size: sf.ButtonSize.small,
                        density: sf.ButtonDensity.iconDense,
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: _AgentHighlightedCodeBlock(
                      code: rawText,
                      language: 'json',
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.only(top: IdeSpacing.space4),
              child: Text(
                context.l10n.agentNoRawPayload,
                style: _agentMetaTextStyle(context),
              ),
            ),
    );
  }
}

/// 复制展开态原文；内容只写入系统剪贴板，不进入 Zeta 持久化或诊断日志。
Future<void> _copyContextRaw(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    showIdeToast(
      context,
      message: context.l10n.agentCopiedOriginal,
      location: sf.ToastLocation.bottomLeft,
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
  required AgentUiTextCatalog catalog,
  required AppLocalizations l10n,
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
            kindLabel: _contextMessageKindLabel(message, l10n),
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
            kindLabel: _contextToolKindLabel(toolCall, l10n),
            raw: _toolCallContextMap(toolCall, catalog),
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
            kindLabel: l10n.agentKindApproval,
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
      case AgentQuestionTimelineEntry(:final request):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: request.id,
            displayId: request.id,
            kindLabel: l10n.agentKindQuestion,
            raw: request.raw.isNotEmpty
                ? request.raw
                : <String, Object?>{
                    'id': request.id,
                    'title': request.title,
                    'description': ?request.description,
                    'questions': request.questions
                        .map(
                          (question) => <String, Object?>{
                            'id': question.questionId,
                            'question': question.question,
                          },
                        )
                        .toList(growable: false),
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
            kindLabel: l10n.agentKindPlanApproval,
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
            kindLabel: _contextHistoryEventLabel(event, l10n),
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
      case AgentTurnFileChangesTimelineEntry(:final turnId, :final snapshot):
        if (filterNonChat) {
          continue;
        }
        items.add(
          _ContextRawItem(
            id: entry.id,
            displayId: turnId,
            kindLabel: l10n.agentKindFileChange,
            raw: <String, Object?>{
              'turnId': turnId,
              'fileChanges': _fileChangeSnapshotContextMap(snapshot),
            },
          ),
        );
    }
  }
  return items;
}

/// 主对话：用户/助手普通消息（排除计划、系统）。
bool _isMainConversationMessage(AgentConversationMessage message) {
  if (message.isPlan) {
    return false;
  }
  return message.role == AgentMessageRole.user ||
      message.role == AgentMessageRole.agent;
}

String _contextMessageKindLabel(
  AgentConversationMessage message,
  AppLocalizations l10n,
) {
  if (message.isPlan) {
    return l10n.contextRolePlan;
  }
  return switch (message.role) {
    AgentMessageRole.user => l10n.contextRoleUser,
    AgentMessageRole.agent => l10n.contextRoleAssistant,
    AgentMessageRole.system => l10n.contextRoleSystem,
  };
}

String _contextToolKindLabel(AgentToolCall toolCall, AppLocalizations l10n) {
  return toolCall.kind.localizedLabel(l10n);
}

String _contextHistoryEventLabel(
  AgentHistoryEventEntry event,
  AppLocalizations l10n,
) {
  return switch (event.kind) {
    AgentHistoryEventKind.permission => l10n.contextEventPermission,
    AgentHistoryEventKind.warning => l10n.contextEventWarning,
    AgentHistoryEventKind.search => l10n.agentToolSearch,
    AgentHistoryEventKind.system => l10n.contextRoleSystem,
  };
}

Map<String, Object?> _toolCallContextMap(
  AgentToolCall toolCall,
  AgentUiTextCatalog catalog,
) {
  final fileChanges = toolCall.fileChanges;
  if (fileChanges != null) {
    return <String, Object?>{
      'id': toolCall.id,
      'title': toolCall.displayTitle(catalog),
      'kind': toolCall.kind.name,
      'status': toolCall.status.name,
      'fileChanges': _fileChangeSnapshotContextMap(fileChanges),
    };
  }
  // 编辑工具没有 typed snapshot 时只展示中立元数据，不再退回 raw/wire payload
  // 猜文件路径或差异正文。其他工具仍保留原有 raw 诊断能力。
  if (toolCall.kind == AgentToolKind.edit) {
    return <String, Object?>{
      'id': toolCall.id,
      'title': toolCall.displayTitle(catalog),
      'kind': toolCall.kind.name,
      'status': toolCall.status.name,
    };
  }
  if (toolCall.raw.isNotEmpty) {
    return toolCall.raw;
  }
  return <String, Object?>{
    'id': toolCall.id,
    'title': toolCall.displayTitle(catalog),
    'kind': toolCall.kind.name,
    'status': toolCall.status.name,
    'content': ?toolCall.content,
    if (toolCall.locations.isNotEmpty) 'locations': toolCall.locations,
    if (toolCall.rawInput.isNotEmpty) 'rawInput': toolCall.rawInput,
    if (toolCall.rawOutput.isNotEmpty) 'rawOutput': toolCall.rawOutput,
  };
}

Map<String, Object?> _fileChangeSnapshotContextMap(
  AgentFileChangeSnapshot snapshot,
) {
  return <String, Object?>{
    'revision': snapshot.revision,
    'replayability': snapshot.replayability.name,
    'changes': snapshot.changes
        .map(_fileChangeContextMap)
        .toList(growable: false),
  };
}

Map<String, Object?> _fileChangeContextMap(AgentFileChange change) {
  return <String, Object?>{
    'id': change.id,
    'path': change.path,
    'destinationPath': ?change.destinationPath,
    'kind': change.kind.name,
    'evidence': ?switch (change.evidence) {
      null => null,
      AgentTextReplacementEvidence(
        :final oldText,
        :final newText,
        :final replaceAll,
      ) =>
        <String, Object?>{
          'type': 'textReplacement',
          'before': oldText,
          'after': newText,
          'replaceAll': ?replaceAll,
        },
      AgentWrittenContentEvidence(:final content) => <String, Object?>{
        'type': 'writtenContent',
        'writtenContent': content,
      },
      AgentUnifiedPatchEvidence(:final patch) => <String, Object?>{
        'type': 'unifiedPatch',
        'unifiedPatch': patch,
      },
    },
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
