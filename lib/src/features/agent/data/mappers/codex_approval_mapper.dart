part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 把服务端审批请求映射为领域事件，并生成回写响应。
class _CodexApprovalMapper {
  _MappedApprovalRequest mapRequest(JsonRpcRequest request) {
    final kindAndTitle = switch (request.method) {
      'item/commandExecution/requestApproval' || 'execCommandApproval' => (
        AgentPermissionKind.commandExecution,
        _string(request.params['command']) ?? 'Run command',
      ),
      'item/fileChange/requestApproval' || 'applyPatchApproval' => (
        AgentPermissionKind.fileChange,
        'Apply file changes',
      ),
      'item/permissions/requestApproval' => (
        AgentPermissionKind.permissions,
        'Grant additional permissions',
      ),
      'item/tool/requestUserInput' || 'mcpServer/elicitation/request' => (
        AgentPermissionKind.userInput,
        'Agent requests input',
      ),
      _ => (AgentPermissionKind.other, request.method),
    };

    final id = '${request.id}';
    final pendingApproval = _PendingApproval(
      id: id,
      requestId: request.id,
      method: request.method,
      params: request.params,
    );
    final reason = _string(request.params['reason']);
    final event = AgentPermissionRequestedEvent(
      AgentPermissionRequest(
        id: id,
        title: kindAndTitle.$2,
        kind: kindAndTitle.$1,
        description: reason,
        command: _string(request.params['command']),
        cwd: _string(request.params['cwd']),
        sessionId: _string(request.params['threadId']),
        turnId: _string(request.params['turnId']),
        fileChanges: _map(request.params['fileChanges']),
        raw: request.params,
      ),
    );
    return _MappedApprovalRequest(
      pendingApproval: pendingApproval,
      event: event,
    );
  }

  /// 根据 Codex 请求类型生成对应审批响应。
  Object? approvalResponse(
    _PendingApproval pending,
    AgentPermissionDecision decision,
  ) {
    final declined = decision.cancelTurn ? 'cancel' : 'decline';
    final accepted = 'accept';
    return switch (pending.method) {
      'item/commandExecution/requestApproval' => <String, Object?>{
        'decision': decision.approved ? accepted : declined,
      },
      'item/fileChange/requestApproval' => <String, Object?>{
        'decision': decision.approved ? accepted : declined,
      },
      'item/permissions/requestApproval' => <String, Object?>{
        'permissions': decision.approved
            ? pending.params['permissions']
            : <String, Object?>{'fileSystem': null, 'network': null},
        'scope': 'turn',
      },
      'execCommandApproval' => <String, Object?>{
        'decision': decision.approved ? 'approved' : 'denied',
      },
      'applyPatchApproval' => <String, Object?>{
        'decision': decision.approved ? 'approved' : 'denied',
      },
      _ => decision.approved ? <String, Object?>{} : null,
    };
  }
}

class _MappedApprovalRequest {
  const _MappedApprovalRequest({
    required this.pendingApproval,
    required this.event,
  });

  final _PendingApproval pendingApproval;
  final AgentPermissionRequestedEvent event;
}

/// 一个尚未回复的 app-server 审批请求。
class _PendingApproval {
  const _PendingApproval({
    required this.id,
    required this.requestId,
    required this.method,
    required this.params,
  });

  /// UI 使用的稳定请求 id。
  final String id;

  /// JSON-RPC 请求的原始 id，用于回写响应时定位。
  final Object requestId;

  /// 审批方法名，如 item/commandExecution/requestApproval。
  final String method;

  /// 审批请求的原始参数，包含命令、文件变更等上下文信息。
  final Map<String, Object?> params;
}
