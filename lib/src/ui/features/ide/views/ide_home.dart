import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/workspace/presentation/file_tree_pane.dart';
import 'package:zeta/src/ui/core/ide_activity_rail.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_resize_handle.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/window_frame.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';

/// IDE 主界面。
///
/// 当前布局是左右图标栏、左右活动面板与中间 Agent 主编辑区组成的五列结构；
/// 具体项目、会话和 Agent thread 编排由 [IdeShellController] 承接。
class IdeHome extends StatefulWidget {
  const IdeHome({
    required this.directoryPicker,
    required this.enableNativeWindowFrame,
    required this.sessionStore,
    required this.agentProviderFactory,
    required this.agentProviderConfigStore,
    required this.projectLocationOpener,
    required this.appearanceController,
    this.showWindowControls = true,
    super.key,
  });

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionStore sessionStore;
  final AgentProviderFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;
  final ProjectLocationOpener projectLocationOpener;
  final AppearanceSettingsController appearanceController;
  final bool showWindowControls;

  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> {
  static const double _activityRailWidth = 36;
  static const double _initialPanelWidth = 260;
  static const double _minPanelWidth = 200;
  static const double _maxPanelWidth = 400;
  static const double _minMainEditorWidth = 320;
  static const double _rightOverlayBreakpoint = 1000;
  static const double _initialPanelRatio = 0.5;
  static const double _minPanelRatio = 0.1;
  static const double _maxPanelRatio = 0.9;

  late final IdeShellController _shellController;

  bool _leftTopVisible = true;
  bool _leftBottomVisible = false;
  bool _rightTopVisible = false;
  bool _rightBottomVisible = false;
  bool _rightOverlayOpen = false;
  double _leftPanelWidth = _initialPanelWidth;
  double _rightPanelWidth = _initialPanelWidth;
  double _leftTopRatio = _initialPanelRatio;
  double _rightTopRatio = _initialPanelRatio;
  sf.ToastOverlay? _statusToast;
  _IdeHomePage _page = _IdeHomePage.home;
  SettingsSection _settingsSection = SettingsSection.appearance;

  @override
  void initState() {
    super.initState();
    unawaited(widget.appearanceController.load());
    _shellController = IdeShellController(
      directoryPicker: widget.directoryPicker,
      sessionStore: widget.sessionStore,
      agentProviderFactory: widget.agentProviderFactory,
      agentProviderConfigStore: widget.agentProviderConfigStore,
      projectLocationOpener: widget.projectLocationOpener,
      statusReporter: _showStatus,
    )..addListener(_handleShellChanged);
    // 生产环境注册原生菜单的「打开项目」回调，与工具栏按钮走同一逻辑。
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(_handleMenuOpenProject);
    }
  }

