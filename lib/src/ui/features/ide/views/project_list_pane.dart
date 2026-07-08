import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

typedef ProjectThreadSelected =
    void Function(String projectPath, AgentThreadSummary thread);

class ProjectListPane extends StatelessWidget {
  const ProjectListPane({
    required this.projects,
    required this.activeProject,
    required this.threadStateFor,
    required this.onOpenProject,
    required this.onSelectProject,
    required this.onSelectThread,
    required this.onLoadMoreThreads,
    required this.onRetryThreads,
    required this.onNewThread,
    required this.onOpenProjectLocation,
    required this.onRemoveProject,
    super.key,
  });

  final List<String> projects;
  final String? activeProject;
  final ProjectThreadListState Function(String projectPath) threadStateFor;
  final VoidCallback onOpenProject;
  final ValueChanged<String> onSelectProject;
  final ProjectThreadSelected onSelectThread;
  final ValueChanged<String> onLoadMoreThreads;
  final ValueChanged<String> onRetryThreads;
  final ValueChanged<String> onNewThread;
  final ValueChanged<String> onOpenProjectLocation;
  final ValueChanged<String> onRemoveProject;

  @override
  Widget build(BuildContext context) {
    return Pane(
      title: 'Projects',
      trailing: IdeTooltip(
        message: 'Open folder',
        child: ShadIconButton.ghost(
          onPressed: onOpenProject,
          width: 30,
          height: 30,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.create_new_folder_outlined, size: 17),
        ),
      ),
      child: projects.isEmpty
          ? const EmptyState(text: 'No folder opened')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final path = projects[index];
                final selected = path == activeProject;
                return _ProjectTile(
                  path: path,
                  selected: selected,
                  threadState: threadStateFor(path),
                  onTap: () => onSelectProject(path),
                  onSelectThread: onSelectThread,
                  onLoadMoreThreads: () => onLoadMoreThreads(path),
                  onRetryThreads: () => onRetryThreads(path),
                  onNewThread: () => onNewThread(path),
                  onOpenProjectLocation: () => onOpenProjectLocation(path),
                  onRemoveProject: () => onRemoveProject(path),
                );
              },
            ),
    );
  }
}

enum _ProjectTileMenuAction {
  refreshThreads,
  openProjectLocation,
  removeProject,
}

class _ProjectTile extends StatefulWidget {
  const _ProjectTile({
    required this.path,
    required this.selected,
    required this.threadState,
    required this.onTap,
    required this.onSelectThread,
    required this.onLoadMoreThreads,
    required this.onRetryThreads,
    required this.onNewThread,
    required this.onOpenProjectLocation,
    required this.onRemoveProject,
  });

  final String path;
  final bool selected;
  final ProjectThreadListState threadState;
  final VoidCallback onTap;
  final ProjectThreadSelected onSelectThread;
  final VoidCallback onLoadMoreThreads;
  final VoidCallback onRetryThreads;
  final VoidCallback onNewThread;
  final VoidCallback onOpenProjectLocation;
  final VoidCallback onRemoveProject;

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  static const double _actionHitSize = 18;
  static const double _actionIconSize = 16;
  static const double _actionIconGap = 6;

  bool _hovered = false;
  bool _focused = false;
  late final ShadPopoverController _moreMenuController;

  bool get _showActions => _hovered || _focused || _moreMenuController.isOpen;

  @override
  void initState() {
    super.initState();
    _moreMenuController = ShadPopoverController();
    _moreMenuController.addListener(_handleMenuVisibilityChanged);
  }

  @override
  void dispose() {
    _moreMenuController
      ..removeListener(_handleMenuVisibilityChanged)
      ..dispose();
    super.dispose();
  }

  void _handleMenuVisibilityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleMoreMenu() {
    if (_moreMenuController.isOpen) {
      _moreMenuController.hide();
      return;
    }
    _moreMenuController.show();
  }

