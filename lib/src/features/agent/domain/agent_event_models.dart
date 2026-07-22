import 'package:zeta/src/features/agent/domain/agent_message_models.dart';
import 'package:zeta/src/features/agent/domain/agent_model_selection_models.dart';
import 'package:zeta/src/features/agent/domain/agent_permission_models.dart';
import 'package:zeta/src/features/agent/domain/agent_plan_approval_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_models.dart';
import 'package:zeta/src/features/agent/domain/agent_session_config_models.dart';
import 'package:zeta/src/features/agent/domain/agent_session_models.dart';
import 'package:zeta/src/features/agent/domain/agent_thread_models.dart';
import 'package:zeta/src/features/agent/domain/agent_tool_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_history_models.dart';

/// Agent provider 向 UI 推送的统一事件基类。
sealed class AgentEvent {
  const AgentEvent();
}

/// Provider 状态变化事件。
class AgentStatusEvent extends AgentEvent {
  const AgentStatusEvent(this.status);

  /// 最新 provider 状态。
  final AgentProviderStatus status;
}

/// 新会话已创建或恢复。
class AgentSessionStartedEvent extends AgentEvent {
  const AgentSessionStartedEvent(this.session);

  /// 已创建或恢复的会话。
  final AgentSession session;
}

/// 线程运行状态变化。
///
/// 对应 Codex `thread/status/changed`；UI 据此更新状态胶囊与列表指示。
class AgentThreadStatusChangedEvent extends AgentEvent {
  const AgentThreadStatusChangedEvent({
    required this.threadId,
    required this.status,
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
    this.raw = const <String, Object?>{},
  });

  /// 状态变化的线程 id。
  final String threadId;

  /// 归一化后的运行状态。
  final AgentThreadRuntimeStatus status;

  /// 是否在等待用户审批。
  final bool waitingOnApproval;

