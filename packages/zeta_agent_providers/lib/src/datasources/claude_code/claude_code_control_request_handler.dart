import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = zetaLoggerFor('zeta.agent.claude_code.control_request');

/// Claude Code `can_use_tool` 的四种宿主决策（设计文档 §4.5）。
///
/// wire 只有 `allow` / `deny`；`always` 变体由 T21 的 session 缓存消费，
/// 本 handler 只负责正确编码 control_response，并标记 outcome 供上层缓存。
enum ClaudeCodeToolPermissionOutcome {
  allowOnce,
  allowAlways,
  denyOnce,
  denyAlways,
}

/// control_request 处理结果。
///
/// - [responseFrame] 非空：应立即写入 stdin 的 `control_response`（malformed /
///   未知 request type 的 fail-closed deny）。
/// - [responseFrame] 为空且 [events] 含权限事件：等待用户决策，
///   之后经 [ClaudeCodeControlRequestHandler.resolveDecision] 回写。
final class ClaudeCodeControlRequestResult {
  const ClaudeCodeControlRequestResult({
    this.responseFrame,
    this.events = const <AgentEvent>[],
  });

  /// 应立即写入 stdin 的 `control_response`；待审批时为 null。
  final Map<String, Object?>? responseFrame;

  /// 发给 UI 的领域事件（`can_use_tool` → [AgentPermissionRequestedEvent]）。
  final List<AgentEvent> events;
}

/// [resolveDecision] 的编码结果。
final class ClaudeCodeControlDecisionResult {
  const ClaudeCodeControlDecisionResult({
    required this.responseFrame,
    required this.outcome,
    required this.toolName,
  });

  final Map<String, Object?> responseFrame;
  final ClaudeCodeToolPermissionOutcome outcome;

  /// 仅 tool_name（白名单字段），供 T21 缓存；不含 input。
  final String toolName;
}

/// 等待用户决策的 `can_use_tool` 请求。
final class ClaudeCodePendingToolPermission {
  const ClaudeCodePendingToolPermission({
    required this.requestId,
    required this.toolUseId,
    required this.toolName,
    required this.toolInput,
    this.sessionId,
    this.turnId,
  });

  final String requestId;
  final String toolUseId;
  final String toolName;

  /// 原始 tool input，allow 时原样回填 `updatedInput`（CLI 契约）。
  final Map<String, Object?> toolInput;
  final String? sessionId;
  final String? turnId;
}

/// Claude Code `control_request` 真实审批 handler（T20）。
///
/// - `can_use_tool` → 登记 pending + [AgentPermissionRequestedEvent]
///   （sessionId/turnId 由调用方从 identity / running turn 注入，帧自身无作用域）。
/// - 用户决策 → [resolveDecision] 产出 `control_response`。
/// - 未知 request subtype / 缺关键字段 → 仍 fail-closed 立即回 error，避免 hang。
///
/// 无 I/O 副作用；`StreamJsonPeer.send` 由 Provider 负责。
final class ClaudeCodeControlRequestHandler {
  ClaudeCodeControlRequestHandler({
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  });

  final AgentUiTextCatalog textCatalog;

  final Map<String, ClaudeCodePendingToolPermission> _pending =
      <String, ClaudeCodePendingToolPermission>{};

  int _deniedCount = 0;
  int _malformedCount = 0;
  int _permissionRequestedCount = 0;
  int _resolvedCount = 0;
  int _unknownDecisionCount = 0;

  /// 立即拒绝的 control_request 次数（malformed / 未知 subtype）。
  int get deniedCount => _deniedCount;

  /// 缺 request_id 等坏形状计数。
  int get malformedCount => _malformedCount;

  /// 已向 UI 发出的 `can_use_tool` 审批次数。
  int get permissionRequestedCount => _permissionRequestedCount;

  /// 已成功 resolve 的决策次数。
  int get resolvedCount => _resolvedCount;

  /// 未知 requestId 的决策次数。
  int get unknownDecisionCount => _unknownDecisionCount;

  /// 当前等待用户决策的请求数。
  int get pendingCount => _pending.length;

  /// 只读 pending 视图（测试 / 诊断）。
  Map<String, ClaudeCodePendingToolPermission> get pending =>
      Map<String, ClaudeCodePendingToolPermission>.unmodifiable(_pending);

