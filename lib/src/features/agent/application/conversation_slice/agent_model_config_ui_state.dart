import 'package:meta/meta.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Composer 模型配置的不可变快照（application 状态）。
///
/// **不含 popover 展开态**：`expandedModelId` 属于 Widget/page scope 的
/// presentation 状态（目标架构 §7.3），由 popover 自己的
/// `_AgentModelConfigPopoverState` 持有。
@immutable
class AgentModelConfigUiState {
  AgentModelConfigUiState({
    required List<AgentModelInfo> models,
    required this.selectedModelId,
    required this.selectedReasoningEffort,
    required this.selectedServiceTierId,
    required Map<String, AgentModelPreference> preferences,
    required Set<String> savingModelIds,
    required this.isRefreshing,
    required this.appliesNextTurn,
    required this.supportsReasoningOptions,
    required this.supportsServiceTierSelection,
    this.compatibilityConflict,
    this.saveError,
    this.selectionNotice,
    this.refreshError,
  }) : models = List<AgentModelInfo>.unmodifiable(models),
       preferences = Map<String, AgentModelPreference>.unmodifiable(
         preferences,
       ),
       savingModelIds = Set<String>.unmodifiable(savingModelIds);

  final List<AgentModelInfo> models;
  final String? selectedModelId;
  final String? selectedReasoningEffort;
  final String? selectedServiceTierId;
  final Map<String, AgentModelPreference> preferences;
  final Set<String> savingModelIds;
  final bool isRefreshing;
  final bool appliesNextTurn;
  final bool supportsReasoningOptions;
  final bool supportsServiceTierSelection;
  final AgentModelCompatibilityConflict? compatibilityConflict;
  final AgentModelSelectionSaveError? saveError;
  final String? selectionNotice;
  final String? refreshError;

  AgentModelInfo? get selectedModel {
    for (final model in models) {
      if (model.id == selectedModelId) {
        return model;
      }
    }
    return null;
  }

  bool get selectedFastEnabled {
    final model = selectedModel;
    final fastTier = model == null ? null : agentFastServiceTier(model);
    return fastTier != null && fastTier.id == selectedServiceTierId;
  }

  /// 返回模型的已保存配置；首次选择时回退到服务端目录默认值。
  AgentModelPreference effectivePreference(AgentModelInfo model) {
    final cached = preferences[model.id];
    if (cached != null) {
      return cached;
    }
    final effort =
        model.supportedReasoningEfforts.any(
          (item) => item.effort == model.defaultReasoningEffort,
        )
        ? model.defaultReasoningEffort
        : model.supportedReasoningEfforts.firstOrNull?.effort;
    final defaultTier =
        model.serviceTiers.any(
          (tier) => tier.id == model.defaultServiceTier && tier.enabled,
        )
        ? model.defaultServiceTier
        : null;
    final fastTier = agentFastServiceTier(model);
    final fastEnabled = fastTier != null && fastTier.id == defaultTier;
    return AgentModelPreference(
      modelId: model.id,
      reasoningEffort: effort,
      fastEnabled: fastEnabled && effort != 'xhigh',
      serviceTierId: fastEnabled && effort == 'xhigh' ? null : defaultTier,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  AgentModelConfigUiState copyWith({
    Object? selectedModelId = _uiStateUnset,
    Object? selectedReasoningEffort = _uiStateUnset,
    Object? selectedServiceTierId = _uiStateUnset,
    List<AgentModelInfo>? models,
    Map<String, AgentModelPreference>? preferences,
    Set<String>? savingModelIds,
    bool? isRefreshing,
    bool? appliesNextTurn,
    bool? supportsReasoningOptions,
    bool? supportsServiceTierSelection,
    Object? compatibilityConflict = _uiStateUnset,
    Object? saveError = _uiStateUnset,
    Object? selectionNotice = _uiStateUnset,
    Object? refreshError = _uiStateUnset,
  }) {
    return AgentModelConfigUiState(
      models: models ?? this.models,
      selectedModelId: identical(selectedModelId, _uiStateUnset)
          ? this.selectedModelId
          : selectedModelId as String?,
      selectedReasoningEffort: identical(selectedReasoningEffort, _uiStateUnset)
          ? this.selectedReasoningEffort
          : selectedReasoningEffort as String?,
      selectedServiceTierId: identical(selectedServiceTierId, _uiStateUnset)
          ? this.selectedServiceTierId
          : selectedServiceTierId as String?,
      preferences: preferences ?? this.preferences,
      savingModelIds: savingModelIds ?? this.savingModelIds,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      appliesNextTurn: appliesNextTurn ?? this.appliesNextTurn,
      supportsReasoningOptions:
          supportsReasoningOptions ?? this.supportsReasoningOptions,
      supportsServiceTierSelection:
          supportsServiceTierSelection ?? this.supportsServiceTierSelection,
      compatibilityConflict: identical(compatibilityConflict, _uiStateUnset)
          ? this.compatibilityConflict
          : compatibilityConflict as AgentModelCompatibilityConflict?,
      saveError: identical(saveError, _uiStateUnset)
          ? this.saveError
          : saveError as AgentModelSelectionSaveError?,
      selectionNotice: identical(selectionNotice, _uiStateUnset)
          ? this.selectionNotice
          : selectionNotice as String?,
      refreshError: identical(refreshError, _uiStateUnset)
          ? this.refreshError
          : refreshError as String?,
    );
  }
}

const Object _uiStateUnset = Object();

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
