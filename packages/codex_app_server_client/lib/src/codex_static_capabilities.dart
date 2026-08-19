import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Conservative Codex capabilities available before runtime negotiation.
abstract final class CodexStaticCapabilities {
  /// Capabilities implemented by the Codex app-server adapter.
  static const AgentProviderCapabilities value = AgentProviderCapabilities(
    canCreateSession: true,
    canResumeSession: true,
    canListThreads: true,
    canReadHistory: true,
    canDeleteThread: true,
    canPrompt: true,
    canCancelTurn: true,
    canSteerTurn: true,
    canRenameThread: true,
    canArchiveThread: true,
    canUnarchiveThread: true,
    canForkThread: true,
    canCompactThread: true,
    supportsLocalImageInput: true,
    supportsResourceInput: true,
    supportsSkillInput: true,
    supportsPermissionRequests: true,
    supportsUserQuestions: true,
    supportsModelSelection: true,
    supportsReasoningOptions: true,
    supportsServiceTierSelection: true,
    supportsUsage: true,
  );
}
