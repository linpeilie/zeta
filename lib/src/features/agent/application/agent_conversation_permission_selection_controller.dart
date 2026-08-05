import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// 权限策略选择的应用层控制器（Codex / Grok 统一入口）。
///
/// 只认中立 [AgentPermissionProfileSummary] 选项与
/// [AgentPermissionSelectionSnapshot.optionId]；不按 provider kind 分支，也不 import
/// 任何厂商 codec。选项列表一律经 [AgentProvider.listPermissionProfiles]。
class AgentConversationPermissionSelectionController {
  AgentConversationPermissionSelectionController({
    required this._persistSelection,
  });

  final Future<void> Function(AgentPermissionSelectionSnapshot selection)
  _persistSelection;

  AgentProvider? _provider;
  AgentPermissionSelectionSnapshot _selection =
      const AgentPermissionSelectionSnapshot();
  List<AgentPermissionProfileSummary> _profiles =
      const <AgentPermissionProfileSummary>[];

  AgentPermissionSelectionSnapshot get selection => _selection;

  List<AgentPermissionProfileSummary> get profiles =>
      List<AgentPermissionProfileSummary>.unmodifiable(_profiles);

  /// 当前选中的选项 id。
  String? get selectedProfileId => _selection.selectedOptionId;

  /// Composer 展示文案：优先选项列表 label，否则 selection 回落。
  String get displayLabel {
    final optionId = selectedProfileId;
    if (optionId != null) {
      for (final profile in _profiles) {
        if (profile.id == optionId) {
          return profile.displayName;
        }
      }
      final preset = AgentPermissionSelectionSnapshot.presetForOptionId(
        optionId,
      );
      if (preset != null) {
        return preset.label;
      }
    }
    return _selection.displayLabel;
  }

  void bindProvider(AgentProvider provider) {
    _provider = provider;
    // 不根据 capability 清除 permissionProfileId：配置中的显式字段原样下发，
    // 不支持 profile 的 Provider（如 Grok）只会读取 optionId，自然忽略 Codex 字段。
    provider.updatePermissionSelection(_selection);
  }

  /// 切换 provider 时解绑旧实例，并恢复新 provider 的配置。
  void resetForProvider(AgentProviderConfig config) {
    _provider = null;
    _profiles = const <AgentPermissionProfileSummary>[];
    seedFromConfig(config);
  }

  void seedFromConfig(AgentProviderConfig config) {
    // 按显式持久化字段构造快照，不通过 startsWith(':') / 内置预设猜测协议类型。
    // selectedPermissionOptionId 仅作通用选择 ID；selectedPermissionProfileId 原样保留。
    _selection = AgentPermissionSelectionSnapshot(
      optionId: config.resolvedPermissionOptionId,
      approvalPolicy: AgentPermissionSelectionSnapshot.normalizeApprovalPolicy(
        config.selectedApprovalPolicy,
      ),
      sandboxPolicy:
          config.selectedSandboxPolicy ??
          AgentPermissionSelectionSnapshot.defaultSandboxPolicy,
      permissionProfileId: config.selectedPermissionProfileId,
    );
    _provider?.updatePermissionSelection(_selection);
  }

  /// 选择列表中的一项（统一入口）。
  Future<void> selectProfile(AgentPermissionProfileSummary profile) async {
    if (!profile.allowed) {
      return;
    }
    final supportsProfile =
        _provider?.capabilities.supportsPermissionProfileSelection == true;
    final next = supportsProfile
        ? AgentPermissionSelectionSnapshot.forProfileId(profile.id)
        : AgentPermissionSelectionSnapshot.forOptionId(profile.id);
    _selection = next;
    await _syncSelection();
  }

