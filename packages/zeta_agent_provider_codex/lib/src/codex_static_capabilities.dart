import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 插件声明的静态能力种子，与原能力目录逐字段相同。
const codexStaticCapabilities = AgentProviderCapabilities(
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
  // 指定 turn 分支取决于运行时 Codex 版本，初始化后动态开启。
  canForkThreadAtTurn: false,
  canCompactThread: true,
  supportsLocalImageInput: true,
  supportsResourceInput: true,
  supportsSkillInput: true,
  supportsPermissionRequests: true,
  supportsUserQuestions: true,
  // 当前 Codex 适配尚未暴露独立计划审批回写端口，避免提前声明可执行能力。
  supportsPlanApproval: false,
  supportsModelSelection: true,
  supportsReasoningOptions: true,
  supportsServiceTierSelection: true,
  supportsUsage: true,
);
