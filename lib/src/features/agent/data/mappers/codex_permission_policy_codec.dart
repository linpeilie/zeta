import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Codex 权限策略编解码（协议私货，仅 Codex data 层使用）。
///
/// 负责 built-in profile 标签、自定义 profile 不透明映射、approval/sandbox
/// 编解码、thread settings 完整快照与旧配置迁移。共享层不得依赖本类型。
abstract final class CodexPermissionPolicyCodec {
  static const String defaultApprovalPolicy = 'on-request';
  static const String defaultSandboxPolicy = 'workspaceWrite';

  /// Codex 内置 permission profile 表（产品短标签）。
  static const List<CodexBuiltInPermissionProfile> builtInProfiles =
      <CodexBuiltInPermissionProfile>[
        CodexBuiltInPermissionProfile(
          id: ':read-only',
          label: 'Read only',
          approvalPolicy: 'on-request',
          sandboxPolicy: 'readOnly',
        ),
        CodexBuiltInPermissionProfile(
          id: ':workspace',
          label: 'Workspace write',
          approvalPolicy: 'on-request',
          sandboxPolicy: 'workspaceWrite',
        ),
        CodexBuiltInPermissionProfile(
          id: ':danger-full-access',
          label: 'Full access',
          approvalPolicy: 'never',
          sandboxPolicy: 'dangerFullAccess',
        ),
      ];

  /// 内置 profile 默认 option（workspace write）。
  static const String defaultBuiltInOptionId = ':workspace';

