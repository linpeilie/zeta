import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_context_menu.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

typedef ProjectThreadSelected =
    void Function(String projectPath, AgentThreadSummary thread);

typedef ProjectThreadSearchChanged =
    void Function(String projectPath, String searchTerm);

typedef ProjectThreadArchivedViewChanged =
    void Function(String projectPath, bool archived);

typedef ProjectThreadRenamed =
    void Function(String projectPath, String threadId, String name);

typedef ProjectThreadAction =
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
    required this.onSearchTermChanged,
    required this.onArchivedViewChanged,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
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
  final ProjectThreadSearchChanged onSearchTermChanged;
  final ProjectThreadArchivedViewChanged onArchivedViewChanged;
  final ProjectThreadRenamed onRenameThread;
  final ProjectThreadAction onArchiveThread;
  final ProjectThreadAction onUnarchiveThread;
  final ProjectThreadAction onDeleteThread;
  final ProjectThreadAction onForkThread;

  @override
  Widget build(BuildContext context) {
    return Pane(
      title: 'Projects',
      trailing: IdeTooltip(
        message: 'Open folder',
        child: sf.IconButton.ghost(
          onPressed: onOpenProject,
          size: sf.ButtonSize.small,
          density: sf.ButtonDensity.iconDense,
          icon: const Icon(Icons.create_new_folder_outlined, size: 17),
        ),
      ),
      child: projects.isEmpty
          ? const EmptyState(text: 'No folder opened')
          : ListView.builder(
              padding: IdeSpacing.vertical6,
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
                  onSearchTermChanged: (searchTerm) =>
                      onSearchTermChanged(path, searchTerm),
                  onArchivedViewChanged: (archived) =>
                      onArchivedViewChanged(path, archived),
                  onRenameThread: (threadId, name) =>
                      onRenameThread(path, threadId, name),
                  onArchiveThread: (thread) => onArchiveThread(path, thread),
                  onUnarchiveThread: (thread) =>
                      onUnarchiveThread(path, thread),
                  onDeleteThread: (thread) => onDeleteThread(path, thread),
                  onForkThread: (thread) => onForkThread(path, thread),
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
    required this.onSearchTermChanged,
    required this.onArchivedViewChanged,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
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
  final ValueChanged<String> onSearchTermChanged;
  final ValueChanged<bool> onArchivedViewChanged;
  final void Function(String threadId, String name) onRenameThread;
  final ValueChanged<AgentThreadSummary> onArchiveThread;
  final ValueChanged<AgentThreadSummary> onUnarchiveThread;
  final ValueChanged<AgentThreadSummary> onDeleteThread;
  final ValueChanged<AgentThreadSummary> onForkThread;

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  static const double _actionHitSize = 18;
  static const double _actionIconSize = 16;
  static const double _actionIconGap = IdeSpacing.space6;

  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;

  bool get _showActions => _hovered || _focused || _menuOpen;

  void _toggleMoreMenu() {
    setState(() {
      _menuOpen = !_menuOpen;
    });
  }

  void _closeMoreMenu() {
    if (!_menuOpen) {
      return;
    }
    setState(() {
      _menuOpen = false;
    });
  }

  void _handleMenuAction(_ProjectTileMenuAction selected) {
    _closeMoreMenu();
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
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final selectedBackground = colors.primaryMuted;
    final hoverBackground = colors.border.withValues(alpha: 0.12);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space6,
        vertical: IdeSpacing.space2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneInteractiveSurface(
            key: ValueKey<String>('project-tile-${widget.path}'),
            onPressed: widget.onTap,
            selected: widget.selected,
            padding: const EdgeInsets.symmetric(
              horizontal: IdeSpacing.space8,
              vertical: 7,
            ),
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
                  color: widget.selected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: IdeSpacing.space8),
                Expanded(
                  child: Text(
                    fileName(widget.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: IdeMotion.durationNormal,
                  curve: IdeMotion.curveDefault,
                  alignment: Alignment.centerRight,
                  child: _showActions
                      ? SizedBox(
                          key: ValueKey<String>(
                            'project-tile-actions-${widget.path}',
                          ),
                          height: _actionHitSize,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IdeTooltip(
                                message: widget.threadState.isExpanded
                                    ? 'Collapse threads'
                                    : 'Expand threads',
                                child: sf.IconButton.ghost(
                                  key: ValueKey<String>(
                                    'project-tile-expand-icon-${widget.path}',
                                  ),
                                  onPressed: widget.onTap,
                                  size: sf.ButtonSize.xSmall,
                                  density: sf.ButtonDensity.iconDense,
                                  icon: Icon(
                                    widget.threadState.isExpanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.chevron_right_rounded,
                                    size: _actionIconSize,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: _actionIconGap),
                              IdeTooltip(
                                message: 'More',
                                child: sf.IconButton.ghost(
                                  key: ValueKey<String>(
                                    'project-tile-more-menu-${widget.path}',
                                  ),
                                  onPressed: _toggleMoreMenu,
                                  size: sf.ButtonSize.xSmall,
                                  density: sf.ButtonDensity.iconDense,
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    key: ValueKey<String>(
                                      'project-tile-more-${widget.path}',
                                    ),
                                    size: _actionIconSize,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: _actionIconGap),
                              IdeTooltip(
                                message: 'New thread',
                                child: sf.IconButton.ghost(
                                  key: ValueKey<String>(
                                    'project-tile-new-thread-${widget.path}',
                                  ),
                                  onPressed: widget.onNewThread,
                                  size: sf.ButtonSize.xSmall,
                                  density: sf.ButtonDensity.iconDense,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: _actionIconSize,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // 用 AnimatedSize 直接收展，避免 AnimatedSwitcher 在快速切换时堆叠旧 child。
                      : const SizedBox(width: 0, height: _actionHitSize),
                ),
              ],
            ),
          ),
          if (_menuOpen)
            Padding(
              padding: const EdgeInsets.only(
                top: IdeSpacing.space4,
                right: IdeSpacing.space6,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: IdeContextMenu(
                  closeOnActivate: false,
                  actions: [
                    IdeContextMenuAction(
                      key: ValueKey<String>(
                        'project-tile-refresh-threads-${widget.path}',
                      ),
                      label: '刷新会话',
                      onPressed: () => _handleMenuAction(
                        _ProjectTileMenuAction.refreshThreads,
                      ),
                    ),
                    IdeContextMenuAction(
                      key: ValueKey<String>(
                        'project-tile-open-location-${widget.path}',
                      ),
                      label: _openProjectLocationLabel(),
                      onPressed: () => _handleMenuAction(
                        _ProjectTileMenuAction.openProjectLocation,
                      ),
                    ),
                    IdeContextMenuAction(
                      key: ValueKey<String>(
                        'project-tile-remove-${widget.path}',
                      ),
                      label: '移除',
                      destructive: true,
                      onPressed: () => _handleMenuAction(
                        _ProjectTileMenuAction.removeProject,
                      ),
                    ),
                  ],
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
              onSearchTermChanged: widget.onSearchTermChanged,
              onArchivedViewChanged: widget.onArchivedViewChanged,
              onRenameThread: widget.onRenameThread,
              onArchiveThread: widget.onArchiveThread,
              onUnarchiveThread: widget.onUnarchiveThread,
              onDeleteThread: widget.onDeleteThread,
              onForkThread: widget.onForkThread,
            ),
        ],
      ),
    );
  }
}

class _ProjectThreadList extends StatefulWidget {
  const _ProjectThreadList({
    required this.projectPath,
    required this.state,
    required this.onSelectThread,
    required this.onLoadMoreThreads,
    required this.onRetryThreads,
    required this.onSearchTermChanged,
    required this.onArchivedViewChanged,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
  });

  final String projectPath;
  final ProjectThreadListState state;
  final ProjectThreadSelected onSelectThread;
  final VoidCallback onLoadMoreThreads;
  final VoidCallback onRetryThreads;
  final ValueChanged<String> onSearchTermChanged;
  final ValueChanged<bool> onArchivedViewChanged;
  final void Function(String threadId, String name) onRenameThread;
  final ValueChanged<AgentThreadSummary> onArchiveThread;
  final ValueChanged<AgentThreadSummary> onUnarchiveThread;
  final ValueChanged<AgentThreadSummary> onDeleteThread;
  final ValueChanged<AgentThreadSummary> onForkThread;

  @override
  State<_ProjectThreadList> createState() => _ProjectThreadListState();
}

class _ProjectThreadListState extends State<_ProjectThreadList> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.state.searchTerm);
  }

  @override
  void didUpdateWidget(covariant _ProjectThreadList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.searchTerm != _searchController.text) {
      _searchController.text = widget.state.searchTerm;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final emptyMessage = state.archived ? 'No archived threads' : 'No threads';
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(
          left: IdeSpacing.space4,
          right: IdeSpacing.space4,
          bottom: IdeSpacing.space6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sf.TextField(
              key: ValueKey<String>(
                'project-thread-search-${widget.projectPath}',
              ),
              controller: _searchController,
              onChanged: widget.onSearchTermChanged,
              placeholder: const Text('搜索会话'),
              features: const [
                sf.InputFeature.leading(Icon(Icons.search_rounded, size: 16)),
              ],
            ),
            const SizedBox(height: IdeSpacing.space6),
            Wrap(
              spacing: IdeSpacing.space6,
              runSpacing: IdeSpacing.space4,
              children: [
                IdeChip(
                  key: ValueKey<String>(
                    'project-thread-active-filter-${widget.projectPath}',
                  ),
                  label: '活动',
                  selected: !state.archived,
                  trailingIcon: null,
                  onPressed: () => widget.onArchivedViewChanged(false),
                ),
                IdeChip(
                  key: ValueKey<String>(
                    'project-thread-archived-filter-${widget.projectPath}',
                  ),
                  label: '已归档',
                  selected: state.archived,
                  trailingIcon: null,
                  onPressed: () => widget.onArchivedViewChanged(true),
                ),
              ],
            ),
          ],
        ),
      ),
      for (final thread in state.threads)
        _ThreadTile(
          projectPath: widget.projectPath,
          thread:
              state.runningThreadIds.contains(thread.id) &&
                  thread.status != AgentThreadRuntimeStatus.active
              ? thread.copyWith(status: AgentThreadRuntimeStatus.active)
              : thread,
          selected: thread.id == state.selectedThreadId,
          archivedView: state.archived,
          onTap: () => widget.onSelectThread(widget.projectPath, thread),
          onRenameThread: widget.onRenameThread,
          onArchiveThread: widget.onArchiveThread,
          onUnarchiveThread: widget.onUnarchiveThread,
          onDeleteThread: widget.onDeleteThread,
          onForkThread: widget.onForkThread,
        ),
      if (state.isLoadingInitial && state.threads.isEmpty)
        const _ThreadListMessage(text: 'Loading threads...'),
      if (state.errorMessage != null)
        _ThreadErrorRow(onRetry: widget.onRetryThreads),
      if (state.hasLoaded &&
          state.threads.isEmpty &&
          !state.isLoadingInitial &&
          state.errorMessage == null)
        _ThreadListMessage(text: emptyMessage),
      if (state.hasMore)
        _LoadMoreThreadsButton(
          loading: state.isLoadingMore,
          onPressed: widget.onLoadMoreThreads,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 4, top: 2, bottom: 4),
      child: Column(children: children),
    );
  }
}

