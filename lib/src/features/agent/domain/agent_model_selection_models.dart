/// 模型支持的推理深度档位。
///
/// 对应 Codex `model/list` 中 `supportedReasoningEfforts` 数组元素，
/// UI 据此在输入框左侧渲染思考按钮的选项列表。
class AgentModelReasoningEffort {
  const AgentModelReasoningEffort({required this.effort, this.description});

  /// 档位标识，如 low/medium/high/xhigh。
  final String effort;

  /// 可选的人类可读说明。
  final String? description;
}

/// 模型服务档位（速率）。
///
/// 对应 Codex `model/list` 中 `serviceTiers` 数组元素，
/// UI 据此在输入框左侧渲染速率选择按钮。
class AgentModelServiceTier {
  const AgentModelServiceTier({
    required this.id,
    required this.name,
    this.description,
    this.enabled = true,
    this.unavailableReason,
  });

  /// 档位 id，如 priority。
  final String id;

  /// 展示名称，如 Fast。
  final String name;

  /// 可选说明。
  final String? description;

  /// 当前服务档位是否可选。
  final bool enabled;

  /// 服务档位不可用时的用户可读原因。
  final String? unavailableReason;
}

/// 可选模型信息。
///
/// 由 `model/list` 返回，UI 据此构建模型下拉、思考按钮和速率按钮。
class AgentModelInfo {
  const AgentModelInfo({
    required this.id,
    required this.model,
    required this.displayName,
    this.description,
    this.hidden = false,
    this.supportedReasoningEfforts = const <AgentModelReasoningEffort>[],
    this.defaultReasoningEffort,
    this.serviceTiers = const <AgentModelServiceTier>[],
    this.defaultServiceTier,
    this.isDefault = false,
    this.enabled = true,
    this.unavailableReason,
    this.contextWindowTokens,
    this.raw = const <String, Object?>{},
  });

  /// 模型稳定 id。
  final String id;

  /// 模型标识，与 CLI 参数中的 model 字段一致。
  final String model;

  /// UI 展示名称。
  final String displayName;

  /// 可选描述。
  final String? description;

  /// 是否在 CLI 中被标记为隐藏。
  final bool hidden;

  /// 支持的推理深度档位列表。
  final List<AgentModelReasoningEffort> supportedReasoningEfforts;

  /// 默认推理深度档位。
  final String? defaultReasoningEffort;

  /// 可选服务档位列表。
  final List<AgentModelServiceTier> serviceTiers;

  /// 默认服务档位 id。
  final String? defaultServiceTier;

  /// 是否为 CLI 默认模型。
  final bool isDefault;

  /// 当前模型是否允许选择。
  ///
  /// Codex app-server 0.144.1 的稳定 `model/list` 仅返回可用目录，不提供
  /// 该字段；其他 provider 或未来适配层可通过此中立字段表达不可用模型。
  final bool enabled;

  /// 模型不可用时的用户可读原因。
  final String? unavailableReason;

  /// 模型上下文窗口 token 上限；仅在 provider 明确返回时设置。
  final int? contextWindowTokens;

  /// 原始 provider payload。
  final Map<String, Object?> raw;
}

/// `model/list` 分页结果。
class AgentModelList {
  const AgentModelList({required this.models, this.nextCursor});

  /// 当前页模型列表。
  final List<AgentModelInfo> models;

  /// 下一页游标；为空表示没有更多。
  final String? nextCursor;
}

/// 用户在输入框选择的模型组合。
///
/// 三个字段均可为空，表示使用 CLI 默认值。持久化到 [AgentProviderConfig]，
/// 并在 `turn/start` 时覆盖默认 model 参数。
class AgentModelSelection {
  const AgentModelSelection({
    this.modelId,
    this.reasoningEffort,
    this.serviceTierId,
  });

  /// 选中的模型 id。
  final String? modelId;

  /// 选中的推理深度档位。
  final String? reasoningEffort;

  /// 选中的服务档位 id。
  final String? serviceTierId;

  /// 是否所有字段都为空。
  bool get isEmpty =>
      modelId == null && reasoningEffort == null && serviceTierId == null;
}

/// 单个模型最近一次由服务端确认有效的用户偏好。
class AgentModelPreference {
  const AgentModelPreference({
    required this.modelId,
    required this.reasoningEffort,
    required this.fastEnabled,
    required this.serviceTierId,
    required this.updatedAt,
    this.version = currentVersion,
  });

