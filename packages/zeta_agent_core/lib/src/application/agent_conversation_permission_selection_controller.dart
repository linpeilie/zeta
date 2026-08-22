import 'package:flutter/foundation.dart';

import 'package:zeta_agent_core/src/application/agent_conversation_permission_state.dart';
import 'package:zeta_agent_core/src/application/agent_permission_catalog_controller.dart';
import 'package:zeta_agent_core/src/application/agent_provider_runtime_identity.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/domain/fallback_agent_ui_text_catalog.dart';

@immutable
final class _AgentPermissionSelectionTransition {
  const _AgentPermissionSelectionTransition({
    required this.previous,
    required this.current,
    required this.runtimeIdentity,
    required this.threadId,
  });

  final AgentPermissionSelection previous;
  final AgentPermissionSelection current;
  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final String? threadId;
}

final class _PlanningOnlyPermissionMemory {
  const _PlanningOnlyPermissionMemory({
    required this.selection,
    required this.providerId,
    required this.threadId,
  });

  final AgentPermissionSelection selection;
  final String? providerId;
  final String? threadId;
}

/// 单个 Conversation Binding 的权限协调器。
///
/// catalog、Provider apply 和偏好持久化在此编排；所有权限事实收敛到一个
/// [AgentConversationPermissionState]，不再维护跨 Provider/runtime/thread 注册表。
/// 迟到异步结果的门闩不依赖内部计数器：runtime 相关路径用精确
/// [AgentProviderRuntimeIdentity] + apply port 实例判定；无 runtime 的
/// dormant 持久化路径用「目标 selection 是否仍是当前 provider default」判定。
class AgentConversationPermissionSelectionController extends ChangeNotifier {
  AgentConversationPermissionSelectionController({
    required this.persistOptionId,
    AgentUiTextCatalog? textCatalog,
  }) : _textCatalog = textCatalog ?? const FallbackAgentUiTextCatalog();

  /// 持久化 provider 默认 optionId。
  final Future<void> Function(String optionId) persistOptionId;
  final AgentUiTextCatalog _textCatalog;
  final AgentPermissionCatalogController _catalogController =
      AgentPermissionCatalogController();

  AgentConversationPermissionState _state =
      const AgentConversationPermissionState();
  AgentPermissionPolicyPort? _runtimePort;
  _AgentPermissionSelectionTransition? _lastUserSelectionTransition;
  _PlanningOnlyPermissionMemory? _permissionBeforePlanning;
  bool _disposed = false;
  String? _lastError;

  AgentConversationPermissionState get state => _state;

  AgentProviderRuntimeIdentity? get runtimeIdentity => _state.runtimeIdentity;

  bool get hasPort => _runtimePort != null || _catalogController.port != null;

  bool get isRuntimeAttached => _state.runtimeIdentity != null;

  List<AgentPermissionOption> get options => _catalogController.options;

  String? get selectedOptionId => effectiveSelection?.optionId;

  String? get defaultOptionId => _state.providerDefaultPreference?.optionId;

  AgentPermissionSelection? get effectiveSelection =>
      _state.effectiveValue?.selection ?? catalogDefault;

  AgentPermissionSelection? get defaultPreference =>
      _state.providerDefaultPreference;

  AgentPermissionSelection? get catalogDefault =>
      _catalogController.catalogDefault;

  /// 返回当前用户选择生效前的权限，仅供同一 Binding/thread/runtime 使用。
  ///
  /// 该方法不解析不透明 optionId；当前选择、thread 或 runtime generation 任一
  /// 发生变化都会 fail-closed 返回 null。
  AgentPermissionSelection? selectionBeforeCurrentUserSelection({
    String? threadId,
  }) {
    final transition = _lastUserSelectionTransition;
    if (transition == null ||
        transition.current != effectiveSelection ||
        transition.runtimeIdentity != _state.runtimeIdentity ||
        transition.threadId != _state.threadId) {
      return null;
    }
    final requestedThreadId = _normalizeThreadId(threadId ?? _state.threadId);
    if (requestedThreadId != _state.threadId) {
      return null;
    }
    return transition.previous;
  }

