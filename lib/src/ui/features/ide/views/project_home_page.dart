import 'package:flutter/material.dart';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
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
  static const double _compactBreakpoint = 640;
  static const double _contentMaxWidth = 760;

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
          final compact = constraints.maxWidth < _compactBreakpoint;
          final horizontalPadding = compact
              ? IdeSpacing.space16
              : IdeSpacing.space24;
          return SingleChildScrollView(
            key: const ValueKey<String>('project-home-scroll-view'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: IdeSpacing.space24,
                  ),
                  child: SizedBox(
                    width: _contentMaxWidth,
                    child: Column(
                      key: const ValueKey<String>(
                        'project-home-centered-content',
                      ),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildProjectHeader(context),
                        const SizedBox(height: IdeSpacing.space32),
                        _buildRecentThreads(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProjectHeader(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final projectName = fileName(widget.projectPath);

    return ColoredBox(
      key: const ValueKey<String>('project-home-header'),
      color: colors.canvasSurface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projectName,
                  key: const ValueKey<String>('project-home-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
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
                    textAlign: TextAlign.start,
                    style: textStyles.codeSmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: IdeSpacing.space20),
          KeyedSubtree(
            key: _newThreadButtonKey,
            child: _FlatActionButton(
              key: const ValueKey<String>('project-home-new-thread-button'),
              label: '新建会话',
              semanticLabel: '为 $projectName 新建会话',
              icon: Icons.add_comment_outlined,
              onPressed: _toggleProviderPopover,
            ),
          ),
        ],
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
                textAlign: TextAlign.start,
                style: textStyles.sectionTitle,
              ),
            ),
            if (state.isLoadingInitial && threads.isNotEmpty)
              IdeBusySpinner(
                key: const ValueKey<String>('project-home-refreshing'),
                size: 16,
                color: colors.accent,
              ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space12),
        if (state.isLoadingInitial && threads.isEmpty)
          _buildLoadingState(context)
        else if (state.errorMessage != null && threads.isEmpty)
          _buildErrorState(context)
        else if (threads.isEmpty)
          const _FlatStateMessage(
            key: ValueKey<String>('project-home-empty-state'),
            icon: Icons.forum_outlined,
            title: '暂无近期会话',
            body: '创建一个 Thread 后，它会显示在这里。',
          )
        else ...[
          if (state.errorMessage != null) ...[
            _buildErrorState(context),
            const SizedBox(height: IdeSpacing.space8),
          ],
          for (final thread in threads) ...[
            _RecentThreadRow(
              key: ValueKey<String>('project-home-thread-${thread.id}'),
              thread: thread,
              isZetaLiveRunning: state.isThreadRunning(thread.id),
              onPressed: () => widget.onSelectThread(thread),
            ),
            const SizedBox(height: IdeSpacing.space2),
          ],
        ],
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      key: const ValueKey<String>('project-home-loading-state'),
      padding: IdeSpacing.all20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          IdeBusySpinner(size: 18, color: colors.accent),
          const SizedBox(width: IdeSpacing.space10),
          Flexible(
            child: Text(
              '正在加载近期会话…',
              textAlign: TextAlign.start,
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return _FlatStateMessage(
      key: const ValueKey<String>('project-home-error-state'),
      icon: Icons.error_outline_rounded,
      tone: _FlatStateTone.error,
      title: '无法加载近期会话',
      body: widget.threadState.errorMessage ?? '请稍后重试。',
      action: _FlatActionButton(
        key: const ValueKey<String>('project-home-retry-button'),
        label: '重试',
        semanticLabel: '重试加载近期会话',
        icon: Icons.refresh_rounded,
        onPressed: widget.onRetryThreads,
      ),
    );
  }
}

class _RecentThreadRow extends StatelessWidget {
  const _RecentThreadRow({
    required this.thread,
    required this.isZetaLiveRunning,
    required this.onPressed,
    super.key,
  });

  final AgentThreadSummary thread;
  final bool isZetaLiveRunning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final statusLabel = _threadStatusLabel(
      thread,
      isZetaLiveRunning: isZetaLiveRunning,
    );
    final lastActiveLabel = _relativeThreadTime(
      thread.lastActiveAt,
      DateTime.now(),
    );
    final preview = thread.preview.trim();

    return PaneInteractiveSurface(
      onPressed: onPressed,
      semanticLabel: '打开会话 ${thread.displayName}',
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space16,
        vertical: IdeSpacing.space12,
      ),
      borderRadius: IdeRadius.allSmall,
      backgroundColor: colors.canvasSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final metadata = _buildMetadata(
            context,
            statusLabel: statusLabel,
            lastActiveLabel: lastActiveLabel,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AgentProviderIcon(
                providerId: thread.providerId,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: IdeSpacing.space12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: textStyles.rowTitle,
                    ),
                    if (preview.isNotEmpty &&
                        preview != thread.displayName) ...[
                      const SizedBox(height: IdeSpacing.space4),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (compact) ...[
                      const SizedBox(height: IdeSpacing.space6),
                      metadata,
                    ],
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: IdeSpacing.space16),
                metadata,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetadata(
    BuildContext context, {
    required String? statusLabel,
    required String? lastActiveLabel,
  }) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final labels = <({String text, Color color})>[
      if (statusLabel != null)
        (
          text: statusLabel,
          color: _threadStatusColor(
            thread,
            colors,
            isZetaLiveRunning: isZetaLiveRunning,
          ),
        ),
      if (lastActiveLabel != null)
        (text: lastActiveLabel, color: colors.textTertiary),
    ];

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: IdeSpacing.space6,
      runSpacing: IdeSpacing.space4,
      children: [
        for (var index = 0; index < labels.length; index += 1) ...[
          if (index > 0)
            Text(
              '·',
              style: textStyles.meta.copyWith(color: colors.textTertiary),
            ),
          Text(
            labels[index].text,
            textAlign: TextAlign.start,
            style: textStyles.meta.copyWith(color: labels[index].color),
          ),
        ],
      ],
    );
  }
}

class _FlatActionButton extends StatelessWidget {
  const _FlatActionButton({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PaneInteractiveSurface(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      borderRadius: IdeRadius.allSmall,
      backgroundColor: colors.canvasSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space12,
        vertical: IdeSpacing.space8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.accent),
          const SizedBox(width: IdeSpacing.space6),
          Text(
            label,
            style: textStyles.rowTitle.copyWith(color: colors.accent),
          ),
        ],
      ),
    );
  }
}

