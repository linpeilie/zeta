import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.claude_code.plan_approval');

/// Claude Code Plan control request 的路由结果。
final class ClaudeCodePlanControlRequestResult {
  const ClaudeCodePlanControlRequestResult({
    required this.handled,
    this.responseFrame,
    this.events = const <AgentEvent>[],
  });

  const ClaudeCodePlanControlRequestResult.notHandled()
    : handled = false,
      responseFrame = null,
      events = const <AgentEvent>[];

  /// true 表示该 control request 属于 `ExitPlanMode`，不得再交给权限 handler。
  final bool handled;

  /// malformed、乱序或重复冲突时立即回写的 fail-closed 响应。
  final Map<String, Object?>? responseFrame;

  /// 成功配对后只产出独立的 Plan 审批事件。
  final List<AgentEvent> events;
}

/// 用户 Plan 决策编码结果。
final class ClaudeCodePlanApprovalDecisionResult {
  const ClaudeCodePlanApprovalDecisionResult({
    required this.responseFrame,
    required this.interruptTurn,
  });

  final Map<String, Object?> responseFrame;

  /// 用户取消整个审批时终止当前 turn；拒绝并附修改意见时让 Claude 继续修订。
  final bool interruptTurn;
}

/// Claude Code `ExitPlanMode` 的独立 Plan 审批 adapter。
///
/// assistant `tool_use.id` 是领域请求 id；随后
/// `control_request.request.tool_use_id` 用来精确配对，独立的
/// `control_request.request_id` 只用于回写。该 registry 与普通工具权限完全隔离。
///
/// 本类无 I/O；Provider 负责发送 [responseFrame]。
final class ClaudeCodePlanApprovalAdapter {
  final Map<String, _ObservedExitPlanTool> _observedByToolUseId =
      <String, _ObservedExitPlanTool>{};
  final Map<String, _PendingPlanApproval> _pendingByToolUseId =
      <String, _PendingPlanApproval>{};
  final Map<({String sessionId, String turnId}), String> _recentTextByTurn =
      <({String sessionId, String turnId}), String>{};

  int _malformedCount = 0;
  int _unknownDecisionCount = 0;

  int get pendingCount => _pendingByToolUseId.length;

  int get malformedCount => _malformedCount;

  int get unknownDecisionCount => _unknownDecisionCount;

  /// 新 turn 开始时清除同 key 的文本回退，避免复用测试 id 时串入旧正文。
  void beginTurn({required String sessionId, required String turnId}) {
    _recentTextByTurn.remove((sessionId: sessionId, turnId: turnId));
  }

  /// 记录当前 turn 最近一段 assistant 正文，仅作为空 `input.plan` 的内存回退。
  void recordAssistantText({
    required String sessionId,
    required String turnId,
    required String text,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }
    _recentTextByTurn[(sessionId: sessionId, turnId: turnId)] = normalized;
  }

  /// 登记 `ExitPlanMode` tool_use，并从此抑制该 id 的普通工具生命周期事件。
  void recordExitPlanToolUse({
    required String toolUseId,
    required Map<String, Object?> input,
    required String sessionId,
    required String turnId,
  }) {
    final key = (sessionId: sessionId, turnId: turnId);
    final markdown = _string(input['plan']) ?? _recentTextByTurn[key] ?? '';
    _observedByToolUseId[toolUseId] = _ObservedExitPlanTool(
      markdown: markdown,
      sessionId: sessionId,
      turnId: turnId,
    );
  }

  /// true 时 mapper 必须丢弃对应 `tool_result`，避免无头完成卡。
  bool shouldSuppressToolResult(String toolUseId) {
    return _observedByToolUseId.containsKey(toolUseId);
  }

