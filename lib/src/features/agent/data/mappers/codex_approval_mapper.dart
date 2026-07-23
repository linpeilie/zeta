part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 把服务端审批请求映射为领域事件，并生成回写响应。
class _CodexApprovalMapper {
  /// 可走 UI 审批卡片流程的服务端请求 method。
  static const Set<String> _interactiveMethods = <String>{
    'item/commandExecution/requestApproval',
    'item/fileChange/requestApproval',
    'item/permissions/requestApproval',
    'mcpServer/elicitation/request',
    'execCommandApproval',
    'applyPatchApproval',
  };

  /// 判断服务端请求是否应当被立即拒绝，返回对应的 JSON-RPC error。
  ///
  /// 返回 null 表示该请求可以进入 UI 审批卡片流程。这些请求的响应有严格
  /// schema，伪造 `{}`/null 成功应答会让服务端 turn 卡住，所以统一用
  /// `-32601 method not found` 诚实告知客户端未实现。
  JsonRpcError? rejectionFor(JsonRpcRequest request) {
    return switch (request.method) {
      // 动态工具调用需要客户端事先注册工具，本客户端未注册也无法执行。
      'item/tool/call' => const JsonRpcError(
        code: -32601,
        message: 'Dynamic tool calls are not supported by this client',
      ),
      // ChatGPT 托管鉴权 token 由服务端自身维护，客户端无法代为刷新。
      'account/chatgptAuthTokens/refresh' => const JsonRpcError(
        code: -32601,
        message: 'ChatGPT auth token refresh is not supported by this client',
      ),
      // 未通过 capabilities 声明支持 attestation，正常不应收到。
      'attestation/generate' => const JsonRpcError(
        code: -32601,
        message: 'Attestation generation is not supported by this client',
      ),
      final method when _interactiveMethods.contains(method) => null,
      final method => JsonRpcError(
        code: -32601,
        message: 'Unsupported server request: $method',
      ),
    };
  }

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
      'mcpServer/elicitation/request' => (
        AgentPermissionKind.other,
        'MCP server requests input',
      ),
      _ => (AgentPermissionKind.other, request.method),
    };

    final id = '${request.id}';
    final pendingApproval = _PendingApproval(
      id: id,
      requestId: request.id,
      runtimeScope: request.runtimeScope,
      method: request.method,
      params: request.params,
    );
    final reason = _string(request.params['reason']);
    final commandActions =
        request.method == 'item/commandExecution/requestApproval' ||
            request.method == 'execCommandApproval'
        ? _commandActionSummaries(request.params['commandActions'])
        : const <String>[];
    final proposedAmendment =
        request.method == 'item/commandExecution/requestApproval'
        ? _stringList(request.params['proposedExecpolicyAmendment'])
        : const <String>[];
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
        commandActions: commandActions,
        proposedExecpolicyAmendment: proposedAmendment,
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
        'decision': _commandExecutionDecision(decision),
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
      // McpServerElicitationRequestResponse 要求 action 字段；
      // decline/cancel 无 content，accept 暂以空表单内容应答。
      'mcpServer/elicitation/request' => switch ((
        decision.approved,
        decision.cancelTurn,
      )) {
        (true, _) => <String, Object?>{
          'action': 'accept',
          'content': <String, Object?>{},
        },
        (false, true) => <String, Object?>{'action': 'cancel'},
        (false, false) => <String, Object?>{'action': 'decline'},
      },
      // rejectionFor 已挡掉未知方法，此分支正常不可达；保留 `{}` 兜底，
      // 避免返回 null 触碰严格 schema。
      _ => const <String, Object?>{},
    };
  }

  /// 编码命令执行审批决策（含 session / execpolicy 变体）。
  Object _commandExecutionDecision(AgentPermissionDecision decision) {
    final kind = decision.commandDecision;
    if (kind != null) {
      return switch (kind) {
        AgentCommandApprovalDecisionKind.accept => 'accept',
        AgentCommandApprovalDecisionKind.acceptForSession => 'acceptForSession',
        AgentCommandApprovalDecisionKind.acceptWithExecpolicyAmendment =>
          <String, Object?>{
            'acceptWithExecpolicyAmendment': <String, Object?>{
              'execpolicy_amendment': List<String>.unmodifiable(
                decision.execpolicyAmendment,
              ),
            },
          },
        AgentCommandApprovalDecisionKind.decline => 'decline',
        AgentCommandApprovalDecisionKind.cancel => 'cancel',
      };
    }
    if (decision.approved) {
      return 'accept';
    }
    return decision.cancelTurn ? 'cancel' : 'decline';
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
    required this.runtimeScope,
    required this.method,
    required this.params,
  });

  /// UI 使用的稳定请求 id。
  final String id;

  /// JSON-RPC 请求的原始 id，用于回写响应时定位。
  final Object requestId;

  /// 收到请求时的连接身份；Provider 重启后禁止向新连接回写旧审批。
  final AgentRuntimeScope? runtimeScope;

  /// 审批方法名，如 item/commandExecution/requestApproval。
  final String method;

  /// 审批请求的原始参数，包含命令、文件变更等上下文信息。
  final Map<String, Object?> params;
}
