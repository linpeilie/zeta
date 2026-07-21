import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/features/ide/views/new_thread_provider_popover.dart';

/// 活动项目未选中 Thread 时显示的中栏首页。
class ProjectHomePage extends StatefulWidget {
  const ProjectHomePage({
    required this.projectPath,
    required this.threadState,
    required this.loadAvailableProviders,
    required this.onNewThread,
    required this.onSelectThread,
    required this.onRetryThreads,
    super.key,
  });

  final String projectPath;
  final ProjectThreadListState threadState;
  final Future<List<AgentProviderConfig>> Function() loadAvailableProviders;
  final ValueChanged<String> onNewThread;
  final ValueChanged<AgentThreadSummary> onSelectThread;
  final VoidCallback onRetryThreads;

  @override
  State<ProjectHomePage> createState() => _ProjectHomePageState();
}

class _ProjectHomePageState extends State<ProjectHomePage> {
  static const double _compactHeaderBreakpoint = 640;
  static const double _contentMaxWidth = 920;

  final GlobalKey _newThreadButtonKey = GlobalKey();
  IdePopoverHandle<AgentProviderConfig?>? _providerPopover;

  @override
  void dispose() {
    _providerPopover?.dismiss();
    _providerPopover = null;
    super.dispose();
  }

  void _toggleProviderPopover() {
    if (_providerPopover != null) {
      _dismissProviderPopover();
      return;
    }
    final anchorContext = _newThreadButtonKey.currentContext ?? context;
    final entry = showIdePopover<AgentProviderConfig?>(
      context: anchorContext,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, IdeSpacing.space4),
      margin: IdeSpacing.all8,
      builder: (context) => NewThreadProviderPopover(
        loadAvailableProviders: widget.loadAvailableProviders,
      ),
    );
    _providerPopover = entry;
    entry.future
        .then((provider) {
          if (!mounted || provider == null) {
            return;
          }
          widget.onNewThread(provider.id);
        })
        .whenComplete(() {
          if (mounted && identical(_providerPopover, entry)) {
            _providerPopover = null;
          }
        });
  }

  void _dismissProviderPopover() {
    final entry = _providerPopover;
    if (entry == null) {
      return;
    }
    _providerPopover = null;
    entry.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return ColoredBox(
      color: colors.canvasSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactHeaderBreakpoint;
          final horizontalPadding = compact
              ? IdeSpacing.space16
              : IdeSpacing.space24;
          return SingleChildScrollView(
            key: const ValueKey<String>('project-home-scroll-view'),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: IdeSpacing.space24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProjectHeader(context, compact: compact),
                    const SizedBox(height: IdeSpacing.space24),
                    _buildRecentThreads(context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProjectHeader(BuildContext context, {required bool compact}) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final projectName = fileName(widget.projectPath);
    final projectDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          projectName,
          key: const ValueKey<String>('project-home-name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textStyles.pageTitle,
        ),
        const SizedBox(height: IdeSpacing.space6),
        IdeTooltip(
          message: widget.projectPath,
          child: Text(
            widget.projectPath,
            key: const ValueKey<String>('project-home-path'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.codeSmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
    final newThreadButton = KeyedSubtree(
      key: _newThreadButtonKey,
      child: Semantics(
        button: true,
        label: '为 $projectName 新建 Thread',
        child: sf.PrimaryButton(
          key: const ValueKey<String>('project-home-new-thread-button'),
          onPressed: _toggleProviderPopover,
          size: sf.ButtonSize.small,
          leading: const Icon(Icons.add_comment_outlined, size: 16),
          child: const Text('新建 Thread'),
        ),
      ),
    );

    return PanelCard(
      key: const ValueKey<String>('project-home-header'),
      color: colors.paneSurface,
      child: Padding(
        padding: IdeSpacing.all20,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  projectDetails,
                  const SizedBox(height: IdeSpacing.space16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: newThreadButton,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: projectDetails),
                  const SizedBox(width: IdeSpacing.space20),
                  newThreadButton,
                ],
              ),
      ),
    );
  }

  Widget _buildRecentThreads(BuildContext context) {
    final state = widget.threadState;
    final threads = state.threads
        .take(projectThreadInitialLimit)
        .toList(growable: false);
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '近期会话',
                key: const ValueKey<String>('project-home-recent-title'),
                style: textStyles.sectionTitle,
              ),
            ),
            if (state.isLoadingInitial && threads.isNotEmpty)
              SizedBox(
                key: const ValueKey<String>('project-home-refreshing'),
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space12),
        if (state.isLoadingInitial && threads.isEmpty)
          _buildLoadingState(context)
        else if (state.errorMessage != null && threads.isEmpty)
          _buildErrorState(context)
        else if (threads.isEmpty)
          const IdeStatusCard(
            key: ValueKey<String>('project-home-empty-state'),
            tone: IdeStatusCardTone.neutral,
            title: '暂无近期会话',
            body: Text('创建一个 Thread 后，它会显示在这里。'),
          )
        else ...[
          if (state.errorMessage != null) _buildErrorState(context),
          for (final thread in threads) ...[
            _RecentThreadCard(
              key: ValueKey<String>('project-home-thread-${thread.id}'),
              thread: thread,
              onPressed: () => widget.onSelectThread(thread),
            ),
            const SizedBox(height: IdeSpacing.space8),
          ],
        ],
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PanelCard(
      key: const ValueKey<String>('project-home-loading-state'),
      color: colors.paneSurface,
      child: Padding(
        padding: IdeSpacing.all20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: IdeSpacing.space10),
            Flexible(
              child: Text(
                '正在加载近期会话…',
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeStatusCard(
      key: const ValueKey<String>('project-home-error-state'),
      tone: IdeStatusCardTone.error,
      title: '无法加载近期会话',
      body: Text(
        widget.threadState.errorMessage ?? '请稍后重试。',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
      ),
      footer: Align(
        alignment: Alignment.centerLeft,
        child: sf.OutlineButton(
          key: const ValueKey<String>('project-home-retry-button'),
          onPressed: widget.onRetryThreads,
          size: sf.ButtonSize.small,
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _RecentThreadCard extends StatelessWidget {
  const _RecentThreadCard({
    required this.thread,
    required this.onPressed,
    super.key,
  });

  final AgentThreadSummary thread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final statusLabel = _threadStatusLabel(thread);
    final lastActiveLabel = _relativeThreadTime(
      thread.lastActiveAt,
      DateTime.now(),
    );
    final preview = thread.preview.trim();

    return PanelCard(
      color: colors.paneSurface,
      borderRadius: IdeRadius.allMedium,
      child: PaneInteractiveSurface(
        onPressed: onPressed,
        semanticLabel: '打开会话 ${thread.displayName}',
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space16,
          vertical: IdeSpacing.space12,
        ),
        borderRadius: IdeRadius.allMedium,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final details = _buildDetails(
              context,
              statusLabel: statusLabel,
              lastActiveLabel: lastActiveLabel,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  _threadStatusIcon(thread),
                  size: 18,
                  color: _threadStatusColor(thread, colors),
                ),
                const SizedBox(width: IdeSpacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        thread.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.rowTitle,
                      ),
                      if (preview.isNotEmpty &&
                          preview != thread.displayName) ...[
                        const SizedBox(height: IdeSpacing.space4),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      if (compact) ...[
                        const SizedBox(height: IdeSpacing.space8),
                        details,
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: IdeSpacing.space16),
                  details,
                ],
                const SizedBox(width: IdeSpacing.space8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetails(
    BuildContext context, {
    required String? statusLabel,
    required String? lastActiveLabel,
  }) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Wrap(
      spacing: IdeSpacing.space8,
      runSpacing: IdeSpacing.space4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IdeChip(
          label: _providerShortLabel(thread.providerId),
          variant: IdeChipVariant.ghost,
        ),
        if (statusLabel != null)
          IdeChip(label: statusLabel, variant: IdeChipVariant.outline),
        if (lastActiveLabel != null)
          Text(
            lastActiveLabel,
            style: textStyles.meta.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }
}

String _providerShortLabel(String providerId) {
  final trimmed = providerId.trim();
  return switch (trimmed) {
    defaultAgentProviderId || 'codex' => 'Codex',
    grokAgentProviderId || 'grok' => 'Grok',
    cursorAgentProviderId || 'cursor' => 'Cursor',
    _ when trimmed.isEmpty => 'Agent',
    _ => trimmed.length <= 10 ? trimmed : trimmed.substring(0, 10),
  };
}

String? _threadStatusLabel(AgentThreadSummary thread) {
  if (thread.waitingOnApproval) {
    return '等待审批';
  }
  if (thread.waitingOnUserInput) {
    return '等待输入';
  }
  if (thread.isBusy) {
    return '执行中';
  }
  if (thread.status == AgentThreadRuntimeStatus.systemError) {
    return '系统错误';
  }
  return null;
}

IconData _threadStatusIcon(AgentThreadSummary thread) {
  if (thread.waitingOnApproval || thread.waitingOnUserInput) {
    return Icons.pending_actions_outlined;
  }
  return switch (thread.status) {
    AgentThreadRuntimeStatus.active => Icons.sync_rounded,
    AgentThreadRuntimeStatus.systemError => Icons.error_outline_rounded,
    AgentThreadRuntimeStatus.notLoaded => Icons.history_toggle_off_rounded,
    AgentThreadRuntimeStatus.idle => Icons.chat_bubble_outline_rounded,
    AgentThreadRuntimeStatus.unknown => Icons.help_outline_rounded,
  };
}

Color _threadStatusColor(AgentThreadSummary thread, IdeColors colors) {
  if (thread.waitingOnApproval || thread.waitingOnUserInput) {
    return colors.warning;
  }
  return switch (thread.status) {
    AgentThreadRuntimeStatus.active => colors.accent,
    AgentThreadRuntimeStatus.systemError => colors.error,
    AgentThreadRuntimeStatus.notLoaded ||
    AgentThreadRuntimeStatus.idle ||
    AgentThreadRuntimeStatus.unknown => colors.textSecondary,
  };
}

String? _relativeThreadTime(DateTime? value, DateTime now) {
  if (value == null) {
    return null;
  }
  final difference = now.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) {
    return '刚刚';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} 分钟前';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours} 小时前';
  }
  return '${difference.inDays} 天前';
}