  /// 当前持久化结构版本。
  static const int currentVersion = 1;

  final String modelId;
  final String? reasoningEffort;

  /// UI 中 Fast 的明确语义；[serviceTierId] 保留 provider 的精确协议值。
  final bool fastEnabled;
  final String? serviceTierId;
  final DateTime updatedAt;
  final int version;

  AgentModelSelection get selection => AgentModelSelection(
    modelId: modelId,
    reasoningEffort: reasoningEffort,
    serviceTierId: serviceTierId,
  );

  AgentModelPreference copyWith({
    String? reasoningEffort,
    bool? fastEnabled,
    Object? serviceTierId = _modelPreferenceUnset,
    DateTime? updatedAt,
    int? version,
  }) {
    return AgentModelPreference(
      modelId: modelId,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      fastEnabled: fastEnabled ?? this.fastEnabled,
      serviceTierId: identical(serviceTierId, _modelPreferenceUnset)
          ? this.serviceTierId
          : serviceTierId as String?,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'modelId': modelId,
    'reasoningEffort': reasoningEffort,
    'fastEnabled': fastEnabled,
    'serviceTierId': serviceTierId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'version': version,
  };

  /// 宽容读取模型偏好；损坏或缺少稳定 id 的条目会被忽略。
  static AgentModelPreference? tryDecode(Object? value) {
    if (value is! Map) {
      return null;
    }
    final map = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final modelId = map['modelId'];
    if (modelId is! String || modelId.trim().isEmpty) {
      return null;
    }
    final updatedAt = DateTime.tryParse('${map['updatedAt'] ?? ''}')?.toUtc();
    final rawVersion = map['version'];
    return AgentModelPreference(
      modelId: modelId.trim(),
      reasoningEffort: map['reasoningEffort'] is String
          ? map['reasoningEffort'] as String
          : null,
      fastEnabled: map['fastEnabled'] == true,
      serviceTierId: map['serviceTierId'] is String
          ? map['serviceTierId'] as String
          : null,
      updatedAt:
          updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      version: rawVersion is int && rawVersion > 0
          ? rawVersion
          : currentVersion,
    );
  }
}

const Object _modelPreferenceUnset = Object();

/// 返回模型目录中代表 Fast 的服务档位。
///
/// 官方协议把它建模为可扩展的 service tier，因此优先按 id/name 识别；只有
/// 一个档位时再使用目录本身作为保守回退，避免把多档服务误标为 Fast。
AgentModelServiceTier? agentFastServiceTier(AgentModelInfo model) {
  for (final tier in model.serviceTiers) {
    final id = tier.id.trim().toLowerCase();
    final name = tier.name.trim().toLowerCase();
    if (id == 'fast' || id == 'priority' || name == 'fast') {
      return tier;
    }
  }
  return model.serviceTiers.length == 1 ? model.serviceTiers.single : null;
}

/// 已知思考档位的强度序号：数值越大表示思考越深。
///
/// 用于 UI 从左到右展示「低 → 高」；协议侧仍可保留服务端原始数组顺序。
const Map<String, int> _reasoningEffortDisplayRank = <String, int>{
  'none': 0,
  'minimal': 1,
  'low': 2,
  'medium': 3,
  'high': 4,
  'xhigh': 5,
};

/// 将思考档位按强度升序排列，便于分段控件左侧为低、右侧为高。
///
/// 未知档位排在已知档位之后，并保持彼此的相对顺序。
List<AgentModelReasoningEffort> orderedReasoningEffortsForDisplay(
  List<AgentModelReasoningEffort> efforts,
) {
  if (efforts.length <= 1) {
    return efforts;
  }
  final indexed = <({int index, AgentModelReasoningEffort effort})>[
    for (var i = 0; i < efforts.length; i++) (index: i, effort: efforts[i]),
  ];
  indexed.sort((a, b) {
    final rankCompare = _reasoningEffortDisplayRankFor(
      a.effort.effort,
    ).compareTo(_reasoningEffortDisplayRankFor(b.effort.effort));
    if (rankCompare != 0) {
      return rankCompare;
    }
    return a.index.compareTo(b.index);
  });
  return <AgentModelReasoningEffort>[for (final item in indexed) item.effort];
}

int _reasoningEffortDisplayRankFor(String effort) {
  return _reasoningEffortDisplayRank[effort.trim().toLowerCase()] ?? 1000;
}
