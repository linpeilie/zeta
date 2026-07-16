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

  /// 审批策略：`untrusted` / `on-request` / `never`。
  ///
  /// 旧配置中的 `on-failure` 会在读取和协议编码前迁移为 `on-request`。
  final String approvalPolicy;

  /// 沙箱策略：`readOnly` / `workspaceWrite` / `dangerFullAccess`。
  final String sandboxPolicy;

  /// 可选的 permission profile id。
  ///
  /// Codex experimental API 可直接消费该值；未显式指定时，内置预设会回填
  /// 对应的稳定 built-in profile id。
  final String? permissionProfileId;

  /// UI 预设组合。
  static const List<AgentPermissionPreset> presets = <AgentPermissionPreset>[
    AgentPermissionPreset(
      id: 'readOnly',
      label: 'Read only',
      approvalPolicy: 'on-request',
      sandboxPolicy: 'readOnly',
      permissionProfileId: ':read-only',
    ),
    AgentPermissionPreset(
      id: 'workspace',
      label: 'Workspace write',
      approvalPolicy: 'on-request',
      sandboxPolicy: 'workspaceWrite',
      permissionProfileId: ':workspace',
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
          preset.sandboxPolicy == sandboxPolicy &&
          (permissionProfileId == null ||
              permissionProfileId == preset.permissionProfileId)) {
        return preset.id;
      }
    }
    return null;
  }

  /// 供协议层使用的权限 profile id。
  ///
  /// 先使用显式 profile；否则对内置预设回填其稳定 id，避免预设仅落成旧版 sandbox。
  String? get protocolPermissionProfileId {
    final explicitProfileId = permissionProfileId?.trim();
    if (explicitProfileId != null && explicitProfileId.isNotEmpty) {
      return explicitProfileId;
    }
    for (final preset in presets) {
      if (preset.approvalPolicy == approvalPolicy &&
          preset.sandboxPolicy == sandboxPolicy) {
        return preset.permissionProfileId;
      }
    }
    return null;
  }

  /// 展示标签。
  String get displayLabel {
    final approvalLabel = approvalPolicyDisplayLabel(approvalPolicy);
    final presetId = matchedPresetId;
    if (presetId != null) {
      for (final preset in presets) {
        if (preset.id == presetId) {
          return '${preset.label} · $approvalLabel';
        }
      }
    }
    final sandboxLabel = sandboxPolicyDisplayLabel(sandboxPolicy);
    final profileId = permissionProfileId?.trim();
    if (profileId != null && profileId.isNotEmpty) {
      return '$sandboxLabel · $approvalLabel · $profileId';
    }
    return '$sandboxLabel · $approvalLabel';
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

  /// 把持久化或 UI 输入归一化为 0.144.5 稳定协议支持的审批策略。
  static String normalizeApprovalPolicy(String? value) {
    return switch (value) {
      'untrusted' || 'on-request' || 'never' => value!,
      'on-failure' => 'on-request',
      _ => defaultApprovalPolicy,
    };
  }

  /// 可空配置的迁移入口；未配置仍保持 `null`，由上层应用默认值。
  static String? normalizePersistedApprovalPolicy(String? value) {
    return value == null ? null : normalizeApprovalPolicy(value);
  }

  /// 用户可见的审批策略标签。
  static String approvalPolicyDisplayLabel(String? value) {
    return switch (normalizeApprovalPolicy(value)) {
      'never' => 'Never ask',
      'untrusted' => 'Ask if untrusted',
      _ => 'Ask first',
    };
  }

  /// 用户可见的沙箱标签。
  static String sandboxPolicyDisplayLabel(String? value) {
    return switch (value) {
      'readOnly' => 'Read only',
      'dangerFullAccess' => 'Full access',
      _ => 'Workspace write',
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
    this.permissionProfileId,
  });

  final String id;
  final String label;
  final String approvalPolicy;
  final String sandboxPolicy;
  final String? permissionProfileId;
}
