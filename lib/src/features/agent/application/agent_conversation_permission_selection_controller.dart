import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// 权限策略选择的应用层控制器（Codex / Grok 统一入口）。
///
/// 只认中立 [AgentPermissionProfileSummary] 选项与
/// [AgentPermissionSelection.optionId]；不按 provider kind 分支，也不 import
/// 任何厂商 codec。选项列表一律经 [AgentProvider.listPermissionProfiles]。
class AgentConversationPermissionSelectionController {
  AgentConversationPermissionSelectionController({
    required this._persistSelection,
  });

  final Future<void> Function(AgentPermissionSelection selection)
  _persistSelection;

  AgentProvider? _provider;
  AgentPermissionSelection _selection = const AgentPermissionSelection();
  List<AgentPermissionProfileSummary> _profiles =
      const <AgentPermissionProfileSummary>[];

  AgentPermissionSelection get selection => _selection;

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
      final preset = AgentPermissionSelection.presetForOptionId(optionId);
      if (preset != null) {
        return preset.label;
      }
    }
    return _selection.displayLabel;
  }

  void bindProvider(AgentProvider provider) {
    _provider = provider;
    final supportsProfiles =
        provider.capabilities.supportsPermissionProfileSelection;
    if (!supportsProfiles && _selection.permissionProfileId != null) {
      // 不支持 profile 下发时清掉 profile 字段，保留 optionId。
      _selection = AgentPermissionSelection(
        optionId: _selection.selectedOptionId,
        approvalPolicy: _selection.approvalPolicy,
        sandboxPolicy: _selection.sandboxPolicy,
      );
    }
    provider.updatePermissionSelection(_selection);
  }

  /// 切换 provider 时解绑旧实例，并恢复新 provider 的配置。
  void resetForProvider(AgentProviderConfig config) {
    _provider = null;
    _profiles = const <AgentPermissionProfileSummary>[];
    seedFromConfig(config);
  }

  void seedFromConfig(AgentProviderConfig config) {
    final optionId = config.resolvedPermissionOptionId;
    if (optionId != null && optionId.isNotEmpty) {
      // forOptionId：Codex 内置 profile 会回填 approval/sandbox；
      // 不透明 id（含 Grok mode）只记 optionId。
      // 自定义 Codex profile 用 forProfileId 保留 permissionProfileId。
      final looksLikeCodexProfile =
          optionId.startsWith(':') ||
          AgentPermissionSelection.presetForOptionId(optionId) != null;
      _selection = looksLikeCodexProfile
          ? AgentPermissionSelection.forProfileId(optionId)
          : AgentPermissionSelection.forOptionId(optionId);
      // 配置里若仍有 approval/sandbox，覆盖 forOptionId 默认值。
      if (config.selectedApprovalPolicy != null ||
          config.selectedSandboxPolicy != null) {
        _selection = _selection.copyWith(
          approvalPolicy: AgentPermissionSelection.normalizeApprovalPolicy(
            config.selectedApprovalPolicy,
          ),
          sandboxPolicy:
              config.selectedSandboxPolicy ?? _selection.sandboxPolicy,
        );
      }
    } else {
      _selection = AgentPermissionSelection(
        approvalPolicy: AgentPermissionSelection.normalizeApprovalPolicy(
          config.selectedApprovalPolicy,
        ),
        sandboxPolicy:
            config.selectedSandboxPolicy ??
            AgentPermissionSelection.defaultSandboxPolicy,
        permissionProfileId: config.selectedPermissionProfileId,
        optionId: config.selectedPermissionProfileId,
      );
    }
    if (_provider != null &&
        !_provider!.capabilities.supportsPermissionProfileSelection &&
        _selection.permissionProfileId != null) {
      _selection = AgentPermissionSelection(
        optionId: _selection.selectedOptionId,
        approvalPolicy: _selection.approvalPolicy,
        sandboxPolicy: _selection.sandboxPolicy,
      );
    }
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
        ? AgentPermissionSelection.forProfileId(profile.id)
        : AgentPermissionSelection.forOptionId(profile.id);
    _selection = next;
    await _syncSelection();
  }

  /// 兼容旧预设入口。
  Future<void> selectPreset(AgentPermissionPreset preset) async {
    final profileId = preset.permissionProfileId;
    if (profileId != null && profileId.isNotEmpty) {
      _selection = AgentPermissionSelection.forProfileId(profileId);
    } else {
      _selection = AgentPermissionSelection(
        optionId: preset.id,
        approvalPolicy: preset.approvalPolicy,
        sandboxPolicy: preset.sandboxPolicy,
      );
    }
    if (_provider?.capabilities.supportsPermissionProfileSelection != true) {
      _selection = AgentPermissionSelection(
        optionId: _selection.selectedOptionId ?? preset.id,
        approvalPolicy: preset.approvalPolicy,
        sandboxPolicy: preset.sandboxPolicy,
      );
    }
    await _syncSelection();
  }

  Future<void> selectSelection(AgentPermissionSelection selection) async {
    final optionId = selection.selectedOptionId;
    if (optionId == null || optionId.isEmpty) {
      _selection = selection;
      await _syncSelection();
      return;
    }
    final supportsProfile =
        _provider?.capabilities.supportsPermissionProfileSelection == true;
    _selection = supportsProfile
        ? AgentPermissionSelection.forProfileId(optionId).copyWith(
            approvalPolicy: selection.approvalPolicy,
            sandboxPolicy: selection.sandboxPolicy,
          )
        : AgentPermissionSelection.forOptionId(optionId);
    await _syncSelection();
  }

  /// 用服务端 `thread/settings/updated` 回写本地选择。
  void applyThreadSettings({
    String? approvalPolicy,
    String? sandboxPolicy,
    String? permissionProfileId,
  }) {
    var changed = false;
    var next = _selection;
    if (approvalPolicy != null &&
        approvalPolicy.isNotEmpty &&
        approvalPolicy != next.approvalPolicy) {
      next = next.copyWith(approvalPolicy: approvalPolicy);
      changed = true;
    }
    if (sandboxPolicy != null &&
        sandboxPolicy.isNotEmpty &&
        sandboxPolicy != next.sandboxPolicy) {
      next = next.copyWith(sandboxPolicy: sandboxPolicy);
      changed = true;
    }
    if (_provider?.capabilities.supportsPermissionProfileSelection == true &&
        permissionProfileId != null &&
        permissionProfileId != next.permissionProfileId) {
      next = AgentPermissionSelection.forProfileId(permissionProfileId);
      changed = true;
    }
    if (!changed) {
      return;
    }
    _selection = next;
    _provider?.updatePermissionSelection(_selection);
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