  /// 查找内置 profile；自定义 id 返回 null。
  static CodexBuiltInPermissionProfile? builtInForId(String? optionId) {
    final normalized = optionId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final profile in builtInProfiles) {
      if (profile.id == normalized) {
        return profile;
      }
    }
    return null;
  }

  /// 用户可见 label：内置用产品名，自定义用 id 本身（不解析 `:` 形状）。
  static String displayLabelForOptionId(String optionId) {
    final builtIn = builtInForId(optionId);
    if (builtIn != null) {
      return builtIn.label;
    }
    final trimmed = optionId.trim();
    return trimmed.isEmpty ? optionId : trimmed;
  }

  /// 规范化审批策略；未知值回落默认。
  static String normalizeApprovalPolicy(String? value) {
    return switch (value) {
      'untrusted' || 'on-request' || 'never' => value!,
      'on-failure' => 'on-request',
      _ => defaultApprovalPolicy,
    };
  }

  /// 持久化字段规范化；null 保持 null。
  static String? normalizePersistedApprovalPolicy(String? value) {
    return value == null ? null : normalizeApprovalPolicy(value);
  }

  /// 协议 sandbox（kebab / camel / 对象）→ 域内 camelCase。
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

  /// `turn/start.sandboxPolicy` 对象。
  static Map<String, Object?> toTurnSandboxPolicy(String sandboxPolicy) {
    return <String, Object?>{'type': sandboxPolicy};
  }

  /// `thread/start.sandbox` 的 SandboxMode 字符串。
  static String toThreadSandboxMode(String sandboxPolicy) {
    return switch (sandboxPolicy) {
      'readOnly' => 'read-only',
      'dangerFullAccess' => 'danger-full-access',
      _ => 'workspace-write',
    };
  }

  /// 供协议层使用的 profile id：显式 profile 优先，不按策略覆盖自定义 id。
  static String? protocolPermissionProfileId(
    CodexPermissionRuntimeSnapshot selection,
  ) {
    final explicitProfileId = selection.permissionProfileId?.trim();
    if (explicitProfileId != null && explicitProfileId.isNotEmpty) {
      return explicitProfileId;
    }
    final fromOption = selection.optionId?.trim();
    if (fromOption != null &&
        fromOption.isNotEmpty &&
        builtInForId(fromOption) != null) {
      return fromOption;
    }
    // 无显式 profile 时，仅用 approval/sandbox 回落内置（legacy）。
    for (final profile in builtInProfiles) {
      if (profile.approvalPolicy == selection.approvalPolicy &&
          profile.sandboxPolicy == selection.sandboxPolicy) {
        return profile.id;
      }
    }
    return null;
  }

  /// 按 option id 构造运行时快照。
  ///
  /// - 内置 id：回填 approval/sandbox/profileId
  /// - 其它 id：仅 optionId（不写入 profile，避免 Grok mode 误绑）
  static CodexPermissionRuntimeSnapshot snapshotForOptionId(String optionId) {
    final normalized = optionId.trim();
    final builtIn = builtInForId(normalized);
    if (builtIn != null) {
      return CodexPermissionRuntimeSnapshot(
        optionId: normalized,
        approvalPolicy: builtIn.approvalPolicy,
        sandboxPolicy: builtIn.sandboxPolicy,
        permissionProfileId: normalized,
      );
    }
    return CodexPermissionRuntimeSnapshot(
      optionId: normalized,
      approvalPolicy: defaultApprovalPolicy,
      sandboxPolicy: defaultSandboxPolicy,
    );
  }

  /// 按 Codex profile id 构造（自定义 id 无 `:` 要求，始终绑定 profile）。
  static CodexPermissionRuntimeSnapshot snapshotForProfileId(String profileId) {
    final normalized = profileId.trim();
    final builtIn = builtInForId(normalized);
    if (builtIn != null) {
      return snapshotForOptionId(normalized);
    }
    return CodexPermissionRuntimeSnapshot(
      optionId: normalized,
      approvalPolicy: defaultApprovalPolicy,
      sandboxPolicy: defaultSandboxPolicy,
      permissionProfileId: normalized,
    );
  }

  /// 从全局配置恢复快照。
  ///
  /// V2 仅有 [AgentProviderConfig.selectedPermissionOptionId]：按 profile 语义
  /// 绑定（自定义 id 无损）。V1 遗留 approval/sandbox/profile 字段若仍在内存中
  /// 则优先显式 profile，否则由 option 展开。
  static CodexPermissionRuntimeSnapshot snapshotFromConfig(
    AgentProviderConfig config,
  ) {
    // V2：配置真源仅为 selectedPermissionOptionId（解码时已完成 V1 迁移）。
    final optionId = config.resolvedPermissionOptionId?.trim();
    if (optionId != null && optionId.isNotEmpty) {
      return snapshotForProfileId(optionId);
    }
    return const CodexPermissionRuntimeSnapshot();
  }

  /// 无 profile 的旧 approval/sandbox 组合 → 内置 option（迁移输入）。
  static String? builtInOptionIdFromPolicies({
    required String approvalPolicy,
    required String sandboxPolicy,
  }) {
    final approval = normalizeApprovalPolicy(approvalPolicy);
    for (final profile in builtInProfiles) {
      if (profile.approvalPolicy == approval &&
          profile.sandboxPolicy == sandboxPolicy) {
        return profile.id;
      }
    }
    return null;
  }

  /// 将中立 selection 应用到 Codex 运行时快照。
  ///
  /// 任意非空 optionId 均作为 profile 绑定（Codex 语义）；不要求前导 `:`。
  static CodexPermissionRuntimeSnapshot applySelection(
    AgentPermissionSelection selection,
  ) {
    return snapshotForProfileId(selection.optionId);
  }

  /// 将阶段 B 的中立请求快照解析为本次 Codex RPC 独占的协议快照。
  ///
  /// 只有请求没有选择时才使用构造 Provider 时冻结的 [configFallback]；
  /// 用户选择与 thread settings 不得修改该 fallback。
  static CodexPermissionRuntimeSnapshot runtimeSnapshotForRequest(
    AgentPermissionRequestSnapshot request, {
    required CodexPermissionRuntimeSnapshot configFallback,
  }) {
    final optionId = request.selection?.optionId.trim();
    if (optionId == null || optionId.isEmpty) {
      return configFallback;
    }
    return snapshotForProfileId(optionId);
  }

  /// 解码 `thread/settings/updated` 中的权限字段为完整快照。
  ///
  /// 规则：
  /// 1. 有 active profile → optionId/profileId 取 profile
  /// 2. 无 profile 时，完整可映射的 approval+sandbox → 对应 built-in optionId
  /// 3. 无法确定稳定 optionId 时返回 null（不猜测更高权限）
  static CodexPermissionRuntimeSnapshot? decodeThreadSettings(
    Map<String, Object?> settings,
  ) {
    final approvalRaw = settings['approvalPolicy'];
    final approval = approvalRaw is String && approvalRaw.trim().isNotEmpty
        ? normalizeApprovalPolicy(approvalRaw)
        : null;
    final sandbox = sandboxPolicyFromProtocol(
      settings['sandboxPolicy'] ?? settings['sandbox'],
    );
    final activeProfile = settings['activePermissionProfile'];
    String? profileId;
    if (activeProfile is Map) {
      final id = activeProfile['id'];
      if (id is String && id.trim().isNotEmpty) {
        profileId = id.trim();
      }
    }
    if (profileId != null) {
      return CodexPermissionRuntimeSnapshot(
        optionId: profileId,
        approvalPolicy: approval ?? defaultApprovalPolicy,
        sandboxPolicy: sandbox ?? defaultSandboxPolicy,
        permissionProfileId: profileId,
      );
    }
    if (approval != null && sandbox != null) {
      final optionId = builtInOptionIdFromPolicies(
        approvalPolicy: approval,
        sandboxPolicy: sandbox,
      );
      if (optionId == null) {
        return null;
      }
      return snapshotForOptionId(optionId);
    }
    return null;
  }

  /// 将 thread settings 原子解码为中立 [AgentPermissionSelection]。
  ///
  /// 无法确定稳定 optionId 时返回 null。
  static AgentPermissionSelection? selectionFromThreadSettings(
    Map<String, Object?> settings,
  ) {
    final snapshot = decodeThreadSettings(settings);
    final optionId = snapshot?.selectedOptionId?.trim();
    if (optionId == null || optionId.isEmpty) {
      return null;
    }
    return AgentPermissionSelection(optionId: optionId);
  }

  /// RPC `permissionProfile/list` 单条 → 中立 option。
  static AgentPermissionOption? optionFromRpcEntry(Map<String, Object?> entry) {
    final id = entry['id'];
    if (id is! String || id.trim().isEmpty) {
      return null;
    }
    final trimmedId = id.trim();
    final description = entry['description'] is String
        ? (entry['description'] as String)
        : null;
    final label = () {
      final builtIn = builtInForId(trimmedId);
      if (builtIn != null) {
        return builtIn.label;
      }
      final desc = description?.trim();
      if (desc != null && desc.isNotEmpty) {
        return desc;
      }
      return trimmedId;
    }();
    return AgentPermissionOption(
      id: trimmedId,
      label: label,
      description: description,
      allowed: entry['allowed'] != false,
    );
  }

  /// 从 option 列表构造 catalog；默认取第一项或内置 workspace。
  static AgentPermissionCatalog catalogFromOptions(
    Iterable<AgentPermissionOption> options,
  ) {
    final list = List<AgentPermissionOption>.from(options);
    final defaultId = list.isNotEmpty ? list.first.id : defaultBuiltInOptionId;
    return AgentPermissionCatalog(options: list, defaultOptionId: defaultId);
  }

  /// 内置静态 catalog（RPC 不可用时的回落）。
  static AgentPermissionCatalog staticBuiltInCatalog() {
    return catalogFromOptions(
      builtInProfiles.map(
        (profile) => AgentPermissionOption(
          id: profile.id,
          label: profile.label,
          description: profile.label,
          allowed: true,
        ),
      ),
    );
  }

  /// `thread/start` 权限相关字段。
  static Map<String, Object?> encodeThreadPermissionFields(
    CodexPermissionRuntimeSnapshot selection,
  ) {
    final profileId = protocolPermissionProfileId(selection);
    return <String, Object?>{
      'approvalPolicy': normalizeApprovalPolicy(selection.approvalPolicy),
      'permissions': ?profileId,
      'sandbox': ?(profileId == null
          ? toThreadSandboxMode(selection.sandboxPolicy)
          : null),
    };
  }

  /// 阶段 B 请求快照 → `thread/start|resume|fork` 权限字段。
  static Map<String, Object?> encodeThreadRequestPermissionFields(
    AgentPermissionRequestSnapshot request, {
    required CodexPermissionRuntimeSnapshot configFallback,
  }) {
    return encodeThreadPermissionFields(
      runtimeSnapshotForRequest(request, configFallback: configFallback),
    );
  }

  /// `turn/start` 权限相关字段。
  static Map<String, Object?> encodeTurnPermissionFields(
    CodexPermissionRuntimeSnapshot selection,
  ) {
    final profileId = protocolPermissionProfileId(selection);
    return <String, Object?>{
      'approvalPolicy': normalizeApprovalPolicy(selection.approvalPolicy),
      'permissions': ?profileId,
      'sandboxPolicy': ?(profileId == null
          ? toTurnSandboxPolicy(selection.sandboxPolicy)
          : null),
    };
  }

  /// 阶段 B 请求快照 → `turn/start` 权限字段。
  static Map<String, Object?> encodeTurnRequestPermissionFields(
    AgentPermissionRequestSnapshot request, {
    required CodexPermissionRuntimeSnapshot configFallback,
  }) {
    return encodeTurnPermissionFields(
      runtimeSnapshotForRequest(request, configFallback: configFallback),
    );
  }
}

