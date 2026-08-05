/// Provider 配置中权限偏好的 V1→V2 迁移（纯领域逻辑，无 IO）。
///
/// 只消费 Zeta 自有 `~/.zeta` 配置字段；严禁读取 `~/.codex` / `~/.grok`。
abstract final class AgentPermissionPreferenceMigration {
  /// 从 V1/V2 原始字段解析最终 `selectedPermissionOptionId`。
  ///
  /// [kindName] 为 [AgentProviderKind.name]（如 `codexAppServer`、`acp`）。
  ///
  /// - Codex：profile 优先；无 profile 时由 approval/sandbox 推导 built-in；
  ///   自定义 profile 原样保留。
  /// - Grok（`acp`）：兼容 mode；default/空/未知 → `ask`。
  /// - 其它 provider：仅接受通用 optionId，不猜语义。
  static String? resolveOptionId({
    required String kindName,
    String? selectedPermissionOptionId,
    String? selectedPermissionProfileId,
    String? selectedPermissionMode,
    String? selectedApprovalPolicy,
    String? selectedSandboxPolicy,
  }) {
    return switch (kindName) {
      'codexAppServer' => _codex(
        selectedPermissionOptionId: selectedPermissionOptionId,
        selectedPermissionProfileId: selectedPermissionProfileId,
        selectedApprovalPolicy: selectedApprovalPolicy,
        selectedSandboxPolicy: selectedSandboxPolicy,
      ),
      'acp' => _grok(
        selectedPermissionOptionId: selectedPermissionOptionId,
        selectedPermissionMode: selectedPermissionMode,
      ),
      _ => _generic(selectedPermissionOptionId: selectedPermissionOptionId),
    };
  }

  static String? _codex({
    String? selectedPermissionOptionId,
    String? selectedPermissionProfileId,
    String? selectedApprovalPolicy,
    String? selectedSandboxPolicy,
  }) {
    final profile = _nonEmpty(selectedPermissionProfileId);
    if (profile != null) {
      return profile;
    }
    final option = _nonEmpty(selectedPermissionOptionId);
    if (option != null) {
      return option;
    }
    final approval = _nonEmpty(selectedApprovalPolicy);
    final sandbox = _nonEmpty(selectedSandboxPolicy);
    if (approval == null && sandbox == null) {
      return null;
    }
    return _builtInFromPolicies(
      approvalPolicy: approval ?? 'on-request',
      sandboxPolicy: sandbox ?? 'workspaceWrite',
    );
  }

  static String? _grok({
    String? selectedPermissionOptionId,
    String? selectedPermissionMode,
  }) {
    final hasField =
        selectedPermissionOptionId != null || selectedPermissionMode != null;
    final raw =
        _nonEmpty(selectedPermissionOptionId) ??
        _nonEmpty(selectedPermissionMode);
    if (raw == null) {
      // 字段存在但为空 → Ask；完全未配置 → null。
      return hasField ? 'ask' : null;
    }
    return switch (raw.toLowerCase()) {
      'default' || 'ask' => 'ask',
      'auto' => 'auto',
      'always-approve' ||
      'always_approve' ||
      'alwaysapprove' ||
      'yolo' ||
      'bypasspermissions' ||
      'bypass_permissions' => 'always-approve',
      _ => 'ask',
    };
  }

  static String? _generic({String? selectedPermissionOptionId}) {
    return _nonEmpty(selectedPermissionOptionId);
  }

  /// 与 Codex built-in 表一致的推导（迁移输入）。
  static String? _builtInFromPolicies({
    required String approvalPolicy,
    required String sandboxPolicy,
  }) {
    final approval = switch (approvalPolicy) {
      'untrusted' || 'on-request' || 'never' => approvalPolicy,
      'on-failure' => 'on-request',
      _ => 'on-request',
    };
    final sandbox = switch (sandboxPolicy) {
      'readOnly' || 'workspaceWrite' || 'dangerFullAccess' => sandboxPolicy,
      'read-only' => 'readOnly',
      'workspace-write' => 'workspaceWrite',
      'danger-full-access' => 'dangerFullAccess',
      _ => 'workspaceWrite',
    };
    return switch ((approval, sandbox)) {
      ('on-request', 'readOnly') => ':read-only',
      ('on-request', 'workspaceWrite') => ':workspace',
      ('never', 'dangerFullAccess') => ':danger-full-access',
      _ => null,
    };
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
