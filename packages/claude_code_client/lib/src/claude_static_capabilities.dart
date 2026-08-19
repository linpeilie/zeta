import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Claude Code capabilities available before a runtime is initialized.
abstract final class ClaudeStaticCapabilities {
  /// The conservative capability baseline for Claude Code.
  static const value = AgentProviderCapabilities(
    canCreateSession: true,
    canResumeSession: true,
    canListThreads: true,
    canReadHistory: true,
    canRemoveThreadFromList: true,
    canPrompt: true,
    canCancelTurn: true,
    canCompactThread: true,
    supportsPermissionRequests: true,
    supportsUserQuestions: true,
    supportsPlanApproval: true,
    supportsModelSelection: true,
    supportsReasoningOptions: true,
    supportsUsage: true,
  );
}