  /// 处理一帧 `control_request`。
  ///
  /// [sessionId] / [turnId] 必须来自当前活跃回合（identity / provider 状态），
  /// 因为 control_request 帧自身不携带 turn 作用域（G2）。
  ClaudeCodeControlRequestResult handle(
    Map<String, Object?> raw, {
    String? sessionId,
    String? turnId,
    String? cwd,
  }) {
    final requestId = _string(raw['request_id']);
    if (requestId == null) {
      _malformedCount += 1;
      _deniedCount += 1;
      _log.w('control_request missing request_id; synthesized deny frame');
      return ClaudeCodeControlRequestResult(
        responseFrame: _errorFrame(
          requestId: 'missing-request-id',
          error: 'Zeta denied control_request without request_id',
        ),
      );
    }

    final request = _map(raw['request']);
    final requestSubtype = _string(request?['subtype']) ?? 'unknown';

    if (requestSubtype != 'can_use_tool') {
      // 未知 control 类型：fail-closed，不 hang。
      _deniedCount += 1;
      _log.t(
        'Fail-closed deny control_request '
        '(subtype=$requestSubtype, deniedCount=$_deniedCount)',
      );
      return ClaudeCodeControlRequestResult(
        responseFrame: _errorFrame(
          requestId: requestId,
          error: 'Zeta denied unsupported control_request subtype',
        ),
      );
    }

    final toolUseId = _string(request?['tool_use_id']);
    final toolName = _string(request?['tool_name']);
    final toolInput = _map(request?['input']);
    if (toolUseId == null || toolName == null || toolInput == null) {
      _malformedCount += 1;
      _deniedCount += 1;
      _log.w('Malformed can_use_tool control_request; fail-closed');
      return ClaudeCodeControlRequestResult(
        responseFrame: _errorFrame(
          requestId: requestId,
          error: 'Zeta denied malformed can_use_tool request',
        ),
      );
    }

    // 同 request_id 重复到达：覆盖 pending，避免双卡；诊断只记 subtype。
    final pending = ClaudeCodePendingToolPermission(
      requestId: requestId,
      toolUseId: toolUseId,
      toolName: toolName,
      toolInput: Map<String, Object?>.unmodifiable(toolInput),
      sessionId: sessionId,
      turnId: turnId,
    );
    _pending[requestId] = pending;
    _permissionRequestedCount += 1;
    _log.t(
      'Permission requested '
      '(tool=$toolName, pending=${_pending.length}, '
      'requested=$_permissionRequestedCount)',
    );

    final event = AgentPermissionRequestedEvent(
      _buildPermissionRequest(pending: pending, cwd: cwd),
    );

    return ClaudeCodeControlRequestResult(events: <AgentEvent>[event]);
  }

  /// 将用户决策编码为 `control_response`，并移除 pending。
  ///
  /// 未知 [AgentPermissionDecision.requestId] 返回 null（调用方应忽略 / 记日志）。
  ClaudeCodeControlDecisionResult? resolveDecision(
    AgentPermissionDecision decision,
  ) {
    final pending = _pending.remove(decision.requestId);
    if (pending == null) {
      _unknownDecisionCount += 1;
      _log.w(
        'Ignoring response for unknown Claude Code permission '
        '${decision.requestId}',
      );
      return null;
    }

    final outcome = mapDecisionOutcome(decision);
    _resolvedCount += 1;
    _log.t(
      'Permission resolved '
      '(outcome=${outcome.name}, resolved=$_resolvedCount, '
      'pending=${_pending.length})',
    );

    return ClaudeCodeControlDecisionResult(
      responseFrame: buildControlResponse(
        requestId: pending.requestId,
        outcome: outcome,
        toolInput: pending.toolInput,
        message: decision.message,
      ),
      outcome: outcome,
      toolName: pending.toolName,
    );
  }

  /// 丢弃全部 pending（peer 关闭 / dispose）；不回写，CLI 侧会 hang 或超时。
  void clearPending() {
    if (_pending.isEmpty) {
      return;
    }
    final n = _pending.length;
    _pending.clear();
    _log.t('Cleared $n pending Claude Code permissions');
  }

