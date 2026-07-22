import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_context_menu.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/features/ide/views/new_thread_provider_popover.dart';

typedef ProjectThreadSelected =
    void Function(String projectPath, AgentThreadSummary thread);

typedef ProjectThreadRenamed =
    void Function(String projectPath, String threadId, String name);

typedef ProjectThreadAction =
    void Function(String projectPath, AgentThreadSummary thread);

typedef ProjectThreadCompletedDismissed =
    void Function(String projectPath, String threadId);

typedef ProjectNewThread = void Function(String projectPath, String providerId);

typedef AgentProviderCapabilitiesResolver =
    AgentProviderCapabilities Function(String providerId);

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
    required this.loadAvailableProviders,
    required this.capabilitiesForProvider,
    required this.onNewThread,
    required this.onOpenProjectLocation,
    required this.onRemoveProject,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
    required this.onDismissCompletedThread,
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
  final Future<List<AgentProviderConfig>> Function() loadAvailableProviders;
  final AgentProviderCapabilitiesResolver capabilitiesForProvider;
  final ProjectNewThread onNewThread;
  final ValueChanged<String> onOpenProjectLocation;
  final ValueChanged<String> onRemoveProject;
  final ProjectThreadRenamed onRenameThread;
  final ProjectThreadAction onArchiveThread;
  final ProjectThreadAction onUnarchiveThread;
  final ProjectThreadAction onDeleteThread;
  final ProjectThreadAction onForkThread;
  final ProjectThreadCompletedDismissed onDismissCompletedThread;

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
                  loadAvailableProviders: loadAvailableProviders,
                  capabilitiesForProvider: capabilitiesForProvider,
                  onNewThread: (providerId) => onNewThread(path, providerId),
                  onOpenProjectLocation: () => onOpenProjectLocation(path),
                  onRemoveProject: () => onRemoveProject(path),
                  onRenameThread: (threadId, name) =>
                      onRenameThread(path, threadId, name),
                  onArchiveThread: (thread) => onArchiveThread(path, thread),
                  onUnarchiveThread: (thread) =>
                      onUnarchiveThread(path, thread),
                  onDeleteThread: (thread) => onDeleteThread(path, thread),
                  onForkThread: (thread) => onForkThread(path, thread),
                  onDismissCompletedThread: (threadId) =>
                      onDismissCompletedThread(path, threadId),
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
    required this.loadAvailableProviders,
    required this.capabilitiesForProvider,
    required this.onNewThread,
    required this.onOpenProjectLocation,
    required this.onRemoveProject,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
    required this.onDismissCompletedThread,
  });

  final String path;
  final bool selected;
  final ProjectThreadListState threadState;
  final VoidCallback onTap;
  final ProjectThreadSelected onSelectThread;
  final VoidCallback onLoadMoreThreads;
  final VoidCallback onRetryThreads;
  final Future<List<AgentProviderConfig>> Function() loadAvailableProviders;
  final AgentProviderCapabilitiesResolver capabilitiesForProvider;
  final ValueChanged<String> onNewThread;
  final VoidCallback onOpenProjectLocation;
  final ValueChanged<String> onDismissCompletedThread;
  final VoidCallback onRemoveProject;
  final void Function(String threadId, String name) onRenameThread;
  final ValueChanged<AgentThreadSummary> onArchiveThread;
  final ValueChanged<AgentThreadSummary> onUnarchiveThread;
  final ValueChanged<AgentThreadSummary> onDeleteThread;
  final ValueChanged<AgentThreadSummary> onForkThread;

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  static const double _actionIconSize = 16;
  static const double _actionIconGap = IdeSpacing.space6;

  final GlobalKey _moreButtonKey = GlobalKey();
  final GlobalKey _newThreadButtonKey = GlobalKey();
  IdePopoverHandle<void>? _morePopoverEntry;
  IdePopoverHandle<AgentProviderConfig?>? _newThreadPopoverEntry;
  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;
  bool _newThreadPopoverOpen = false;

  bool get _showActions =>
      _hovered || _focused || _menuOpen || _newThreadPopoverOpen;

  @override
  void dispose() {
    _morePopoverEntry?.dismiss();
    _morePopoverEntry = null;
    _newThreadPopoverEntry?.dismiss();
    _newThreadPopoverEntry = null;
    super.dispose();
  }

  void _toggleMoreMenu() {
    if (_menuOpen) {
      _dismissMoreMenu();
      return;
    }
    _showMoreMenu();
  }

  void _showMoreMenu() {
    _dismissNewThreadPopover();
    if (_morePopoverEntry != null) {
      return;
    }
    // 锚到 more 按钮所在行，避免展开 thread 列表后菜单落到整块项目下方。
    final anchorContext = _moreButtonKey.currentContext ?? context;
    setState(() {
      _menuOpen = true;
    });
    final entry = showIdePopover<void>(
      context: anchorContext,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      modal: false,
      builder: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 100, maxWidth: 140),
          child: IdeContextMenu(
            actions: [
              IdeContextMenuAction(
                key: ValueKey<String>(
                  'project-tile-refresh-threads-${widget.path}',
                ),
                label: '刷新会话',
                onPressed: () =>
                    _handleMenuAction(_ProjectTileMenuAction.refreshThreads),
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
                key: ValueKey<String>('project-tile-remove-${widget.path}'),
                label: '移除',
                destructive: true,
                onPressed: () =>
                    _handleMenuAction(_ProjectTileMenuAction.removeProject),
              ),
            ],
          ),
        );
      },
    );
    _morePopoverEntry = entry;
    entry.future.whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        if (identical(_morePopoverEntry, entry)) {
          _morePopoverEntry = null;
        }
        _menuOpen = false;
      });
    });
  }

  void _dismissMoreMenu() {
    final entry = _morePopoverEntry;
    if (entry == null) {
      return;
    }
    _morePopoverEntry = null;
    setState(() {
      _menuOpen = false;
    });
    entry.dismiss();
  }

  void _toggleNewThreadPopover() {
    if (_newThreadPopoverEntry != null) {
      _dismissNewThreadPopover();
      return;
    }
    _showNewThreadPopover();
  }

  void _showNewThreadPopover() {
    _dismissMoreMenu();
    if (_newThreadPopoverEntry != null) {
      return;
    }
    final anchorContext = _newThreadButtonKey.currentContext ?? context;
    setState(() {
      _newThreadPopoverOpen = true;
    });
    final entry = showIdePopover<AgentProviderConfig?>(
      context: anchorContext,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      margin: IdeSpacing.all8,
      builder: (context) => NewThreadProviderPopover(
        loadAvailableProviders: widget.loadAvailableProviders,
      ),
    );
    _newThreadPopoverEntry = entry;
    entry.future
        .then((provider) {
          if (!mounted || provider == null) {
            return;
          }
          widget.onNewThread(provider.id);
        })
        .whenComplete(() {
          if (!mounted) {
            return;
          }
          setState(() {
            if (identical(_newThreadPopoverEntry, entry)) {
              _newThreadPopoverEntry = null;
            }
            _newThreadPopoverOpen = false;
          });
        });
  }

  void _dismissNewThreadPopover() {
    final entry = _newThreadPopoverEntry;
    if (entry == null) {
      return;
    }
    _newThreadPopoverEntry = null;
    setState(() {
      _newThreadPopoverOpen = false;
    });
    entry.dismiss();
  }

  void _handleMenuAction(_ProjectTileMenuAction selected) {
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
    return Padding(
      key: ValueKey<String>('project-tile-padding-${widget.path}'),
      padding: IdeSpacing.horizontal6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneInteractiveSurface(
            key: ValueKey<String>('project-tile-${widget.path}'),
            onPressed: widget.onTap,
            selected: widget.selected,
            padding: IdeSpacing.horizontal8,
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
                          height: IdeMetrics.iconButtonHitSize,
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
                              KeyedSubtree(
                                key: _moreButtonKey,
                                child: IdeTooltip(
                                  message: '更多',
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
                                      color: _menuOpen
                                          ? colors.textPrimary
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: _actionIconGap),
                              KeyedSubtree(
                                key: _newThreadButtonKey,
                                child: IdeTooltip(
                                  message: 'New thread',
                                  child: sf.IconButton.ghost(
                                    key: ValueKey<String>(
                                      'project-tile-new-thread-${widget.path}',
                                    ),
                                    onPressed: _toggleNewThreadPopover,
                                    size: sf.ButtonSize.xSmall,
                                    density: sf.ButtonDensity.iconDense,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: _actionIconSize,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // 用 AnimatedSize 直接收展，避免 AnimatedSwitcher 在快速切换时堆叠旧 child。
                      : const SizedBox(
                          width: 0,
                          height: IdeMetrics.iconButtonHitSize,
                        ),
                ),
              ],
            ),
          ),
          if (widget.threadState.isExpanded)
            _ProjectThreadList(
              projectPath: widget.path,
              state: widget.threadState,
              onSelectThread: widget.onSelectThread,
              onLoadMoreThreads: widget.onLoadMoreThreads,
              onRetryThreads: widget.onRetryThreads,
              capabilitiesForProvider: widget.capabilitiesForProvider,
              onRenameThread: widget.onRenameThread,
              onArchiveThread: widget.onArchiveThread,
              onUnarchiveThread: widget.onUnarchiveThread,
              onDeleteThread: widget.onDeleteThread,
              onForkThread: widget.onForkThread,
              onDismissCompletedThread: widget.onDismissCompletedThread,
            ),
        ],
      ),
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
    required this.capabilitiesForProvider,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
    required this.onDismissCompletedThread,
  });

  final String projectPath;
  final ProjectThreadListState state;
  final ProjectThreadSelected onSelectThread;
  final VoidCallback onLoadMoreThreads;
  final VoidCallback onRetryThreads;
  final AgentProviderCapabilitiesResolver capabilitiesForProvider;
  final void Function(String threadId, String name) onRenameThread;
  final ValueChanged<AgentThreadSummary> onArchiveThread;
  final ValueChanged<AgentThreadSummary> onUnarchiveThread;
  final ValueChanged<AgentThreadSummary> onDeleteThread;
  final ValueChanged<AgentThreadSummary> onForkThread;
  final ValueChanged<String> onDismissCompletedThread;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final thread in state.threads)
        _ThreadTile(
          projectPath: projectPath,
          thread:
              state.runningThreadIds.contains(thread.id) &&
                  thread.status != AgentThreadRuntimeStatus.active
              ? thread.copyWith(status: AgentThreadRuntimeStatus.active)
              : thread,
          selected: thread.id == state.selectedThreadId,
          showCompleted: state.completedThreadIds.contains(thread.id),
          archivedView: state.archived,
          capabilities: capabilitiesForProvider(thread.providerId),
          onTap: () => onSelectThread(projectPath, thread),
          onDismissCompleted: () => onDismissCompletedThread(thread.id),
          onRenameThread: onRenameThread,
          onArchiveThread: onArchiveThread,
          onUnarchiveThread: onUnarchiveThread,
          onDeleteThread: onDeleteThread,
          onForkThread: onForkThread,
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

enum _ThreadTileMenuAction { rename, archive, unarchive, fork, delete }

class _ThreadTile extends StatefulWidget {
  const _ThreadTile({
    required this.projectPath,
    required this.thread,
    required this.selected,
    required this.showCompleted,
    required this.archivedView,
    required this.capabilities,
    required this.onTap,
    required this.onDismissCompleted,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onUnarchiveThread,
    required this.onDeleteThread,
    required this.onForkThread,
  });

  final String projectPath;
  final AgentThreadSummary thread;
  final bool selected;

  /// 后台执行完毕且尚未确认时，在原 spinner 位置展示绿色完成 icon。
  final bool showCompleted;
  final bool archivedView;
  final AgentProviderCapabilities capabilities;
  final VoidCallback onTap;
  final VoidCallback onDismissCompleted;
  final void Function(String threadId, String name) onRenameThread;
  final ValueChanged<AgentThreadSummary> onArchiveThread;
  final ValueChanged<AgentThreadSummary> onUnarchiveThread;
  final ValueChanged<AgentThreadSummary> onDeleteThread;
  final ValueChanged<AgentThreadSummary> onForkThread;

  @override
  State<_ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<_ThreadTile> {
  static const double _actionIconSize = 14;

  IdePopoverHandle<void>? _popoverEntry;
  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;

  bool get _showActions => _hovered || _focused || _menuOpen;

  bool get _hasMenuActions {
    final capabilities = widget.capabilities;
    return capabilities.canRenameThread ||
        (widget.archivedView
            ? capabilities.canUnarchiveThread
            : capabilities.canArchiveThread) ||
        capabilities.canForkThread ||
        capabilities.canDeleteThread ||
        capabilities.canRemoveThreadFromList;
  }

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _popoverEntry = null;
    super.dispose();
  }

  void _toggleMoreMenu() {
    if (_menuOpen) {
      _dismissMoreMenu();
      return;
    }
    _showMoreMenu();
  }

  void _showMoreMenu() {
    if (_popoverEntry != null) {
      return;
    }
    setState(() {
      _menuOpen = true;
    });
    final thread = widget.thread;
    final entry = showIdePopover<void>(
      context: context,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      modal: false,
      builder: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 80, maxWidth: 200),
          child: IdeContextMenu(
            actions: [
              if (widget.capabilities.canRenameThread)
                IdeContextMenuAction(
                  key: ValueKey<String>(
                    'project-thread-rename-${widget.projectPath}-${thread.id}',
                  ),
                  label: '重命名',
                  onPressed: () =>
                      _handleMenuAction(_ThreadTileMenuAction.rename),
                ),
              if (widget.archivedView && widget.capabilities.canUnarchiveThread)
                IdeContextMenuAction(
                  key: ValueKey<String>(
                    'project-thread-unarchive-${widget.projectPath}-${thread.id}',
                  ),
                  label: '取消归档',
                  onPressed: () =>
                      _handleMenuAction(_ThreadTileMenuAction.unarchive),
                )
              else if (!widget.archivedView &&
                  widget.capabilities.canArchiveThread)
                IdeContextMenuAction(
                  key: ValueKey<String>(
                    'project-thread-archive-${widget.projectPath}-${thread.id}',
                  ),
                  label: '归档',
                  onPressed: () =>
                      _handleMenuAction(_ThreadTileMenuAction.archive),
                ),
              if (widget.capabilities.canForkThread)
                IdeContextMenuAction(
                  key: ValueKey<String>(
                    'project-thread-fork-${widget.projectPath}-${thread.id}',
                  ),
                  label: '分叉',
                  onPressed: () =>
                      _handleMenuAction(_ThreadTileMenuAction.fork),
                ),
              if (widget.capabilities.canDeleteThread ||
                  widget.capabilities.canRemoveThreadFromList)
                IdeContextMenuAction(
                  key: ValueKey<String>(
                    'project-thread-delete-${widget.projectPath}-${thread.id}',
                  ),
                  label: widget.capabilities.canDeleteThread
                      ? '删除'
                      : '仅从 Zeta 列表移除',
                  destructive: widget.capabilities.canDeleteThread,
                  dividerAbove: true,
                  onPressed: () =>
                      _handleMenuAction(_ThreadTileMenuAction.delete),
                ),
            ],
          ),
        );
      },
    );
    _popoverEntry = entry;
    entry.future.whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        if (identical(_popoverEntry, entry)) {
          _popoverEntry = null;
        }
        _menuOpen = false;
      });
    });
  }

  void _dismissMoreMenu() {
    final entry = _popoverEntry;
    if (entry == null) {
      return;
    }
    _popoverEntry = null;
    setState(() {
      _menuOpen = false;
    });
    entry.dismiss();
  }

  Future<void> _showRenameDialog() async {
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
    final deletesProviderHistory = widget.capabilities.canDeleteThread;
    final confirmed = await showIdeDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          key: ValueKey<String>(
            'project-thread-delete-dialog-${widget.projectPath}-${widget.thread.id}',
          ),
          title: Text(deletesProviderHistory ? '删除会话' : '从列表移除会话'),
          content: Text(
            deletesProviderHistory
                ? '此操作不可撤销，将永久删除该会话。'
                : '只会移除 Zeta 的本地索引记录，Cursor 端历史仍会保留。',
          ),
          actions: [
            IdeDialogAction.cancel(
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            if (deletesProviderHistory)
              IdeDialogAction.destructive(
                label: '删除',
                onPressed: () => Navigator.of(dialogContext).pop(true),
              )
            else
              IdeDialogAction.confirm(
                label: '移除',
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
        widget.onArchiveThread(widget.thread);
        return;
      case _ThreadTileMenuAction.unarchive:
        widget.onUnarchiveThread(widget.thread);
        return;
      case _ThreadTileMenuAction.fork:
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneInteractiveSurface(
          key: ValueKey<String>(
            'project-thread-${widget.projectPath}-${thread.id}',
          ),
          onPressed: widget.onTap,
          selected: widget.selected,
          padding: IdeSpacing.horizontal8,
          borderRadius: IdeRadius.allSmall,
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
              AgentProviderIcon(
                providerId: thread.providerId,
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
                IdeBusySpinner(
                  key: ValueKey<String>(
                    'project-thread-running-icon-${widget.projectPath}-${thread.id}',
                  ),
                  size: 12,
                  strokeWidth: 1.8,
                  semanticsLabel: 'Thread running',
                ),
              ] else if (widget.showCompleted) ...[
                const SizedBox(width: IdeSpacing.space8),
                IdeTooltip(
                  message: '执行完毕，点击关闭',
                  child: sf.IconButton.ghost(
                    key: ValueKey<String>(
                      'project-thread-completed-icon-${widget.projectPath}-${thread.id}',
                    ),
                    onPressed: widget.onDismissCompleted,
                    size: sf.ButtonSize.xSmall,
                    density: sf.ButtonDensity.iconDense,
                    icon: Icon(
                      Icons.check_circle_rounded,
                      size: 12,
                      color: colors.success,
                    ),
                  ),
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
                child: _showActions && _hasMenuActions
                    ? SizedBox(
                        key: ValueKey<String>(
                          'project-thread-actions-${widget.projectPath}-${thread.id}',
                        ),
                        width: IdeMetrics.iconButtonHitSize,
                        height: IdeMetrics.iconButtonHitSize,
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
                              color: _menuOpen
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      )
                    // 用 AnimatedSize 直接收展，避免 AnimatedSwitcher 在快速切换时堆叠旧 child。
                    : const SizedBox(
                        width: 0,
                        height: IdeMetrics.iconButtonHitSize,
                      ),
              ),
            ],
          ),
        ),
      ],
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
      padding: IdeSpacing.horizontal8,
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
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space4),
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