  /// 是否在等待用户输入。
  final bool waitingOnUserInput;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 线程标题已更新（`thread/name/updated`）。
class AgentThreadNameUpdatedEvent extends AgentEvent {
  const AgentThreadNameUpdatedEvent({
    required this.threadId,
    this.threadName,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 新标题；为空表示清除自定义标题。
  final String? threadName;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 线程已归档（`thread/archived`）。
class AgentThreadArchivedEvent extends AgentEvent {
  const AgentThreadArchivedEvent({
    required this.threadId,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 线程已取消归档（`thread/unarchived`）。
class AgentThreadUnarchivedEvent extends AgentEvent {
  const AgentThreadUnarchivedEvent({
    required this.threadId,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 线程已删除（`thread/deleted`）。
class AgentThreadDeletedEvent extends AgentEvent {
  const AgentThreadDeletedEvent({
    required this.threadId,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 线程已关闭（`thread/closed`）。
///
/// 客户端应释放本地运行态并 best-effort 取消订阅。
class AgentThreadClosedEvent extends AgentEvent {
  const AgentThreadClosedEvent({
    required this.threadId,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 上下文压缩已完成通知（`thread/compacted`，协议已 deprecated）。
///
/// 主 UI 仍以 `contextCompaction` item 为准；本事件用于清除 compact 进行中标志。
class AgentThreadCompactedEvent extends AgentEvent {
  const AgentThreadCompactedEvent({
    required this.threadId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 可选回合 id。
  final String? turnId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 线程设置已变更（`thread/settings/updated`）。
class AgentThreadSettingsUpdatedEvent extends AgentEvent {
  const AgentThreadSettingsUpdatedEvent({
    required this.threadId,
    this.model,
    this.approvalPolicy,
    this.sandboxPolicy,
    this.activePermissionProfileId,
    this.raw = const <String, Object?>{},
  });

  /// 线程 id。
  final String threadId;

  /// 服务端当前生效的模型 id（若有）。
  final String? model;

  /// 审批策略字符串变体（若有）。
  final String? approvalPolicy;

  /// 沙箱策略域内标识（readOnly/workspaceWrite/dangerFullAccess）。
  final String? sandboxPolicy;

  /// 当前生效的 permission profile id。
  final String? activePermissionProfileId;

  /// 原始通知 payload（含完整 `threadSettings`）。
  final Map<String, Object?> raw;
}

/// Guardian 自动审批评审状态（`item/autoApprovalReview/*`）。
class AgentAutoApprovalReviewEvent extends AgentEvent {
  const AgentAutoApprovalReviewEvent({
    required this.threadId,
    required this.turnId,
    required this.reviewId,
    required this.status,
    this.rationale,
    this.riskLevel,
    this.targetItemId,
    this.raw = const <String, Object?>{},
  });

  final String threadId;
  final String turnId;
  final String reviewId;

  /// inProgress / approved / denied / timedOut / aborted
  final String status;
  final String? rationale;
  final String? riskLevel;
  final String? targetItemId;
  final Map<String, Object?> raw;
}

/// 新回合已开始。
class AgentTurnStartedEvent extends AgentEvent {
  const AgentTurnStartedEvent(this.turn);

  /// 已开始的回合。
  final AgentTurn turn;
}

/// 回合已结束（完成、被中断或失败）。
class AgentTurnCompletedEvent extends AgentEvent {
  const AgentTurnCompletedEvent({
    required this.sessionId,
    required this.turnId,
    this.status = AgentHistoryTurnStatus.completed,
    this.errorMessage,
    this.duration,
    this.raw = const <String, Object?>{},
  });

  /// 完成回合所属会话 id。
  final String sessionId;

  /// 完成的回合 id。
  final String turnId;

  /// 回合终态；对应 Codex `turn.status`（completed/interrupted/failed）。
  final AgentHistoryTurnStatus status;

  /// 失败原因；仅 `turn.error` 存在时携带。
  final String? errorMessage;

  /// provider 上报的回合耗时（`turn.durationMs`）。
  final Duration? duration;

  /// 原始完成事件 payload。
  final Map<String, Object?> raw;
}

/// 回合 token 用量更新。
///
/// 对应 Codex `thread/tokenUsage/updated` 通知（旧版为 `turn/tokenCount`），
/// 以及 Grok ACP `turn_completed.usage`。
///
/// 当 [isSessionCumulative] 为 true（Codex 默认）时，[tokenUsage] 的
/// breakdown 是整个会话累计；时间线层保存会话总量，并把 turn 用量差分后
/// 写入回合分隔线。
///
/// 当 [isSessionCumulative] 为 false（Grok）时，[tokenUsage] 是**本回合**
/// 绝对用量，不得再相对上一 turn 做差分。
class AgentTokenUsageEvent extends AgentEvent {
  const AgentTokenUsageEvent({
    required this.tokenUsage,
    this.sessionId,
    this.turnId,
    this.isSessionCumulative = true,
    this.raw = const <String, Object?>{},
  });

  /// 所属会话 id。
  final String? sessionId;

  /// 所属回合 id；为空时由 ViewModel 归入当前活跃回合。
  final String? turnId;

  /// 本次上报的 token 用量。
  final AgentTokenUsage tokenUsage;

  /// 为 true 时 [tokenUsage] 是会话累计（Codex）；为 false 时为本回合绝对用量（Grok）。
  final bool isSessionCumulative;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// Agent 消息的流式增量。
class AgentMessageDeltaEvent extends AgentEvent {
  const AgentMessageDeltaEvent({
    required this.messageId,
    required this.delta,
    required this.role,
    this.sourceMessageId,
    this.kind = AgentMessageKind.regular,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
    this.sessionId,
    this.turnId,
  });

  /// Zeta 规范化 entryId，用于合并同一可见消息的多个 delta。
  ///
  /// 字段名在迁移期保留为 `messageId`，不得再将它解释为 Provider 原始身份。
  final String messageId;

  /// Provider 原始消息身份；不作为 UI 合并键。
  final String? sourceMessageId;

  /// 消息的显式展示语义。
  final AgentMessageKind kind;

  /// 本次增量文本。
  final String delta;

  /// 消息角色。
  final AgentMessageRole role;

  /// 可选消息阶段。
  final AgentMessagePhase? phase;

  /// 可选消息状态。
  final AgentMessageStatus? status;

  /// 可选耗时。
  final Duration? duration;

  /// 原始 provider payload。
  final Map<String, Object?> raw;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// Reasoning item 的流式增量种类。
///
/// 对应 Codex `item/reasoning/*` 三类通知：
/// - [text]：原始推理文本 delta（`item/reasoning/textDelta`）
/// - [summaryText]：面向用户的摘要 delta（`item/reasoning/summaryTextDelta`）
/// - [summaryPart]：摘要新分段边界（`item/reasoning/summaryPartAdded`，无文本）
enum AgentReasoningDeltaKind { text, summaryText, summaryPart }

/// Reasoning item 的流式增量。
///
/// Timeline 将其聚合到 `AgentToolKind.think` 卡片；优先展示摘要流，
/// 若本回合未收到摘要则回退到原始推理文本。
class AgentReasoningDeltaEvent extends AgentEvent {
  const AgentReasoningDeltaEvent({
    required this.itemId,
    required this.kind,
    this.sourceItemId,
    this.delta = '',
    this.contentIndex,
    this.summaryIndex,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// Zeta 规范化 reasoning entryId，用于合并同一思考卡片的多个 delta。
  final String itemId;

  /// Provider 原始 reasoning item 身份；不作为 UI 合并键。
  final String? sourceItemId;

  /// 增量种类。
  final AgentReasoningDeltaKind kind;

  /// 本次增量文本；[summaryPart] 通常为空。
  final String delta;

  /// `textDelta` 的 content 分段下标。
  final int? contentIndex;

  /// `summaryTextDelta` / `summaryPartAdded` 的 summary 分段下标。
  final int? summaryIndex;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// Agent 消息 metadata 或最终文本更新。
class AgentMessageUpdatedEvent extends AgentEvent {
  const AgentMessageUpdatedEvent({
    required this.messageId,
    this.sourceMessageId,
    this.kind = AgentMessageKind.regular,
    this.text,
    this.role,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
    this.sessionId,
    this.turnId,
  });

  /// Zeta 规范化 entryId，必须与对应 delta 的 [AgentMessageDeltaEvent.messageId] 相同。
  ///
  /// 字段名在迁移期保留为 `messageId`，不得再将它解释为 Provider 原始身份。
  final String messageId;

  /// Provider 原始消息身份；不作为 UI 合并键。
  final String? sourceMessageId;

  /// 消息的显式展示语义。
  final AgentMessageKind kind;

  /// 可选完整文本。
  final String? text;

  /// 可选消息角色。
  final AgentMessageRole? role;

  /// 可选消息阶段。
  final AgentMessagePhase? phase;

  /// 可选消息状态。
  final AgentMessageStatus? status;

  /// 可选耗时。
  final Duration? duration;

  /// 原始 provider payload。
  final Map<String, Object?> raw;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// Agent 计划更新。
class AgentPlanUpdatedEvent extends AgentEvent {
  const AgentPlanUpdatedEvent({
    required this.entries,
    this.sessionId,
    this.turnId,
  });

  /// 最新计划条目。
  final List<AgentPlanEntry> entries;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// Session 动态配置的完整快照。
class AgentSessionConfigUpdatedEvent extends AgentEvent {
  const AgentSessionConfigUpdatedEvent({
    required this.sessionId,
    required this.options,
  });

  final String sessionId;
  final List<AgentSessionConfigOption> options;
}

/// Provider 请求用户独立审批计划。
class AgentPlanApprovalRequestedEvent extends AgentEvent {
  const AgentPlanApprovalRequestedEvent(this.request);

  final AgentPlanApprovalRequest request;
}

/// 计划审批已超时、取消或由其他路径解决。
class AgentPlanApprovalResolvedEvent extends AgentEvent {
  const AgentPlanApprovalResolvedEvent({
    required this.requestId,
    this.sessionId,
  });

  final String requestId;
  final String? sessionId;
}

/// 回合级聚合 diff 更新。
///
/// 对应 Codex `turn/diff/updated`：携带本回合全部文件改动的最新 unified diff。
class AgentTurnDiffEvent extends AgentEvent {
  const AgentTurnDiffEvent({
    required this.sessionId,
    required this.turnId,
    required this.diff,
    this.raw = const <String, Object?>{},
  });

  /// 所属会话 id。
  final String sessionId;

  /// 所属回合 id。
  final String turnId;

  /// 最新聚合 unified diff；空字符串表示本回合暂无改动。
  final String diff;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 工具调用新增或更新。
class AgentToolCallEvent extends AgentEvent {
  const AgentToolCallEvent(this.toolCall);

  /// 新增或更新的工具调用。
  final AgentToolCall toolCall;
}

/// Provider 请求用户审批或输入。
class AgentPermissionRequestedEvent extends AgentEvent {
  const AgentPermissionRequestedEvent(this.request);

  /// 等待用户处理的审批请求。
  final AgentPermissionRequest request;
}

/// 服务端审批请求已被他端解决，本端应撤销对应审批卡片。
///
/// 对应 Codex `serverRequest/resolved`（多客户端 / daemon 场景）。
class AgentPermissionResolvedEvent extends AgentEvent {
  const AgentPermissionResolvedEvent({
    required this.requestId,
    required this.threadId,
    this.raw = const <String, Object?>{},
  });

  /// 被解决的 JSON-RPC 请求 id，与 [AgentPermissionRequest.id] 对齐。
  final String requestId;

  /// 所属线程 id。
  final String threadId;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// 服务端将本回合模型改道到另一模型。
///
/// 对应 Codex `model/rerouted`；UI 插入系统事件并在头栏提示。
class AgentModelReroutedEvent extends AgentEvent {
  const AgentModelReroutedEvent({
    required this.threadId,
    required this.turnId,
    required this.fromModel,
    required this.toModel,
    required this.reason,
    this.raw = const <String, Object?>{},
  });

  /// 所属线程 id。
  final String threadId;

  /// 所属回合 id。
  final String turnId;

  /// 改道前的模型 id。
  final String fromModel;

  /// 改道后的模型 id。
  final String toModel;

  /// 改道原因（协议枚举字符串，如 `highRiskCyberActivity`）。
  final String reason;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// Codex API / 适配层弃用提示。
///
/// 对应 `deprecationNotice`；应记日志并在 UI 一次性展示，提示升级适配层。
class AgentDeprecationNoticeEvent extends AgentEvent {
  const AgentDeprecationNoticeEvent({
    required this.summary,
    this.details,
    this.raw = const <String, Object?>{},
  });

  /// 弃用概要。
  final String summary;

  /// 可选迁移说明或细节。
  final String? details;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// ThreadItem 中的系统类条目（评审模式、压缩、hook、sleep 等）。
///
/// 对应 `item/started` / `item/completed` 中不宜做成工具卡的类型；
/// UI 以 [AgentHistoryEventEntry] 渲染为系统/搜索类状态卡。
class AgentSystemItemEvent extends AgentEvent {
  const AgentSystemItemEvent({
    required this.entry,
    this.sessionId,
    this.turnId,
  });

  /// 可直接插入时间线的历史事件条目。
  final AgentHistoryEventEntry entry;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// 协议错误、stderr 或 provider 运行错误。
class AgentErrorEvent extends AgentEvent {
  const AgentErrorEvent({
    required this.message,
    this.details,
    this.code,
    this.willRetry,
    this.sessionId,
    this.turnId,
    this.exception,
    this.stackTrace,
    this.raw = const <String, Object?>{},
  });

  /// 错误概要。
  final String message;

  /// 错误详情。
  final String? details;

  /// Codex 错误码（`codexErrorInfo`），如 `contextWindowExceeded`、
  /// `unauthorized`、`sessionBudgetExceeded`、`httpConnectionFailed`；
  /// 非协议错误或旧版协议为空。
  ///
  /// UI 可据此提供针对性引导（如上下文超限时建议压缩会话）。
  final String? code;

  /// 服务端是否会自动重试本回合；仅 `error` 通知携带，其余场景为空。
  final bool? willRetry;

  /// 可选会话 id；全局 stderr / protocol 错误为空。
  final String? sessionId;

  /// 可选回合 id；全局 stderr / protocol 错误为空。
  final String? turnId;

  /// Provider 捕获到的原始异常；仅用于通用诊断日志，不进入用户可见文本。
  final Object? exception;

  /// 捕获异常时的堆栈；仅用于通用诊断日志。
  final StackTrace? stackTrace;

  /// 原始错误 payload。
  final Map<String, Object?> raw;
}

/// provider 拉取到模型列表后推送的事件。
///
/// ViewModel 据此更新输入框下方的模型/思考/速率控件。
class AgentModelListEvent extends AgentEvent {
  const AgentModelListEvent(this.models);

  /// 最新可用的模型列表。
  final AgentModelList models;
}