  /// [AgentPermissionDecision] → 四种 CC outcome。
  ///
  /// | domain | outcome |
  /// |---|---|
  /// | approved + acceptForSession | allowAlways |
  /// | approved（含 accept） | allowOnce |
  /// | cancelTurn / commandDecision.cancel | denyAlways |
  /// | 其余拒绝 | denyOnce |
  static ClaudeCodeToolPermissionOutcome mapDecisionOutcome(
    AgentPermissionDecision decision,
  ) {
    final kind = decision.commandDecision;
    if (kind != null) {
      return switch (kind) {
        AgentCommandApprovalDecisionKind.accept =>
          ClaudeCodeToolPermissionOutcome.allowOnce,
        AgentCommandApprovalDecisionKind.acceptForSession =>
          ClaudeCodeToolPermissionOutcome.allowAlways,
        AgentCommandApprovalDecisionKind.acceptWithExecpolicyAmendment =>
          ClaudeCodeToolPermissionOutcome.allowOnce,
        AgentCommandApprovalDecisionKind.decline =>
          ClaudeCodeToolPermissionOutcome.denyOnce,
        AgentCommandApprovalDecisionKind.cancel =>
          ClaudeCodeToolPermissionOutcome.denyAlways,
      };
    }
    if (decision.approved) {
      return ClaudeCodeToolPermissionOutcome.allowOnce;
    }
    if (decision.cancelTurn) {
      return ClaudeCodeToolPermissionOutcome.denyAlways;
    }
    return ClaudeCodeToolPermissionOutcome.denyOnce;
  }

  /// 四种 outcome → SDK control protocol 的嵌套 `control_response`。
  static Map<String, Object?> buildControlResponse({
    required String requestId,
    required ClaudeCodeToolPermissionOutcome outcome,
    Map<String, Object?> toolInput = const <String, Object?>{},
    String? message,
  }) {
    final response = switch (outcome) {
      ClaudeCodeToolPermissionOutcome.allowOnce ||
      ClaudeCodeToolPermissionOutcome.allowAlways => <String, Object?>{
        'behavior': 'allow',
        'updatedInput': Map<String, Object?>.of(toolInput),
      },
      ClaudeCodeToolPermissionOutcome.denyOnce ||
      ClaudeCodeToolPermissionOutcome.denyAlways => <String, Object?>{
        'behavior': 'deny',
        'message': _denyMessage(message, outcome),
      },
    };
    return _successFrame(requestId: requestId, response: response);
  }

  static String _denyMessage(
    String? message,
    ClaudeCodeToolPermissionOutcome outcome,
  ) {
    final trimmed = message?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return switch (outcome) {
      ClaudeCodeToolPermissionOutcome.denyAlways =>
        'User denied tool use for this session',
      _ => 'User denied tool use',
    };
  }

  AgentPermissionRequest _buildPermissionRequest({
    required ClaudeCodePendingToolPermission pending,
    String? cwd,
  }) {
    final kind = _permissionKind(pending.toolName);
    final command = kind == AgentPermissionKind.commandExecution
        ? _string(pending.toolInput['command'])
        : null;
    final title = _titleFor(pending.toolName, command: command);

    // raw 只放白名单元数据（tool_name），不放 input/路径/命令正文（G7）。
    // command / description 走专用字段供 UI 展示。
    return AgentPermissionRequest(
      id: pending.requestId,
      title: title,
      kind: kind,
      description: textCatalog.permissionRequestDescription(
        'Claude Code',
        pending.toolName,
      ),
      command: command,
      cwd: cwd,
      sessionId: pending.sessionId,
      turnId: pending.turnId,
      raw: AgentProviderRawPayload.wrap(<String, Object?>{
        'tool_name': pending.toolName,
        'source': 'claude_code.can_use_tool',
      }),
    );
  }

  static AgentPermissionKind _permissionKind(String toolName) {
    final lower = toolName.toLowerCase();
    if (lower == 'bash' || lower == 'shell' || lower.contains('bash')) {
      return AgentPermissionKind.commandExecution;
    }
    if (lower == 'edit' ||
        lower == 'write' ||
        lower == 'multiedit' ||
        lower == 'notebookedit' ||
        lower.contains('edit') ||
        lower.contains('write')) {
      return AgentPermissionKind.fileChange;
    }
    return AgentPermissionKind.other;
  }

  static String _titleFor(String toolName, {String? command}) {
    if (command != null && command.isNotEmpty) {
      return 'Run $toolName';
    }
    return 'Use $toolName';
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
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
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
