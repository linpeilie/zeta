import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_permission_catalog_controller.dart';
import 'package:zeta/src/features/agent/application/agent_permission_state_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 权限选项选择的应用层协调器。
///
/// catalog 生命周期由 [AgentPermissionCatalogController] 管理；provider default、
/// thread effective 与 runtime broadcast 统一由 [AgentPermissionStateStore] 管理。
/// 本类只编排 port apply、持久化与当前 Canvas 的 thread 绑定。
class AgentConversationPermissionSelectionController extends ChangeNotifier {
  AgentConversationPermissionSelectionController({
    required this.persistOptionId,
    AgentPermissionStateStore? stateStore,
  }) : _stateStore = stateStore ?? AgentPermissionStateStore(),
       _ownsStateStore = stateStore == null {
    _runtimeIdentity = AgentProviderRuntimeIdentity(
      providerId: '__permission-controller-${_nextDetachedId += 1}',
      generation: 0,
      isProvisional: true,
    );
    _stateStore.activateRuntime(_runtimeIdentity);
    _stateStore.addListener(_handleStateStoreChanged);
  }

  static int _nextDetachedId = 0;

  /// 持久化 provider 默认 optionId。
  final Future<void> Function(String optionId) persistOptionId;
  final AgentPermissionCatalogController _catalogController =
      AgentPermissionCatalogController();
  final AgentPermissionStateStore _stateStore;
  final bool _ownsStateStore;

  late AgentProviderRuntimeIdentity _runtimeIdentity;
  String? _boundThreadId;
  int _bindingGeneration = 0;
  bool _disposed = false;
  String? _lastError;

  AgentPermissionState get state => _stateStore.stateFor(_runtimeIdentity);

  AgentProviderRuntimeIdentity get runtimeIdentity => _runtimeIdentity;

  AgentPermissionPolicyPort? get port => _catalogController.port;

  bool get hasPort => port != null;

  List<AgentPermissionOption> get options => _catalogController.options;

  String? get selectedOptionId => effectiveSelection?.optionId;

  String? get defaultOptionId => state.providerDefaultPreference?.optionId;

  AgentPermissionSelection? get effectiveSelection {
    return state.effectiveStateForThread(_boundThreadId)?.selection ??
        catalogDefault;
  }

  AgentPermissionSelection? get defaultPreference =>
      state.providerDefaultPreference;

  AgentPermissionSelection? get catalogDefault =>
      _catalogController.catalogDefault;

  AgentPermissionStateSource? get stateSource =>
      state.effectiveStateForThread(_boundThreadId)?.source;

  AgentPermissionApplyScope? get lastApplyScope => state.lastApplyScope;

  String? get lastApplyWarning => state.warning;

  String? get lastError => _lastError ?? state.persistenceFailure?.message;

  bool get canRetryPersistence => state.persistenceFailure != null;

  /// 为一次请求冻结权限来源；`currentTurn` 选择在冻结后即从 pending 状态取走。
  AgentPermissionRequestSnapshot snapshotForRequest({String? threadId}) {
    final normalized = _normalizeThreadId(threadId) ?? _boundThreadId;
    return _stateStore.takeRequestSnapshot(
      identity: _runtimeIdentity,
      threadId: normalized,
      catalogDefault: catalogDefault,
    );
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
    final warning = lastApplyWarning?.trim();
    if (warning != null && warning.isNotEmpty) {
      return warning;
    }
    return switch (lastApplyScope) {
      AgentPermissionApplyScope.nextSession => '下次会话生效',
      AgentPermissionApplyScope.currentTurn => '本回合生效',
      AgentPermissionApplyScope.currentSession => null,
      AgentPermissionApplyScope.runtime => null,
      null => null,
    };
  }

  /// 绑定 permission port 与精确的 provider runtime generation。
  void bind({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
    AgentProviderRuntimeIdentity? runtimeIdentity,
  }) {
    if (_disposed) {
      return;
    }
    _bindingGeneration += 1;
    _catalogController.bind(port);
    final previousIdentity = _runtimeIdentity;
    _runtimeIdentity = runtimeIdentity ?? _runtimeIdentity;
    _lastError = null;
    _stateStore.activateRuntime(
      _runtimeIdentity,
      initialProviderDefault: _selectionFromId(persistedOptionId),
    );
    _stateStore.adoptProvisionalThreadState(
      provisionalIdentity: previousIdentity,
      runtimeIdentity: _runtimeIdentity,
    );
    _notify();
  }

  /// provider 尚未取得 runtime lease 时绑定一个仅用于配置展示的隔离身份。
  void resetForProvider({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
    String? providerId,
  }) {
    if (_disposed) {
      return;
    }
    _boundThreadId = null;
    final normalizedProvider = providerId?.trim();
    final detachedProviderId =
        normalizedProvider == null || normalizedProvider.isEmpty
        ? '__permission-controller-${_nextDetachedId += 1}'
        : '$normalizedProvider#detached-${_nextDetachedId += 1}';
    bind(
      port: port,
      persistedOptionId: persistedOptionId,
      runtimeIdentity: AgentProviderRuntimeIdentity(
        providerId: detachedProviderId,
        generation: 0,
        isProvisional: true,
      ),
    );
  }

  /// 仅在当前状态尚无内存默认时从配置恢复 preference。
  void seedFromConfig(String? persistedOptionId) {
    if (_disposed) {
      return;
    }
    _stateStore.seedProviderDefault(
      _runtimeIdentity,
      _selectionFromId(persistedOptionId),
    );
  }

  void bindThread(String? threadId) {
    if (_disposed) {
      return;
    }
    final nextId = _normalizeThreadId(threadId);
    if (nextId == _boundThreadId) {
      return;
    }
    _boundThreadId = nextId;
    _notify();
  }