  void _handleMenuAction(_ProjectTileMenuAction selected) {
    _moreMenuController.hide();
    switch (selected) {
      case _ProjectTileMenuAction.refreshThreads:
        widget.onRetryThreads();
        break;
      case _ProjectTileMenuAction.openProjectLocation:
        widget.onOpenProjectLocation();
        break;
      case _ProjectTileMenuAction.removeProject:
        widget.onRemoveProject();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final colorScheme = shadTheme.colorScheme;
    final selectedBackground = colorScheme.primary.withValues(
      alpha: shadTheme.brightness == Brightness.dark ? 0.16 : 0.1,
    );
    final hoverBackground = colorScheme.border.withValues(alpha: 0.12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneInteractiveSurface(
            key: ValueKey<String>('project-tile-${widget.path}'),
            onPressed: widget.onTap,
            selected: widget.selected,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            selectedBackgroundColor: selectedBackground,
            hoverBackgroundColor: hoverBackground,
            onHoverChanged: (value) {
              setState(() {
                _hovered = value;
              });
            },
            onFocusChanged: (value) {
              setState(() {
                _focused = value;
              });
            },
            child: Row(
              children: [
                Icon(
                  widget.selected
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded,
                  size: 16,
                  color: widget.selected
                      ? colorScheme.primary
                      : colorScheme.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName(widget.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: SizedBox(
                    key: ValueKey<String>(
                      _showActions
                          ? 'project-tile-actions-${widget.path}'
                          : 'project-tile-actions-hidden-${widget.path}',
                    ),
                    height: _actionHitSize,
                    child: _showActions
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IdeTooltip(
                                message: widget.threadState.isExpanded
                                    ? 'Collapse threads'
                                    : 'Expand threads',
                                child: ShadIconButton.ghost(
                                  key: ValueKey<String>(
                                    'project-tile-expand-icon-${widget.path}',
                                  ),
                                  onPressed: widget.onTap,
                                  width: _actionHitSize,
                                  height: _actionHitSize,
                                  padding: EdgeInsets.zero,
                                  foregroundColor: colorScheme.mutedForeground,
                                  hoverBackgroundColor: hoverBackground,
                                  icon: Icon(
                                    widget.threadState.isExpanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.chevron_right_rounded,
                                    size: _actionIconSize,
                                  ),
                                ),
                              ),
                              const SizedBox(width: _actionIconGap),
                              IdeTooltip(
                                message: 'More',
                                child: GestureDetector(
                                  key: ValueKey<String>(
                                    'project-tile-more-menu-${widget.path}',
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleMoreMenu,
                                  child: Container(
                                    width: _actionHitSize,
                                    height: _actionHitSize,
                                    color: Colors.transparent,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.more_horiz_rounded,
                                      key: ValueKey<String>(
                                        'project-tile-more-${widget.path}',
                                      ),
                                      size: _actionIconSize,
                                      color: colorScheme.mutedForeground,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: _actionIconGap),
                              IdeTooltip(
                                message: 'New thread',
                                child: ShadIconButton.ghost(
                                  key: ValueKey<String>(
                                    'project-tile-new-thread-${widget.path}',
                                  ),
                                  onPressed: widget.onNewThread,
                                  width: _actionHitSize,
                                  height: _actionHitSize,
                                  padding: EdgeInsets.zero,
                                  foregroundColor: colorScheme.mutedForeground,
                                  hoverBackgroundColor: hoverBackground,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: _actionIconSize,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox(width: 0),
                  ),
                ),
              ],
            ),
          ),
          if (_moreMenuController.isOpen)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.popover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 156),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMenuActionButton(
                            value: _ProjectTileMenuAction.refreshThreads,
                            key: ValueKey<String>(
                              'project-tile-refresh-threads-${widget.path}',
                            ),
                            label: '刷新会话',
                          ),
                          _buildMenuActionButton(
                            value: _ProjectTileMenuAction.openProjectLocation,
                            key: ValueKey<String>(
                              'project-tile-open-location-${widget.path}',
                            ),
                            label: _openProjectLocationLabel(),
                          ),
                          _buildMenuActionButton(
                            value: _ProjectTileMenuAction.removeProject,
                            key: ValueKey<String>(
                              'project-tile-remove-${widget.path}',
                            ),
                            label: '移除',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.threadState.isExpanded)
            _ProjectThreadList(
              projectPath: widget.path,
              state: widget.threadState,
              onSelectThread: widget.onSelectThread,
              onLoadMoreThreads: widget.onLoadMoreThreads,
              onRetryThreads: widget.onRetryThreads,
            ),
        ],
      ),
    );
  }

  Widget _buildMenuActionButton({
    required _ProjectTileMenuAction value,
    required Key key,
    required String label,
  }) {
    return ShadButton.ghost(
      key: key,
      onPressed: () => _handleMenuAction(value),
      width: double.infinity,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      mainAxisAlignment: MainAxisAlignment.start,
      child: Text(label, style: const TextStyle(fontSize: 12, height: 1.1)),
    );
  }
}

class _ProjectThreadList extends StatelessWidget {
  const _ProjectThreadList({
    required this.projectPath,
    required this.state,
    required this.onSelectThread,
    required this.onLoadMoreThreads,
    required this.onRetryThreads,
  });

  final String projectPath;
  final ProjectThreadListState state;
  final ProjectThreadSelected onSelectThread;
  final VoidCallback onLoadMoreThreads;
  final VoidCallback onRetryThreads;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final thread in state.threads)
        _ThreadTile(
          projectPath: projectPath,
          thread: state.runningThreadIds.contains(thread.id)
              ? thread.copyWith(status: AgentThreadRuntimeStatus.active)
              : thread,
          selected: thread.id == state.selectedThreadId,
          onTap: () => onSelectThread(projectPath, thread),
        ),
      if (state.isLoadingInitial && state.threads.isEmpty)
        const _ThreadListMessage(text: 'Loading threads...'),
      if (state.errorMessage != null) _ThreadErrorRow(onRetry: onRetryThreads),
      if (state.hasLoaded &&
          state.threads.isEmpty &&
          !state.isLoadingInitial &&
          state.errorMessage == null)
        const _ThreadListMessage(text: 'No threads'),
      if (state.hasMore)
        _LoadMoreThreadsButton(
          loading: state.isLoadingMore,
          onPressed: onLoadMoreThreads,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 4, top: 2, bottom: 4),
      child: Column(children: children),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.projectPath,
    required this.thread,
    required this.selected,
    required this.onTap,
  });

  final String projectPath;
  final AgentThreadSummary thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final shadTheme = ShadTheme.of(context);
    final colorScheme = shadTheme.colorScheme;
    final isRunning = thread.status == AgentThreadRuntimeStatus.active;
    final lastActiveLabel = _relativeThreadTime(
      thread.lastActiveAt,
      DateTime.now(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: PaneInteractiveSurface(
        key: ValueKey<String>('project-thread-$projectPath-${thread.id}'),
        onPressed: onTap,
        selected: selected,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        borderRadius: BorderRadius.circular(5),
        selectedBackgroundColor: colorScheme.primary.withValues(
          alpha: shadTheme.brightness == Brightness.dark ? 0.14 : 0.08,
        ),
        hoverBackgroundColor: colorScheme.border.withValues(alpha: 0.12),
        child: Row(
          children: [
            Icon(
              _threadIcon(thread.status),
              size: 14,
              color: selected ? colors.accent : colors.mutedText,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                thread.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: shadTheme.textTheme.small.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isRunning) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.autorenew_rounded,
                key: ValueKey<String>(
                  'project-thread-running-icon-$projectPath-${thread.id}',
                ),
                size: 14,
                color: colors.accent,
              ),
            ] else if (lastActiveLabel != null) ...[
              const SizedBox(width: 8),
              Text(
                lastActiveLabel,
                maxLines: 1,
                style: TextStyle(color: colors.mutedText, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThreadListMessage extends StatelessWidget {
  const _ThreadListMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: IdeColors.of(context).mutedText,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _ThreadErrorRow extends StatelessWidget {
  const _ThreadErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Could not load threads',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: IdeColors.of(context).mutedText,
                fontSize: 11,
              ),
            ),
          ),
          IdeTooltip(
            message: 'Retry',
            child: ShadIconButton.ghost(
              key: const ValueKey<String>('project-thread-retry-button'),
              onPressed: onRetry,
              width: 28,
              height: 28,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.refresh_rounded, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreThreadsButton extends StatelessWidget {
  const _LoadMoreThreadsButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ShadButton.ghost(
        key: const ValueKey<String>('project-thread-load-more-button'),
        onPressed: loading ? null : onPressed,
        size: ShadButtonSize.sm,
        leading: loading
            ? const IdeLoadingIndicator(width: 16, height: 10, barHeight: 3)
            : const Icon(Icons.more_horiz_rounded, size: 15),
        textStyle: const TextStyle(fontSize: 11),
        child: Text(loading ? 'Loading' : 'Load more'),
      ),
    );
  }
}

IconData _threadIcon(AgentThreadRuntimeStatus status) {
  return switch (status) {
    AgentThreadRuntimeStatus.active => Icons.play_circle_outline_rounded,
    AgentThreadRuntimeStatus.systemError => Icons.error_outline_rounded,
    _ => Icons.chat_bubble_outline_rounded,
  };
}

String? _relativeThreadTime(DateTime? value, DateTime now) {
  if (value == null) {
    return null;
  }

  final difference = now.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) {
    return 'now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h';
  }
  return '${difference.inDays}d';
}

String _openProjectLocationLabel() {
  if (Platform.isMacOS) {
    return '在 Finder 中打开';
  }
  if (Platform.isWindows) {
    return '在资源管理器中打开';
  }
  return '在文件管理器中打开';
}