  @override
  void dispose() {
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(null);
    }
    _shellController.removeListener(_handleShellChanged);
    _shellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = WindowFrame(
      enableNativeWindowFrame: widget.enableNativeWindowFrame,
      menus: _windowMenus,
      titleBarActions: <WindowTitleBarAction>[
        WindowTitleBarAction(
          key: const ValueKey('titlebar-settings-action'),
          icon: Icons.settings_rounded,
          tooltip: 'Settings',
          semanticLabel: 'Open settings page',
          active: _page == _IdeHomePage.settings,
          onPressed: _openSettingsPage,
        ),
      ],
      showWindowControls: widget.showWindowControls,
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space8),
        child: _buildPageBody(),
      ),
    );

    return body;
  }

  Widget _buildPageBody() {
    return switch (_page) {
      _IdeHomePage.home => LayoutBuilder(
        builder: (context, constraints) {
          return _buildIdeLayout(maxWidth: constraints.maxWidth);
        },
      ),
      _IdeHomePage.settings => SettingsPage(
        key: const ValueKey('settings-page'),
        activeSection: _settingsSection,
        appearanceController: widget.appearanceController,
        onBackPressed: _closeSettingsPage,
        onSectionSelected: (section) {
          setState(() {
            _settingsSection = section;
          });
        },
      ),
    };
  }

  List<WindowMenu> get _windowMenus {
    if (!widget.enableNativeWindowFrame ||
        !(Platform.isWindows || Platform.isLinux)) {
      return const <WindowMenu>[];
    }
    return [
      WindowMenu(
        key: const ValueKey('window-menu-file'),
        label: '文件',
        items: [
          WindowMenuItem(
            key: const ValueKey('window-menu-open-project'),
            label: '打开项目',
            onPressed: _handleMenuOpenProject,
          ),
          WindowMenuItem(
            key: const ValueKey('window-menu-exit'),
            label: '退出',
            onPressed: _handleMenuExit,
          ),
        ],
      ),
    ];
  }

  Widget _buildIdeLayout({required double maxWidth}) {
    final colors = IdeColors.of(context);
    final leftPanelVisible = _leftTopVisible || _leftBottomVisible;
    final rightPanelVisible = _rightTopVisible || _rightBottomVisible;
    final rightOverlayAvailableWidth =
        maxWidth - _activityRailWidth - IdeSpacing.space8;
    final useRightOverlay =
        rightOverlayAvailableWidth < _rightOverlayBreakpoint;
    final panelWidths = _effectivePanelWidths(
      maxWidth: maxWidth,
      leftPanelVisible: leftPanelVisible,
      rightPanelVisible: !useRightOverlay && rightPanelVisible,
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _activityRailWidth,
          child: IdeActivityRail(
            leadingActions: [
              IdeRailAction(
                key: const ValueKey('left-projects-action'),
                icon: Icons.account_tree_rounded,
                tooltip: 'Projects',
                semanticLabel: 'Toggle projects panel',
                active: _leftTopVisible,
                onPressed: () {
                  setState(() {
                    _leftTopVisible = !_leftTopVisible;
                  });
                },
              ),
            ],
            trailingActions: [
              IdeRailAction(
                key: const ValueKey('left-context-action'),
                icon: Icons.data_object_rounded,
                tooltip: 'Context',
                semanticLabel: 'Toggle context panel',
                active: _leftBottomVisible,
                onPressed: () {
                  setState(() {
                    _leftBottomVisible = !_leftBottomVisible;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: IdeSpacing.space8),
        if (leftPanelVisible) ...[
          SizedBox(
            key: const ValueKey('left-activity-panel'),
            width: panelWidths.left,
            child: _ResizableColumn(
              topVisible: _leftTopVisible,
              bottomVisible: _leftBottomVisible,
              topRatio: _leftTopRatio,
              onTopRatioChanged: (ratio) {
                setState(() {
                  _leftTopRatio = ratio.clamp(_minPanelRatio, _maxPanelRatio);
                });
              },
              heightHandleKey: const ValueKey('left-height-resize-handle'),
              top: _buildProjectsPanel(),
              bottom: _buildPlaceholderPanel(
                key: const ValueKey('context-panel-card'),
                title: 'Context',
                icon: Icons.hub_rounded,
                message: 'No file context',
              ),
            ),
          ),
          IdeResizeHandle(
            key: const ValueKey('left-width-resize-handle'),
            axis: IdeResizeHandleAxis.horizontal,
            semanticLabel: 'Resize left panel width',
            onDragUpdate: (details) {
              setState(() {
                _leftPanelWidth = (_leftPanelWidth + details.delta.dx).clamp(
                  _minPanelWidth,
                  _maxPanelWidth,
                );
              });
            },
          ),
        ],
        Expanded(
          child: PanelCard(
            key: const ValueKey('agent-pane-host'),
            color: colors.editor,
            showBorder: false,
            child: AgentPane(viewModel: _shellController.agentViewModel),
          ),
        ),
        if (!useRightOverlay && rightPanelVisible) ...[
          IdeResizeHandle(
            key: const ValueKey('right-width-resize-handle'),
            axis: IdeResizeHandleAxis.horizontal,
            semanticLabel: 'Resize right panel width',
            onDragUpdate: (details) {
              setState(() {
                _rightPanelWidth = (_rightPanelWidth - details.delta.dx).clamp(
                  _minPanelWidth,
                  _maxPanelWidth,
                );
              });
            },
          ),
          SizedBox(
            key: const ValueKey('right-activity-panel'),
            width: panelWidths.right,
            child: _buildRightPanel(),
          ),
        ],
        const SizedBox(width: IdeSpacing.space8),
        SizedBox(
          width: _activityRailWidth,
          child: IdeActivityRail(
            leadingActions: [
              IdeRailAction(
                key: const ValueKey('right-files-action'),
                icon: Icons.folder_rounded,
                tooltip: 'Files',
                semanticLabel: 'Toggle files panel',
                active: _rightTopVisible,
                onPressed: () {
                  _toggleRightPanel(isTop: true, useOverlay: useRightOverlay);
                },
              ),
            ],
            trailingActions: [
              IdeRailAction(
                key: const ValueKey('right-tools-action'),
                icon: Icons.build_circle_rounded,
                tooltip: 'Tools',
                semanticLabel: 'Toggle tools panel',
                active: _rightBottomVisible,
                onPressed: () {
                  _toggleRightPanel(isTop: false, useOverlay: useRightOverlay);
                },
              ),
            ],
          ),
        ),
      ],
    );

    if (!useRightOverlay || !_rightOverlayOpen || !rightPanelVisible) {
      return content;
    }

    final overlayWidth = _rightPanelWidth.clamp(_minPanelWidth, _maxPanelWidth);
    final rightInset = _activityRailWidth + IdeSpacing.space8;
    final brightness = sf.Theme.of(context).brightness;
    return Stack(
      children: [
        content,
        Positioned.fill(
          right: rightInset,
          child: GestureDetector(
            key: const ValueKey('right-overlay-scrim'),
            behavior: HitTestBehavior.translucent,
            onTap: _closeRightOverlay,
            child: ColoredBox(color: IdeEffects.scrim(brightness)),
          ),
        ),
        Positioned(
          key: const ValueKey('right-activity-overlay'),
          top: 0,
          right: rightInset,
          bottom: 0,
          width: overlayWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: IdeRadius.allMedium,
              boxShadow: IdeEffects.overlayShadow(brightness),
            ),
            child: _buildRightPanel(),
          ),
        ),
      ],
    );
  }

  _PanelWidths _effectivePanelWidths({
    required double maxWidth,
    required bool leftPanelVisible,
    required bool rightPanelVisible,
  }) {
    var leftWidth = _leftPanelWidth;
    var rightWidth = _rightPanelWidth;
    final visiblePanels =
        (leftPanelVisible ? 1 : 0) + (rightPanelVisible ? 1 : 0);
    if (visiblePanels == 0 || !maxWidth.isFinite) {
      return _PanelWidths(left: leftWidth, right: rightWidth);
    }

    final fixedWidth =
        (_activityRailWidth * 2) +
        (IdeSpacing.space8 * 2) +
        (leftPanelVisible ? IdeSpacing.space8 : 0) +
        (rightPanelVisible ? IdeSpacing.space8 : 0);
    final availablePanelWidth = maxWidth - fixedWidth - _minMainEditorWidth;
    final minimumPanelWidth = _minPanelWidth * visiblePanels;

    if (availablePanelWidth < minimumPanelWidth) {
      if (leftPanelVisible) {
        leftWidth = _minPanelWidth;
      }
      if (rightPanelVisible) {
        rightWidth = _minPanelWidth;
      }
      return _PanelWidths(left: leftWidth, right: rightWidth);
    }

    if (visiblePanels == 1) {
      if (leftPanelVisible) {
        leftWidth = leftWidth.clamp(_minPanelWidth, availablePanelWidth);
      }
      if (rightPanelVisible) {
        rightWidth = rightWidth.clamp(_minPanelWidth, availablePanelWidth);
      }
      return _PanelWidths(left: leftWidth, right: rightWidth);
    }

    final requestedPanelWidth = leftWidth + rightWidth;
    if (requestedPanelWidth <= availablePanelWidth) {
      return _PanelWidths(left: leftWidth, right: rightWidth);
    }

    final extraWidth = availablePanelWidth - minimumPanelWidth;
    final requestedExtraWidth =
        (leftWidth - _minPanelWidth) + (rightWidth - _minPanelWidth);
    if (requestedExtraWidth <= 0) {
      return _PanelWidths(left: _minPanelWidth, right: _minPanelWidth);
    }

    final shrinkRatio = extraWidth / requestedExtraWidth;
    leftWidth = _minPanelWidth + ((leftWidth - _minPanelWidth) * shrinkRatio);
    rightWidth = _minPanelWidth + ((rightWidth - _minPanelWidth) * shrinkRatio);
    return _PanelWidths(left: leftWidth, right: rightWidth);
  }

  Widget _buildProjectsPanel() {
    return PanelCard(
      key: const ValueKey('projects-panel-card'),
      showBorder: false,
      child: ProjectListPane(
        projects: _shellController.projects,
        activeProject: _shellController.activeProjectPath,
        threadStateFor: _shellController.projectThreadStateFor,
        onOpenProject: _openProject,
        onSelectProject: (path) {
          unawaited(_shellController.selectKnownProject(path));
        },
        onSelectThread: (projectPath, thread) {
          unawaited(_shellController.selectProjectThread(projectPath, thread));
        },
        onLoadMoreThreads: (projectPath) {
          unawaited(_shellController.loadMoreThreads(projectPath));
        },
        onRetryThreads: (projectPath) {
          unawaited(_shellController.retryThreads(projectPath));
        },
        onNewThread: (projectPath) {
          unawaited(_shellController.startNewThreadForProject(projectPath));
        },
        onOpenProjectLocation: (projectPath) {
          unawaited(
            _shellController.openProjectInSystemFileManager(projectPath),
          );
        },
        onRemoveProject: (projectPath) {
          unawaited(_shellController.removeProject(projectPath));
        },
        onSearchTermChanged: (projectPath, searchTerm) {
          _shellController.setThreadSearchTerm(projectPath, searchTerm);
        },
        onArchivedViewChanged: (projectPath, archived) {
          unawaited(
            _shellController.setThreadArchivedView(projectPath, archived),
          );
        },
        onRenameThread: (projectPath, threadId, name) {
          unawaited(
            _shellController.renameProjectThread(projectPath, threadId, name),
          );
        },
        onArchiveThread: (projectPath, thread) {
          unawaited(_shellController.archiveProjectThread(projectPath, thread));
        },
        onUnarchiveThread: (projectPath, thread) {
          unawaited(
            _shellController.unarchiveProjectThread(projectPath, thread),
          );
        },
        onDeleteThread: (projectPath, thread) {
          unawaited(_shellController.deleteProjectThread(projectPath, thread));
        },
        onForkThread: (projectPath, thread) {
          unawaited(_shellController.forkProjectThread(projectPath, thread));
        },
      ),
    );
  }

  Widget _buildFilesPanel() {
    return PanelCard(
      key: const ValueKey('files-panel-card'),
      showBorder: false,
      child: FileTreePane(
        nodes: _shellController.workspaceTree,
        expandedPaths: _shellController.expandedDirectoryPaths,
        selectedPath: _shellController.selectedTreePath,
        projectPath: _shellController.activeProjectPath,
        isLoading: _shellController.isLoadingProject,
        onNodeTap: _shellController.handleTreeNodeTap,
        onExpansionChanged: _shellController.handleTreeExpansionChanged,
      ),
    );
  }

  Widget _buildRightPanel() {
    return _ResizableColumn(
      topVisible: _rightTopVisible,
      bottomVisible: _rightBottomVisible,
      topRatio: _rightTopRatio,
      onTopRatioChanged: (ratio) {
        setState(() {
          _rightTopRatio = ratio.clamp(_minPanelRatio, _maxPanelRatio);
        });
      },
      heightHandleKey: const ValueKey('right-height-resize-handle'),
      top: _buildFilesPanel(),
      bottom: _buildPlaceholderPanel(
        key: const ValueKey('tools-panel-card'),
        title: 'Tools',
        icon: Icons.terminal_rounded,
        message: 'No tools running',
      ),
    );
  }

  Widget _buildPlaceholderPanel({
    required Key key,
    required String title,
    required IconData icon,
    required String message,
  }) {
    final colors = IdeColors.of(context);
    return PanelCard(
      key: key,
      showBorder: false,
      child: Pane(
        title: title,
        trailing: Icon(icon, size: 16, color: colors.mutedText),
        child: EmptyState(text: message),
      ),
    );
  }

  void _openProject() {
    unawaited(_shellController.openProject());
  }

  void _toggleRightPanel({required bool isTop, required bool useOverlay}) {
    setState(() {
      if (!useOverlay) {
        if (isTop) {
          _rightTopVisible = !_rightTopVisible;
        } else {
          _rightBottomVisible = !_rightBottomVisible;
        }
        return;
      }

      final currentlyVisible = isTop ? _rightTopVisible : _rightBottomVisible;
      final otherVisible = isTop ? _rightBottomVisible : _rightTopVisible;
      if (_rightOverlayOpen && currentlyVisible && !otherVisible) {
        if (isTop) {
          _rightTopVisible = false;
        } else {
          _rightBottomVisible = false;
        }
        _rightOverlayOpen = false;
        return;
      }

      if (_rightOverlayOpen && currentlyVisible) {
        if (isTop) {
          _rightTopVisible = false;
        } else {
          _rightBottomVisible = false;
        }
        _rightOverlayOpen = _rightTopVisible || _rightBottomVisible;
        return;
      }

      if (isTop) {
        _rightTopVisible = true;
      } else {
        _rightBottomVisible = true;
      }
      _rightOverlayOpen = true;
    });
  }

  void _closeRightOverlay() {
    if (!_rightOverlayOpen) {
      return;
    }
    setState(() {
      _rightOverlayOpen = false;
    });
  }

  /// 标题栏 / 原生菜单「文件 - 打开项目」入口，与工具栏按钮一致。
  void _handleMenuOpenProject() {
    _openProject();
  }

  void _handleMenuExit() {
    unawaited(windowManager.close());
  }

  void _handleShellChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showStatus(String message) {
    if (!mounted) {
      return;
    }
    // 连续状态提示只保留最新一条，避免右下角堆叠。
    _statusToast?.close();
    _statusToast = showIdeToast(
      context,
      message: message,
      showDuration: const Duration(seconds: 2),
    );
  }

  void _openSettingsPage() {
    if (_page == _IdeHomePage.settings) {
      return;
    }
    setState(() {
      _page = _IdeHomePage.settings;
      _settingsSection = SettingsSection.appearance;
    });
  }

  void _closeSettingsPage() {
    if (_page == _IdeHomePage.home) {
      return;
    }
    setState(() {
      _page = _IdeHomePage.home;
    });
  }
}

enum _IdeHomePage { home, settings }

class _PanelWidths {
  const _PanelWidths({required this.left, required this.right});

  final double left;
  final double right;
}

class _ResizableColumn extends StatelessWidget {
  const _ResizableColumn({
    required this.topVisible,
    required this.bottomVisible,
    required this.topRatio,
    required this.onTopRatioChanged,
    required this.top,
    required this.bottom,
    required this.heightHandleKey,
  });

  final bool topVisible;
  final bool bottomVisible;
  final double topRatio;
  final ValueChanged<double> onTopRatioChanged;
  final Widget top;
  final Widget bottom;
  final Key heightHandleKey;

  @override
  Widget build(BuildContext context) {
    if (topVisible && !bottomVisible) {
      return SizedBox.expand(child: top);
    }
    if (!topVisible && bottomVisible) {
      return SizedBox.expand(child: bottom);
    }
    if (!topVisible && !bottomVisible) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final resizableHeight = constraints.maxHeight - IdeSpacing.space8;
        final topHeight = resizableHeight * topRatio.clamp(0.1, 0.9);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topHeight, child: top),
            IdeResizeHandle(
              key: heightHandleKey,
              axis: IdeResizeHandleAxis.vertical,
              semanticLabel: 'Resize panel height',
              onDragUpdate: (details) {
                onTopRatioChanged(
                  (topHeight + details.delta.dy) / resizableHeight,
                );
              },
            ),
            Expanded(child: bottom),
          ],
        );
      },
    );
  }
}