  Future<void> refreshOptions() async {
    final changed = await _catalogController.refresh();
    if (!_disposed && changed) {
      _notify();
    }
  }

  /// 用户选择：所有成功路径统一提交 adapter 返回的完整 apply result。
  Future<void> selectOption(AgentPermissionOption option) async {
    if (_disposed || !option.allowed) {
      return;
    }
    final port = this.port;
    if (port == null) {
      _lastError = '当前 Provider 不支持权限选择';
      _notify();
      return;
    }
    await _applyThroughPort(
      port: port,
      selection: AgentPermissionSelection(optionId: option.id),
      threadId: _boundThreadId,
      source: AgentPermissionStateSource.userSelection,
      updateDefault: true,
      persistDefault: true,
    );
  }

  /// 外部选择同步；无 port/无需 RPC 时也构造统一的 currentSession result 提交。
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
    final port = this.port;
    if (!syncPort || port == null) {
      _commitApplyResult(
        AgentPermissionApplyResult(
          normalizedSelection: normalized,
          scope: AgentPermissionApplyScope.currentSession,
        ),
        threadId: _boundThreadId,
        source: AgentPermissionStateSource.userSelection,
        updateDefault: false,
      );
      return;
    }
    await _applyThroughPort(
      port: port,
      selection: normalized,
      threadId: _boundThreadId,
      source: AgentPermissionStateSource.userSelection,
      updateDefault: false,
      persistDefault: false,
    );
  }

  /// `thread/settings/updated` 服务端事实回写。
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
    final port = this.port;
    if (syncPort && port != null) {
      await _applyThroughPort(
        port: port,
        selection: selection,
        threadId: normalizedThread,
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
      threadId: normalizedThread,
      source: AgentPermissionStateSource.serverSettings,
      updateDefault: false,
    );
  }

  /// 重试“provider 已 apply、默认偏好保存失败”的持久化步骤，不重复 apply。
  Future<bool> retryPersistOptionId() async {
    if (_disposed) {
      return false;
    }
    final identity = _runtimeIdentity;
    final failure = state.persistenceFailure;
    if (failure == null || !_stateStore.isCurrent(identity)) {
      return false;
    }
    try {
      await persistOptionId(failure.selection.optionId);
      if (_disposed ||
          identity != _runtimeIdentity ||
          !_stateStore.isCurrent(identity)) {
        return false;
      }
      _stateStore.clearPersistenceFailure(
        identity: identity,
        selection: failure.selection,
      );
      _lastError = null;
      return true;
    } catch (_) {
      if (!_disposed &&
          identity == _runtimeIdentity &&
          _stateStore.isCurrent(identity)) {
        _stateStore.recordPersistenceFailure(
          identity: identity,
          selection: failure.selection,
          message: '权限偏好已应用，但保存失败；可重试',
        );
      }
      return false;
    }
  }

  String? takeLastError() {
    final error = lastError;
    _lastError = null;
    return error;
  }

  String? takeApplyHint() => applyScopeHint;

  Future<void> _applyThroughPort({
    required AgentPermissionPolicyPort port,
    required AgentPermissionSelection selection,
    required String? threadId,
    required AgentPermissionStateSource source,
    required bool updateDefault,
    required bool persistDefault,
  }) async {
    final generation = _bindingGeneration;
    final identity = _runtimeIdentity;
    if (!_stateStore.isCurrent(identity)) {
      _lastError = 'Provider 运行实例已失效，请重试';
      _notify();
      return;
    }
    _lastError = null;
    try {
      final result = await port.applyPermissionSelection(selection);
      if (_disposed ||
          generation != _bindingGeneration ||
          identity != _runtimeIdentity ||
          !identical(port, this.port) ||
          !_stateStore.isCurrent(identity)) {
        return;
      }
      final committed = _commitApplyResult(
        result,
        threadId: threadId,
        source: source,
        updateDefault: updateDefault,
      );
      final shouldPersist =
          committed &&
          persistDefault &&
          result.scope != AgentPermissionApplyScope.currentTurn;
      if (!shouldPersist) {
        return;
      }
      try {
        await persistOptionId(result.normalizedSelection.optionId);
        if (!_disposed &&
            generation == _bindingGeneration &&
            identity == _runtimeIdentity &&
            _stateStore.isCurrent(identity)) {
          _stateStore.clearPersistenceFailure(
            identity: identity,
            selection: result.normalizedSelection,
          );
        }
      } catch (_) {
        if (!_disposed &&
            generation == _bindingGeneration &&
            identity == _runtimeIdentity &&
            _stateStore.isCurrent(identity)) {
          _stateStore.recordPersistenceFailure(
            identity: identity,
            selection: result.normalizedSelection,
            message: '权限偏好已应用，但保存失败；可重试',
          );
        }
      }
    } catch (_) {
      if (_disposed ||
          generation != _bindingGeneration ||
          identity != _runtimeIdentity) {
        return;
      }
      _lastError = '权限模式切换失败';
      _notify();
    }
  }

  bool _commitApplyResult(
    AgentPermissionApplyResult result, {
    required String? threadId,
    required AgentPermissionStateSource source,
    required bool updateDefault,
  }) {
    return _stateStore.commitApplyResult(
      identity: _runtimeIdentity,
      threadId: threadId,
      result: result,
      source: source,
      updateDefault: updateDefault,
    );
  }

  void _handleStateStoreChanged() {
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
    _bindingGeneration += 1;
    _catalogController.dispose();
    _stateStore.removeListener(_handleStateStoreChanged);
    _stateStore.discardProvisionalRuntime(_runtimeIdentity);
    if (_ownsStateStore) {
      _stateStore.dispose();
    }
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
