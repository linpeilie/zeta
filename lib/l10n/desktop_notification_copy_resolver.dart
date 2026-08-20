import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:zeta/l10n/gen/app_localizations.dart';

/// Safe localized values to be translated into a notification request by the
/// owning feature boundary.
final class DesktopNotificationCopy {
  /// Creates safe desktop notification copy.
  const DesktopNotificationCopy({
    required this.title,
    required this.body,
    required this.tag,
  });

  /// Localized title.
  final String title;

  /// Localized body containing only the project directory name.
  final String body;

  /// Stable replacement/grouping identifier.
  final String tag;
}

/// Resolves safe, already-localized desktop notification copy.
///
/// The resolver is created from the locale frozen during bootstrap and never
/// reads a build context or provider diagnostic payload.
final class DesktopNotificationCopyResolver {
  /// Creates a resolver for one already-frozen localization instance.
  const DesktopNotificationCopyResolver(this._l10n);

  final AppLocalizations _l10n;

  /// The localized default action label used by Linux notifications.
  String get linuxActionName => _l10n.desktopAttentionLinuxAction;

  /// Resolves one provider-neutral attention signal into safe display copy.
  DesktopNotificationCopy resolve(AgentWorkspaceAttention attention) {
    final projectName = _projectName(attention.projectPath);
    return DesktopNotificationCopy(
      title: _titleFor(attention.signal.kind),
      body: _l10n.desktopAttentionSessionBody(projectName),
      tag: attention.identity,
    );
  }

  String _titleFor(AgentAttentionKind kind) => switch (kind) {
    AgentAttentionKind.turnCompleted => _l10n.desktopAttentionTurnCompleted,
    AgentAttentionKind.turnFailed => _l10n.desktopAttentionTurnFailed,
    AgentAttentionKind.turnInterrupted => _l10n.desktopAttentionTurnInterrupted,
    AgentAttentionKind.permissionRequired =>
      _l10n.desktopAttentionPermissionRequired,
    AgentAttentionKind.questionRequired =>
      _l10n.desktopAttentionQuestionRequired,
    AgentAttentionKind.planApprovalRequired =>
      _l10n.desktopAttentionPlanApprovalRequired,
    AgentAttentionKind.planExecutionRequired =>
      _l10n.desktopAttentionPlanExecutionRequired,
  };

  String _projectName(String projectPath) {
    final segments = projectPath
        .replaceAll(r'\', '/')
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty
        ? _l10n.desktopAttentionCurrentProject
        : segments.last;
  }
}
