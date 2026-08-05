/// Provider 配置中权限偏好的 V1→V2 迁移（纯领域逻辑，无 IO）。
///
/// 只消费 Zeta 自有 `~/.zeta` 配置字段；严禁读取 `~/.codex` / `~/.grok`。
abstract final class AgentPermissionPreferenceMigration {
  /// 从 V1/V2 原始字段解析最终 `selectedPermissionOptionId`。
  ///
  /// [kindName] 为 [AgentProviderKind.name]（如 `codexAppServer`、`acp`）。
  ///
  /// **优先级（所有 provider）：**
  /// 1. V2 `selectedPermissionOptionId` 存在且非空 → 唯一真源
  /// 2. 否则 Codex：V1 profile → approval/sandbox 推导 built-in
  /// 3. 否则 Grok：V1 `selectedPermissionMode`（default/空/未知 → `ask`）
  /// 4. 其它 provider：仅接受 optionId，不猜语义
  ///
  /// 未知或损坏的 policy 组合不得推导为更高权限（返回 null）。
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
    // V2 真源：optionId 优先于全部 V1 字段（含 stale profile）。
    final option = _nonEmpty(selectedPermissionOptionId);
    if (option != null) {
      return option;
    }
    final profile = _nonEmpty(selectedPermissionProfileId);
    if (profile != null) {
      return profile;
    }
    final approval = _nonEmpty(selectedApprovalPolicy);
    final sandbox = _nonEmpty(selectedSandboxPolicy);
    // 不完整 policy 不填默认值，避免把残缺数据抬升为内置权限。
    if (approval == null || sandbox == null) {
      return null;
    }
    return _builtInFromPolicies(
      approvalPolicy: approval,
      sandboxPolicy: sandbox,
    );
  }

  static String? _grok({
    String? selectedPermissionOptionId,
    String? selectedPermissionMode,
  }) {
    // V2 optionId 优先；仅在缺失时回退 legacy mode。
    final option = _nonEmpty(selectedPermissionOptionId);
    if (option != null) {
      return _normalizeGrokMode(option);
    }
    final hasModeField = selectedPermissionMode != null;
    final mode = _nonEmpty(selectedPermissionMode);
    if (mode == null) {
      // 字段存在但为空 → Ask；完全未配置 → null。
      // 亦覆盖：optionId 字段存在但为空串、且无 mode 的情况。
      final hasOptionField = selectedPermissionOptionId != null;
      return (hasOptionField || hasModeField) ? 'ask' : null;
    }
    return _normalizeGrokMode(mode);
  }

  /// Grok mode / option 归一化：合法三态保留；default/未知 fail-closed 为 ask。
  static String _normalizeGrokMode(String raw) {
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
  ///
  /// 未知 approval/sandbox 返回 null，不默认同化为更高权限组合。
  static String? _builtInFromPolicies({
    required String approvalPolicy,
    required String sandboxPolicy,
  }) {
    final approval = switch (approvalPolicy) {
      'untrusted' || 'on-request' || 'never' => approvalPolicy,
      'on-failure' => 'on-request',
      _ => null,
    };
    final sandbox = switch (sandboxPolicy) {
      'readOnly' || 'workspaceWrite' || 'dangerFullAccess' => sandboxPolicy,
      'read-only' => 'readOnly',
      'workspace-write' => 'workspaceWrite',
      'danger-full-access' => 'dangerFullAccess',
      _ => null,
    };
    if (approval == null || sandbox == null) {
      return null;
    }
    return switch ((approval, sandbox)) {
      ('on-request', 'readOnly') => ':read-only',
      ('on-request', 'workspaceWrite') => ':workspace',
      ('never', 'dangerFullAccess') => ':danger-full-access',
      // untrusted 等无稳定 built-in 映射 → null（fail-closed）
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
