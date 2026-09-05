import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 插件声明的静态能力种子，与原能力目录逐字段相同。
const grokStaticCapabilities = AgentProviderCapabilities(
  canCreateSession: true,
  canResumeSession: true,
  canListThreads: true,
  canReadHistory: true,
  canDeleteThread: true,
  canPrompt: true,
  canCancelTurn: true,
  canRenameThread: true,
  supportsResourceInput: true,
  supportsSkillInput: true,
  supportsPermissionRequests: true,
  // `_x.ai/ask_user_question` park 到 UI 并经 respondToQuestion 回写。
  supportsUserQuestions: true,
  supportsModeSelection: true,
  supportsPlanApproval: true,
  supportsModelSelection: true,
  supportsReasoningOptions: true,
  supportsUsage: true,
);