enum _ThreadTileMenuAction { rename, archive, unarchive, fork, delete }

class _ThreadTile extends StatefulWidget {
  const _ThreadTile({
    required this.projectPath,
    required this.thread,
    required this.selected,
    required this.archivedView,
    required this.onTap,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
  });

  final String projectPath;
  final AgentThreadSummary thread;
  final bool selected;
  final bool archivedView;
  final VoidCallback onTap;
  final void Function(String threadId, String name) onRenameThread;
  final ValueChanged<AgentThreadSummary> onArchiveThread;
  final ValueChanged<AgentThreadSummary> onUnarchiveThread;
  final ValueChanged<AgentThreadSummary> onDeleteThread;
  final ValueChanged<AgentThreadSummary> onForkThread;

  @override
  State<_ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<_ThreadTile> {
  static const double _actionHitSize = 18;
  static const double _actionIconSize = 14;

  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;

  bool get _showActions => _hovered || _focused || _menuOpen;

  void _toggleMoreMenu() {
    setState(() {
      _menuOpen = !_menuOpen;
    });
  }

  void _closeMoreMenu() {
    if (!_menuOpen) {
      return;
    }
    setState(() {
      _menuOpen = false;
    });
  }

  Future<void> _showRenameDialog() async {
    _closeMoreMenu();
    final controller = TextEditingController(text: widget.thread.displayName);
    final name = await showIdeDialog<String>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          key: ValueKey<String>(
            'project-thread-rename-dialog-${widget.projectPath}-${widget.thread.id}',
          ),
          title: const Text('重命名'),
          content: SizedBox(
            width: 320,
            child: sf.TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value.trim());
              },
            ),
          ),
          actions: [
            IdeDialogAction.cancel(
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            IdeDialogAction.confirm(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) {
      return;
    }
    widget.onRenameThread(widget.thread.id, name);
  }

  Future<void> _showDeleteDialog() async {
    _closeMoreMenu();
    final confirmed = await showIdeDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          key: ValueKey<String>(
            'project-thread-delete-dialog-${widget.projectPath}-${widget.thread.id}',
          ),
          title: const Text('删除会话'),
          content: const Text('此操作不可撤销，将永久删除该会话。'),
          actions: [
            IdeDialogAction.cancel(
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            IdeDialogAction.destructive(
              label: '删除',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      widget.onDeleteThread(widget.thread);
    }
  }

  void _handleMenuAction(_ThreadTileMenuAction action) {
    switch (action) {
      case _ThreadTileMenuAction.rename:
        unawaited(_showRenameDialog());
        return;
      case _ThreadTileMenuAction.archive:
        _closeMoreMenu();
        widget.onArchiveThread(widget.thread);
        return;
      case _ThreadTileMenuAction.unarchive:
        _closeMoreMenu();
        widget.onUnarchiveThread(widget.thread);
        return;
      case _ThreadTileMenuAction.fork:
        _closeMoreMenu();
        widget.onForkThread(widget.thread);
        return;
      case _ThreadTileMenuAction.delete:
        unawaited(_showDeleteDialog());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final hoverBackground = colors.border.withValues(alpha: 0.12);
    final thread = widget.thread;
    final isBusy = thread.isBusy;
    final waitingLabel = thread.waitingOnApproval
        ? '等待审批'
        : thread.waitingOnUserInput
        ? '等待输入'
        : null;
    final lastActiveLabel = _relativeThreadTime(
      thread.lastActiveAt,
      DateTime.now(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneInteractiveSurface(
            key: ValueKey<String>(
              'project-thread-${widget.projectPath}-${thread.id}',
            ),
            onPressed: widget.onTap,
            selected: widget.selected,
            padding: const EdgeInsets.symmetric(
              horizontal: IdeSpacing.space8,
              vertical: IdeSpacing.space6,
            ),
            borderRadius: IdeRadius.allSmall,
            selectedBackgroundColor: colors.primaryMuted,
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
                  _threadIcon(thread.status),
                  size: 14,
                  color: widget.selected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: IdeSpacing.space8),
                Expanded(
                  child: Text(
                    thread.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (waitingLabel != null) ...[
                  const SizedBox(width: IdeSpacing.space8),
                  Text(
                    waitingLabel,
                    key: ValueKey<String>(
                      'project-thread-waiting-${widget.projectPath}-${thread.id}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.caption.copyWith(
                      color: colors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (isBusy) ...[
                  const SizedBox(width: IdeSpacing.space8),
                  Icon(
                    Icons.autorenew_rounded,
                    key: ValueKey<String>(
                      'project-thread-running-icon-${widget.projectPath}-${thread.id}',
                    ),
                    size: 14,
                    color: colors.accent,
                  ),
                ] else if (lastActiveLabel != null) ...[
                  const SizedBox(width: IdeSpacing.space8),
                  Text(
                    lastActiveLabel,
                    maxLines: 1,
                    style: textStyles.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                AnimatedSize(
                  duration: IdeMotion.durationNormal,
                  curve: IdeMotion.curveDefault,
                  alignment: Alignment.centerRight,
                  child: _showActions
                      ? SizedBox(
                          key: ValueKey<String>(
                            'project-thread-actions-${widget.projectPath}-${thread.id}',
                          ),
                          width: _actionHitSize,
                          height: _actionHitSize,
                          child: IdeTooltip(
                            message: '更多',
                            child: sf.IconButton.ghost(
                              key: ValueKey<String>(
                                'project-thread-more-menu-${widget.projectPath}-${thread.id}',
                              ),
                              onPressed: _toggleMoreMenu,
                              size: sf.ButtonSize.xSmall,
                              density: sf.ButtonDensity.iconDense,
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                size: _actionIconSize,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      // 用 AnimatedSize 直接收展，避免 AnimatedSwitcher 在快速切换时堆叠旧 child。
                      : const SizedBox(width: 0, height: _actionHitSize),
                ),
              ],
            ),
          ),
          if (_menuOpen)
            Padding(
              padding: const EdgeInsets.only(
                top: IdeSpacing.space2,
                left: IdeSpacing.space8,
                right: IdeSpacing.space4,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: IdeContextMenu(
                  closeOnActivate: false,
                  actions: [
                    IdeContextMenuAction(
                      key: ValueKey<String>(
                        'project-thread-rename-${widget.projectPath}-${thread.id}',
                      ),
                      label: '重命名',
                      onPressed: () =>
                          _handleMenuAction(_ThreadTileMenuAction.rename),
                    ),
                    if (widget.archivedView)
                      IdeContextMenuAction(
                        key: ValueKey<String>(
                          'project-thread-unarchive-${widget.projectPath}-${thread.id}',
                        ),
                        label: '取消归档',
                        onPressed: () =>
                            _handleMenuAction(_ThreadTileMenuAction.unarchive),
                      )
                    else
                      IdeContextMenuAction(
                        key: ValueKey<String>(
                          'project-thread-archive-${widget.projectPath}-${thread.id}',
                        ),
                        label: '归档',
                        onPressed: () =>
                            _handleMenuAction(_ThreadTileMenuAction.archive),
                      ),
                    IdeContextMenuAction(
                      key: ValueKey<String>(
                        'project-thread-fork-${widget.projectPath}-${thread.id}',
                      ),
                      label: '分叉',
                      onPressed: () =>
                          _handleMenuAction(_ThreadTileMenuAction.fork),
                    ),
                    IdeContextMenuAction(
                      key: ValueKey<String>(
                        'project-thread-delete-${widget.projectPath}-${thread.id}',
                      ),
                      label: '删除',
                      destructive: true,
                      dividerAbove: true,
                      onPressed: () =>
                          _handleMenuAction(_ThreadTileMenuAction.delete),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadListMessage extends StatelessWidget {
  const _ThreadListMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space8,
        vertical: IdeSpacing.space6,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
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
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space4,
        vertical: IdeSpacing.space4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Could not load threads',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(color: colors.error),
            ),
          ),
          IdeTooltip(
            message: 'Retry',
            child: sf.IconButton.ghost(
              key: const ValueKey<String>('project-thread-retry-button'),
              onPressed: onRetry,
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.iconDense,
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
    final textStyles = IdeTextStyles.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: sf.GhostButton(
        key: const ValueKey<String>('project-thread-load-more-button'),
        onPressed: loading ? null : onPressed,
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
        leading: loading
            ? const IdeLoadingIndicator(width: 16, height: 10, barHeight: 3)
            : const Icon(Icons.more_horiz_rounded, size: 15),
        child: Text(
          loading ? 'Loading' : 'Load more',
          style: textStyles.bodySmall,
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
