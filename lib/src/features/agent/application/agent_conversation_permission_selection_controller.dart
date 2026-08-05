import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// Agent 审批/沙箱策略选择的应用层控制器。
///
/// 负责从配置恢复选择、同步到 provider，以及持久化用户变更。
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

  /// 当前选择对应的 profile id（优先显式 id，否则内置预设回填）。
  String? get selectedProfileId => _selection.protocolPermissionProfileId;

  /// Composer 展示文案：list 命中时用 profile.displayName（含预设回落）。
  String get displayLabel {
    final profileId = selectedProfileId;
    if (profileId != null) {
      for (final profile in _profiles) {
        if (profile.id == profileId) {
          return profile.displayName;
        }
      }
      // list 尚未返回时，仍用内置预设 label 覆盖纯 id。
      final preset = AgentPermissionSelection.presetForProfileId(profileId);
      if (preset != null) {
        return preset.label;
      }
    }
    return _selection.displayLabel;
  }

  void bindProvider(AgentProvider provider) {
    _provider = provider;
    if (!provider.capabilities.supportsPermissionProfileSelection &&
        _selection.permissionProfileId != null) {
      _selection = _selection.copyWith(clearPermissionProfileId: true);
    }
    provider.updatePermissionSelection(_selection);
  }

  /// 切换 provider 时解绑旧实例，并恢复新 provider 的审批配置。
  void resetForProvider(AgentProviderConfig config) {
    _provider = null;
    _profiles = const <AgentPermissionProfileSummary>[];
    seedFromConfig(config);
  }

  void seedFromConfig(AgentProviderConfig config) {
    // provider 尚未 bind 时也先保留持久化的 profile id；真正不支持时在
    // [bindProvider] 再清除，避免 list 驱动的选择在预加载阶段丢失。
    _selection = AgentPermissionSelection(
      approvalPolicy: AgentPermissionSelection.normalizeApprovalPolicy(
        config.selectedApprovalPolicy,
      ),
      sandboxPolicy:
          config.selectedSandboxPolicy ??
          AgentPermissionSelection.defaultSandboxPolicy,
      permissionProfileId: config.selectedPermissionProfileId,
    );
    if (_provider != null &&
        !_provider!.capabilities.supportsPermissionProfileSelection &&
        _selection.permissionProfileId != null) {
      _selection = _selection.copyWith(clearPermissionProfileId: true);
    }
    _provider?.updatePermissionSelection(_selection);
  }

  /// 选择 `permissionProfile/list` 中的一项。
  Future<void> selectProfile(AgentPermissionProfileSummary profile) async {
    if (!profile.allowed) {
      return;
    }
    final supportsProfile =
        _provider?.capabilities.supportsPermissionProfileSelection == true;
    final next = AgentPermissionSelection.forProfileId(profile.id);
    _selection = supportsProfile
        ? next
        : next.copyWith(clearPermissionProfileId: true);
    await _syncSelection();
  }

  /// 兼容旧预设入口；新 UI 应走 [selectProfile]。
  Future<void> selectPreset(AgentPermissionPreset preset) async {
    _selection = AgentPermissionSelection(
      approvalPolicy: preset.approvalPolicy,
      sandboxPolicy: preset.sandboxPolicy,
      permissionProfileId:
          _provider?.capabilities.supportsPermissionProfileSelection == true
          ? preset.permissionProfileId
          : null,
    );
    await _syncSelection();
  }

  Future<void> selectSelection(AgentPermissionSelection selection) async {
    _selection =
        _provider?.capabilities.supportsPermissionProfileSelection == true
        ? selection
        : selection.copyWith(clearPermissionProfileId: true);
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
      next = next.copyWith(permissionProfileId: permissionProfileId);
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
        !provider.capabilities.supportsPermissionProfileDiscovery) {
      _profiles = const <AgentPermissionProfileSummary>[];
      return;
    }
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
