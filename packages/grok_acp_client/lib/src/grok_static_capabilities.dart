import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Grok capabilities available before an ACP runtime is initialized.
abstract final class GrokStaticCapabilities {
  /// The conservative capability baseline for Grok ACP.
  static const value = AgentProviderCapabilities(
    canCreateSession: true,
    canResumeSession: true,
    canListThreads: true,
    canReadHistory: true,
    canDeleteThread: true,
    canRenameThread: true,
    canPrompt: true,
    canCancelTurn: true,
    supportsResourceInput: true,
    supportsSkillInput: true,
    supportsPermissionRequests: true,
    supportsUserQuestions: true,
    supportsPlanApproval: true,
    supportsModelSelection: true,
    supportsModeSelection: true,
    supportsReasoningOptions: true,
    supportsUsage: true,
  );
}
