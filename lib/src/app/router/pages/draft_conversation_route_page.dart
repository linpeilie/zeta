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
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

class DraftConversationRoutePage extends ConsumerStatefulWidget {
  const DraftConversationRoutePage({
    required this.projectId,
    required this.providerId,
    super.key,
  });

  final String projectId;
  final String providerId;

  @override
  ConsumerState<DraftConversationRoutePage> createState() =>
      _DraftConversationRoutePageState();
}

class _DraftConversationRoutePageState
    extends ConsumerState<DraftConversationRoutePage> {
  Timer? _spinnerTimer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _armSpinner();
  }

  @override
  void didUpdateWidget(covariant DraftConversationRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.providerId != widget.providerId) {
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
        final matches = state.entries.where(
          (entry) =>
              entry.projectPath == projectPath &&
              entry.providerId == widget.providerId,
        );
        for (final entry in matches) {
          if (entry.isDraft) {
            return entry;
          }
        }
        for (final entry in matches) {
          if (entry.entryId == state.selectedEntryId) {
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

    final target = DraftThreadLocation(widget.projectId, widget.providerId);
    final status = ref.watch(routerReconcileStatusProvider);
    if (status is RouteReconcileFailed && status.location == target) {
      _disarmSpinner();
      return ConversationOpenFailedPage(
        onBack: () => context.goLocation(ProjectHomeLocation(widget.projectId)),
      );
    }

    return ConversationSkeletonPage(
      title: context.l10n.conversationLoadingTitle,
      showSpinner: _showSpinner,
    );
  }
}
