/// 中立权限选项摘要（Codex profile 或 Grok mode 等均用此结构）。
///
/// [id] 对共享层不透明；具体协议含义由各 Provider 解释。
///
/// 迁移期保留；新代码应优先使用 [AgentPermissionOption] 与
/// [AgentPermissionPolicyPort]。
@Deprecated(
  'Use AgentPermissionOption via AgentPermissionPolicyPort.listPermissionOptions',
)
class AgentPermissionProfileSummary {
  /// 创建旧版权限选项摘要。
  const AgentPermissionProfileSummary({
    required this.id,
    required this.allowed,
    this.description,
  });

  /// 选项 id（如 `:workspace`、`ask`）。
  final String id;

  /// 当前环境是否允许选择。
  final bool allowed;

  /// 可选说明；非空时优先作为 [displayName]。
  final String? description;

  /// 与本 id 关联的内置 Composer 预设（若有）。
  AgentPermissionPreset? get matchedPreset =>
      AgentPermissionSelectionSnapshot.presetForOptionId(id);

  /// Composer 触发器 / 选项主标题：短 option label。
  ///
  /// 产品契约：触发器与 popover 选项均使用短标签（如 `Workspace write`、`Ask`），
  /// 不在触发器拼接审批副标题（` · Ask first`）。副标题见 [displaySubtitle]。
  String get displayName {
    final trimmed = description?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final preset = matchedPreset;
    if (preset != null) {
      return preset.label;
    }
    final rawId = id.trim();
    if (rawId.startsWith(':') && rawId.length > 1) {
      return rawId.substring(1);
    }
    return rawId;
  }

  /// 可选副标题（审批策略等）；Composer 触发器不使用。
  String get displaySubtitle {
    final preset = matchedPreset;
    if (preset != null) {
      return AgentPermissionSelectionSnapshot.approvalPolicyDisplayLabel(
        preset.approvalPolicy,
      );
    }
    return id.trim();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentPermissionProfileSummary &&
            other.id == id &&
            other.allowed == allowed &&
            other.description == description;
  }

  @override
  int get hashCode => Object.hash(id, allowed, description);
}

/// 迁移期权限策略运行时快照（含协议编码字段）。
///
/// 共享层以 [optionId] 为选择主键；[approvalPolicy] / [sandboxPolicy] /
/// [permissionProfileId] 是 Provider 可选编码细节，将在阶段 6 退出共享层。
///
/// 新 port API 请使用仅含 optionId 的 [AgentPermissionSelection]。
class AgentPermissionSelectionSnapshot {
  /// 创建运行时权限快照。
  const AgentPermissionSelectionSnapshot({
    this.optionId,
    this.approvalPolicy = defaultApprovalPolicy,
    this.sandboxPolicy = defaultSandboxPolicy,
    this.permissionProfileId,
  });

  /// 默认审批策略（协议 `AskForApproval` 字符串变体）。
  static const String defaultApprovalPolicy = 'on-request';

  /// 默认沙箱策略（域内 camelCase；编码时再映射到协议形状）。
  static const String defaultSandboxPolicy = 'workspaceWrite';

  /// 中立选项 id（唯一选择主键）。
  ///
  /// Codex 多为 `:workspace` 等 profile id；Grok 为 `ask` / `auto` 等。
  final String? optionId;

  /// 审批策略：`untrusted` / `on-request` / `never`。
  final String approvalPolicy;

  /// 沙箱策略：`readOnly` / `workspaceWrite` / `dangerFullAccess`。
  final String sandboxPolicy;

