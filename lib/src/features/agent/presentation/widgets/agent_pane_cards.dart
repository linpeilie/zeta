part of '../agent_pane.dart';

/// 命令集折叠卡片。
///
/// 连续工具调用和搜索事件会先规约成命令集，在这里统一展示摘要与展开列表。
class _AgentCommandGroupCard extends StatelessWidget {
  const _AgentCommandGroupCard({required this.group, required this.viewModel});

  final AgentTimelineCommandGroup group;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return ListenableBuilder(
      listenable: viewModel.expansionStateListenable,
      builder: (context, _) {
        final expanded = viewModel.expansionState.isCommandGroupExpanded(
          group.id,
        );
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-command-group-header-${group.id}'),
          bodyKey: ValueKey<String>('agent-command-group-body-${group.id}'),
          expanded: expanded,
          onToggle: () => viewModel.toggleCommandGroup(group.id),
          titleWidget: Text(
            _commandGroupSummary(group),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _agentSummaryTextStyle(context),
          ),
          leading: Icon(
            Icons.segment_rounded,
            size: 14,
            color: colors.textTertiary.withValues(alpha: 0.65),
          ),
          bodyPadding: const EdgeInsets.only(
            top: IdeSpacing.space8,
            left: IdeSpacing.space20,
          ),
          hoverBackgroundColor: _agentHoverBackground(context),
          semanticLabel: '命令组',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < group.items.length; index++) ...[
                if (index > 0) const SizedBox(height: IdeSpacing.space8),
                _AgentCommandGroupItemRow(item: group.items[index]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AgentCommandGroupItemRow extends StatelessWidget {
  const _AgentCommandGroupItemRow({required this.item});

  final AgentTimelineCommandGroupItem item;

  @override
  Widget build(BuildContext context) {
    return Text(
      key: ValueKey<String>('agent-command-group-item-${item.id}'),
      _commandGroupItemTitle(item),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _agentItemTextStyle(context),
    );
  }
}

/// 展开命令组后同时显示事件类型和具体标题，避免 Grok 事件退化成重复的「操作」。
String _commandGroupItemTitle(AgentTimelineCommandGroupItem item) {
  final kindLabel = _toolKindLabel(item.kind);
  final title = item.title.trim();
  if (title.isEmpty || title == kindLabel || title.startsWith('$kindLabel ·')) {
    return title.isEmpty ? kindLabel : title;
  }
  return '$kindLabel · $title';
}

/// 文件编辑组折叠卡片。
///
/// 连续编辑操作会按文件拆分后显示在该组中，每个文件项支持独立展开详情。
class _AgentFileEditGroupCard extends StatefulWidget {
  const _AgentFileEditGroupCard({required this.group, required this.viewModel});

  final AgentTimelineFileEditGroup group;
  final AgentConversationViewModel viewModel;

  @override
  State<_AgentFileEditGroupCard> createState() =>
      _AgentFileEditGroupCardState();
}

class _AgentFileEditGroupCardState extends State<_AgentFileEditGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return IdeCollapsibleCard(
      headerKey: ValueKey<String>(
        'agent-file-edit-group-header-${widget.group.id}',
      ),
      bodyKey: ValueKey<String>(
        'agent-file-edit-group-body-${widget.group.id}',
      ),
      expanded: _expanded,
      onToggle: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      leading: Icon(
        Icons.edit_note_rounded,
        size: 14,
        color: colors.textTertiary.withValues(alpha: 0.65),
      ),
      titleWidget: Text.rich(
        key: ValueKey<String>(
          'agent-file-edit-group-summary-${widget.group.id}',
        ),
        _fileEditGroupSummarySpan(context, widget.group),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _agentSummaryTextStyle(context),
      ),
      bodyPadding: const EdgeInsets.only(
        top: IdeSpacing.space8,
        left: IdeSpacing.space20,
      ),
      hoverBackgroundColor: _agentHoverBackground(context),
      semanticLabel: '文件编辑组',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < widget.group.items.length; index++) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space8),
            _AgentFileEditItemRow(
              key: ValueKey<String>(
                'agent-file-edit-item-${widget.group.items[index].id}',
              ),
              item: widget.group.items[index],
              viewModel: widget.viewModel,
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentFileEditItemRow extends StatelessWidget {
  const _AgentFileEditItemRow({
    super.key,
    required this.item,
    required this.viewModel,
  });

  final AgentTimelineFileEditItem item;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel.expansionStateListenable,
      builder: (context, _) {
        final expanded = viewModel.expansionState.isFileEditItemExpanded(
          item.id,
        );
        final canExpand = item.hasDetails;
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-file-edit-item-row-${item.id}'),
          toggleKey: ValueKey<String>('agent-file-edit-item-toggle-${item.id}'),
          bodyKey: ValueKey<String>('agent-file-edit-item-details-${item.id}'),
          expanded: expanded,
          canExpand: canExpand,
          onToggle: canExpand
              ? () => viewModel.toggleFileEditItem(item.id)
              : () {},
          hoverBackgroundColor: _agentHoverBackground(context),
          padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
          bodyPadding: const EdgeInsets.only(
            top: IdeSpacing.space6,
            right: IdeSpacing.space20,
          ),
          semanticLabel: canExpand ? '查看文件编辑详情' : '文件编辑详情',
          titleWidget: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _agentItemTextStyle(context),
                ),
              ),
              if (item.addedLines != null || item.removedLines != null) ...[
                const SizedBox(width: IdeSpacing.space12),
                Text.rich(
                  key: ValueKey<String>(
                    'agent-file-edit-item-line-stats-${item.id}',
                  ),
                  _fileEditLineStatsSpan(context, item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          body: item.details == null ? null : _AgentDiffDetails(item: item),
        );
      },
    );
  }
}

class _AgentDiffDetails extends StatefulWidget {
  const _AgentDiffDetails({required this.item});

  final AgentTimelineFileEditItem item;

  @override
  State<_AgentDiffDetails> createState() => _AgentDiffDetailsState();
}

class _AgentDiffDetailsState extends State<_AgentDiffDetails> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final details = widget.item.details!;
    final shouldCollapse = _shouldPreviewCodeBlock(
      details,
      maxLines: _diffPreviewLineCount,
    );
    final code = !_showAll && shouldCollapse
        ? _previewCodeBlock(details, maxLines: _diffPreviewLineCount)
        : details;
    final hiddenLines = shouldCollapse
        ? _codeBlockLineCount(details) - _diffPreviewLineCount
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AgentHighlightedCodeBlock(code: code, language: 'diff'),
        if (shouldCollapse)
          Padding(
            padding: const EdgeInsets.only(top: IdeSpacing.space6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showAll ? '已显示完整差异' : '已省略 $hiddenLines 行',
                  style: _agentMetaTextStyle(context),
                ),
                const SizedBox(width: IdeSpacing.space8),
                sf.GhostButton(
                  key: ValueKey<String>(
                    'agent-file-edit-item-expand-all-${widget.item.id}',
                  ),
                  onPressed: () {
                    setState(() {
                      _showAll = !_showAll;
                    });
                  },
                  size: sf.ButtonSize.small,
                  child: Text(
                    _showAll ? '收起差异' : '展开全部',
                    style: textStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AgentHighlightedCodeBlock extends StatefulWidget {
  const _AgentHighlightedCodeBlock({
    required this.code,
    required this.language,
  });

  final String code;
  final String language;

  @override
  State<_AgentHighlightedCodeBlock> createState() =>
      _AgentHighlightedCodeBlockState();
}

class _AgentHighlightedCodeBlockState
    extends State<_AgentHighlightedCodeBlock> {
  Widget? _cachedHighlight;
  String? _cachedCode;
  String? _cachedLanguage;
  Object? _cachedThemeSignature;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final highlightTheme = _agentHighlightTheme(context);
    final codeTextStyle = _agentCodeTextStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final themeSignature = _AgentHighlightThemeSignature(
      brightness: sf.Theme.of(context).brightness,
      highlightTheme: highlightTheme,
      codeTextStyle: codeTextStyle,
      scaledCodeFontSize: textScaler.scale(codeTextStyle.fontSize ?? 1),
    );
    if (_cachedHighlight == null ||
        _cachedCode != widget.code ||
        _cachedLanguage != widget.language ||
        _cachedThemeSignature != themeSignature) {
      _cachedHighlight = HighlightView(
        widget.code,
        language: widget.language,
        theme: highlightTheme,
        padding: IdeSpacing.cardPadding,
        textStyle: codeTextStyle,
      );
      _cachedCode = widget.code;
      _cachedLanguage = widget.language;
      _cachedThemeSignature = themeSignature;
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: _agentCodeBlockDecoration(colors),
        child: ClipRRect(
          borderRadius: IdeRadius.allSmall,
          // 相同 Widget identity 会跳过 HighlightView.build，避免 resize 重复 parse。
          child: _cachedHighlight!,
        ),
      ),
    );
  }
}

@immutable
class _AgentHighlightThemeSignature {
  const _AgentHighlightThemeSignature({
    required this.brightness,
    required this.highlightTheme,
    required this.codeTextStyle,
    required this.scaledCodeFontSize,
  });

  final Brightness brightness;
  final Map<String, TextStyle> highlightTheme;
  final TextStyle codeTextStyle;
  final double scaledCodeFontSize;

  @override
  bool operator ==(Object other) {
    return other is _AgentHighlightThemeSignature &&
        other.brightness == brightness &&
        other.codeTextStyle == codeTextStyle &&
        other.scaledCodeFontSize == scaledCodeFontSize &&
        mapEquals(other.highlightTheme, highlightTheme);
  }

  @override
  int get hashCode => Object.hash(
    brightness,
    codeTextStyle,
    scaledCodeFontSize,
    Object.hashAllUnordered(
      highlightTheme.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}

/// 工具调用卡片。
///
/// 命令输出、文件变更、计划等 provider 事件都会规约到这个组件展示。
class _AgentToolCallCard extends StatelessWidget {
  const _AgentToolCallCard({required this.toolCall, required this.viewModel});

  final AgentToolCall toolCall;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final needsElapsedTick =
        toolCall.duration == null &&
        toolCall.startedAt != null &&
        toolCall.isActiveStatus;
    final listenables = <Listenable>[viewModel.expansionStateListenable];
    if (needsElapsedTick) {
      listenables.add(viewModel.elapsedClockListenable);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final canExpand =
            toolCall.content != null && toolCall.content!.isNotEmpty;
        final expanded = viewModel.expansionState.isToolCallExpanded(
          toolCall.id,
        );
        final elapsedLabel = _toolElapsedLabel(
          viewModel,
          toolCall,
          viewModel.elapsedNow,
        );
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-tool-header-${toolCall.id}'),
          bodyKey: ValueKey<String>('agent-tool-body-${toolCall.id}'),
          expanded: expanded,
          canExpand: canExpand,
          onToggle: canExpand
              ? () => viewModel.toggleToolCall(toolCall.id)
              : () {},
          titleWidget: Row(
            children: [
              Expanded(
                child: Text(
                  _toolCardTitle(toolCall),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _agentItemTextStyle(context),
                ),
              ),
              if (elapsedLabel != null) ...[
                const SizedBox(width: IdeSpacing.space8),
                Text(
                  elapsedLabel,
                  key: ValueKey<String>('agent-tool-elapsed-${toolCall.id}'),
                  style: textStyles.caption.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          leading: toolCall.isActiveStatus
              ? const IdeBusySpinner(
                  size: 12,
                  strokeWidth: 1.8,
                  semanticsLabel: 'Tool running',
                )
              : Icon(
                  _toolIcon(toolCall.kind),
                  size: 14,
                  color: colors.textTertiary,
                ),
          margin: const EdgeInsets.only(bottom: IdeSpacing.space10),
          bodyPadding: const EdgeInsets.only(top: IdeSpacing.space8),
          hoverBackgroundColor: _agentHoverBackground(context),
          semanticLabel: '工具调用',
          body: toolCall.content == null
              ? null
              : SelectableText(
                  toolCall.content!,
                  style: _agentCodeTextStyle(context).copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
        );
      },
    );
  }
}

/// 思考/命令卡标题：进行中时用更明确的相位文案。
String _toolCardTitle(AgentToolCall toolCall) {
  // displayTitle 会把 call-... 合成成「类型 · 路径/命令」。
  final resolved = toolCall.displayTitle.trim();
  if (!toolCall.isActiveStatus) {
    return resolved;
  }
  if (toolCall.kind == AgentToolKind.think) {
    return '思考中';
  }
  if (resolved.isEmpty) {
    return '执行中';
  }
  // 已是「执行中」前缀则不再重复。
  if (resolved.startsWith('执行中') || resolved.startsWith('思考中')) {
    return resolved;
  }
  return '执行中 · $resolved';
}

/// 计划文档在对话流中的统一卡片。
///
/// 本地执行交接与 Provider 计划审批共用同一形态：标题栏 + 计划正文全文 +
/// 底部迷你 composer（修改 / 模型 / 执行 / 放弃）。
///
/// 正文**不套内部滚动视图**：卡片本身就是时间线条目，高度交给虚拟列表测量，
/// 再嵌一层滚动会同时破坏测量与阅读体验。
///
/// 修改输入的控制器由 [AgentPlanRevisionDraftStore] 托管：卡片会随虚拟列表
/// 回收，State 自持控制器会丢草稿。
class _AgentPlanDocumentCard extends StatelessWidget {
  const _AgentPlanDocumentCard({
    required this.requestId,
    required this.title,
    required this.subtitle,
    required this.markdown,
    required this.revisionController,
    required this.revisionFocusNode,
    required this.viewModel,
    required this.onRevise,
    required this.onExecute,
    required this.onAbandon,
    this.todos = const <AgentPlanEntry>[],
    this.phases = const <AgentPlanApprovalPhase>[],
    super.key,
  });

  /// 计划请求的稳定 id；用于按钮 key 与草稿寻址。
  final String requestId;
  final String title;

  /// 权限边界说明；必须点明「执行不等于预授权」（G5）。
  final String subtitle;
  final String markdown;
  final TextEditingController revisionController;
  final FocusNode revisionFocusNode;
  final AgentConversationViewModel viewModel;

  /// 提交修改意见；仅在输入非空时被调用。
  final ValueChanged<String> onRevise;
  final VoidCallback onExecute;
  final VoidCallback onAbandon;
  final List<AgentPlanEntry> todos;
  final List<AgentPlanApprovalPhase> phases;

  void _submitRevision() {
    final text = revisionController.text.trim();
    if (text.isEmpty) {
      return;
    }
    onRevise(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: IdeSpacing.space12),
        child: PanelCard(
          key: ValueKey<String>('agent-plan-document-card-$requestId'),
          color: colors.surfaceElevated,
          showBorder: true,
          borderColor: colors.border,
          borderRadius: IdeRadius.allMedium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colors, textStyles),
              Container(height: 1, color: colors.borderSubtle),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  IdeSpacing.space12,
                  IdeSpacing.space10,
                  IdeSpacing.space12,
                  IdeSpacing.space10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (markdown.trim().isNotEmpty)
                      _AgentRawMarkdownBody(data: markdown),
                    if (todos.isNotEmpty) ...[
                      const SizedBox(height: IdeSpacing.space8),
                      _AgentPlanTodoList(title: '步骤', todos: todos),
                    ],
                    for (final phase in phases) ...[
                      const SizedBox(height: IdeSpacing.space8),
                      _AgentPlanTodoList(title: phase.name, todos: phase.todos),
                    ],
                  ],
                ),
              ),
              Container(height: 1, color: colors.borderSubtle),
              _buildActionBar(context, colors, textStyles),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(IdeColors colors, IdeTextStyles textStyles) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space12,
        IdeSpacing.space10,
        IdeSpacing.space12,
        IdeSpacing.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.checklist_rounded,
            size: 16,
            color: colors.textSecondary.withValues(alpha: 0.78),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: IdeSpacing.space4),
                  Text(
                    subtitle,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部迷你 composer：输入框 + 「修改 / 模型 / 执行 / 放弃」。
  Widget _buildActionBar(
    BuildContext context,
    IdeColors colors,
    IdeTextStyles textStyles,
  ) {
    final inputTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textPrimary,
    );
    final lineHeight =
        (inputTextStyle.fontSize ?? 12) * (inputTextStyle.height ?? 1.35);
    final minHeight = lineHeight * 2;
    final maxHeight = lineHeight * 8;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space12,
        IdeSpacing.space10,
        IdeSpacing.space12,
        IdeSpacing.space10,
      ),
      child: ListenableBuilder(
        listenable: revisionController,
        builder: (context, _) {
          final hasRevision = revisionController.text.trim().isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 无独立描边/底色，仅依赖计划卡外框，避免输入区双重边框。
              KeyedSubtree(
                key: ValueKey<String>('agent-plan-revision-input-$requestId'),
                child: sf.ComponentTheme<sf.FocusOutlineTheme>(
                  data: const sf.FocusOutlineTheme(
                    border: Border.fromBorderSide(BorderSide.none),
                  ),
                  child: sf.TextArea(
                    controller: revisionController,
                    focusNode: revisionFocusNode,
                    placeholder: Text(
                      '补充或修改计划…',
                      style: textStyles.bodyMedium.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    style: inputTextStyle,
                    padding: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      border: const Border.fromBorderSide(BorderSide.none),
                      borderRadius: BorderRadius.zero,
                    ),
                    initialHeight: _textAreaHeight(
                      revisionController.text,
                      lineHeight,
                      minHeight,
                      maxHeight,
                      minLines: 2,
                      maxLines: 8,
                    ),
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                  ),
                ),
              ),
              const SizedBox(height: IdeSpacing.space8),
              Row(
                children: [
                  IdeButton(
                    key: ValueKey<String>('agent-plan-revise-$requestId'),
                    label: '修改',
                    variant: IdeButtonVariant.outline,
                    // 空输入没有可发送的修改意见，保持禁用而非静默无响应。
                    onPressed: hasRevision ? _submitRevision : null,
                  ),
                  const Spacer(),
                  // 模型可在卡内直接切换；跟随 composer 状态刷新标签。
                  ListenableBuilder(
                    listenable: viewModel.composerStateListenable,
                    builder: (context, _) {
                      final selector = _buildModelSelector();
                      if (selector == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(
                          right: IdeSpacing.space6,
                        ),
                        child: selector,
                      );
                    },
                  ),
                  IdeButton(
                    key: ValueKey<String>('agent-plan-execute-$requestId'),
                    label: '执行',
                    variant: IdeButtonVariant.primary,
                    leadingIcon: Icons.play_arrow_rounded,
                    onPressed: onExecute,
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                  IdeButton(
                    key: ValueKey<String>('agent-plan-abandon-$requestId'),
                    label: '放弃',
                    variant: IdeButtonVariant.ghost,
                    onPressed: onAbandon,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 与主 Composer 共用同一个模型配置入口与回调集合。
  Widget? _buildModelSelector() {
    final state = viewModel.composerState;
    if (!state.showModelSelection) {
      return null;
    }
    final modelConfigState = state.modelConfigState;
    if (modelConfigState.models.isEmpty && !modelConfigState.isRefreshing) {
      return null;
    }
    return _AgentModelConfig(
      state: modelConfigState,
      onSelectModel: viewModel.selectModel,
      onSelectReasoningEffort: viewModel.selectReasoningEffort,
      onSelectFastEnabled: viewModel.selectFastEnabled,
      onResolveCompatibility: viewModel.resolveModelCompatibilityConflict,
      onRetrySave: viewModel.retryModelConfigurationSave,
      onPopoverClosed: viewModel.clearModelConfigurationTransientState,
    );
  }
}

class _AgentPlanTodoList extends StatelessWidget {
  const _AgentPlanTodoList({required this.title, required this.todos});

  final String title;
  final List<AgentPlanEntry> todos;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.bodySmall.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: IdeSpacing.space4),
        for (final todo in todos)
          Padding(
            padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _planTodoIcon(todo.status),
                  size: 14,
                  color: todo.status == 'completed'
                      ? colors.success
                      : colors.textTertiary,
                ),
                const SizedBox(width: IdeSpacing.space6),
                Expanded(
                  child: Text(
                    todo.content,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

IconData _planTodoIcon(String? status) {
  return switch (status) {
    'completed' => Icons.check_circle_outline_rounded,
    'in_progress' => Icons.radio_button_checked_rounded,
    'cancelled' => Icons.cancel_outlined,
    _ => Icons.radio_button_unchecked_rounded,
  };
}

/// 权限审批卡片。
///
/// 两段式布局：
/// 1. 标题栏单行：左侧协议类型（如「命令」），右侧操作按钮，禁止换行；
/// 2. 资源区：语义标题 + 命令代码块及 cwd / 文件等详情。
class _AgentPermissionCard extends StatefulWidget {
  const _AgentPermissionCard({
    required this.request,
    required this.onRespond,
    this.autoReview,
    this.onApproveGuardian,
  });

  final AgentPermissionRequest request;
  final void Function({
    required bool approved,
    bool cancelTurn,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment,
  })
  onRespond;
  final AgentAutoApprovalReviewEvent? autoReview;
  final VoidCallback? onApproveGuardian;

  @override
  State<_AgentPermissionCard> createState() => _AgentPermissionCardState();
}

class _AgentPermissionCardState extends State<_AgentPermissionCard> {
  AgentPermissionRequest get request => widget.request;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final hasAmendment = request.proposedExecpolicyAmendment.isNotEmpty;
    final isCommand = request.kind == AgentPermissionKind.commandExecution;
    final displayTitle = _permissionDisplayTitle(request);
    final command = request.command?.trim();
    final kindLabel = _permissionKindLabel(request.kind);

    return Semantics(
      container: true,
      label: '权限请求：$kindLabel · $displayTitle',
      child: PanelCard(
        key: ValueKey<String>('agent-permission-card-${request.id}'),
        color: colors.warning.withValues(alpha: 0.08),
        showBorder: true,
        borderColor: colors.warning.withValues(alpha: 0.35),
        borderRadius: IdeRadius.allMedium,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IdeSpacing.space12,
            IdeSpacing.space8,
            IdeSpacing.space8,
            IdeSpacing.space10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // —— 标题栏：类型 | 操作，固定单行 ——
              SizedBox(
                height: 28,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _permissionKindIcon(request.kind),
                      size: 15,
                      color: colors.warning,
                    ),
                    const SizedBox(width: IdeSpacing.space6),
                    Text(
                      kindLabel,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.bodyMedium.copyWith(
                        color: colors.warning,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: IdeSpacing.space8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _buildHeaderActions(
                              colors: colors,
                              isCommand: isCommand,
                              hasAmendment: hasAmendment,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IdeSpacing.space8),
              // —— 资源区：语义标题 + 命令代码块 ——
              Text(
                displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (command != null && command.isNotEmpty) ...[
                const SizedBox(height: IdeSpacing.space8),
                _AgentPermissionCommandBlock(
                  key: ValueKey<String>(
                    'agent-permission-command-${request.id}',
                  ),
                  command: command,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 标题栏右侧操作：始终单行，窄宽度时由外层横向滚动承接。
  List<Widget> _buildHeaderActions({
    required IdeColors colors,
    required bool isCommand,
    required bool hasAmendment,
  }) {
    final actions = <Widget>[
      sf.GhostButton(
        key: ValueKey('agent-permission-cancel-${request.id}'),
        onPressed: () => widget.onRespond(approved: false, cancelTurn: true),
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
        child: const Text('取消回合'),
      ),
      const SizedBox(width: IdeSpacing.space4),
      sf.OutlineButton(
        key: ValueKey('agent-permission-deny-${request.id}'),
        onPressed: () => widget.onRespond(
          approved: false,
          commandDecision: isCommand
              ? AgentCommandApprovalDecisionKind.decline
              : null,
        ),
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
        child: Text('拒绝', style: TextStyle(color: colors.error)),
      ),
      if (isCommand) ...[
        const SizedBox(width: IdeSpacing.space4),
        sf.OutlineButton(
          key: ValueKey('agent-permission-session-${request.id}'),
          onPressed: () => widget.onRespond(
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.acceptForSession,
          ),
          size: sf.ButtonSize.small,
          density: sf.ButtonDensity.dense,
          child: const Text('本会话允许'),
        ),
        if (hasAmendment) ...[
          const SizedBox(width: IdeSpacing.space4),
          sf.OutlineButton(
            key: ValueKey('agent-permission-always-${request.id}'),
            onPressed: () => widget.onRespond(
              approved: true,
              commandDecision: AgentCommandApprovalDecisionKind
                  .acceptWithExecpolicyAmendment,
              execpolicyAmendment: request.proposedExecpolicyAmendment,
            ),
            size: sf.ButtonSize.small,
            density: sf.ButtonDensity.dense,
            child: const Text('始终允许'),
          ),
        ],
      ],
      if (widget.autoReview?.status == 'denied' &&
          widget.onApproveGuardian != null) ...[
        const SizedBox(width: IdeSpacing.space4),
        sf.OutlineButton(
          key: ValueKey('agent-permission-guardian-override-${request.id}'),
          onPressed: widget.onApproveGuardian,
          size: sf.ButtonSize.small,
          density: sf.ButtonDensity.dense,
          child: const Text('覆盖守护'),
        ),
      ],
      const SizedBox(width: IdeSpacing.space4),
      sf.PrimaryButton(
        key: ValueKey('agent-permission-approve-${request.id}'),
        onPressed: () => widget.onRespond(
          approved: true,
          commandDecision: isCommand
              ? AgentCommandApprovalDecisionKind.accept
              : null,
        ),
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
        leading: const Icon(Icons.check_rounded, size: 14),
        child: const Text('允许'),
      ),
    ];
    return actions;
  }
}

/// 权限类型语义标题：命令已单独展示时，避免把长命令再塞进标题。
String _permissionDisplayTitle(AgentPermissionRequest request) {
  final title = request.title.trim();
  final command = request.command?.trim();
  if (command != null &&
      command.isNotEmpty &&
      (title.isEmpty || title == command)) {
    return _permissionKindTitle(request.kind);
  }
  if (title.isNotEmpty) {
    return title;
  }
  return _permissionKindTitle(request.kind);
}

String _permissionKindTitle(AgentPermissionKind kind) {
  return switch (kind) {
    AgentPermissionKind.commandExecution => '请求执行命令',
    AgentPermissionKind.fileChange => '请求应用文件变更',
    AgentPermissionKind.permissions => '请求授予权限',
    AgentPermissionKind.other => '请求确认',
  };
}

String _permissionKindLabel(AgentPermissionKind kind) {
  return switch (kind) {
    AgentPermissionKind.commandExecution => '命令',
    AgentPermissionKind.fileChange => '文件',
    AgentPermissionKind.permissions => '权限',
    AgentPermissionKind.other => '确认',
  };
}

IconData _permissionKindIcon(AgentPermissionKind kind) {
  return switch (kind) {
    AgentPermissionKind.commandExecution => Icons.terminal_rounded,
    AgentPermissionKind.fileChange => Icons.difference_outlined,
    AgentPermissionKind.permissions => Icons.verified_user_outlined,
    AgentPermissionKind.other => Icons.shield_outlined,
  };
}

class _AgentPermissionCommandBlock extends StatelessWidget {
  const _AgentPermissionCommandBlock({required this.command, super.key});

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return DecoratedBox(
      decoration: _agentCodeBlockDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space10,
          vertical: IdeSpacing.space8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\$',
              style: _agentCodeTextStyle(context).copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: IdeSpacing.space8),
            Expanded(
              child: Text(
                command,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _agentCodeTextStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 独立用户提问卡；只表达结构化 answers 或跳过，不复用 approve/deny。
///
/// 同一请求一次只展示一道题。单选自动推进，多选和自由文本显式确认，
/// 所有答案在最后一题完成时一次性回写 Provider。
class _AgentQuestionCard extends StatefulWidget {
  const _AgentQuestionCard({required this.request, required this.onRespond});

  final AgentQuestionRequest request;
  final ValueChanged<Map<String, List<String>>> onRespond;

  @override
  State<_AgentQuestionCard> createState() => _AgentQuestionCardState();
}

class _AgentQuestionCardState extends State<_AgentQuestionCard>
    with SingleTickerProviderStateMixin {
  static const double _compactHeaderBreakpoint = 520;

  final Map<String, List<String>> _answers = <String, List<String>>{};
  final Map<String, TextEditingController> _otherControllers =
      <String, TextEditingController>{};
  final Set<String> _skippedQuestionIds = <String>{};
  final Set<String> _expandedOtherQuestionIds = <String>{};

  late final AnimationController _enterController;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;

  int _currentQuestionIndex = 0;
  int _transitionDirection = 1;
  bool _enterStarted = false;
  bool _advancing = false;
  bool _responded = false;

  AgentQuestionRequest get request => widget.request;

  AgentUserInputQaPair? get _currentQuestion {
    if (request.questions.isEmpty) {
      return null;
    }
    return request.questions[_currentQuestionIndex];
  }

  @override
  void initState() {
    super.initState();
    for (final question in request.questions) {
      if (question.isOther || question.resolvedOptions.isEmpty) {
        _otherControllers[question.questionId] = TextEditingController();
        if (question.resolvedOptions.isEmpty) {
          _expandedOtherQuestionIds.add(question.questionId);
        }
      }
    }
    _enterController = AnimationController(
      vsync: this,
      duration: IdeMotion.durationSlow,
    );
    final enterCurve = CurvedAnimation(
      parent: _enterController,
      curve: IdeMotion.curvePopup,
    );
    _enterFade = enterCurve;
    _enterSlide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(enterCurve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enterStarted) {
      return;
    }
    _enterStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enterController.value = 1;
    } else {
      _enterController.forward();
    }
  }

  @override
  void dispose() {
    _enterController.dispose();
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final question = _currentQuestion;
    final questionPage = question == null
        ? _buildEmptyRequest(context)
        : KeyedSubtree(
            key: ValueKey<String>(
              'agent-question-page-${request.id}-${question.questionId}',
            ),
            child: _buildQuestionPage(context, question),
          );
    final switchingPage = question == null || reduceMotion
        ? questionPage
        : TweenAnimationBuilder<double>(
            key: ValueKey<String>(
              'agent-question-transition-${request.id}-${question.questionId}',
            ),
            tween: Tween<double>(begin: 0, end: 1),
            duration: IdeMotion.durationNormal,
            curve: IdeMotion.curvePopup,
            child: questionPage,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(
                    _transitionDirection * IdeSpacing.space24 * (1 - value),
                    0,
                  ),
                  child: child,
                ),
              );
            },
          );
    final cardContent = reduceMotion
        ? switchingPage
        : AnimatedSize(
            duration: IdeMotion.durationNormal,
            curve: IdeMotion.curveDefault,
            alignment: Alignment.topCenter,
            child: switchingPage,
          );

    return FadeTransition(
      opacity: _enterFade,
      child: SlideTransition(
        position: _enterSlide,
        child: Semantics(
          container: true,
          label: 'Agent 提问',
          child: PanelCard(
            key: ValueKey<String>('agent-question-card-${request.id}'),
            color: colors.panel,
            borderColor: colors.border,
            borderRadius: IdeRadius.allMedium,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                IdeSpacing.space16,
                IdeSpacing.space12,
                IdeSpacing.space12,
                IdeSpacing.space12,
              ),
              child: cardContent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyRequest(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                request.title,
                style: textStyles.titleLarge.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            _AgentQuestionToolbarButton(
              buttonKey: ValueKey<String>('agent-question-close-${request.id}'),
              icon: Icons.close_rounded,
              semanticLabel: '关闭提问',
              onPressed: _closeRequest,
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space8),
        Text(
          '该请求没有可回答的问题。',
          style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildQuestionPage(
    BuildContext context,
    AgentUserInputQaPair question,
  ) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final options = question.resolvedOptions;
    final selected = _answers[question.questionId] ?? const <String>[];
    final otherController = _otherControllers[question.questionId];
    final isLastQuestion =
        _currentQuestionIndex == request.questions.length - 1;
    final canConfirm =
        selected.isNotEmpty ||
        (otherController?.text.trim().isNotEmpty ?? false);
    final showManualConfirm =
        question.allowMultiple || options.isEmpty || question.isOther;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _compactHeaderBreakpoint;
            final title = Text(
              question.question,
              maxLines: compact ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: textStyles.titleLarge.copyWith(
                color: colors.textPrimary,
                height: 1.3,
              ),
            );
            final toolbar = _buildQuestionToolbar();
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  const SizedBox(height: IdeSpacing.space6),
                  Align(alignment: Alignment.centerRight, child: toolbar),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: IdeSpacing.space12),
                toolbar,
              ],
            );
          },
        ),
        ..._buildQuestionSupportingText(context, question),
        if (options.isNotEmpty) ...[
          const SizedBox(height: IdeSpacing.space12),
          for (var index = 0; index < options.length; index++) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space4),
            _AgentQuestionOptionRow(
              key: ValueKey<String>(
                'agent-question-${request.id}-${question.questionId}-${options[index].id}',
              ),
              index: index,
              option: options[index],
              selected: selected.contains(options[index].id),
              allowMultiple: question.allowMultiple,
              enabled: !_advancing,
              onPressed: () => _selectOption(question, options[index].id),
            ),
          ],
        ],
        if (otherController != null) ...[
          SizedBox(
            height: options.isEmpty ? IdeSpacing.space12 : IdeSpacing.space6,
          ),
          _AgentQuestionOtherField(
            fieldKey: ValueKey<String>(
              'agent-question-other-${request.id}-${question.questionId}',
            ),
            triggerKey: ValueKey<String>(
              'agent-question-other-trigger-${request.id}-${question.questionId}',
            ),
            submitKey: ValueKey<String>(
              'agent-question-other-submit-${request.id}-${question.questionId}',
            ),
            controller: otherController,
            isSecret: question.isSecret,
            hasOptions: options.isNotEmpty,
            expanded: _expandedOtherQuestionIds.contains(question.questionId),
            enabled: !_advancing,
            submitLabel: isLastQuestion ? '提交答案' : '确认并进入下一题',
            onExpand: () => _expandOther(question),
            onChanged: (value) => _setOtherAnswer(question.questionId, value),
            onSubmitted: (_) => _confirmTextAnswer(question),
          ),
        ],
        const SizedBox(height: IdeSpacing.space12),
        Row(
          children: [
            const Spacer(),
            sf.GhostButton(
              key: ValueKey<String>(
                'agent-question-skip-${request.id}-${question.questionId}',
              ),
              onPressed: _advancing ? null : _skipCurrentQuestion,
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.dense,
              child: const Text('跳过'),
            ),
            if (showManualConfirm && options.isNotEmpty) ...[
              const SizedBox(width: IdeSpacing.space6),
              sf.PrimaryButton(
                key: ValueKey<String>(
                  'agent-question-submit-${request.id}-${question.questionId}',
                ),
                onPressed: canConfirm && !_advancing
                    ? _confirmCurrentQuestion
                    : null,
                size: sf.ButtonSize.small,
                density: sf.ButtonDensity.dense,
                trailing: Icon(
                  isLastQuestion
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  size: 14,
                ),
                child: Text(isLastQuestion ? '提交' : '下一步'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  List<Widget> _buildQuestionSupportingText(
    BuildContext context,
    AgentUserInputQaPair question,
  ) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final questionText = question.question.trim();
    final header = question.header?.trim();
    final requestTitle = request.title.trim();
    final description = request.description?.trim();
    final labels = <String>[
      if (header != null && header.isNotEmpty && header != questionText) header,
      if (requestTitle.isNotEmpty &&
          requestTitle != questionText &&
          requestTitle != header)
        requestTitle,
    ];

    return <Widget>[
      if (labels.isNotEmpty) ...[
        const SizedBox(height: IdeSpacing.space4),
        Text(
          labels.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.caption.copyWith(color: colors.textTertiary),
        ),
      ],
      if (description != null &&
          description.isNotEmpty &&
          description != questionText) ...[
        const SizedBox(height: IdeSpacing.space4),
        Text(
          description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: textStyles.bodySmall.copyWith(
            color: colors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
      if (question.allowMultiple) ...[
        const SizedBox(height: IdeSpacing.space4),
        Text(
          '可选择多个选项',
          style: textStyles.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    ];
  }

  Widget _buildQuestionToolbar() {
    final questionCount = request.questions.length;
    final canGoBack = _currentQuestionIndex > 0 && !_advancing;
    final canGoForward =
        _currentQuestionIndex < questionCount - 1 &&
        _isQuestionProcessed(request.questions[_currentQuestionIndex]) &&
        !_advancing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AgentQuestionToolbarButton(
          buttonKey: ValueKey<String>(
            'agent-question-previous-${request.id}-${_currentQuestion!.questionId}',
          ),
          icon: Icons.chevron_left_rounded,
          semanticLabel: '上一题',
          onPressed: canGoBack
              ? () => _goToQuestion(_currentQuestionIndex - 1)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space4),
          child: Text(
            '${_currentQuestionIndex + 1} of $questionCount',
            key: ValueKey<String>(
              'agent-question-progress-${request.id}-${_currentQuestion!.questionId}',
            ),
            style: IdeTextStyles.of(context).bodySmall.copyWith(
              color: IdeColors.of(context).textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _AgentQuestionToolbarButton(
          buttonKey: ValueKey<String>(
            'agent-question-next-${request.id}-${_currentQuestion!.questionId}',
          ),
          icon: Icons.chevron_right_rounded,
          semanticLabel: '下一题',
          onPressed: canGoForward
              ? () => _goToQuestion(_currentQuestionIndex + 1)
              : null,
        ),
        const SizedBox(width: IdeSpacing.space2),
        _AgentQuestionToolbarButton(
          buttonKey: ValueKey<String>(
            'agent-question-close-${request.id}-${_currentQuestion!.questionId}',
          ),
          icon: Icons.close_rounded,
          semanticLabel: '关闭提问',
          onPressed: _advancing ? null : _closeRequest,
        ),
      ],
    );
  }

  bool _isQuestionProcessed(AgentUserInputQaPair question) {
    return (_answers[question.questionId]?.isNotEmpty ?? false) ||
        _skippedQuestionIds.contains(question.questionId);
  }

  void _selectOption(AgentUserInputQaPair question, String optionId) {
    if (_advancing) {
      return;
    }
    if (question.allowMultiple) {
      _toggleMultipleOption(question, optionId);
      return;
    }

    setState(() {
      _answers[question.questionId] = <String>[optionId];
      _skippedQuestionIds.remove(question.questionId);
      _expandedOtherQuestionIds.remove(question.questionId);
      _otherControllers[question.questionId]?.clear();
      _advancing = true;
    });
    _advanceAfterSelection(question.questionId);
  }

  Future<void> _advanceAfterSelection(String questionId) async {
    if (!MediaQuery.disableAnimationsOf(context)) {
      await Future<void>.delayed(IdeMotion.durationFast);
    }
    if (!mounted || _responded || _currentQuestion?.questionId != questionId) {
      return;
    }
    _advanceOrSubmit();
  }

  void _toggleMultipleOption(AgentUserInputQaPair question, String optionId) {
    final optionIds = question.resolvedOptions
        .map((option) => option.id)
        .toSet();
    setState(() {
      final current = (_answers[question.questionId] ?? const <String>[])
          .where(optionIds.contains)
          .toList();
      _otherControllers[question.questionId]?.clear();
      _expandedOtherQuestionIds.remove(question.questionId);
      if (current.contains(optionId)) {
        current.remove(optionId);
      } else {
        current.add(optionId);
      }
      if (current.isEmpty) {
        _answers.remove(question.questionId);
      } else {
        _answers[question.questionId] = current;
        _skippedQuestionIds.remove(question.questionId);
      }
    });
  }

  void _expandOther(AgentUserInputQaPair question) {
    if (_advancing) {
      return;
    }
    setState(() {
      _expandedOtherQuestionIds.add(question.questionId);
    });
  }

  void _setOtherAnswer(String questionId, String value) {
    final trimmed = value.trim();
    setState(() {
      if (trimmed.isEmpty) {
        _answers.remove(questionId);
        return;
      }
      // 自由文本与结构化选项互斥，避免把显示文案误写为选项 id。
      _answers[questionId] = <String>[trimmed];
      _skippedQuestionIds.remove(questionId);
    });
  }

  void _confirmTextAnswer(AgentUserInputQaPair question) {
    final answer = _otherControllers[question.questionId]?.text.trim();
    if (_advancing || answer == null || answer.isEmpty) {
      return;
    }
    setState(() {
      _answers[question.questionId] = <String>[answer];
      _skippedQuestionIds.remove(question.questionId);
      _advancing = true;
    });
    _advanceOrSubmit();
  }

  void _confirmCurrentQuestion() {
    final question = _currentQuestion;
    if (question == null || !_isQuestionProcessed(question) || _advancing) {
      return;
    }
    setState(() {
      _advancing = true;
    });
    _advanceOrSubmit();
  }

  void _skipCurrentQuestion() {
    final question = _currentQuestion;
    if (question == null || _advancing) {
      _closeRequest();
      return;
    }
    setState(() {
      _answers.remove(question.questionId);
      _otherControllers[question.questionId]?.clear();
      _expandedOtherQuestionIds.remove(question.questionId);
      _skippedQuestionIds.add(question.questionId);
      _advancing = true;
    });
    _advanceOrSubmit();
  }

  void _advanceOrSubmit() {
    if (_currentQuestionIndex >= request.questions.length - 1) {
      _submitAnswers();
      return;
    }
    _goToQuestion(_currentQuestionIndex + 1);
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= request.questions.length) {
      return;
    }
    setState(() {
      _transitionDirection = index >= _currentQuestionIndex ? 1 : -1;
      _currentQuestionIndex = index;
      _advancing = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : IdeMotion.durationNormal,
          curve: IdeMotion.curveDefault,
        ),
      );
    });
  }

  void _closeRequest() {
    _respond(const <String, List<String>>{});
  }

  void _submitAnswers() {
    final answers = <String, List<String>>{};
    for (final question in request.questions) {
      if (_skippedQuestionIds.contains(question.questionId)) {
        continue;
      }
      final answer = _answers[question.questionId];
      if (answer != null && answer.isNotEmpty) {
        answers[question.questionId] = List<String>.unmodifiable(answer);
      }
    }
    _respond(Map<String, List<String>>.unmodifiable(answers));
  }

  void _respond(Map<String, List<String>> answers) {
    if (_responded) {
      return;
    }
    _responded = true;
    widget.onRespond(answers);
  }
}

/// 顶部题目导航按钮。
class _AgentQuestionToolbarButton extends StatelessWidget {
  const _AgentQuestionToolbarButton({
    required this.buttonKey,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: semanticLabel,
      child: sf.GhostButton(
        key: buttonKey,
        onPressed: onPressed,
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
        child: Icon(icon, size: 16, semanticLabel: semanticLabel),
      ),
    );
  }
}

/// 提问选项行：编号、主副文案和方向提示组成的紧凑列表项。
class _AgentQuestionOptionRow extends StatelessWidget {
  const _AgentQuestionOptionRow({
    required this.index,
    required this.option,
    required this.selected,
    required this.allowMultiple,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final int index;
  final AgentUserInputOption option;
  final bool selected;
  final bool allowMultiple;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final description = option.description?.trim();

    return PaneInteractiveSurface(
      onPressed: onPressed,
      selected: selected,
      enabled: enabled,
      button: true,
      semanticLabel:
          '${index + 1}，${option.label}'
          '${selected ? '，已选择' : ''}'
          '${description == null || description.isEmpty ? '' : '，$description'}',
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space10,
        vertical: IdeSpacing.space8,
      ),
      borderRadius: IdeRadius.allMedium,
      borderColor: colors.borderSubtle.withValues(alpha: 0),
      selectedBorderColor: colors.accent.withValues(alpha: 0.55),
      hoverBackgroundColor: colors.hoverSurface,
      pressedBackgroundColor: colors.pressedSurface,
      selectedBackgroundColor: colors.selectedSurface,
      selectedHoverBackgroundColor: colors.selectedHoverSurface,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : IdeMotion.durationFast,
            curve: IdeMotion.curveDefault,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 序号徽章是实心圆片，两态都取不透明表面档；选中态靠更亮一档
              // 加 accent 描边区分，不能混用半透明的交互态 token。
              color: selected ? colors.surfaceElevated : colors.surface,
              borderRadius: IdeRadius.pill,
              border: Border.all(
                color: selected ? colors.accent : colors.border,
              ),
            ),
            child: Text(
              '${index + 1}',
              style: textStyles.bodySmall.copyWith(
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space10),
          Expanded(
            child: Wrap(
              spacing: IdeSpacing.space8,
              runSpacing: IdeSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  option.label,
                  style: textStyles.rowTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (description != null && description.isNotEmpty)
                  Text(
                    description,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : IdeMotion.durationFast,
            child: Icon(
              allowMultiple && selected
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded,
              key: ValueKey<bool>(allowMultiple && selected),
              size: 17,
              color: selected ? colors.accent : colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 自由文本入口；有结构化选项时先显示一条次级“其他”列表行。
class _AgentQuestionOtherField extends StatelessWidget {
  const _AgentQuestionOtherField({
    required this.fieldKey,
    required this.triggerKey,
    required this.submitKey,
    required this.controller,
    required this.isSecret,
    required this.hasOptions,
    required this.expanded,
    required this.enabled,
    required this.submitLabel,
    required this.onExpand,
    required this.onChanged,
    required this.onSubmitted,
  });

  final Key fieldKey;
  final Key triggerKey;
  final Key submitKey;
  final TextEditingController controller;
  final bool isSecret;
  final bool hasOptions;
  final bool expanded;
  final bool enabled;
  final String submitLabel;
  final VoidCallback onExpand;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = expanded
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: sf.TextField(
                  key: fieldKey,
                  controller: controller,
                  autofocus: hasOptions,
                  enabled: enabled,
                  placeholder: Text(
                    '输入你的解决方案…',
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  obscureText: isSecret,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              const SizedBox(width: IdeSpacing.space6),
              Tooltip(
                message: submitLabel,
                child: sf.OutlineButton(
                  key: submitKey,
                  onPressed: enabled && controller.text.trim().isNotEmpty
                      ? () => onSubmitted(controller.text)
                      : null,
                  size: sf.ButtonSize.small,
                  density: sf.ButtonDensity.dense,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    semanticLabel: submitLabel,
                  ),
                ),
              ),
            ],
          )
        : PaneInteractiveSurface(
            key: triggerKey,
            onPressed: onExpand,
            enabled: enabled,
            button: true,
            semanticLabel: '其他，输入自定义解决方案',
            padding: const EdgeInsets.symmetric(
              horizontal: IdeSpacing.space10,
              vertical: IdeSpacing.space8,
            ),
            borderRadius: IdeRadius.allMedium,
            borderColor: colors.borderSubtle.withValues(alpha: 0),
            hoverBackgroundColor: colors.hoverSurface,
            pressedBackgroundColor: colors.pressedSurface,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: IdeRadius.pill,
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: IdeSpacing.space10),
                Expanded(
                  child: Text(
                    '其他，输入自定义解决方案',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.rowTitle.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
    if (reduceMotion) {
      return content;
    }
    return AnimatedSize(
      duration: IdeMotion.durationNormal,
      curve: IdeMotion.curveDefault,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}

/// 只读历史事件卡片。
class _AgentHistoryEventCard extends StatelessWidget {
  const _AgentHistoryEventCard({required this.event});

  final AgentHistoryEventEntry event;

  @override
  Widget build(BuildContext context) {
    if (event.qaPairs != null && event.qaPairs!.isNotEmpty) {
      return _AgentUserInputQaList(
        title: event.title,
        description: event.description,
        qaPairs: event.qaPairs!,
      );
    }

    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final accent = _historyEventAccent(event.kind, colors);

    return IdeStatusCard(
      key: ValueKey<String>('agent-history-event-${event.id}'),
      tone: _historyEventTone(event.kind),
      title: event.title,
      leading: Icon(_historyEventIcon(event.kind), size: 16, color: accent),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (event.description != null)
            Text(
              event.description!,
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          if (event.content != null)
            Padding(
              padding: EdgeInsets.only(
                top: event.description == null ? 0 : IdeSpacing.space8,
              ),
              child: Text(
                event.content!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: _agentCodeTextStyle(
                  context,
                ).copyWith(color: colors.textSecondary.withValues(alpha: 0.78)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 用户输入问答列表（历史只读）。
///
/// 与实时提问卡视觉对齐：扁平紧凑；问题一行、回答一行；
/// 回答未回填时展示占位符。整体弱化以突出 Agent 正文。
class _AgentUserInputQaList extends StatelessWidget {
  const _AgentUserInputQaList({
    required this.title,
    required this.description,
    required this.qaPairs,
  });

  final String title;
  final String? description;
  final List<AgentUserInputQaPair> qaPairs;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final desc = description?.trim();
    return IdeStatusCard(
      tone: IdeStatusCardTone.info,
      title: title,
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space10,
        IdeSpacing.space8,
        IdeSpacing.space10,
        IdeSpacing.space8,
      ),
      leading: Icon(Icons.help_outline_rounded, size: 15, color: colors.info),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (desc != null && desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
              child: Text(
                desc,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          for (var index = 0; index < qaPairs.length; index++) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space8),
            _AgentUserInputQaRow(
              pair: qaPairs[index],
              index: index,
              showIndex: qaPairs.length > 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentUserInputQaRow extends StatelessWidget {
  const _AgentUserInputQaRow({
    required this.pair,
    required this.index,
    required this.showIndex,
  });

  final AgentUserInputQaPair pair;
  final int index;
  final bool showIndex;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final answerText = pair.answers.isEmpty ? '—' : pair.answers.join('、');
    final header = pair.header?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null && header.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
            child: Text(
              header,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showIndex) ...[
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: colors.info.withValues(alpha: 0.12),
                  borderRadius: IdeRadius.allSmall,
                ),
                child: Text(
                  '${index + 1}',
                  // 固定 16x16 徽标内的序号：保持 UI 字体，跟随界面字号而非
                  // 代码字号，避免用户调大代码字号时撑破固定尺寸容器。
                  style: textStyles.caption.copyWith(
                    color: colors.info,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: IdeSpacing.space6),
            ],
            Expanded(
              child: Text(
                pair.question,
                style: textStyles.bodyMedium.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: IdeSpacing.space4,
            left: showIndex ? IdeSpacing.space20 + IdeSpacing.space2 : 0,
          ),
          child: Text(
            answerText,
            style: textStyles.bodySmall.copyWith(
              color: pair.answers.isEmpty
                  ? colors.textTertiary
                  : colors.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
