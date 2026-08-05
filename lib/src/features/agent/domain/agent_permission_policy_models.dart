// 中立权限策略领域模型与端口。
//
// 本文件中的 AgentPermissionOption / AgentPermissionCatalog /
// AgentPermissionSelection / AgentPermissionApplyResult 不得包含
// Codex/Grok 协议字段名、raw payload 或协议编码方法。协议映射只允许出现在
// data adapter/codec 中。

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
/// 这是 [AgentPermissionPolicyPort] 的输入/输出规范形态。
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

/// 请求权限快照的解析来源。
///
/// 来源只描述 Zeta application 的优先级决策，不携带任何 Provider 协议字段。
enum AgentPermissionRequestSource {
  /// 当前 thread 已由 settings feedback 或本地选择确定的有效值。
  threadEffective,

  /// Provider 配置中持久化的默认偏好。
  providerDefault,

  /// Provider 权限目录声明的默认项。
  catalogDefault,

  /// application 没有可解析的选择，允许 adapter 沿用兼容 fallback。
  providerFallback,
}

/// 一次 create/resume/fork/send 请求独占的中立权限快照。
///
/// 快照不可变，且只保存不透明的 [AgentPermissionSelection] 与解析来源。
/// [providerFallback] 快照不携带 selection，由 data adapter 兼容现有默认逻辑。
final class AgentPermissionRequestSnapshot {
  /// 创建已经由 application 解析完成的请求快照。
  const AgentPermissionRequestSnapshot.resolved({
    required this.selection,
    required this.source,
  }) : assert(selection != null),
       assert(source != AgentPermissionRequestSource.providerFallback);

  /// 创建不覆盖 Provider 兼容 fallback 的请求快照。
  const AgentPermissionRequestSnapshot.providerFallback()
    : selection = null,
      source = AgentPermissionRequestSource.providerFallback;

  /// 本次请求使用的中立权限选择。
  final AgentPermissionSelection? selection;

  /// application 解析该选择时命中的优先级来源。
  final AgentPermissionRequestSource source;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentPermissionRequestSnapshot &&
            other.selection == selection &&
            other.source == source;
  }

  @override
  int get hashCode => Object.hash(selection, source);

  @override
  String toString() {
    return 'AgentPermissionRequestSnapshot('
        'selection: $selection, source: $source)';
  }
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
