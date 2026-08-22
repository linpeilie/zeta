part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 负责把 `model/list` 响应转换成领域模型。
class _CodexModelListMapper {
  AgentModelList modelListFromResult(Object? value) {
    final map = _map(value);
    final data = map['data'];
    final models = <AgentModelInfo>[];
    if (data is List<Object?>) {
      for (final item in data) {
        final model = _modelInfoFromItem(item);
        if (model != null) {
          models.add(model);
        }
      }
    }
    return AgentModelList(
      models: List<AgentModelInfo>.unmodifiable(models),
      nextCursor: _string(map['nextCursor']),
    );
  }

  AgentModelInfo? _modelInfoFromItem(Object? value) {
    final item = _map(value);
    final id = _string(item['id']) ?? _string(item['model']);
    final model = _string(item['model']) ?? id;
    if (id == null || model == null) {
      return null;
    }

    final efforts = <AgentModelReasoningEffort>[];
    final rawEfforts = item['supportedReasoningEfforts'];
    if (rawEfforts is List<Object?>) {
      for (final effortValue in rawEfforts) {
        final effortMap = _map(effortValue);
        final effortId = _string(effortMap['reasoningEffort']);
        if (effortId != null) {
          efforts.add(
            AgentModelReasoningEffort(
              effort: effortId,
              description: _string(effortMap['description']),
            ),
          );
        }
      }
    }

    final tiers = <AgentModelServiceTier>[];
    final rawTiers = item['serviceTiers'];
    if (rawTiers is List<Object?>) {
      for (final tierValue in rawTiers) {
        final tierMap = _map(tierValue);
        final tierId = _string(tierMap['id']);
        final tierName = _string(tierMap['name']) ?? tierId;
        if (tierId != null) {
          tiers.add(
            AgentModelServiceTier(
              id: tierId,
              name: tierName ?? tierId,
              description: _string(tierMap['description']),
            ),
          );
        }
      }
    }

    return AgentModelInfo(
      id: id,
      model: model,
      displayName: _string(item['displayName']) ?? model,
      description: _string(item['description']),
      hidden: item['hidden'] == true,
      supportedReasoningEfforts: efforts,
      defaultReasoningEffort: _string(item['defaultReasoningEffort']),
      serviceTiers: tiers,
      defaultServiceTier: _string(item['defaultServiceTier']),
      isDefault: item['isDefault'] == true,
      raw: item,
    );
  }
}
