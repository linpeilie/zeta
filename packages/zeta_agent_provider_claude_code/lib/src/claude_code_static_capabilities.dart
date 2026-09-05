import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 插件声明的静态能力种子，与原能力目录逐字段相同。
const claudeCodeStaticCapabilities = AgentProviderCapabilities(
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
