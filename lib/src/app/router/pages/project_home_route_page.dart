import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/composition/zeta_environment_providers.dart';
import 'package:zeta/src/app/router/app_route_context.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_slice/project_threads_slice_providers.dart';
import 'package:zeta/src/ui/features/ide/views/project_home_page.dart';

class ProjectHomeRoutePage extends ConsumerWidget {
  const ProjectHomeRoutePage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectPath = ref.watch(
      projectIdMappingProvider.select(
        (mapping) => mapping.pathForId(projectId),
      ),
    );
    if (projectPath == null) {
      return const SizedBox.shrink();
    }
    final threadState = ref.watch(projectThreadListStateProvider(projectPath));
    final shell = ref.read(workbenchSessionProvider).shell;
    return ProjectHomePage(
      projectPath: projectPath,
      threadState: threadState,
      loadAvailableProviders: () {
        final injected = ref.read(agentProviderAvailabilityLoaderProvider);
        if (injected != null) {
          return injected();
        }
        return ref
            .read(agentManagementOperationsProvider)
            .loadAvailableThreadProviders();
      },
      onNewThread: (providerId) =>
          context.goLocation(DraftThreadLocation(projectId, providerId)),
      onSelectThread: (thread) =>
          context.goLocation(ThreadLocation(projectId, thread.id)),
      onRetryThreads: () => unawaited(shell.retryThreads(projectPath)),
    );
  }
}