  /// Codex permission profile id；未显式指定时可由内置预设回填。
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
      permissionProfileId: ':danger-full-access',
    ),
  ];

  /// 解析后的选项 id：显式 [optionId] → profile id → 预设回填。
  String? get selectedOptionId {
    final explicit = optionId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return protocolPermissionProfileId;
  }

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

  /// 供 Codex 协议层使用的权限 profile id。
  String? get protocolPermissionProfileId {
    final explicitProfileId = permissionProfileId?.trim();
    if (explicitProfileId != null && explicitProfileId.isNotEmpty) {
      return explicitProfileId;
    }
    final fromOption = optionId?.trim();
    if (fromOption != null &&
        fromOption.isNotEmpty &&
        presetForOptionId(fromOption) != null) {
      return fromOption;
    }
    for (final preset in presets) {
      if (preset.approvalPolicy == approvalPolicy &&
          preset.sandboxPolicy == sandboxPolicy) {
        return preset.permissionProfileId;
      }
    }
    return null;
  }

  /// 展示标签（无选项列表时的回落）。
  ///
  /// 产品契约（与 Composer 触发器一致）：
  /// - 内置 Codex option → 短标签（`Workspace write` / `Read only` / `Full access`）
  /// - 显式非内置 option（含 Grok `ask`/`auto`/`always-approve`、自定义 profile id）
  ///   → 使用 option id 本身，**不得**按 approval/sandbox 误判成内置预设
  /// - 无 option、仅策略时 → 短预设名或策略组合回落
  String get displayLabel {
    final id = selectedOptionId;
    if (id != null && id.isNotEmpty) {
      final preset = presetForOptionId(id);
      if (preset != null) {
        return preset.label;
      }
      // Grok mode / 自定义 profile id：短 option 文案。
      return id;
    }
    final approvalLabel = approvalPolicyDisplayLabel(approvalPolicy);
    final sandboxLabel = sandboxPolicyDisplayLabel(sandboxPolicy);
    final presetId = matchedPresetId;
    if (presetId != null) {
      for (final preset in presets) {
        if (preset.id == presetId) {
          return preset.label;
        }
      }
    }
    return '$sandboxLabel · $approvalLabel';
  }

  AgentPermissionSelectionSnapshot copyWith({
    String? optionId,
    String? approvalPolicy,
    String? sandboxPolicy,
    String? permissionProfileId,
    bool clearOptionId = false,
    bool clearPermissionProfileId = false,
  }) {
    return AgentPermissionSelectionSnapshot(
      optionId: clearOptionId ? null : (optionId ?? this.optionId),
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

  static String normalizeApprovalPolicy(String? value) {
    return switch (value) {
      'untrusted' || 'on-request' || 'never' => value!,
      'on-failure' => 'on-request',
      _ => defaultApprovalPolicy,
    };
  }

  static String? normalizePersistedApprovalPolicy(String? value) {
    return value == null ? null : normalizeApprovalPolicy(value);
  }

  static String approvalPolicyDisplayLabel(String? value) {
    return switch (normalizeApprovalPolicy(value)) {
      'never' => 'Never ask',
      'untrusted' => 'Ask if untrusted',
      _ => 'Ask first',
    };
  }

  static String sandboxPolicyDisplayLabel(String? value) {
    return switch (value) {
      'readOnly' => 'Read only',
      'dangerFullAccess' => 'Full access',
      _ => 'Workspace write',
    };
  }

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

  /// 将选项 id 关联到内置 Composer 预设（Codex built-in profile）。
  static AgentPermissionPreset? presetForOptionId(String? optionId) {
    final normalized = optionId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final preset in presets) {
      final presetProfileId = preset.permissionProfileId?.trim();
      if (presetProfileId != null &&
          presetProfileId.isNotEmpty &&
          presetProfileId == normalized) {
        return preset;
      }
    }
    return null;
  }

  /// @nodoc 兼容旧名。
  static AgentPermissionPreset? presetForProfileId(String? profileId) =>
      presetForOptionId(profileId);

  /// 按中立选项 id 构造选择快照。
  ///
  /// - 命中 Codex 内置 profile：回填 approval/sandbox/profileId
  /// - 其它不透明 id（含 Grok mode）：只记录 [optionId]，approval/sandbox 用默认
  static AgentPermissionSelectionSnapshot forOptionId(String optionId) {
    final normalized = optionId.trim();
    final preset = presetForOptionId(normalized);
    if (preset != null) {
      return AgentPermissionSelectionSnapshot(
        optionId: normalized,
        approvalPolicy: preset.approvalPolicy,
        sandboxPolicy: preset.sandboxPolicy,
        permissionProfileId: normalized,
      );
    }
    return AgentPermissionSelectionSnapshot(
      optionId: normalized,
      approvalPolicy: defaultApprovalPolicy,
      sandboxPolicy: defaultSandboxPolicy,
      // 非内置 id 不自动当作 Codex profile，避免 Grok mode 误写入 profile 字段。
    );
  }

  /// 兼容旧 API：按 profile id 构造（等同 [forOptionId] 且绑定 profile）。
  static AgentPermissionSelectionSnapshot forProfileId(String profileId) {
    final normalized = profileId.trim();
    final preset = presetForOptionId(normalized);
    if (preset != null) {
      return forOptionId(normalized);
    }
    // 自定义 Codex profile：仍绑定 permissionProfileId。
    return AgentPermissionSelectionSnapshot(
      optionId: normalized,
      approvalPolicy: defaultApprovalPolicy,
      sandboxPolicy: defaultSandboxPolicy,
      permissionProfileId: normalized,
    );
  }
}

/// Composer 策略预设项（Codex 内置 profile 表）。
///
/// 将迁入 Codex data codec；新代码不应在 application 层依赖本类型。
@Deprecated(
  'Codex built-in presets will move to data-layer codec; use opaque option ids',
)
class AgentPermissionPreset {
  /// 创建内置预设。
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