/// Codex 运行时权限快照（data 层；含 approval/sandbox/profile 协议字段）。
///
/// 不得泄漏到 application/presentation；共享层只使用 [AgentPermissionSelection]。
final class CodexPermissionRuntimeSnapshot {
  /// 创建 Codex 运行时快照。
  const CodexPermissionRuntimeSnapshot({
    this.optionId,
    this.approvalPolicy = CodexPermissionPolicyCodec.defaultApprovalPolicy,
    this.sandboxPolicy = CodexPermissionPolicyCodec.defaultSandboxPolicy,
    this.permissionProfileId,
  });

  /// 中立 option id（与 profile id 对齐）。
  final String? optionId;

  /// 审批策略。
  final String approvalPolicy;

  /// 沙箱策略（域内 camelCase）。
  final String sandboxPolicy;

  /// 显式 Codex permission profile id。
  final String? permissionProfileId;

  /// 解析后的 option/profile id。
  String? get selectedOptionId {
    final explicit = optionId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return CodexPermissionPolicyCodec.protocolPermissionProfileId(this);
  }

  /// 展示标签（内置短名 / 自定义 id）。
  String get displayLabel {
    final id = selectedOptionId;
    if (id != null && id.isNotEmpty) {
      return CodexPermissionPolicyCodec.displayLabelForOptionId(id);
    }
    return CodexPermissionPolicyCodec.displayLabelForOptionId(
      CodexPermissionPolicyCodec.defaultBuiltInOptionId,
    );
  }