  /// 进入只读规划档之前的权限；同 Binding/thread 有效，不绑定 runtime generation。
  AgentPermissionSelection? selectionBeforePlanningOnly({String? threadId}) {
    final memory = _permissionBeforePlanning;
    if (memory == null) {
      return null;
    }
    final current = effectiveSelection;
    if (current == null ||
        _optionById(current.optionId)?.planningOnly != true) {
      return null;
    }
    if (memory.threadId != _state.threadId) {
      return null;
    }
    final requestedThreadId = _normalizeThreadId(threadId ?? _state.threadId);
    if (requestedThreadId != _state.threadId) {
      return null;
    }
    final currentProviderId = _state.runtimeIdentity?.providerId;
    if (memory.providerId != null &&
        currentProviderId != null &&
        memory.providerId != currentProviderId) {
      return null;
    }
    return memory.selection;
  }

  /// 将会话权限改为 [selection]，应用到当前 runtime，不写持久化默认。
  Future<bool> adoptSessionPermission(
    AgentPermissionSelection selection,
  ) async {
    if (_disposed) {
      return false;
    }
    await applyEffectiveSelection(selection, syncPort: true);
    if (effectiveSelection != selection) {
      // apply 可能因 Claude 重启进程导致 runtime generation 变化而被丢弃；
      // 会话工具栏仍必须离开 planning，本回合发送另带 permission 快照。
      await applyEffectiveSelection(selection, syncPort: false);
    }
    return effectiveSelection == selection;
  }

  AgentPermissionStateSource? get stateSource => _state.effectiveValue?.source;

  AgentPermissionApplyScope? get lastApplyScope => _state.lastApplyScope;

  String? get lastApplyWarning => _state.warning;

  bool get isCatalogLoading => _catalogController.isLoading;

  String? get lastError =>
      _lastError ??
      _state.persistenceFailure?.message ??
      _catalogController.lastError?.toString();

  bool get canRetryPersistence => _state.persistenceFailure != null;

  /// 为一次请求冻结权限来源；`currentTurn` 在冻结后即被取走。
  AgentPermissionRequestSnapshot snapshotForRequest({String? threadId}) {
    final result = _state.takeRequestSnapshot(
      requestedThreadId: threadId ?? _state.threadId,
      catalogDefault: catalogDefault,
    );
    _setState(result.state);
    return result.snapshot;
  }

  String get displayLabel {
    final optionId = selectedOptionId;
    if (optionId == null || optionId.isEmpty) {
      return 'Permission';
    }
    final option = _catalogController.catalog?.optionById(optionId);
    return option?.label ?? optionId;
  }

  String? get applyScopeHint {
    // 尚无 session runtime 时，选择已经是下一次启动的确定配置，不把它展示成
    // “尚未设置成功”。已有 runtime 明确返回 nextSession 时仍保留提示。
    if (lastApplyScope == AgentPermissionApplyScope.nextSession &&
        !isRuntimeAttached) {
      return null;
    }
    final warning = lastApplyWarning?.trim();
    if (warning != null && warning.isNotEmpty) {
      return warning;
    }
    return switch (lastApplyScope) {
      AgentPermissionApplyScope.nextSession => _textCatalog.permNextSession,
      AgentPermissionApplyScope.currentTurn => _textCatalog.permCurrentTurn,
      AgentPermissionApplyScope.currentSession ||
      AgentPermissionApplyScope.runtime ||
      null => null,
    };
  }

  /// 绑定当前 Binding 的可写 session runtime。
  void bind({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
    required AgentProviderRuntimeIdentity runtimeIdentity,
  }) {
    if (_disposed) {
      return;
    }
    _runtimePort = port;
    _catalogController.bind(port, preserveLastKnownGood: true);
    _lastError = null;
    _setState(
      _state.attachRuntime(
        runtimeIdentity,
        initialProviderDefault: _selectionFromId(persistedOptionId),
      ),
    );
  }

