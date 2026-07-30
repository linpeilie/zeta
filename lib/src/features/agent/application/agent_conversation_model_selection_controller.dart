import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

typedef AgentModelSelectionPersistCallback =
    Future<void> Function(
      AgentModelSelection selection,
      Map<String, AgentModelPreference> preferences,
    );

/// 模型配置保存失败时对应的交互字段。
enum AgentModelConfigField { model, reasoningEffort, fast }

/// Fast 与思考程度发生冲突后，等待用户确认的原子调整。
class AgentModelCompatibilityConflict {
  const AgentModelCompatibilityConflict({
    required this.modelId,
    required this.message,
    required this.actionLabel,
    required this.resolution,
  });

  final String modelId;
  final String message;
  final String actionLabel;
  final AgentModelSelection resolution;
}

/// 最近一次模型配置保存失败。
class AgentModelSelectionSaveError {
  const AgentModelSelectionSaveError({
    required this.modelId,
    required this.field,
    required this.message,
    required this.details,
  });

  final String modelId;
  final AgentModelConfigField field;
  final String message;
  final String details;
}

/// Agent 模型列表、模型级偏好与保存竞态的应用层控制器。
///
/// UI 只消费规范化后的中立状态；provider 的 `serviceTier` 精确值仍保留在
/// [AgentModelPreference] 中。快速连续修改通过串行保存循环合并，最终一次写入
/// 始终覆盖过期快照。
class AgentConversationModelSelectionController extends ChangeNotifier {
  AgentConversationModelSelectionController({
    required this.persistSelection,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AgentModelSelectionPersistCallback persistSelection;
  final DateTime Function() _clock;

  AgentProvider? _provider;
  AgentModelList? _modelList;
  AgentModelSelection _modelSelection = const AgentModelSelection();
  Map<String, AgentModelPreference> _preferences =
      <String, AgentModelPreference>{};

  AgentModelSelection _confirmedSelection = const AgentModelSelection();
  Map<String, AgentModelPreference> _confirmedPreferences =
      <String, AgentModelPreference>{};
  _ModelConfigurationSnapshot? _failedSnapshot;

  final Set<String> _savingModelIds = <String>{};
  AgentModelCompatibilityConflict? _compatibilityConflict;
  AgentModelSelectionSaveError? _saveError;
  String? _selectionNotice;

  Future<void>? _saveLoop;
  final Map<int, Completer<bool>> _saveWaiters = <int, Completer<bool>>{};
  int _revision = 0;
  int _processedRevision = 0;
  int _generation = 0;
  AgentModelConfigField _latestField = AgentModelConfigField.model;
  String _latestModelId = '';
  bool _needsPreferenceMigration = false;
  bool _disposed = false;

  List<AgentModelInfo> get models =>
      _modelList?.models ?? const <AgentModelInfo>[];

  AgentModelList? get modelList => _modelList;

  AgentModelSelection get selection => _modelSelection;

  Map<String, AgentModelPreference> get preferences =>
      Map<String, AgentModelPreference>.unmodifiable(_preferences);

  Set<String> get savingModelIds => Set<String>.unmodifiable(_savingModelIds);

  AgentModelCompatibilityConflict? get compatibilityConflict =>
      _compatibilityConflict;

  AgentModelSelectionSaveError? get saveError => _saveError;

  /// 当前模型失效后自动回退的单次非阻断提示。
  String? get selectionNotice => _selectionNotice;

  AgentModelInfo? get selectedModel {
    final id = _modelSelection.modelId;
    return id == null ? null : findModel(id);
  }

  String? get selectedModelId => _modelSelection.modelId;

  String? get selectedReasoningEffort => _modelSelection.reasoningEffort;

  String? get selectedServiceTierId => _modelSelection.serviceTierId;

  bool get selectedFastEnabled {
    final model = selectedModel;
    final fastTier = model == null ? null : agentFastServiceTier(model);
    return fastTier != null &&
        fastTier.id == _modelSelection.serviceTierId &&
        fastTier.enabled;
  }

  void bindProvider(AgentProvider provider) {
    _provider = provider;
    provider.updateModelSelection(_modelSelection);
  }

  /// 切换 provider 时解绑旧实例，并按新配置清空、恢复模型状态。
  void resetForProvider(AgentProviderConfig config) {
    _generation += 1;
    _completeAllWaiters(false);
    _revision = 0;
    _processedRevision = 0;
    _savingModelIds.clear();
    _compatibilityConflict = null;
    _saveError = null;
    _selectionNotice = null;
    _failedSnapshot = null;
    _provider = null;
    _modelList = null;
    seedFromConfig(config);
  }

  void seedFromConfig(AgentProviderConfig config) {
    _selectionNotice = null;
    _modelSelection = AgentModelSelection(
      modelId: config.selectedModel,
      reasoningEffort: config.selectedReasoningEffort,
      serviceTierId: config.selectedServiceTier,
    );
    _preferences = Map<String, AgentModelPreference>.from(
      config.modelPreferences,
    );
    final modelId = config.selectedModel;
    _needsPreferenceMigration =
        modelId != null && !_preferences.containsKey(modelId);
    if (modelId != null && _needsPreferenceMigration) {
      _preferences[modelId] = AgentModelPreference(
        modelId: modelId,
        reasoningEffort: config.selectedReasoningEffort,
        fastEnabled: config.selectedServiceTier != null,
        serviceTierId: config.selectedServiceTier,
        updatedAt: _clock().toUtc(),
      );
    }
    _confirmedSelection = _modelSelection;
    _confirmedPreferences = Map<String, AgentModelPreference>.from(
      config.modelPreferences,
    );
    _provider?.updateModelSelection(_modelSelection);
    _notify();
  }

  /// 用当前 thread/session 已知的运行时配置回填选择器，但不持久化为 provider 默认值。
  void applyRuntimeSelection(AgentModelSelection selection) {
    _generation += 1;
    _completeAllWaiters(false);
    _revision = 0;
    _processedRevision = 0;
    _savingModelIds.clear();
    _compatibilityConflict = null;
    _saveError = null;
    _selectionNotice = null;
    _failedSnapshot = null;

    final resolvedModelId = selection.modelId?.trim().isNotEmpty == true
        ? selection.modelId!.trim()
        : _modelSelection.modelId;
    if (resolvedModelId == null || resolvedModelId.isEmpty) {
      return;
    }
    final model = findModel(resolvedModelId);
    final nextSelection = selection.modelId == resolvedModelId
        ? selection
        : AgentModelSelection(
            modelId: resolvedModelId,
            reasoningEffort: selection.reasoningEffort,
            serviceTierId: selection.serviceTierId,
          );
    if (model != null) {
      final fastTier = agentFastServiceTier(model);
      final preference = _normalizePreference(
        model,
        AgentModelPreference(
          modelId: model.id,
          reasoningEffort: nextSelection.reasoningEffort,
          fastEnabled:
              fastTier != null && fastTier.id == nextSelection.serviceTierId,
          serviceTierId: nextSelection.serviceTierId,
          updatedAt: _clock().toUtc(),
        ),
      );
      _preferences = <String, AgentModelPreference>{
        ..._preferences,
        model.id: preference,
      };
      _modelSelection = preference.selection;
    } else {
      _preferences = <String, AgentModelPreference>{
        ..._preferences,
        resolvedModelId: AgentModelPreference(
          modelId: resolvedModelId,
          reasoningEffort: nextSelection.reasoningEffort,
          fastEnabled: nextSelection.serviceTierId != null,
          serviceTierId: nextSelection.serviceTierId,
          updatedAt: _clock().toUtc(),
        ),
      };
      _modelSelection = nextSelection;
    }
    _needsPreferenceMigration = false;
    _confirmedSelection = _modelSelection;
    _confirmedPreferences = Map<String, AgentModelPreference>.from(
      _preferences,
    );
    _provider?.updateModelSelection(_modelSelection);
    _notify();
  }

  AgentModelInfo? findModel(String modelId) {
    for (final model in models) {
      if (model.id == modelId || model.model == modelId) {
        return model;
      }
    }
    return null;
  }

  /// 选择模型并恢复该模型上次通过 capability 校验的配置。
  Future<bool> selectModel(String modelId) {
    final model = findModel(modelId);
    if (model == null || !model.enabled) {
      return Future<bool>.value(false);
    }
    if (_modelSelection.modelId == modelId) {
      _clearTransientState();
      return Future<bool>.value(true);
    }
    final preference = _normalizePreference(
      model,
      _preferences[modelId],
    ).copyWith(updatedAt: _clock().toUtc());
    return _applyPreference(preference, field: AgentModelConfigField.model);
  }

  Future<bool> selectReasoningEffort(String? effort) {
    final model = selectedModel;
    if (model == null) {
      return Future<bool>.value(false);
    }
    final supported =
        effort == null ||
        model.supportedReasoningEfforts.any((item) => item.effort == effort);
    if (!supported) {
      return Future<bool>.value(false);
    }
    if (_isExtraHigh(effort) && selectedFastEnabled) {
      final effortLabel = effort!.trim();
      _compatibilityConflict = AgentModelCompatibilityConflict(
        modelId: model.id,
        message: 'Fast 与“$effortLabel”不兼容',
        actionLabel: '关闭 Fast 并切换到 $effortLabel',
        resolution: AgentModelSelection(
          modelId: model.id,
          reasoningEffort: effort,
        ),
      );
      _notify();
      return Future<bool>.value(false);
    }

    final current = _preferenceForSelectedModel(model);
    final preference = AgentModelPreference(
      modelId: model.id,
      reasoningEffort: effort,
      fastEnabled: current.fastEnabled,
      serviceTierId: current.serviceTierId,
      updatedAt: _clock().toUtc(),
    );
    return _applyPreference(
      preference,
      field: AgentModelConfigField.reasoningEffort,
    );
  }

  /// 打开或关闭当前模型的 Fast 服务档位。
  Future<bool> selectFastEnabled(bool enabled) {
    final model = selectedModel;
    final fastTier = model == null ? null : agentFastServiceTier(model);
    if (model == null || fastTier == null || !fastTier.enabled) {
      return Future<bool>.value(false);
    }
    if (enabled && _isExtraHigh(_modelSelection.reasoningEffort)) {
      final compatibleEffort = _fastCompatibleEffort(model);
      if (compatibleEffort == null) {
        return Future<bool>.value(false);
      }
      final currentEffort = _modelSelection.reasoningEffort!.trim();
      _compatibilityConflict = AgentModelCompatibilityConflict(
        modelId: model.id,
        message: 'Fast 与“$currentEffort”不兼容',
        actionLabel: '切换到 $compatibleEffort 并开启 Fast',
        resolution: AgentModelSelection(
          modelId: model.id,
          reasoningEffort: compatibleEffort,
          serviceTierId: fastTier.id,
        ),
      );
      _notify();
      return Future<bool>.value(false);
    }

    final current = _preferenceForSelectedModel(model);
    final preference = AgentModelPreference(
      modelId: model.id,
      reasoningEffort: current.reasoningEffort,
      fastEnabled: enabled,
      serviceTierId: enabled ? fastTier.id : null,
      updatedAt: _clock().toUtc(),
    );
    return _applyPreference(preference, field: AgentModelConfigField.fast);
  }

  /// 兼容旧调用点的通用 service tier 更新。
  Future<bool> selectServiceTier(String? tierId) {
    final model = selectedModel;
    if (model == null) {
      return Future<bool>.value(false);
    }
    final tier = tierId == null
        ? null
        : model.serviceTiers.where((item) => item.id == tierId).firstOrNull;
    if (tierId != null && (tier == null || !tier.enabled)) {
      return Future<bool>.value(false);
    }
    final fastTier = agentFastServiceTier(model);
    if (tierId != null && tierId == fastTier?.id) {
      return selectFastEnabled(true);
    }
    final current = _preferenceForSelectedModel(model);
    return _applyPreference(
      AgentModelPreference(
        modelId: model.id,
        reasoningEffort: current.reasoningEffort,
        fastEnabled: false,
        serviceTierId: tierId,
        updatedAt: _clock().toUtc(),
      ),
      field: AgentModelConfigField.fast,
    );
  }

  /// 按提示一次提交 Fast 与思考程度的兼容调整。
  Future<bool> resolveCompatibilityConflict() {
    final conflict = _compatibilityConflict;
    final model = selectedModel;
    if (conflict == null || model == null || conflict.modelId != model.id) {
      return Future<bool>.value(false);
    }
    final fastTier = agentFastServiceTier(model);
    final resolution = conflict.resolution;
    final preference = AgentModelPreference(
      modelId: model.id,
      reasoningEffort: resolution.reasoningEffort,
      fastEnabled: fastTier != null && resolution.serviceTierId == fastTier.id,
      serviceTierId: resolution.serviceTierId,
      updatedAt: _clock().toUtc(),
    );
    return _applyPreference(preference, field: AgentModelConfigField.fast);
  }

  /// 重试最近一次失败的完整快照。
  Future<bool> retryFailedSelection() {
    final failed = _failedSnapshot;
    if (failed == null) {
      return Future<bool>.value(false);
    }
    _modelSelection = failed.selection;
    _preferences = Map<String, AgentModelPreference>.from(failed.preferences);
    _provider?.updateModelSelection(_modelSelection);
    _saveError = null;
    _compatibilityConflict = null;
    return _schedulePersistence(field: failed.field, modelId: failed.modelId);
  }

  /// 关闭 Popover 时清除未确认的兼容性提示和已展示的自动回退通知。
  void clearTransientState() => _clearTransientState();

  void handleModelList(AgentModelList modelList) {
    _modelList = modelList;
    _reconcileSelection();
  }

  Future<bool> _applyPreference(
    AgentModelPreference preference, {
    required AgentModelConfigField field,
  }) {
    _preferences = <String, AgentModelPreference>{
      ..._preferences,
      preference.modelId: preference,
    };
    _modelSelection = preference.selection;
    _provider?.updateModelSelection(_modelSelection);
    _compatibilityConflict = null;
    _saveError = null;
    _selectionNotice = null;
    _failedSnapshot = null;
    return _schedulePersistence(field: field, modelId: preference.modelId);
  }

  Future<bool> _schedulePersistence({
    required AgentModelConfigField field,
    required String modelId,
  }) {
    final revision = ++_revision;
    final completer = Completer<bool>();
    _saveWaiters[revision] = completer;
    _latestField = field;
    _latestModelId = modelId;
    _savingModelIds.add(modelId);
    _notify();
    _ensureSaveLoop();
    return completer.future;
  }

  void _ensureSaveLoop() {
    if (_saveLoop != null || _processedRevision >= _revision || _disposed) {
      return;
    }
    final generation = _generation;
    final loop = _drainPersistence(generation);
    _saveLoop = loop;
    loop.whenComplete(() {
      if (!identical(_saveLoop, loop)) {
        return;
      }
      _saveLoop = null;
      if (!_disposed && _processedRevision < _revision) {
        _ensureSaveLoop();
      }
    });
  }

  Future<void> _drainPersistence(int generation) async {
    while (!_disposed &&
        generation == _generation &&
        _processedRevision < _revision) {
      final targetRevision = _revision;
      final snapshot = _ModelConfigurationSnapshot(
        selection: _modelSelection,
        preferences: Map<String, AgentModelPreference>.from(_preferences),
        field: _latestField,
        modelId: _latestModelId,
      );
      try {
        await persistSelection(
          snapshot.selection,
          Map<String, AgentModelPreference>.unmodifiable(snapshot.preferences),
        );
      } catch (error) {
        if (_disposed || generation != _generation) {
          return;
        }
        _processedRevision = targetRevision;
        if (targetRevision < _revision) {
          // 新快照已接管状态；继续保存最终值，不让过期失败触发回滚。
          continue;
        }
        _failedSnapshot = snapshot;
        _modelSelection = _confirmedSelection;
        _preferences = Map<String, AgentModelPreference>.from(
          _confirmedPreferences,
        );
        _provider?.updateModelSelection(_modelSelection);
        _savingModelIds.clear();
        _saveError = AgentModelSelectionSaveError(
          // 模型切换失败后 UI 已回到确认态，错误必须挂在当前展开卡片上；
          // 失败快照仍由 [_failedSnapshot] 保留用于重试。
          modelId: _confirmedSelection.modelId ?? snapshot.modelId,
          field: snapshot.field,
          message: '配置保存失败，已恢复上次有效设置。',
          details: error.toString(),
        );
        _completeWaitersThrough(targetRevision, false);
        _notify();
        return;
      }

      if (_disposed || generation != _generation) {
        return;
      }
      _confirmedSelection = snapshot.selection;
      _confirmedPreferences = Map<String, AgentModelPreference>.from(
        snapshot.preferences,
      );
      _processedRevision = targetRevision;
      _completeWaitersThrough(targetRevision, true);
      if (_processedRevision == _revision) {
        _savingModelIds.clear();
        _saveError = null;
        _failedSnapshot = null;
        _notify();
      }
    }
  }

  void _reconcileSelection() {
    final available = models.where((model) => model.enabled).toList();
    if (available.isEmpty) {
      _notify();
      return;
    }

    var changed = _needsPreferenceMigration;
    final normalizedPreferences = Map<String, AgentModelPreference>.from(
      _preferences,
    );
    for (final model in models) {
      final preference = normalizedPreferences[model.id];
      if (preference == null) {
        continue;
      }
      final normalized = _normalizePreference(model, preference);
      if (!_samePreference(preference, normalized)) {
        normalizedPreferences[model.id] = normalized;
        changed = true;
      }
    }

    final previousModelId = _modelSelection.modelId;
    var selected = findModel(previousModelId ?? '');
    if (selected == null || !selected.enabled) {
      selected = available.firstWhere(
        (model) => model.isDefault,
        orElse: () => available.first,
      );
      if (previousModelId != null && previousModelId.isNotEmpty) {
        _selectionNotice =
            '模型“$previousModelId”当前不可用，已切换到 ${selected.displayName}。';
      }
      changed = true;
    }

    AgentModelPreference? source = normalizedPreferences[selected.id];
    if (source == null && _modelSelection.modelId == selected.id) {
      final fastTier = agentFastServiceTier(selected);
      source = AgentModelPreference(
        modelId: selected.id,
        reasoningEffort: _modelSelection.reasoningEffort,
        fastEnabled:
            fastTier != null && fastTier.id == _modelSelection.serviceTierId,
        serviceTierId: _modelSelection.serviceTierId,
        updatedAt: _clock().toUtc(),
      );
    }
    final normalizedSelected = _normalizePreference(selected, source);
    normalizedPreferences[selected.id] = normalizedSelected;
    final nextSelection = normalizedSelected.selection;
    changed = changed || !_sameSelection(_modelSelection, nextSelection);

    _preferences = normalizedPreferences;
    _modelSelection = nextSelection;
    _provider?.updateModelSelection(_modelSelection);
    _needsPreferenceMigration = false;

    if (changed) {
      unawaited(
        _schedulePersistence(
          field: AgentModelConfigField.model,
          modelId: selected.id,
        ),
      );
      return;
    }
    _confirmedSelection = _modelSelection;
    _confirmedPreferences = Map<String, AgentModelPreference>.from(
      _preferences,
    );
    _notify();
  }

  AgentModelPreference _preferenceForSelectedModel(AgentModelInfo model) {
    return _normalizePreference(model, _preferences[model.id]);
  }

  AgentModelPreference _normalizePreference(
    AgentModelInfo model,
    AgentModelPreference? preference,
  ) {
    final now = _clock().toUtc();
    final defaultEffort = _validDefaultEffort(model);
    final candidateEffort = preference?.reasoningEffort;
    final effort =
        candidateEffort != null &&
            model.supportedReasoningEfforts.any(
              (item) => item.effort == candidateEffort,
            )
        ? candidateEffort
        : defaultEffort;

    final fastTier = agentFastServiceTier(model);
    String? tierId;
    var fastEnabled = false;
    if (preference == null) {
      tierId = _validDefaultTier(model);
      fastEnabled = fastTier != null && tierId == fastTier.id;
    } else if (preference.fastEnabled) {
      if (fastTier?.enabled ?? false) {
        tierId = fastTier!.id;
        fastEnabled = true;
      }
    } else if (preference.serviceTierId == null) {
      tierId = null;
    } else {
      final candidate = model.serviceTiers.where(
        (item) => item.id == preference.serviceTierId && item.enabled,
      );
      tierId = candidate.isEmpty
          ? _validDefaultTier(model)
          : candidate.first.id;
      fastEnabled = fastTier != null && tierId == fastTier.id;
    }

    if (_isExtraHigh(effort) && fastEnabled) {
      tierId = null;
      fastEnabled = false;
    }

    final normalized = AgentModelPreference(
      modelId: model.id,
      reasoningEffort: effort,
      fastEnabled: fastEnabled,
      serviceTierId: tierId,
      updatedAt: preference?.updatedAt ?? now,
      version: AgentModelPreference.currentVersion,
    );
    if (preference != null && !_samePreference(preference, normalized)) {
      return normalized.copyWith(updatedAt: now);
    }
    return normalized;
  }

  String? _validDefaultEffort(AgentModelInfo model) {
    final value = model.defaultReasoningEffort;
    if (value != null &&
        model.supportedReasoningEfforts.any((item) => item.effort == value)) {
      return value;
    }
    return model.supportedReasoningEfforts.firstOrNull?.effort;
  }

  String? _validDefaultTier(AgentModelInfo model) {
    final value = model.defaultServiceTier;
    if (value == null) {
      return null;
    }
    for (final tier in model.serviceTiers) {
      if (tier.id == value && tier.enabled) {
        return value;
      }
    }
    return null;
  }

  String? _fastCompatibleEffort(AgentModelInfo model) {
    for (final effort in model.supportedReasoningEfforts.reversed) {
      if (!_isExtraHigh(effort.effort)) {
        return effort.effort;
      }
    }
    return null;
  }

  bool _isExtraHigh(String? effort) => effort?.trim().toLowerCase() == 'xhigh';

  void _clearTransientState() {
    if (_compatibilityConflict == null && _selectionNotice == null) {
      return;
    }
    _compatibilityConflict = null;
    _selectionNotice = null;
    _notify();
  }

  void _completeWaitersThrough(int revision, bool result) {
    final completed = _saveWaiters.keys
        .where((candidate) => candidate <= revision)
        .toList(growable: false);
    for (final key in completed) {
      final waiter = _saveWaiters.remove(key);
      if (waiter != null && !waiter.isCompleted) {
        waiter.complete(result);
      }
    }
  }

  void _completeAllWaiters(bool result) {
    for (final waiter in _saveWaiters.values) {
      if (!waiter.isCompleted) {
        waiter.complete(result);
      }
    }
    _saveWaiters.clear();
  }

  bool _sameSelection(AgentModelSelection a, AgentModelSelection b) =>
      a.modelId == b.modelId &&
      a.reasoningEffort == b.reasoningEffort &&
      a.serviceTierId == b.serviceTierId;

  bool _samePreference(AgentModelPreference a, AgentModelPreference b) =>
      a.modelId == b.modelId &&
      a.reasoningEffort == b.reasoningEffort &&
      a.fastEnabled == b.fastEnabled &&
      a.serviceTierId == b.serviceTierId &&
      a.updatedAt == b.updatedAt &&
      a.version == b.version;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _completeAllWaiters(false);
    super.dispose();
  }
}

class _ModelConfigurationSnapshot {
  const _ModelConfigurationSnapshot({
    required this.selection,
    required this.preferences,
    required this.field,
    required this.modelId,
  });

  final AgentModelSelection selection;
  final Map<String, AgentModelPreference> preferences;
  final AgentModelConfigField field;
  final String modelId;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
