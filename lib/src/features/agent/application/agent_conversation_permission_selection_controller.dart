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

  List<AgentPermissionProfileSummary> get profiles => _profiles;

  String get displayLabel => _selection.displayLabel;

  void bindProvider(AgentProvider provider) {
    _provider = provider;
    provider.updatePermissionSelection(_selection);
  }

  /// 切换 provider 时解绑旧实例，并恢复新 provider 的审批配置。
  void resetForProvider(AgentProviderConfig config) {
    _provider = null;
    _profiles = const <AgentPermissionProfileSummary>[];
    seedFromConfig(config);
  }

  void seedFromConfig(AgentProviderConfig config) {
    _selection = AgentPermissionSelection(
      approvalPolicy:
          config.selectedApprovalPolicy ??
          AgentPermissionSelection.defaultApprovalPolicy,
      sandboxPolicy:
          config.selectedSandboxPolicy ??
          AgentPermissionSelection.defaultSandboxPolicy,
      permissionProfileId: config.selectedPermissionProfileId,
    );
    _provider?.updatePermissionSelection(_selection);
  }

  Future<void> selectPreset(AgentPermissionPreset preset) async {
    _selection = AgentPermissionSelection(
      approvalPolicy: preset.approvalPolicy,
      sandboxPolicy: preset.sandboxPolicy,
      permissionProfileId: _selection.permissionProfileId,
    );
    await _syncSelection();
  }

  Future<void> selectSelection(AgentPermissionSelection selection) async {
    _selection = selection;
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
    if (permissionProfileId != null &&
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
    if (provider == null) {
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