  /// 尝试接管一帧 `control_request`。
  ///
  /// 只要工具名为 `ExitPlanMode`，或 `tool_use_id` 已由本 adapter 登记，就认为
  /// 属于 Plan 路径；坏形状一律在本路径 fail-closed，不得降级成普通权限卡。
  ClaudeCodePlanControlRequestResult handleControlRequest(
    Map<String, Object?> raw,
  ) {
    final request = _map(raw['request']);
    final toolUseId = _string(request?['tool_use_id']);
    final toolName = _string(request?['tool_name']);
    final observed = toolUseId == null ? null : _observedByToolUseId[toolUseId];
    final isExitPlanMode = toolName == 'ExitPlanMode' || observed != null;
    if (!isExitPlanMode) {
      return const ClaudeCodePlanControlRequestResult.notHandled();
    }

    final requestId = _string(raw['request_id']);
    final subtype = _string(request?['subtype']);
    final toolInput = _map(request?['input']);
    if (requestId == null ||
        subtype != 'can_use_tool' ||
        toolUseId == null ||
        toolName != 'ExitPlanMode' ||
        toolInput == null) {
      _malformedCount += 1;
      _log.w('Malformed ExitPlanMode control_request; fail-closed');
      return ClaudeCodePlanControlRequestResult(
        handled: true,
        responseFrame: _errorFrame(
          requestId: requestId ?? 'missing-request-id',
          error: 'Zeta denied malformed ExitPlanMode request',
        ),
      );
    }
    if (observed == null) {
      _malformedCount += 1;
      _log.w('Unmatched ExitPlanMode control_request; fail-closed');
      return ClaudeCodePlanControlRequestResult(
        handled: true,
        responseFrame: _errorFrame(
          requestId: requestId,
          error: 'Zeta denied unmatched ExitPlanMode request',
        ),
      );
    }

    final existing = _pendingByToolUseId[toolUseId];
    if (existing != null) {
      if (existing.controlRequestId == requestId) {
        // stdout 重复帧不生成第二张卡；原请求继续等待同一用户决定。
        return const ClaudeCodePlanControlRequestResult(handled: true);
      }
      _malformedCount += 1;
      _log.w('Conflicting ExitPlanMode control_request; fail-closed');
      return ClaudeCodePlanControlRequestResult(
        handled: true,
        responseFrame: _errorFrame(
          requestId: requestId,
          error: 'Zeta denied duplicate ExitPlanMode request',
        ),
      );
    }

    final pending = _PendingPlanApproval(
      controlRequestId: requestId,
      toolInput: Map<String, Object?>.unmodifiable(toolInput),
    );
    _pendingByToolUseId[toolUseId] = pending;
    final controlPlan = _string(toolInput['plan']);
    final approval = AgentPlanApprovalRequest(
      id: toolUseId,
      title: 'Plan approval',
      markdown: controlPlan ?? observed.markdown,
      sessionId: observed.sessionId,
      turnId: observed.turnId,
      isProject: false,
      continuation: AgentPlanApprovalContinuation.localExecutionHandoff,
      // 不把 plan/path/input/raw payload 复制到诊断 metadata（G8）。
      raw: const <String, Object?>{
        'source': 'claude_code.exit_plan_mode',
        'tool_name': 'ExitPlanMode',
      },
    );
    _log.t('Plan approval requested (pending=${_pendingByToolUseId.length})');
    return ClaudeCodePlanControlRequestResult(
      handled: true,
      events: <AgentEvent>[AgentPlanApprovalRequestedEvent(approval)],
    );
  }

  /// 将领域 Plan 决策编码成 SDK control wire，并移除独立 pending。
  ClaudeCodePlanApprovalDecisionResult? resolveDecision(
    AgentPlanApprovalDecision decision,
  ) {
    final pending = _pendingByToolUseId.remove(decision.requestId);
    if (pending == null) {
      _unknownDecisionCount += 1;
      _log.w('Ignoring response for unknown Claude Code plan approval');
      return null;
    }

    final response = switch (decision.kind) {
      AgentPlanApprovalDecisionKind.accepted => <String, Object?>{
        'behavior': 'allow',
        'updatedInput': Map<String, Object?>.of(pending.toolInput),
      },
      AgentPlanApprovalDecisionKind.rejected => <String, Object?>{
        'behavior': 'deny',
        'message': _decisionMessage(
          decision.reason,
          fallback: 'User requested plan changes',
        ),
      },
      AgentPlanApprovalDecisionKind.cancelled => <String, Object?>{
        'behavior': 'deny',
        'message': _decisionMessage(
          decision.reason,
          fallback: 'User cancelled plan approval',
        ),
      },
    };
    return ClaudeCodePlanApprovalDecisionResult(
      responseFrame: _successFrame(
        requestId: pending.controlRequestId,
        response: response,
      ),
      interruptTurn: decision.kind == AgentPlanApprovalDecisionKind.cancelled,
    );
  }

  /// turn 终态后释放回退正文、tool 观察与 pending；不会写盘或回写旧 peer。
  void completeTurn({required String sessionId, required String turnId}) {
    final key = (sessionId: sessionId, turnId: turnId);
    _recentTextByTurn.remove(key);
    final completedToolIds = _observedByToolUseId.entries
        .where(
          (entry) =>
              entry.value.sessionId == sessionId &&
              entry.value.turnId == turnId,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final toolUseId in completedToolIds) {
      _observedByToolUseId.remove(toolUseId);
      _pendingByToolUseId.remove(toolUseId);
    }
  }

  /// peer 重启 / dispose 时清空全部内存状态，避免跨 epoch 串味。
  void clear() {
    _observedByToolUseId.clear();
    _pendingByToolUseId.clear();
    _recentTextByTurn.clear();
  }

  static String _decisionMessage(String? value, {required String fallback}) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  static Map<String, Object?> _successFrame({
    required String requestId,
    required Map<String, Object?> response,
  }) {
    return <String, Object?>{
      'type': 'control_response',
      'response': <String, Object?>{
        'subtype': 'success',
        'request_id': requestId,
        'response': response,
      },
    };
  }

  static Map<String, Object?> _errorFrame({
    required String requestId,
    required String error,
  }) {
    return <String, Object?>{
      'type': 'control_response',
      'response': <String, Object?>{
        'subtype': 'error',
        'request_id': requestId,
        'error': error,
      },
    };
  }

  static String? _string(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return null;
  }
}

final class _ObservedExitPlanTool {
  const _ObservedExitPlanTool({
    required this.markdown,
    required this.sessionId,
    required this.turnId,
  });

  final String markdown;
  final String sessionId;
  final String turnId;
}

final class _PendingPlanApproval {
  const _PendingPlanApproval({
    required this.controlRequestId,
    required this.toolInput,
  });

  final String controlRequestId;
  final Map<String, Object?> toolInput;
}
