import 'package:zeta/src/features/agent/domain/agent_permission_models.dart';
import 'package:zeta/src/features/agent/domain/agent_tool_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_navigation.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

extension AgentToolKindL10n on AgentToolKind {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentToolKind.read => l10n.agentToolRead,
    AgentToolKind.edit => l10n.agentToolEdit,
    AgentToolKind.delete => l10n.agentToolDelete,
    AgentToolKind.move => l10n.agentToolMove,
    AgentToolKind.search => l10n.agentToolSearch,
    AgentToolKind.execute => l10n.agentToolExecute,
    AgentToolKind.think => l10n.agentToolThink,
    AgentToolKind.fetch => l10n.agentToolFetch,
    AgentToolKind.other => l10n.agentToolOther,
  };
}

extension AgentPermissionKindL10n on AgentPermissionKind {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentPermissionKind.commandExecution => l10n.agentPermKindCommand,
    AgentPermissionKind.fileChange => l10n.agentPermKindFile,
    AgentPermissionKind.permissions => l10n.agentPermKindPermissions,
    AgentPermissionKind.other => l10n.agentPermKindOther,
  };

  String localizedShortLabel(AppLocalizations l10n) => switch (this) {
    AgentPermissionKind.commandExecution => l10n.agentPermShortCommand,
    AgentPermissionKind.fileChange => l10n.agentPermShortFile,
    AgentPermissionKind.permissions => l10n.agentPermShortPermissions,
    AgentPermissionKind.other => l10n.agentPermShortOther,
  };
}

extension AgentPlanEntryStatusL10n on AgentPlanEntryStatus {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentPlanEntryStatus.completed => l10n.agentPlanCompleted,
    AgentPlanEntryStatus.inProgress => l10n.agentPlanInProgress,
    AgentPlanEntryStatus.pending => l10n.agentPlanPending,
    AgentPlanEntryStatus.unknown => l10n.agentPlanUnknown,
  };
}

extension AgentConversationNavigationStatusL10n
    on AgentConversationNavigationStatus {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentConversationNavigationStatus.streaming => l10n.agentStatusStreaming,
    AgentConversationNavigationStatus.completed => l10n.agentStatusCompleted,
    AgentConversationNavigationStatus.failed => l10n.agentStatusFailed,
    AgentConversationNavigationStatus.interrupted =>
      l10n.agentStatusInterrupted,
    AgentConversationNavigationStatus.unknown => l10n.agentStatusUnknown,
  };
}

extension AgentFileChangeKindL10n on AgentFileChangeKind {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentFileChangeKind.created => l10n.agentFileCreated,
    AgentFileChangeKind.modified => l10n.agentFileModified,
    AgentFileChangeKind.deleted => l10n.agentFileDeleted,
    AgentFileChangeKind.moved => l10n.agentFileMoved,
    AgentFileChangeKind.unknown => l10n.agentFileChanged,
  };
}

extension AgentToolStatusL10n on AgentToolStatus {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentToolStatus.pending => l10n.agentToolPending,
    AgentToolStatus.inProgress => l10n.agentToolInProgress,
    AgentToolStatus.completed => l10n.agentToolCompleted,
    AgentToolStatus.failed => l10n.agentToolFailed,
    AgentToolStatus.cancelled => l10n.agentToolCancelled,
  };
}
