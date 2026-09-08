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

class ConversationRoutePage extends ConsumerStatefulWidget {
  const ConversationRoutePage({required this.location, super.key});

  final AppRouteLocation location;

  String get projectId => switch (location) {
    ThreadLocation(:final projectId) ||
    DraftThreadLocation(:final projectId) => projectId,
    _ => throw StateError('Expected a conversation route'),
  };

  @override
  ConsumerState<ConversationRoutePage> createState() =>
      _ConversationRoutePageState();
}

class _ConversationRoutePageState extends ConsumerState<ConversationRoutePage> {
  Timer? _spinnerTimer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _armSpinner();
  }

  @override
  void didUpdateWidget(covariant ConversationRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
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
              switch (widget.location) {
                ThreadLocation(:final threadId) => entry.threadId == threadId,
                DraftThreadLocation(:final providerId) =>
                  entry.isDraft && entry.providerId == providerId,
                _ => false,
              }) {
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
        key: ObjectKey(resources.controller),
        controller: resources.controller,
        messageSendShortcut: shortcut,
      );
    }

    final target = widget.location;
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
          if (target is ThreadLocation && thread.id == target.threadId) {
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
