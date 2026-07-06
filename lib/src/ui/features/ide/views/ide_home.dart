import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';

import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/workspace/presentation/file_tree_pane.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/window_frame.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';

/// IDE 主界面。
///
/// 当前布局是 Projects / Agent / Files 三栏；具体项目、会话和 Agent thread
/// 编排由 [IdeShellController] 承接。
class IdeHome extends StatefulWidget {
  const IdeHome({
    required this.directoryPicker,
    required this.enableNativeWindowFrame,
    required this.sessionStore,
    required this.agentProviderFactory,
    required this.agentProviderConfigStore,
    super.key,
  });

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionStore sessionStore;
  final AgentProviderFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;

  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> {
  late final IdeShellController _shellController;
  late final MultiSplitViewController _splitController;

  @override
  void initState() {
    super.initState();
    _shellController = IdeShellController(
      directoryPicker: widget.directoryPicker,
      sessionStore: widget.sessionStore,
      agentProviderFactory: widget.agentProviderFactory,
      agentProviderConfigStore: widget.agentProviderConfigStore,
      statusReporter: _showStatus,
    )..addListener(_handleShellChanged);
    _splitController = MultiSplitViewController(
      areas: [
        Area(id: 'projects', size: 220, min: 180, max: 340),
        Area(id: 'agent', flex: 1, min: 360),
        Area(id: 'files', size: 280, min: 220, max: 460),
      ],
    );
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
    _splitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = WindowFrame(
      enableNativeWindowFrame: widget.enableNativeWindowFrame,
      child: Padding(
        padding: const EdgeInsets.only(
          left: idePanelGap,
          right: idePanelGap,
          bottom: idePanelGap,
        ),
        child: MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerThickness: idePanelGap,
            dividerPainter: DividerPainters.background(
              color: ideFrameColor,
              highlightedColor: ideFrameColor,
            ),
          ),
          child: MultiSplitView(
            controller: _splitController,
            axis: Axis.horizontal,
            pushDividers: true,
            builder: _buildSplitArea,
          ),
        ),
      ),
    );

    return Scaffold(body: body);
  }

  Widget _buildSplitArea(BuildContext context, Area area) {
    return switch (area.id) {
      'projects' => PanelCard(
        key: const ValueKey('projects-panel-card'),
        child: ProjectListPane(
          projects: _shellController.projects,
          activeProject: _shellController.activeProjectPath,
          threadStateFor: _shellController.projectThreadStateFor,
          onOpenProject: _openProject,
          onSelectProject: (path) {
            unawaited(_shellController.selectKnownProject(path));
          },
          onSelectThread: (projectPath, thread) {
            unawaited(
              _shellController.selectProjectThread(projectPath, thread),
            );
          },
          onLoadMoreThreads: (projectPath) {
            unawaited(_shellController.loadMoreThreads(projectPath));
          },
          onRetryThreads: (projectPath) {
            unawaited(_shellController.retryThreads(projectPath));
          },
        ),
      ),
      'files' => PanelCard(
        key: const ValueKey('files-panel-card'),
        child: FileTreePane(
          controller: _shellController.treeController,
          projectPath: _shellController.activeProjectPath,
          isLoading: _shellController.isLoadingProject,
          onNodeTap: _shellController.handleTreeNodeTap,
          onExpansionChanged: _shellController.handleTreeExpansionChanged,
        ),
      ),
      _ => ColoredBox(
        key: const ValueKey('agent-pane-host'),
        color: ideFrameColor,
        child: AgentPane(viewModel: _shellController.agentViewModel),
      ),
    };
  }

  void _openProject() {
    unawaited(_shellController.openProject());
  }

  /// 原生菜单「文件 - 打开项目」入口，与工具栏按钮一致。
  void _handleMenuOpenProject() {
    _openProject();
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
