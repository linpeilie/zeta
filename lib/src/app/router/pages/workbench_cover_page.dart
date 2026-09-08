import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/router/app_route_context.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// 根导航覆盖页共用窗口 chrome；壳内内容保持挂载。
class WorkbenchCoverPage extends ConsumerWidget {
  const WorkbenchCoverPage({
    required this.location,
    required this.child,
    this.navigationPane,
    super.key,
  });
  final AppRouteLocation location;
  final Widget child;
  final Widget? navigationPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowHost = ref.read(zetaWindowHostProvider);
    return FocusScope(
      autofocus: true,
      child: WindowFrame(
        brandLogo: SvgPicture.asset(brandingLogoAsset),
        key: const ValueKey('ide-window-frame'),
        enableNativeWindowFrame: windowHost.rendersNativeChrome,
        menus: _windowMenus(context, ref, windowHost),
        titleBarLeadingActions: <WindowTitleBarAction>[
          WindowTitleBarAction(
            key: const ValueKey('titlebar-back-action'),
            icon: Icons.arrow_back_rounded,
            tooltip: context.l10n.workbenchBackToHome,
            semanticLabel: context.l10n.workbenchBackToHome,
            onPressed: () => _leave(context),
          ),
        ],
        titleBarActions: <WindowTitleBarAction>[
          WindowTitleBarAction(
            key: const ValueKey('titlebar-usage-statistics-action'),
            icon: sf.LucideIcons.chartLine,
            tooltip: context.l10n.workbenchUsageStatistics,
            semanticLabel: context.l10n.workbenchOpenUsageStatistics,
            active: location is UsageLocation,
            onPressed: () {
              if (location is! UsageLocation) {
                context.replaceLocation(const UsageLocation());
              }
            },
          ),
          WindowTitleBarAction(
            key: const ValueKey('titlebar-settings-action'),
            icon: sf.RadixIcons.mixerHorizontal,
            tooltip: 'Settings',
            semanticLabel: context.l10n.workbenchOpenSettings,
            active: location is SettingsLocation,
            onPressed: () {
              if (location is! SettingsLocation) {
                context.replaceLocation(
                  const SettingsLocation(SettingsSection.general),
                );
              }
            },
          ),
          WindowTitleBarAction(
            key: const ValueKey('titlebar-right-sidebar-action'),
            icon: sf.LucideIcons.panelRightOpen,
            tooltip: context.l10n.workbenchRightSidebarHomeOnly,
            semanticLabel: context.l10n.workbenchRightSidebarHomeOnly,
            enabled: false,
            onPressed: () {},
          ),
        ],
        showWindowControls: windowHost.showsWindowControls,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IdeSpacing.space8,
            IdeSpacing.space0,
            IdeSpacing.space8,
            IdeSpacing.space8,
          ),
          child: IdeWorkbenchScaffold(
            key: const ValueKey('ide-workbench'),
            navigationPane: navigationPane,
            navigationVisible: navigationPane != null,
            navigationInlineInCompact: true,
            navigationWidth: IdeMetrics.sidePaneDefaultWidth,
            canvas: child,
            inspectorVisible: false,
          ),
        ),
      ),
    );
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.goLocation(const GlobalHomeLocation());
  }

  List<WindowMenu> _windowMenus(
    BuildContext context,
    WidgetRef ref,
    ZetaWindowHost windowHost,
  ) {
    if (!windowHost.rendersNativeChrome) {
      return const <WindowMenu>[];
    }
    final l10n = context.l10n;
    return [
      WindowMenu(
        key: const ValueKey('window-menu-file'),
        label: l10n.workbenchMenuFile,
        items: [
          WindowMenuItem(
            key: const ValueKey('window-menu-open-project'),
            label: l10n.workbenchMenuOpenProject,
            onPressed: () {
              unawaited(ref.read(workbenchSessionProvider).shell.openProject());
            },
          ),
          WindowMenuItem(
            key: const ValueKey('window-menu-exit'),
            label: l10n.workbenchMenuQuit,
            onPressed: () {
              unawaited(windowHost.closeWindow());
            },
          ),
        ],
      ),
    ];
  }
}