  /// 复制并覆盖字段。
  CodexPermissionRuntimeSnapshot copyWith({
    String? optionId,
    String? approvalPolicy,
    String? sandboxPolicy,
    String? permissionProfileId,
    bool clearOptionId = false,
    bool clearPermissionProfileId = false,
  }) {
    return CodexPermissionRuntimeSnapshot(
      optionId: clearOptionId ? null : (optionId ?? this.optionId),
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      sandboxPolicy: sandboxPolicy ?? this.sandboxPolicy,
      permissionProfileId: clearPermissionProfileId
          ? null
          : (permissionProfileId ?? this.permissionProfileId),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CodexPermissionRuntimeSnapshot &&
            other.optionId == optionId &&
            other.approvalPolicy == approvalPolicy &&
            other.sandboxPolicy == sandboxPolicy &&
            other.permissionProfileId == permissionProfileId;
  }

  @override
  int get hashCode =>
      Object.hash(optionId, approvalPolicy, sandboxPolicy, permissionProfileId);
}

/// Codex 内置 profile 元数据（data 层公开，供 adapter/测试使用）。
final class CodexBuiltInPermissionProfile {
  /// 创建内置 profile 描述。
  const CodexBuiltInPermissionProfile({
    required this.id,
    required this.label,
    required this.approvalPolicy,
    required this.sandboxPolicy,
  });

  /// 协议 profile id（如 `:workspace`）。
  final String id;

  /// 用户可见短标签。
  final String label;

  /// 关联审批策略。
  final String approvalPolicy;

  /// 关联沙箱策略（域内 camelCase）。
  final String sandboxPolicy;
}
