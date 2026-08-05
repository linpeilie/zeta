import 'package:zeta/src/features/agent/domain/agent_permission_selection_models.dart';

/// 中立权限策略领域模型与端口（解耦目标形态）。
///
/// 本文件中的 [AgentPermissionOption] / [AgentPermissionCatalog] /
/// [AgentPermissionSelection] / [AgentPermissionApplyResult] **不得**包含
/// Codex/Grok 协议字段名、raw payload 或协议编码方法。协议映射只允许出现在
/// data adapter/codec 中。
///
/// 迁移期与 [AgentPermissionSelectionSnapshot] / [AgentPermissionProfileSummary]
/// 并存；阶段 4+ 将 application/UI 迁到本端口，阶段 6 删除旧模型。

/// 共享层可见的单个权限选项。
///
/// [id] 对 application/presentation 完全不透明；label/description 由 adapter 提供。
class AgentPermissionOption {
  /// 创建权限选项。
  const AgentPermissionOption({
    required this.id,
    required this.label,
    this.description,
    this.allowed = true,
  });

  /// 稳定选项 id（不透明；不得由共享层解析协议语义）。
  final String id;

  /// 用户可见主标签。
  final String label;

  /// 可选说明；仅用于展示，不承载协议 payload。
  final String? description;

  /// 当前环境是否允许选择。
  final bool allowed;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentPermissionOption &&
            other.id == id &&
            other.label == label &&
            other.description == description &&
            other.allowed == allowed;
  }

  @override
  int get hashCode => Object.hash(id, label, description, allowed);

  @override
  String toString() =>
      'AgentPermissionOption(id: $id, label: $label, allowed: $allowed)';
}

/// Provider 暴露的权限选项目录。
class AgentPermissionCatalog {
  /// 创建不可变目录快照。
  ///
  /// [defaultOptionId] 应指向 [options] 中的某一项；共享层不强制校验存在性，
  /// 由 adapter 保证一致性。
  AgentPermissionCatalog({
    required Iterable<AgentPermissionOption> options,
    required this.defaultOptionId,
  }) : options = List<AgentPermissionOption>.unmodifiable(
         List<AgentPermissionOption>.from(options),
       );

  /// 可选权限项（不可修改快照）。
  final List<AgentPermissionOption> options;

  /// 默认选项 id。
  final String defaultOptionId;

  /// 按 id 查找选项；不存在时返回 null。
  AgentPermissionOption? optionById(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final option in options) {
      if (option.id == normalized) {
        return option;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AgentPermissionCatalog) {
      return false;
    }
    if (other.defaultOptionId != defaultOptionId ||
        other.options.length != options.length) {
      return false;
    }
    for (var i = 0; i < options.length; i++) {
      if (other.options[i] != options[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(defaultOptionId, Object.hashAll(options));
}

/// 中立权限选择（仅 [optionId]）。
///
/// 这是 [AgentPermissionPolicyPort] 的输入/输出规范形态。迁移期运行时仍可能
/// 使用带协议字段的 [AgentPermissionSelectionSnapshot]。
class AgentPermissionSelection {
  /// 创建仅含 optionId 的选择。
  const AgentPermissionSelection({required this.optionId});

  /// 不透明权限选项 id。
  final String optionId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentPermissionSelection && other.optionId == optionId;
  }

  @override
  int get hashCode => optionId.hashCode;

  @override
  String toString() => 'AgentPermissionSelection(optionId: $optionId)';
}

/// 权限选择生效范围。
enum AgentPermissionApplyScope {
  /// 仅影响当前 turn。
  currentTurn,

  /// 影响当前 session/thread。
  currentSession,

  /// 影响整个 provider runtime（可能跨 thread/Canvas）。
  runtime,

  /// 需新建 session 后才生效。
  nextSession,
}

/// 将权限选择应用到 provider 后的结果。
class AgentPermissionApplyResult {
  /// 创建应用结果。
  const AgentPermissionApplyResult({
    required this.normalizedSelection,
    required this.scope,
    this.warning,
  });

  /// adapter 归一化后的选择（可能与输入 optionId 不同，如别名迁移）。
  final AgentPermissionSelection normalizedSelection;

  /// 选择实际生效的范围。
  final AgentPermissionApplyScope scope;

  /// 可选用户可见警告（例如仅下次会话生效、版本降级）。
  final String? warning;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentPermissionApplyResult &&
            other.normalizedSelection == normalizedSelection &&
            other.scope == scope &&
            other.warning == warning;
  }

  @override
  int get hashCode => Object.hash(normalizedSelection, scope, warning);
}

/// Provider 权限策略端口：目录列举与选择应用。
///
/// 端口为空（[AgentProviderBundle.permissionPolicy] == null）表示不支持权限选择。
abstract interface class AgentPermissionPolicyPort {
  /// 拉取当前可用权限选项目录。
  ///
  /// 临时失败应由实现决定是否抛错；application 层应避免用空列表覆盖旧目录。
  Future<AgentPermissionCatalog> listPermissionOptions();

  /// 将选择应用到 provider 运行时，并返回归一化结果与生效范围。
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  );
}

/// 旧 profile 摘要与中立 [AgentPermissionOption] 之间的薄适配。
///
/// 仅做字段映射，不解析 id 协议语义。
abstract final class AgentPermissionPolicyAdapters {
  /// 将旧 [AgentPermissionProfileSummary] 转为中立 option。
  static AgentPermissionOption optionFromProfileSummary(
    AgentPermissionProfileSummary summary,
  ) {
    final description = summary.description?.trim();
    final label = (description != null && description.isNotEmpty)
        ? description
        : summary.id;
    return AgentPermissionOption(
      id: summary.id,
      label: label,
      description: summary.description,
      allowed: summary.allowed,
    );
  }

  /// 将中立 option 转回旧 profile 摘要（兼容旧 UI/API）。
  static AgentPermissionProfileSummary profileSummaryFromOption(
    AgentPermissionOption option,
  ) {
    return AgentPermissionProfileSummary(
      id: option.id,
      allowed: option.allowed,
      description: option.description ?? option.label,
    );
  }

  /// 从运行时快照提取中立选择（优先 optionId，再 profileId）。
  static AgentPermissionSelection? selectionFromSnapshot(
    AgentPermissionSelectionSnapshot snapshot,
  ) {
    final id = snapshot.selectedOptionId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    return AgentPermissionSelection(optionId: id);
  }

  /// 将中立选择展开为运行时快照（供旧 [AgentProvider.updatePermissionSelection]）。
  ///
  /// [preferProfileBinding] 为 true 时绑定 permissionProfileId（Codex 风格）；
  /// 为 false 时仅写 optionId（Grok 风格）。
  static AgentPermissionSelectionSnapshot snapshotFromSelection(
    AgentPermissionSelection selection, {
    bool preferProfileBinding = false,
  }) {
    final id = selection.optionId.trim();
    if (preferProfileBinding) {
      return AgentPermissionSelectionSnapshot.forProfileId(id);
    }
    return AgentPermissionSelectionSnapshot.forOptionId(id);
  }
}
