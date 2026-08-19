import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 初始化前可判断的厂商静态能力目录。
///
/// Domain 的 [AgentProviderCapabilities] 只是中立值对象。具体默认值由 data
/// 组合层持有，供 settings / factory 在 runtime 尚未创建时查询；握手后仍以
/// `runtime.capabilities` 为准。
abstract final class AgentProviderStaticCapabilities {
  /// Codex app-server 当前已落地能力。
  static const codexAppServer = AgentProviderCapabilities(
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

  /// Grok ACP 当前真实可用能力。
  ///
  /// 本地图片当前只会退化为路径文本，因此不声明图片输入能力。
  /// 重命名/删除走 xAI 扩展 `_x.ai/session/rename|delete`；归档无协议支持，保持关闭。
  /// Skill 目录走 xAI 扩展 `_x.ai/skills/list`；发送时以 `$name` 文本 marker 调用。
  static const grokAcp = AgentProviderCapabilities(
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

  /// Claude Code 当前已落地能力集。
  ///
  /// 开放创建/恢复会话、本地历史列表与读取、prompt / cancel / usage、权限审批、
  /// Plan 审批、Zeta 本地隐藏记录、静态模型选择与 `/compact`；其他能力随后续任务
  /// 逐步打开，避免「入口在但点了报错」的窗口期（G4）。
  static const claudeCode = AgentProviderCapabilities(
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

  /// 在 provider 尚未实例化时，根据持久化 kind 提供保守静态能力。
  static AgentProviderCapabilities forKind(AgentProviderKind kind) {
    return switch (kind) {
      AgentProviderKind.codexAppServer => codexAppServer,
      AgentProviderKind.acp => grokAcp,
      AgentProviderKind.claudeCode => claudeCode,
    };
  }
}
