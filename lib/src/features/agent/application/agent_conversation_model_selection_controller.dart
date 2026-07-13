import 'dart:async';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// Agent 模型列表与选择状态的应用层控制器。
///
/// 它负责：
/// - 从 provider 配置恢复当前选择
/// - 接收 provider 推送的模型列表并校正无效选择
/// - 将用户的模型/推理档位/服务档位选择同步到 provider 与持久化配置
class AgentConversationModelSelectionController {
  AgentConversationModelSelectionController({required this._persistSelection});

  final Future<void> Function(AgentModelSelection selection) _persistSelection;

  AgentProvider? _provider;
  AgentModelList? _modelList;
  AgentModelSelection _modelSelection = const AgentModelSelection();

  List<AgentModelInfo> get models =>
      _modelList?.models ?? const <AgentModelInfo>[];

  AgentModelList? get modelList => _modelList;

  AgentModelSelection get selection => _modelSelection;

  AgentModelInfo? get selectedModel {
    final id = _modelSelection.modelId;
    if (id == null) {
      return null;
    }
    return findModel(id);
  }

  String? get selectedModelId => _modelSelection.modelId;

  String? get selectedReasoningEffort => _modelSelection.reasoningEffort;

  String? get selectedServiceTierId => _modelSelection.serviceTierId;

  void bindProvider(AgentProvider provider) {
    _provider = provider;
    provider.updateModelSelection(_modelSelection);
  }

  /// 切换 provider 时解绑旧实例，并按新配置清空、恢复模型状态。
  void resetForProvider(AgentProviderConfig config) {
    _provider = null;
    _modelList = null;
    seedFromConfig(config);
  }

  void seedFromConfig(AgentProviderConfig config) {
    _modelSelection = AgentModelSelection(
      modelId: config.selectedModel,
      reasoningEffort: config.selectedReasoningEffort,
      serviceTierId: config.selectedServiceTier,
    );
    _provider?.updateModelSelection(_modelSelection);
  }

  AgentModelInfo? findModel(String modelId) {
    for (final model in models) {
      if (model.id == modelId) {
        return model;
      }
    }
    return null;
  }

  Future<void> selectModel(String modelId) async {
    final model = findModel(modelId);
    if (model == null) {
      return;
    }
    _modelSelection = AgentModelSelection(
      modelId: modelId,
      reasoningEffort: model.defaultReasoningEffort,
      serviceTierId: model.defaultServiceTier,
    );
    await _syncSelection();
  }

  Future<void> selectReasoningEffort(String? effort) async {
    _modelSelection = AgentModelSelection(
      modelId: _modelSelection.modelId,
      reasoningEffort: effort,
      serviceTierId: _modelSelection.serviceTierId,
    );
    await _syncSelection();
  }

  Future<void> selectServiceTier(String? tierId) async {
    _modelSelection = AgentModelSelection(
      modelId: _modelSelection.modelId,
      reasoningEffort: _modelSelection.reasoningEffort,
      serviceTierId: tierId,
    );
    await _syncSelection();
  }

  void handleModelList(AgentModelList modelList) {
    _modelList = modelList;
    _reconcileSelection();
  }

  Future<void> _syncSelection() async {
    _provider?.updateModelSelection(_modelSelection);
    await _persistSelection(_modelSelection);
  }

  void _reconcileSelection() {
    final models = _modelList?.models ?? const <AgentModelInfo>[];
    if (models.isEmpty) {
      return;
    }

    var modelId = _modelSelection.modelId;
    AgentModelInfo? selected = findModel(modelId ?? '');
    if (selected == null) {
      final defaultModel = models.firstWhere(
        (model) => model.isDefault,
        orElse: () => models.first,
      );
      modelId = defaultModel.id;
      selected = defaultModel;
    }

    var effort = _modelSelection.reasoningEffort;
    if (effort == null ||
        !selected.supportedReasoningEfforts.any((e) => e.effort == effort)) {
      effort = selected.defaultReasoningEffort;
    }

    var tierId = _modelSelection.serviceTierId;
    if (tierId == null || !selected.serviceTiers.any((t) => t.id == tierId)) {
      tierId = selected.defaultServiceTier;
    }

    final newSelection = AgentModelSelection(
      modelId: modelId,
      reasoningEffort: effort,
      serviceTierId: tierId,
    );
    if (newSelection.modelId != _modelSelection.modelId ||
        newSelection.reasoningEffort != _modelSelection.reasoningEffort ||
        newSelection.serviceTierId != _modelSelection.serviceTierId) {
      _modelSelection = newSelection;
      _provider?.updateModelSelection(_modelSelection);
      unawaited(_persistSelection(_modelSelection));
    }
  }
}
