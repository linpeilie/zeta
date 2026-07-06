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
  });

  /// 档位 id，如 priority。
  final String id;

  /// 展示名称，如 Fast。
  final String name;

  /// 可选说明。
  final String? description;
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