  /// 仅绑定 global runtime 的权限目录，不改变 session runtime 身份或 apply 端口。
  void bindCatalogOnly({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
  }) {
    if (_disposed) {
      return;
    }
    _catalogController.bind(port, preserveLastKnownGood: true);
    _setState(_state.seedProviderDefault(_selectionFromId(persistedOptionId)));
  }

  /// 标记 session runtime 已退出；保留默认、session effective、pending turn 和
  /// 持久化失败，只清除 runtime-only selection。
  void detachRuntime() {
    if (_disposed || _state.runtimeIdentity == null) {
      return;
    }
    _runtimePort = null;
    _setState(_state.detachRuntime());
  }

  /// 初始化一个尚未启动 session runtime 的 Binding。
  void resetForProvider({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
  }) {
    if (_disposed) {
      return;
    }
    _runtimePort = null;
    _lastUserSelectionTransition = null;
    _permissionBeforePlanning = null;
    _catalogController.bind(port);
    _lastError = null;
    _setState(
      AgentConversationPermissionState(
        providerDefaultPreference: _selectionFromId(persistedOptionId),
        source: persistedOptionId == null
            ? null
            : AgentPermissionStateSource.providerDefault,
      ),
    );
  }

  /// 仅在当前状态尚无内存默认时从配置恢复 preference。
  void seedFromConfig(String? persistedOptionId) {
    if (_disposed) {
      return;
    }
    _setState(_state.seedProviderDefault(_selectionFromId(persistedOptionId)));
  }

  void bindThread(String? threadId) {
    if (_disposed) {
      return;
    }
    final nextThread = _normalizeThreadId(threadId);
    if (_permissionBeforePlanning != null &&
        _permissionBeforePlanning!.threadId != nextThread) {
      _permissionBeforePlanning = null;
    }
    _setState(_state.bindThread(threadId));
  }

  Future<void> refreshOptions() async {
    final operation = _catalogController.refresh();
    _notify();
    final changed = await operation;
    if (!_disposed && changed) {
      _notify();
    }
  }

  /// 用户选择：runtime 存在时调用 session port；dormant 时只更新下一次请求。
  Future<void> selectOption(AgentPermissionOption option) async {
    if (_disposed || !option.allowed) {
      return;
    }
    final previous = effectiveSelection;
    final expectedIdentity = _state.runtimeIdentity;
    final expectedThreadId = _state.threadId;
    if (!isRuntimeAttached) {
      await _selectDormantOption(option);
      _recordUserSelectionTransition(
        previous: previous,
        current: effectiveSelection,
        expectedIdentity: expectedIdentity,
        expectedThreadId: expectedThreadId,
      );
      _rememberBeforePlanning(previous: previous, current: effectiveSelection);
      return;
    }
    final port = _runtimePort;
    if (port == null) {
      _lastError = _textCatalog.permUnsupported;
      _notify();
      return;
    }
    final appliedSelection = await _applyThroughPort(
      port: port,
      selection: AgentPermissionSelection(optionId: option.id),
      source: AgentPermissionStateSource.userSelection,
      updateDefault: true,
      persistDefault: true,
    );
    _recordUserSelectionTransition(
      previous: previous,
      current: appliedSelection,
      expectedIdentity: expectedIdentity,
      expectedThreadId: expectedThreadId,
    );
    _rememberBeforePlanning(previous: previous, current: appliedSelection);
  }

  Future<void> _selectDormantOption(AgentPermissionOption option) async {
    final selection = AgentPermissionSelection(optionId: option.id);
    _commitApplyResult(
      AgentPermissionApplyResult(
        normalizedSelection: selection,
        scope: AgentPermissionApplyScope.nextSession,
        warning: _textCatalog.permNextSend,
      ),
      source: AgentPermissionStateSource.userSelection,
      updateDefault: true,
    );
    await _persistSelection(
      selection,
      successFailureMessage: _textCatalog.permSavedButPersistFailed,
    );
  }

