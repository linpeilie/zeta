/// `permissionProfile/list` 返回的权限配置摘要。
class AgentPermissionProfileSummary {
  const AgentPermissionProfileSummary({
    required this.id,
    required this.allowed,
    this.description,
  });

  /// 配置 id（如 `:workspace`）。
  final String id;

  /// 当前环境是否允许选择该配置。
  final bool allowed;

  /// 可选的用户可见说明。
  final String? description;
}

/// Composer 中选择的审批/沙箱策略组合。
///
/// 持久化到 [AgentProviderConfig]，并在 `turn/start` / `thread/start` 时下发。
class AgentPermissionSelection {
  const AgentPermissionSelection({
    this.approvalPolicy = defaultApprovalPolicy,
    this.sandboxPolicy = defaultSandboxPolicy,
    this.permissionProfileId,
  });

  /// 默认审批策略（协议 `AskForApproval` 字符串变体）。
  static const String defaultApprovalPolicy = 'on-request';

  /// 默认沙箱策略（域内 camelCase；编码时再映射到协议形状）。
  static const String defaultSandboxPolicy = 'workspaceWrite';

  /// 审批策略：`untrusted` / `on-failure` / `on-request` / `never`。
  final String approvalPolicy;

  /// 沙箱策略：`readOnly` / `workspaceWrite` / `dangerFullAccess`。
  final String sandboxPolicy;

  /// 可选的 permission profile id（展示用；turn/start 仍发 approval+sandbox）。
  final String? permissionProfileId;

  /// UI 预设组合。
  static const List<AgentPermissionPreset> presets = <AgentPermissionPreset>[
    AgentPermissionPreset(
      id: 'readOnly',
      label: 'Read only',
      approvalPolicy: 'on-request',
      sandboxPolicy: 'readOnly',
    ),
    AgentPermissionPreset(
      id: 'workspace',
      label: 'Workspace write',
      approvalPolicy: 'on-request',
      sandboxPolicy: 'workspaceWrite',
    ),
    AgentPermissionPreset(
      id: 'fullAccess',
      label: 'Full access',
      approvalPolicy: 'never',
      sandboxPolicy: 'dangerFullAccess',
    ),
  ];

  /// 匹配预设 id；无匹配时返回 null。
  String? get matchedPresetId {
    for (final preset in presets) {
      if (preset.approvalPolicy == approvalPolicy &&
          preset.sandboxPolicy == sandboxPolicy) {
        return preset.id;
      }
    }
    return null;
  }

  /// 展示标签。
  String get displayLabel {
    final presetId = matchedPresetId;
    if (presetId != null) {
      for (final preset in presets) {
        if (preset.id == presetId) {
          return preset.label;
        }
      }
    }
    return '$sandboxPolicy · $approvalPolicy';
  }

  AgentPermissionSelection copyWith({
    String? approvalPolicy,
    String? sandboxPolicy,
    String? permissionProfileId,
    bool clearPermissionProfileId = false,
  }) {
    return AgentPermissionSelection(
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      sandboxPolicy: sandboxPolicy ?? this.sandboxPolicy,
      permissionProfileId: clearPermissionProfileId
          ? null
          : (permissionProfileId ?? this.permissionProfileId),
    );
  }

  /// 编码为 `turn/start.sandboxPolicy` 对象。
  Map<String, Object?> toTurnSandboxPolicy() {
    return <String, Object?>{'type': sandboxPolicy};
  }

  /// 编码为 `thread/start.sandbox` 的 SandboxMode 字符串。
  String toThreadSandboxMode() {
    return switch (sandboxPolicy) {
      'readOnly' => 'read-only',
      'dangerFullAccess' => 'danger-full-access',
      _ => 'workspace-write',
    };
  }

  /// 从协议 sandbox 对象或 SandboxMode 字符串解析域内 sandboxPolicy。
  static String? sandboxPolicyFromProtocol(Object? value) {
    if (value is String) {
      return switch (value) {
        'read-only' || 'readOnly' => 'readOnly',
        'danger-full-access' || 'dangerFullAccess' => 'dangerFullAccess',
        'workspace-write' || 'workspaceWrite' => 'workspaceWrite',
        _ => null,
      };
    }
    if (value is Map) {
      final type = value['type'];
      if (type is String) {
        return sandboxPolicyFromProtocol(type);
      }
    }
    return null;
  }
}

/// Composer 策略预设项。
class AgentPermissionPreset {
  const AgentPermissionPreset({
    required this.id,
    required this.label,
    required this.approvalPolicy,
    required this.sandboxPolicy,
  });

  final String id;
  final String label;
  final String approvalPolicy;
  final String sandboxPolicy;
}
