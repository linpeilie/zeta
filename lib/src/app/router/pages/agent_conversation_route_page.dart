import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
import 'package:zeta/src/app/router/app_route_context.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/pages/conversation_route_chrome.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/route_reconcile_status.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_slice/project_threads_slice_providers.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

class AgentConversationRoutePage extends ConsumerStatefulWidget {
  const AgentConversationRoutePage({
    required this.projectId,
    required this.threadId,
    super.key,
  });

  final String projectId;
  final String threadId;

  @override
  ConsumerState<AgentConversationRoutePage> createState() =>
      _AgentConversationRoutePageState();
}

class _AgentConversationRoutePageState
    extends ConsumerState<AgentConversationRoutePage> {
  Timer? _spinnerTimer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _armSpinner();
  }

  @override
  void didUpdateWidget(covariant AgentConversationRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.threadId != widget.threadId) {
      _armSpinner();
    }
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    super.dispose();
  }

  void _armSpinner() {
    _spinnerTimer?.cancel();
    _showSpinner = false;
    _spinnerTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _showSpinner = true);
      }
    });
  }

  void _disarmSpinner() {
    _spinnerTimer?.cancel();
    _spinnerTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final shortcut = ref.watch(
      generalSettingsSliceValueProvider.select(
        (settings) => settings.sendMessageShortcut,
      ),
    );
    final restoreCompleted = ref.watch(
      ideSessionSliceProvider.select((state) => state.initialRestoreCompleted),
    );
    if (!restoreCompleted) {
      return ConversationSkeletonPage(
        title: context.l10n.conversationLoadingTitle,
        showSpinner: _showSpinner,
      );
    }

    final projectPath = ref.watch(
      projectIdMappingProvider.select(
        (mapping) => mapping.pathForId(widget.projectId),
      ),
    );
    if (projectPath == null) {
      return const SizedBox.shrink();
    }

    final entryState = ref.watch(
      agentConversationWorkspaceProvider.select((state) {
        for (final entry in state.entries) {
          if (entry.projectPath == projectPath &&
              entry.threadId == widget.threadId) {
            return entry;
          }
        }
        return null;
      }),
    );
    if (entryState != null) {
      _disarmSpinner();
      final resources = ref
          .read(agentConversationWorkspaceProvider.notifier)
          .entryById(entryState.entryId);
      return AgentPane(
        controller: resources.controller,
        messageSendShortcut: shortcut,
      );
    }

    final target = ThreadLocation(widget.projectId, widget.threadId);
    final status = ref.watch(routerReconcileStatusProvider);
    if (status is RouteReconcileFailed && status.location == target) {
      _disarmSpinner();
      return ConversationOpenFailedPage(
        onBack: () => context.goLocation(ProjectHomeLocation(widget.projectId)),
      );
    }

    final summary = ref.watch(
      projectThreadListStateProvider(projectPath).select((state) {
        for (final thread in state.threads) {
          if (thread.id == widget.threadId) {
            return thread;
          }
        }
        return null;
      }),
    );
    return ConversationSkeletonPage(
      title: summary?.title ?? context.l10n.conversationLoadingTitle,
      showSpinner: _showSpinner,
    );
  }
}
