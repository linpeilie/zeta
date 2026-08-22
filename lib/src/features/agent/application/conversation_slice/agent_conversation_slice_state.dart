import 'package:flutter/foundation.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_ui_state.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 一次命令类操作的失败描述。
///
/// 只承载**已经可以展示给用户的中立文本**与操作身份：不带 Provider 原文、
/// 不带 prompt、不带路径（G7）。
@immutable
final class AgentConversationOperationFailure {
  const AgentConversationOperationFailure({
    required this.operationId,
    required this.message,
  });

  /// 失败所属的操作身份。
  final OperationId operationId;

  /// 已本地化、可直接展示的失败说明。
  final String message;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationOperationFailure &&
      other.operationId == operationId &&
      other.message == message;

  @override
  int get hashCode => Object.hash(operationId, message);

  @override
  String toString() =>
      'AgentConversationOperationFailure($operationId, $message)';
}

/// 单个 Agent Conversation 的完整可渲染切片。
///
/// **零新增业务事实**：五个 region 直接复用现有的不可变 region state 类，它们
/// 的 owner 仍然是 `AgentConversationTimelineStore` 与既有 controller
/// （见 `docs/architecture/phase2_conversation_slice.md` §2）。切片只是这些事实
/// 的只读投影，外加"命令类操作的在途身份"这一份纯 UI 事实。
///
/// 流式 turn 的局部内容**不在这里**：`AgentUiRegion.liveTurn` /
/// `liveTurnBinding` 继续走 TimelineStore 的局部重建路径（同文档 §2.7），
/// 否则每个 token 都会触发一次切片发布，直接撞穿 Phase 0 的帧预算。
@immutable
final class AgentConversationSliceState {
  const AgentConversationSliceState({
    required this.header,
    required this.composer,
    required this.pendingInteractions,
    required this.expansion,
    required this.history,
    this.pendingOperations = const <OperationId>{},
    this.lastFailure,
  });

  /// 头栏投影。
  final AgentHeaderState header;

  /// Composer 投影。
  ///
  /// 只含发送可用性与配置类事实；**输入框正文不在切片里**，否则每次按键都会
  /// 触发一次发布。
  final AgentComposerState composer;

  /// 四种审批语义各自独立的待处理交互（G5）。
  final AgentPendingInteractionState pendingInteractions;

  /// 展开态投影；集合本身仍由 TimelineStore 拥有。
  final AgentExpansionState expansion;

  /// 已完成的历史时间线投影；存的是 turn group 引用，不复制正文。
  final AgentConversationHistoryState history;

  /// 仍在途的命令类操作。
  ///
  /// 迟到结果先比对这里再决定是否写回；不在集合里的 id 一律丢弃。
  final Set<OperationId> pendingOperations;

  /// 最近一次失败；成功或发起新操作时清空。
  final AgentConversationOperationFailure? lastFailure;

  /// 是否有任何命令在途。
  bool get hasPendingOperation => pendingOperations.isNotEmpty;

  /// 指定作用域下是否有命令在途，例如 `conversation.send`。
  bool hasPendingOperationInScope(String scope) =>
      pendingOperations.any((operation) => operation.scope == scope);

  AgentConversationSliceState copyWith({
    AgentHeaderState? header,
    AgentComposerState? composer,
    AgentPendingInteractionState? pendingInteractions,
    AgentExpansionState? expansion,
    AgentConversationHistoryState? history,
    Set<OperationId>? pendingOperations,
    AgentConversationOperationFailure? lastFailure,
    bool clearLastFailure = false,
  }) {
    return AgentConversationSliceState(
      header: header ?? this.header,
      composer: composer ?? this.composer,
      pendingInteractions: pendingInteractions ?? this.pendingInteractions,
      expansion: expansion ?? this.expansion,
      history: history ?? this.history,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      lastFailure: clearLastFailure ? null : (lastFailure ?? this.lastFailure),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentConversationSliceState &&
            other.header == header &&
            other.composer == composer &&
            other.pendingInteractions == pendingInteractions &&
            other.expansion == expansion &&
            other.history == history &&
            setEquals(other.pendingOperations, pendingOperations) &&
            other.lastFailure == lastFailure;
  }

  @override
  int get hashCode => Object.hash(
    header,
    composer,
    pendingInteractions,
    expansion,
    history,
    Object.hashAllUnordered(pendingOperations),
    lastFailure,
  );
}