enum _FlatStateTone { neutral, error }

class _FlatStateMessage extends StatelessWidget {
  const _FlatStateMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.tone = _FlatStateTone.neutral,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final _FlatStateTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = tone == _FlatStateTone.error
        ? colors.error
        : colors.textSecondary;

    return Padding(
      padding: IdeSpacing.all20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(height: IdeSpacing.space8),
          Text(
            title,
            textAlign: TextAlign.start,
            style: textStyles.rowTitle.copyWith(color: foreground),
          ),
          const SizedBox(height: IdeSpacing.space4),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
          if (action != null) ...[
            const SizedBox(height: IdeSpacing.space8),
            action!,
          ],
        ],
      ),
    );
  }
}

String? _threadStatusLabel(
  AgentThreadSummary thread, {
  required bool isZetaLiveRunning,
}) {
  if (isZetaLiveRunning && thread.waitingOnApproval) {
    return '等待审批';
  }
  if (isZetaLiveRunning && thread.waitingOnUserInput) {
    return '等待输入';
  }
  if (isZetaLiveRunning) {
    return '执行中';
  }
  if (thread.status == AgentThreadRuntimeStatus.systemError) {
    return '系统错误';
  }
  return null;
}

Color _threadStatusColor(
  AgentThreadSummary thread,
  IdeColors colors, {
  required bool isZetaLiveRunning,
}) {
  if (isZetaLiveRunning &&
      (thread.waitingOnApproval || thread.waitingOnUserInput)) {
    return colors.warning;
  }
  if (isZetaLiveRunning) {
    return colors.accent;
  }
  return switch (thread.status) {
    AgentThreadRuntimeStatus.systemError => colors.error,
    AgentThreadRuntimeStatus.active ||
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
