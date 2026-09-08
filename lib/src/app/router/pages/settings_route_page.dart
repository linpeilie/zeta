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
import 'package:zeta/src/app/router/settings_route_intents.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// 根导航上的全屏设置页。盖住 IdeHome，不替换壳；分区来自路由参数。
class SettingsRoutePage extends ConsumerWidget {
  const SettingsRoutePage({required this.section, super.key});

  final SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowHost = ref.read(zetaWindowHostProvider);
    return WindowFrame(
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
          onPressed: () {
            ref
                .read(openUsageStatisticsAfterSettingsProvider.notifier)
                .request();
            _leave(context);
          },
        ),
        WindowTitleBarAction(
          key: const ValueKey('titlebar-settings-action'),
          icon: sf.RadixIcons.mixerHorizontal,
          tooltip: 'Settings',
          semanticLabel: context.l10n.workbenchOpenSettings,
          active: true,
          onPressed: () {},
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
          navigationPane: SettingsNavigationPane(
            activeSection: section,
            showAgentManagement: true,
            onSectionSelected: (next) {
              if (next == section) {
                return;
              }
              context.replaceLocation(SettingsLocation(next));
            },
          ),
          navigationVisible: true,
          navigationInlineInCompact: true,
          navigationWidth: IdeMetrics.sidePaneDefaultWidth,
          canvas: SettingsPageCanvas(
            activeSection: section,
            showAgentManagement: true,
          ),
          inspectorVisible: false,
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