  /// 外部选择同步；无需 RPC 时直接提交 currentSession 状态。
  Future<void> applyEffectiveSelection(
    AgentPermissionSelection selection, {
    bool syncPort = true,
  }) async {
    if (_disposed) {
      return;
    }
    final normalized = _selectionFromId(selection.optionId);
    if (normalized == null) {
      return;
    }
    final port = _runtimePort;
    final previous = effectiveSelection;
    if (!syncPort || port == null) {
      _commitApplyResult(
        AgentPermissionApplyResult(
          normalizedSelection: normalized,
          scope: AgentPermissionApplyScope.currentSession,
        ),
        source: AgentPermissionStateSource.userSelection,
        updateDefault: false,
      );
      _rememberBeforePlanning(previous: previous, current: effectiveSelection);
      return;
    }
    await _applyThroughPort(
      port: port,
      selection: normalized,
      source: AgentPermissionStateSource.userSelection,
      updateDefault: false,
      persistDefault: false,
    );
    _rememberBeforePlanning(previous: previous, current: effectiveSelection);
  }

  /// `thread/settings/updated` 服务端事实回写。
  ///
  /// 一个 Binding 只接受自己的 thread；未晋升 draft 收到首个真实 thread 事件时
  /// 原子采用该 id，其他 thread 的迟到通知直接丢弃。
  Future<void> applyThreadSettings({
    required String threadId,
    AgentPermissionSelection? permissionSelection,
    bool syncPort = false,
  }) async {
    if (_disposed) {
      return;
    }
    final normalizedThread = _normalizeThreadId(threadId);
    final selection = _selectionFromId(permissionSelection?.optionId);
    if (normalizedThread == null || selection == null) {
      return;
    }
    final boundThread = _state.threadId;
    if (boundThread == null) {
      _setState(_state.bindThread(normalizedThread));
    } else if (boundThread != normalizedThread) {
      return;
    }
    final port = _runtimePort;
    if (syncPort && port != null) {
      await _applyThroughPort(
        port: port,
        selection: selection,
        source: AgentPermissionStateSource.serverSettings,
        updateDefault: false,
        persistDefault: false,
      );
      return;
    }
    _commitApplyResult(
      AgentPermissionApplyResult(
        normalizedSelection: selection,
        scope: AgentPermissionApplyScope.currentSession,
      ),
      source: AgentPermissionStateSource.serverSettings,
      updateDefault: false,
    );
  }

  /// 只重试偏好持久化，不重复 Provider apply。
  Future<bool> retryPersistOptionId() async {
    if (_disposed) {
      return false;
    }
    final failure = _state.persistenceFailure;
    if (failure == null) {
      return false;
    }
    try {
      await persistOptionId(failure.selection.optionId);
      if (_disposed ||
          _state.persistenceFailure?.selection != failure.selection) {
        return false;
      }
      _setState(_state.clearPersistenceFailure(failure.selection));
      _lastError = null;
      return true;
    } catch (_) {
      if (!_disposed &&
          _state.persistenceFailure?.selection == failure.selection) {
        _setState(
          _state.recordPersistenceFailure(
            selection: failure.selection,
            message: _textCatalog.permAppliedButPersistFailed,
          ),
        );
      }
      return false;
    }
  }

  String? takeLastError() {
    final error = lastError;
    _lastError = null;
    _catalogController.takeLastError();
    return error;
  }

  String? takeApplyHint() => applyScopeHint;

  Future<AgentPermissionSelection?> _applyThroughPort({
    required AgentPermissionPolicyPort port,
    required AgentPermissionSelection selection,
    required AgentPermissionStateSource source,
    required bool updateDefault,
    required bool persistDefault,
  }) async {
    final identity = _state.runtimeIdentity;
    if (identity == null || !_state.isCurrent(identity)) {
      _lastError = _textCatalog.permRuntimeStale;
      _notify();
      return null;
    }
    _lastError = null;
    try {
      final result = await port.applyPermissionSelection(selection);
      if (!_isRuntimeCurrent(identity, port)) {
        return null;
      }
      _commitApplyResult(result, source: source, updateDefault: updateDefault);
      if (!persistDefault ||
          result.scope == AgentPermissionApplyScope.currentTurn) {
        return result.normalizedSelection;
      }
      await _persistSelection(
        result.normalizedSelection,
        expectedIdentity: identity,
        successFailureMessage: _textCatalog.permAppliedButPersistFailed,
      );
      return result.normalizedSelection;
    } catch (_) {
      if (_isRuntimeCurrent(identity, port)) {
        _lastError = _textCatalog.permSwitchFailed;
        _notify();
      }
      return null;
    }
  }

