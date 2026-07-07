import 'dart:io';

import 'package:flutter/material.dart';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
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
      trailing: Tooltip(
        message: 'Open folder',
        child: IconButton(
          onPressed: onOpenProject,
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
  static const double _menuItemHeight = 32;
  static const EdgeInsets _menuItemPadding = EdgeInsets.symmetric(
    horizontal: 12,
  );

  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;
  final GlobalKey _moreMenuAnchorKey = GlobalKey();

  bool get _showActions => _hovered || _focused || _menuOpen;

  Future<void> _showMoreMenu() async {
    final anchorContext = _moreMenuAnchorKey.currentContext;
    if (anchorContext == null) {
      return;
    }
    final button = anchorContext.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      Offset(button.size.width, button.size.height),
      ancestor: overlay,
    );

    setState(() {
      _menuOpen = true;
    });

    // 手动弹出菜单，避免 PopupMenuButton 的默认最小点击尺寸把项目行撑高。
    final selected = await showMenu<_ProjectTileMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_ProjectTileMenuAction>>[
        _buildMenuItem(
          value: _ProjectTileMenuAction.refreshThreads,
          key: ValueKey<String>('project-tile-refresh-threads-${widget.path}'),
          label: '刷新会话',
        ),
        _buildMenuItem(
          value: _ProjectTileMenuAction.openProjectLocation,
          key: ValueKey<String>('project-tile-open-location-${widget.path}'),
          label: _openProjectLocationLabel(),
        ),
        _buildMenuItem(
          value: _ProjectTileMenuAction.removeProject,
          key: ValueKey<String>('project-tile-remove-${widget.path}'),
          label: '移除',
        ),
      ],
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _menuOpen = false;
    });

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
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: widget.selected
                ? ideAccentColor.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                setState(() {
                  _hovered = true;
                });
              },
              onExit: (_) {
                setState(() {
                  _hovered = false;
                });
              },
              child: FocusableActionDetector(
                onShowFocusHighlight: (value) {
                  setState(() {
                    _focused = value;
                  });
                },
                child: InkWell(
                  key: ValueKey<String>('project-tile-${widget.path}'),
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.selected
                              ? Icons.folder_open_rounded
                              : Icons.folder_rounded,
                          size: 16,
                          color: widget.selected
                              ? ideAccentColor
                              : ideMutedTextColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fileName(widget.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                                      Tooltip(
                                        message: widget.threadState.isExpanded
                                            ? 'Collapse threads'
                                            : 'Expand threads',
                                        child: GestureDetector(
                                          key: ValueKey<String>(
                                            'project-tile-expand-icon-${widget.path}',
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          onTap: widget.onTap,
                                          child: SizedBox.square(
                                            dimension: _actionHitSize,
                                            child: Icon(
                                              widget.threadState.isExpanded
                                                  ? Icons
                                                        .keyboard_arrow_down_rounded
                                                  : Icons.chevron_right_rounded,
                                              size: _actionIconSize,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: _actionIconGap),
                                      Tooltip(
                                        message: 'More',
                                        child: GestureDetector(
                                          key: ValueKey<String>(
                                            'project-tile-more-menu-${widget.path}',
                                          ),
                                          onTap: _showMoreMenu,
                                          behavior: HitTestBehavior.opaque,
                                          child: SizedBox.square(
                                            key: ValueKey<String>(
                                              'project-tile-more-${widget.path}',
                                            ),
                                            dimension: _actionHitSize,
                                            child: Icon(
                                              Icons.more_horiz_rounded,
                                              key: _moreMenuAnchorKey,
                                              size: _actionIconSize,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: _actionIconGap),
                                      Tooltip(
                                        message: 'New thread',
                                        child: GestureDetector(
                                          key: ValueKey<String>(
                                            'project-tile-new-thread-${widget.path}',
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          onTap: widget.onNewThread,
                                          child: SizedBox.square(
                                            dimension: _actionHitSize,
                                            child: const Icon(
                                              Icons.edit_outlined,
                                              size: _actionIconSize,
                                            ),
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

  PopupMenuItem<_ProjectTileMenuAction> _buildMenuItem({
    required _ProjectTileMenuAction value,
    required Key key,
    required String label,
  }) {
    return PopupMenuItem<_ProjectTileMenuAction>(
      key: key,
      value: value,
      height: _menuItemHeight,
      padding: _menuItemPadding,
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
    final isRunning = thread.status == AgentThreadRuntimeStatus.active;
    final lastActiveLabel = _relativeThreadTime(
      thread.lastActiveAt,
      DateTime.now(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? ideAccentColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: ValueKey<String>('project-thread-$projectPath-${thread.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _threadIcon(thread.status),
                  size: 14,
                  color: selected ? ideAccentColor : ideMutedTextColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    thread.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
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
                    color: ideAccentColor,
                  ),
                ] else if (lastActiveLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    lastActiveLabel,
                    maxLines: 1,
                    style: const TextStyle(
                      color: ideMutedTextColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
          style: const TextStyle(color: ideMutedTextColor, fontSize: 11),
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
          const Expanded(
            child: Text(
              'Could not load threads',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ideMutedTextColor, fontSize: 11),
            ),
          ),
          Tooltip(
            message: 'Retry',
            child: IconButton(
              key: const ValueKey<String>('project-thread-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              visualDensity: VisualDensity.compact,
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
      child: TextButton.icon(
        key: const ValueKey<String>('project-thread-load-more-button'),
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : const Icon(Icons.more_horiz_rounded, size: 15),
        label: Text(loading ? 'Loading' : 'Load more'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 11),
        ),
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