  /// 兼容旧预设入口。
  Future<void> selectPreset(AgentPermissionPreset preset) async {
    final profileId = preset.permissionProfileId;
    if (profileId != null && profileId.isNotEmpty) {
      _selection = AgentPermissionSelectionSnapshot.forProfileId(profileId);
    } else {
      _selection = AgentPermissionSelectionSnapshot(
        optionId: preset.id,
        approvalPolicy: preset.approvalPolicy,
        sandboxPolicy: preset.sandboxPolicy,
      );
    }
    if (_provider?.capabilities.supportsPermissionProfileSelection != true) {
      _selection = AgentPermissionSelectionSnapshot(
        optionId: _selection.selectedOptionId ?? preset.id,
        approvalPolicy: preset.approvalPolicy,
        sandboxPolicy: preset.sandboxPolicy,
      );
    }
    await _syncSelection();
  }

  Future<void> selectSelection(
    AgentPermissionSelectionSnapshot selection,
  ) async {
    final optionId = selection.selectedOptionId;
    if (optionId == null || optionId.isEmpty) {
      _selection = selection;
      await _syncSelection();
      return;
    }
    final supportsProfile =
        _provider?.capabilities.supportsPermissionProfileSelection == true;
    _selection = supportsProfile
        ? AgentPermissionSelectionSnapshot.forProfileId(optionId).copyWith(
            approvalPolicy: selection.approvalPolicy,
            sandboxPolicy: selection.sandboxPolicy,
          )
        : AgentPermissionSelectionSnapshot.forOptionId(optionId);
    await _syncSelection();
  }

  /// 用服务端 `thread/settings/updated` 回写本地选择。
  ///
  /// 同一事件中的 approval / sandbox / profile 在同一 [next] 上原子合并；
  /// 全部字段处理完后只写一次 `_selection`、只同步一次 provider。
  /// 空串、缺失与无法识别的字段不覆盖已有有效值；不触发全局持久化。
  void applyThreadSettings({
    String? approvalPolicy,
    String? sandboxPolicy,
    String? permissionProfileId,
  }) {
    var changed = false;
    var next = _selection;

    final nextApproval = _validApprovalPolicy(approvalPolicy);
    if (nextApproval != null && nextApproval != next.approvalPolicy) {
      next = next.copyWith(approvalPolicy: nextApproval);
      changed = true;
    }

    final nextSandbox = _validSandboxPolicy(sandboxPolicy);
    if (nextSandbox != null && nextSandbox != next.sandboxPolicy) {
      next = next.copyWith(sandboxPolicy: nextSandbox);
      changed = true;
    }

    final nextProfileId = _nonEmpty(permissionProfileId);
    if (_provider?.capabilities.supportsPermissionProfileSelection == true &&
        nextProfileId != null &&
        nextProfileId != next.permissionProfileId) {
      // 只合并 profile 字段，禁止 forProfileId 整对象替换冲掉已合并的策略。
      next = next.copyWith(
        optionId: nextProfileId,
        permissionProfileId: nextProfileId,
      );
      changed = true;
    }

    if (!changed) {
      return;
    }
    _selection = next;
    // 服务端 settings 只更新当前 thread 有效状态，不调用 _persistSelection。
    _provider?.updatePermissionSelection(_selection);
  }

  /// 可识别的审批策略；空串/未知值返回 null，避免覆盖本地有效值。
  static String? _validApprovalPolicy(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return switch (trimmed) {
      'untrusted' || 'on-request' || 'never' => trimmed,
      'on-failure' => 'on-request',
      _ => null,
    };
  }

  /// 可识别的沙箱策略；空串/未知值返回 null。
  static String? _validSandboxPolicy(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return switch (trimmed) {
      'readOnly' || 'workspaceWrite' || 'dangerFullAccess' => trimmed,
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

  Future<void> refreshProfiles() async {
    final provider = _provider;
    if (provider == null ||
        !provider.capabilities.supportsPermissionPolicySelection) {
      _profiles = const <AgentPermissionProfileSummary>[];
      return;
    }
    // 统一走 listPermissionProfiles：Codex RPC / Grok 静态 catalog。
    try {
      _profiles = await provider.listPermissionProfiles();
    } catch (_) {
      _profiles = const <AgentPermissionProfileSummary>[];
    }
  }

  Future<void> _syncSelection() async {
    _provider?.updatePermissionSelection(_selection);
    await _persistSelection(_selection);
  }
}
