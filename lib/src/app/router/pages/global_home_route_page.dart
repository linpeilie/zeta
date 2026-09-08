import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_home_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta_ui/zeta_ui.dart';

class GlobalHomeRoutePage extends ConsumerWidget {
  const GlobalHomeRoutePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoreCompleted = ref.watch(
      ideSessionSliceProvider.select((state) => state.initialRestoreCompleted),
    );
    if (!restoreCompleted) {
      final colors = IdeColors.of(context);
      return ColoredBox(
        key: const ValueKey<String>('global-home-restoring'),
        color: colors.canvasSurface,
        child: Center(child: IdeBusySpinner(size: 20, color: colors.accent)),
      );
    }

    final home = ref.watch(agentManagementHomeProvider);
    final shell = ref.read(workbenchSessionProvider).shell;
    return GlobalHomePage(
      installedProviders: home.installedProviders,
      onOpenProject: () => unawaited(shell.openProject()),
      isLoadingProviders: home.isLoading,
      providerError: home.detectionFailure == null
          ? null
          : context.l10n.workbenchProviderDetectionFailed(
              context.l10n.mgmtUnknownError,
            ),
    );
  }
}