  AgentPermissionOption? _optionById(String? optionId) {
    final normalized = optionId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final option in options) {
      if (option.id == normalized) {
        return option;
      }
    }
    return null;
  }

  void _rememberBeforePlanning({
    required AgentPermissionSelection? previous,
    required AgentPermissionSelection? current,
  }) {
    if (current == null ||
        _optionById(current.optionId)?.planningOnly != true) {
      _permissionBeforePlanning = null;
      return;
    }
    if (previous == null ||
        _optionById(previous.optionId)?.planningOnly == true) {
      return;
    }
    _permissionBeforePlanning = _PlanningOnlyPermissionMemory(
      selection: previous,
      providerId: _state.runtimeIdentity?.providerId,
      threadId: _state.threadId,
    );
  }

  void _recordUserSelectionTransition({
    required AgentPermissionSelection? previous,
    required AgentPermissionSelection? current,
    required AgentProviderRuntimeIdentity? expectedIdentity,
    required String? expectedThreadId,
  }) {
    if (_disposed ||
        previous == null ||
        current == null ||
        previous == current ||
        _state.runtimeIdentity != expectedIdentity ||
        _state.threadId != expectedThreadId ||
        effectiveSelection != current) {
      _lastUserSelectionTransition = null;
      return;
    }
    _lastUserSelectionTransition = _AgentPermissionSelectionTransition(
      previous: previous,
      current: current,
      runtimeIdentity: expectedIdentity,
      threadId: expectedThreadId,
    );
  }

  Future<void> _persistSelection(
    AgentPermissionSelection selection, {
    AgentProviderRuntimeIdentity? expectedIdentity,
    required String successFailureMessage,
  }) async {
    try {
      await persistOptionId(selection.optionId);
      if (!_isPersistenceCurrent(selection, expectedIdentity)) {
        return;
      }
      _setState(_state.clearPersistenceFailure(selection));
    } catch (_) {
      if (_isPersistenceCurrent(selection, expectedIdentity)) {
        _setState(
          _state.recordPersistenceFailure(
            selection: selection,
            message: successFailureMessage,
          ),
        );
      }
    }
  }

  void _commitApplyResult(
    AgentPermissionApplyResult result, {
    required AgentPermissionStateSource source,
    required bool updateDefault,
  }) {
    _setState(
      _state.commitApplyResult(
        result: result,
        source: source,
        updateDefault: updateDefault,
      ),
    );
  }

  bool _isRuntimeCurrent(
    AgentProviderRuntimeIdentity identity,
    AgentPermissionPolicyPort port,
  ) {
    return !_disposed &&
        _state.isCurrent(identity) &&
        identical(port, _runtimePort);
  }

  /// runtime 路径按精确 identity 判定；dormant 路径（无 runtime）按「要保存的
  /// selection 是否仍是当前 provider default」判定——被更晚的选择顶掉即视为
  /// 过期，不回写错误状态。
  bool _isPersistenceCurrent(
    AgentPermissionSelection selection,
    AgentProviderRuntimeIdentity? identity,
  ) {
    if (_disposed) {
      return false;
    }
    if (identity != null) {
      return _state.isCurrent(identity);
    }
    return _state.providerDefaultPreference == selection;
  }

  void _setState(AgentConversationPermissionState next) {
    if (identical(next, _state)) {
      return;
    }
    _state = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtimePort = null;
    _catalogController.dispose();
    super.dispose();
  }
}

AgentPermissionSelection? _selectionFromId(String? optionId) {
  final normalized = optionId?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return AgentPermissionSelection(optionId: normalized);
}

String? _normalizeThreadId(String? threadId) {
  final normalized = threadId?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
