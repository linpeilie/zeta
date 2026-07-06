import 'package:zeta/src/features/agent/domain/agent_message_models.dart';
import 'package:zeta/src/features/agent/domain/agent_model_selection_models.dart';
import 'package:zeta/src/features/agent/domain/agent_permission_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_models.dart';
import 'package:zeta/src/features/agent/domain/agent_session_models.dart';
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

/// 新回合已开始。
class AgentTurnStartedEvent extends AgentEvent {
  const AgentTurnStartedEvent(this.turn);

  /// 已开始的回合。
  final AgentTurn turn;
}

/// 回合已完成。
class AgentTurnCompletedEvent extends AgentEvent {
  const AgentTurnCompletedEvent({
    required this.sessionId,
    required this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 完成回合所属会话 id。
  final String sessionId;

  /// 完成的回合 id。
  final String turnId;

  /// 原始完成事件 payload。
  final Map<String, Object?> raw;
}

/// 回合 token 用量更新。
///
/// 对应 Codex `turn/tokenCount` 通知，UI 据此在回合分隔线展示 token 成本。
class AgentTokenUsageEvent extends AgentEvent {
  const AgentTokenUsageEvent({
    required this.tokenUsage,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 所属会话 id。
  final String? sessionId;

  /// 所属回合 id；为空时由 ViewModel 归入当前活跃回合。
  final String? turnId;

  /// 本次上报的 token 用量。
  final AgentTokenUsage tokenUsage;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// Agent 消息的流式增量。
class AgentMessageDeltaEvent extends AgentEvent {
  const AgentMessageDeltaEvent({
    required this.messageId,
    required this.delta,
    required this.role,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
    this.sessionId,
    this.turnId,
  });

  /// provider 消息 id，用于合并同一条消息的多个 delta。
  final String messageId;

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

/// Agent 消息 metadata 或最终文本更新。
class AgentMessageUpdatedEvent extends AgentEvent {
  const AgentMessageUpdatedEvent({
    required this.messageId,
    this.text,
    this.role,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
    this.sessionId,
    this.turnId,
  });

  /// provider 消息 id。
  final String messageId;

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

/// 协议错误、stderr 或 provider 运行错误。
class AgentErrorEvent extends AgentEvent {
  const AgentErrorEvent({
    required this.message,
    this.details,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 错误概要。
  final String message;

  /// 错误详情。
  final String? details;

  /// 可选会话 id；全局 stderr / protocol 错误为空。
  final String? sessionId;

  /// 可选回合 id；全局 stderr / protocol 错误为空。
  final String? turnId;

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
