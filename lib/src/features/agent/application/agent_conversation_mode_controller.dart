import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/domain/agent_conversation_mode_models.dart';
import 'package:zeta/src/features/agent/domain/agent_event_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent/domain/agent_ui_text_catalog.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

/// 对话模式目录的加载状态。
enum AgentConversationModeLoadStatus {
  /// 当前 Provider 不提供完整的模式选择能力。
  unavailable,

  /// 正在探测当前 Provider 的模式目录。
  loading,

  /// 已取得可选择的 Default 与 Plan 目录。
  ready,

  /// 目录探测暂时失败，可以重试。
  error,
}

/// Composer 消费的不可变对话模式状态。
@immutable
final class AgentConversationModeState {
  AgentConversationModeState({
    required this.status,
    required Iterable<AgentConversationModePreset> presets,
    this.confirmedMode,
    this.draftMode,
    this.pendingTurnMode,
    this.errorMessage,
    this.appliesToNextTurn = false,
  }) : presets = List<AgentConversationModePreset>.unmodifiable(presets);

  /// 当前目录是否可用。
  final AgentConversationModeLoadStatus status;

  /// 当前 Provider 返回的不可修改模式目录。
  final List<AgentConversationModePreset> presets;

  /// 服务端、历史或已接受请求确认的 thread 模式。
  final AgentConversationModeId? confirmedMode;

  /// 用户希望下一个新 turn 使用的模式。
  final AgentConversationModeId? draftMode;

  /// 已冻结并进入发送流程、尚未确认的模式快照。
  final AgentConversationModeSelection? pendingTurnMode;

  /// 目录加载失败时供 UI 展示的中立错误文案。
  final String? errorMessage;

  /// 当前存在 active turn，draft 只会应用于下一新 turn。
  final bool appliesToNextTurn;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationModeState &&
      other.status == status &&
      listEquals(other.presets, presets) &&
      other.confirmedMode == confirmedMode &&
      other.draftMode == draftMode &&
      other.pendingTurnMode == pendingTurnMode &&
      other.errorMessage == errorMessage &&
      other.appliesToNextTurn == appliesToNextTurn;

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAll(presets),
    confirmedMode,
    draftMode,
    pendingTurnMode,
    errorMessage,
    appliesToNextTurn,
  );
}

/// 集中管理模式目录、thread draft、发送快照与异步竞态。
///
/// Controller 仅依赖 Provider 中立的 domain 端口和事件。JSON-RPC、Codex mask
/// 解析与 Widget 展示均留在各自层中，ViewModel 只需要转交生命周期事件。
final class AgentConversationModeController extends ChangeNotifier {
  AgentConversationModeController({AgentUiTextCatalog? textCatalog})
    : _textCatalog = textCatalog ?? const FallbackAgentUiTextCatalog();

  final AgentUiTextCatalog _textCatalog;

  AgentConversationModeState _state = AgentConversationModeState(
    status: AgentConversationModeLoadStatus.unavailable,
    presets: const <AgentConversationModePreset>[],
  );

  String? _providerId;
  AgentConversationModeCatalogPort? _catalogPort;
  String? _threadId;
  _PendingTurnMode? _pendingTurn;

  int _providerGeneration = 0;
  int _threadGeneration = 0;
  int _selectionRevision = 0;
  int _draftAuthorityRevision = 0;
  bool _disposed = false;

  /// 当前不可变 UI 状态。
  AgentConversationModeState get state => _state;

  /// 为新的 Provider 作用域加载模式目录。
  ///
  /// 每次调用都会使旧 Provider 的异步结果失效。能力端口为空、运行时明确不支持，
  /// 或目录缺少可选择的 Default/Plan 时安全降级为 [AgentConversationModeLoadStatus.unavailable]。
  Future<void> loadCatalog({
    required String providerId,
    required AgentConversationModeCatalogPort? port,
  }) async {
    if (_disposed) {
      return;
    }

    final generation = ++_providerGeneration;
    _providerId = providerId;
    _catalogPort = port;
    _threadId = null;
    _threadGeneration += 1;
    _pendingTurn = null;
    _selectionRevision += 1;
    _draftAuthorityRevision = _selectionRevision;

    if (port == null) {
      _replaceState(
        AgentConversationModeState(
          status: AgentConversationModeLoadStatus.unavailable,
          presets: const <AgentConversationModePreset>[],
        ),
      );
      return;
    }

    _replaceState(
      AgentConversationModeState(
        status: AgentConversationModeLoadStatus.loading,
        presets: const <AgentConversationModePreset>[],
      ),
    );
    await _loadCatalogForGeneration(
      providerId: providerId,
      port: port,
      generation: generation,
    );
  }

  /// 重试当前 Provider 最近一次失败的目录加载，并保留已绑定 thread 的模式。
  Future<void> retryCatalog() async {
    if (_disposed) {
      return;
    }
    final providerId = _providerId;
    final port = _catalogPort;
    if (providerId == null || port == null) {
      return;
    }

    final generation = ++_providerGeneration;
    _replaceState(
      AgentConversationModeState(
        status: AgentConversationModeLoadStatus.loading,
        presets: _state.presets,
        confirmedMode: _state.confirmedMode,
        draftMode: _state.draftMode,
        pendingTurnMode: _state.pendingTurnMode,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
    await _loadCatalogForGeneration(
      providerId: providerId,
      port: port,
      generation: generation,
    );
  }

  /// 绑定新建或恢复的 thread，并使旧 thread 的发送回调立即失效。
  void bindThread({
    required String? threadId,
    AgentConversationModeId? historyMode,
  }) {
    if (_disposed) {
      return;
    }

    _threadGeneration += 1;
    _threadId = _nonEmpty(threadId);
    _pendingTurn = null;
    _selectionRevision += 1;
    _draftAuthorityRevision = _selectionRevision;
    final restoredMode = historyMode ?? AgentConversationModeId.defaultMode;
    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: restoredMode,
        draftMode: restoredMode,
        errorMessage: _state.errorMessage,
      ),
    );
  }

  /// 更新用户希望下一新 turn 使用的已知、可选择模式。
  void selectMode(AgentConversationModeId modeId) {
    if (_disposed ||
        _state.status != AgentConversationModeLoadStatus.ready ||
        modeId.kind == AgentConversationModeKind.unknown ||
        _state.draftMode == modeId ||
        !_isSelectableMode(modeId)) {
      return;
    }

    _selectionRevision += 1;
    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: _state.confirmedMode,
        draftMode: modeId,
        pendingTurnMode: _state.pendingTurnMode,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
  }

  /// 冻结一次新 turn 使用的模式、模型与推理深度。
  ///
  /// Provider 不支持模式、目录尚未就绪或恢复到未知只读模式时返回空配置，
  /// 让调用方继续走原有发送链；空有效模型会在发出 RPC 前以 [ArgumentError] 阻止。
  AgentTurnConfiguration snapshotForNewTurn({
    required String effectiveModelId,
    String? selectedReasoningEffort,
  }) {
    if (_disposed || _state.status != AgentConversationModeLoadStatus.ready) {
      return const AgentTurnConfiguration();
    }

    final modeId = _state.draftMode;
    if (modeId == null || modeId.kind == AgentConversationModeKind.unknown) {
      return const AgentTurnConfiguration();
    }
    final preset = _presetFor(modeId);
    if (preset == null || !preset.isSelectable) {
      return const AgentTurnConfiguration();
    }

    final modelId =
        _nonEmpty(preset.suggestedModelId) ?? _nonEmpty(effectiveModelId);
    if (modelId == null) {
      throw ArgumentError.value(
        effectiveModelId,
        'effectiveModelId',
        'Conversation mode requires a non-empty effective model',
      );
    }
    final selection = AgentConversationModeSelection(
      modeId: modeId,
      effectiveModelId: modelId,
      effectiveReasoningEffort:
          _nonEmpty(preset.suggestedReasoningEffort) ??
          _nonEmpty(selectedReasoningEffort),
    );
    _pendingTurn = _PendingTurnMode(
      threadId: _threadId,
      threadGeneration: _threadGeneration,
      selectionRevision: _selectionRevision,
      selection: selection,
    );
    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: _state.confirmedMode,
        draftMode: _state.draftMode,
        pendingTurnMode: selection,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
    return AgentTurnConfiguration(conversationMode: selection);
  }

  /// 确认一次 `turn/start` 已被当前 thread 接受。
  ///
  /// [selection] 必须是 [snapshotForNewTurn] 返回的同一个不可变实例；相同值的旧
  /// 请求也不能清理更新的 pending。
  void markTurnAccepted({
    required String threadId,
    required AgentConversationModeSelection? selection,
  }) {
    if (_disposed || selection == null) {
      return;
    }
    final pending = _matchingPending(threadId, selection);
    if (pending == null) {
      return;
    }

    final canSyncDraft = _selectionRevision == pending.selectionRevision;
    if (canSyncDraft) {
      _draftAuthorityRevision = _selectionRevision;
    }
    _pendingTurn = null;
    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: selection.modeId,
        draftMode: canSyncDraft ? selection.modeId : _state.draftMode,
        errorMessage: _state.errorMessage,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
  }

  /// 清理一次失败请求自己的 pending，同时保留用户 draft 和 confirmed。
  void markTurnFailed({
    required String threadId,
    required AgentConversationModeSelection? selection,
  }) {
    if (_disposed || selection == null) {
      return;
    }
    if (_matchingPending(threadId, selection) == null) {
      return;
    }

    _pendingTurn = null;
    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: _state.confirmedMode,
        draftMode: _state.draftMode,
        errorMessage: _state.errorMessage,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
  }

  /// 应用当前 thread 的服务端权威设置。
  ///
  /// 迟到通知可以修正 confirmed；只有用户没有在对应请求后继续选择时才同步 draft。
  void applyThreadSettings(AgentThreadSettingsUpdatedEvent event) {
    if (_disposed ||
        _threadId == null ||
        event.threadId != _threadId ||
        event.collaborationMode == null) {
      return;
    }

    final serverSelection = event.collaborationMode!;
    final pending = _pendingTurn;
    final matchesPending =
        pending != null &&
        pending.threadGeneration == _threadGeneration &&
        pending.threadId == _threadId &&
        pending.selection == serverSelection;
    final canSyncDraft =
        _selectionRevision == _draftAuthorityRevision ||
        (matchesPending && _selectionRevision == pending.selectionRevision);
    if (canSyncDraft) {
      _draftAuthorityRevision = _selectionRevision;
    }
    if (matchesPending) {
      _pendingTurn = null;
    }

    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: serverSelection.modeId,
        draftMode: canSyncDraft ? serverSelection.modeId : _state.draftMode,
        pendingTurnMode: matchesPending ? null : _state.pendingTurnMode,
        errorMessage: _state.errorMessage,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
  }

  /// 应用服务端权威的会话模式（如 Grok `current_mode_update`）。
  ///
  /// 与 [applyThreadSettings] 相同，迟到通知可以修正 confirmed，但只有用户没有
  /// 继续选择时才同步 draft；未知模式宽容忽略。会话模式不携带模型，因此只更新
  /// 模式标识。
  ///
  /// [clearPendingTurn] 用于 provider 计划审批消费 plan 模式后的复位：此时
  /// pending 仍可能是 plan（Grok 的 `markTurnAccepted` 在阻塞 `session/prompt`
  /// 返回后才执行），必须强制丢弃 pending 并同步 draft，避免迟到的
  /// [markTurnAccepted] 把 confirmed 写回 plan、再次触发本地执行交接。
  void applyServerMode(
    AgentConversationModeId modeId, {
    bool clearPendingTurn = false,
  }) {
    if (_disposed || _threadId == null) {
      return;
    }
    if (modeId.kind == AgentConversationModeKind.unknown) {
      return;
    }
    final pending = _pendingTurn;
    final matchesPending =
        pending != null &&
        pending.threadGeneration == _threadGeneration &&
        pending.threadId == _threadId &&
        pending.selection.modeId == modeId;
    final shouldClearPending = matchesPending || clearPendingTurn;
    final canSyncDraft =
        clearPendingTurn ||
        _selectionRevision == _draftAuthorityRevision ||
        (matchesPending && _selectionRevision == pending.selectionRevision);
    if (canSyncDraft) {
      _draftAuthorityRevision = _selectionRevision;
    }
    if (shouldClearPending) {
      _pendingTurn = null;
    }

    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: modeId,
        draftMode: canSyncDraft ? modeId : _state.draftMode,
        pendingTurnMode: shouldClearPending ? null : _state.pendingTurnMode,
        errorMessage: _state.errorMessage,
        appliesToNextTurn: _state.appliesToNextTurn,
      ),
    );
  }

  /// 标记当前是否存在 active turn。
  void setTurnRunning(bool running) {
    if (_disposed || _state.appliesToNextTurn == running) {
      return;
    }
    _replaceState(
      AgentConversationModeState(
        status: _state.status,
        presets: _state.presets,
        confirmedMode: _state.confirmedMode,
        draftMode: _state.draftMode,
        pendingTurnMode: _state.pendingTurnMode,
        errorMessage: _state.errorMessage,
        appliesToNextTurn: running,
      ),
    );
  }

  Future<void> _loadCatalogForGeneration({
    required String providerId,
    required AgentConversationModeCatalogPort port,
    required int generation,
  }) async {
    try {
      final catalog = await port.listConversationModes();
      if (!_acceptsProviderResult(providerId, port, generation)) {
        return;
      }
      if (!_hasRequiredModes(catalog)) {
        _replaceState(
          AgentConversationModeState(
            status: AgentConversationModeLoadStatus.unavailable,
            presets: const <AgentConversationModePreset>[],
            confirmedMode: _state.confirmedMode,
            draftMode: _state.draftMode,
            appliesToNextTurn: _state.appliesToNextTurn,
          ),
        );
        return;
      }

      final defaultMode = catalog.presets
          .where(
            (preset) =>
                preset.id.kind == AgentConversationModeKind.defaultMode &&
                preset.isSelectable,
          )
          .first;
      final draftMode = _state.draftMode ?? defaultMode.id;
      if (_state.draftMode == null) {
        _draftAuthorityRevision = _selectionRevision;
      }
      _replaceState(
        AgentConversationModeState(
          status: AgentConversationModeLoadStatus.ready,
          presets: catalog.presets,
          confirmedMode: _state.confirmedMode,
          draftMode: draftMode,
          pendingTurnMode: _state.pendingTurnMode,
          appliesToNextTurn: _state.appliesToNextTurn,
        ),
      );
    } on UnsupportedError {
      if (!_acceptsProviderResult(providerId, port, generation)) {
        return;
      }
      _replaceState(
        AgentConversationModeState(
          status: AgentConversationModeLoadStatus.unavailable,
          presets: const <AgentConversationModePreset>[],
          confirmedMode: _state.confirmedMode,
          draftMode: _state.draftMode,
          appliesToNextTurn: _state.appliesToNextTurn,
        ),
      );
    } catch (_) {
      if (!_acceptsProviderResult(providerId, port, generation)) {
        return;
      }
      _replaceState(
        AgentConversationModeState(
          status: AgentConversationModeLoadStatus.error,
          presets: const <AgentConversationModePreset>[],
          confirmedMode: _state.confirmedMode,
          draftMode: _state.draftMode,
          errorMessage: _textCatalog.modeLoadFailed,
          appliesToNextTurn: _state.appliesToNextTurn,
        ),
      );
    }
  }

  bool _acceptsProviderResult(
    String providerId,
    AgentConversationModeCatalogPort port,
    int generation,
  ) =>
      !_disposed &&
      generation == _providerGeneration &&
      providerId == _providerId &&
      identical(port, _catalogPort);

  bool _hasRequiredModes(AgentConversationModeCatalog catalog) {
    var hasDefault = false;
    var hasPlan = false;
    for (final preset in catalog.presets) {
      if (!preset.isSelectable) {
        continue;
      }
      switch (preset.id.kind) {
        case AgentConversationModeKind.defaultMode:
          hasDefault = true;
        case AgentConversationModeKind.plan:
          hasPlan = true;
        case AgentConversationModeKind.unknown:
          break;
      }
    }
    return hasDefault && hasPlan;
  }

  bool _isSelectableMode(AgentConversationModeId modeId) {
    final preset = _presetFor(modeId);
    return preset != null && preset.isSelectable;
  }

  AgentConversationModePreset? _presetFor(AgentConversationModeId modeId) {
    for (final preset in _state.presets) {
      if (preset.id == modeId) {
        return preset;
      }
    }
    return null;
  }

  _PendingTurnMode? _matchingPending(
    String threadId,
    AgentConversationModeSelection selection,
  ) {
    final pending = _pendingTurn;
    if (pending == null ||
        pending.threadGeneration != _threadGeneration ||
        pending.threadId != threadId ||
        threadId != _threadId ||
        !identical(pending.selection, selection)) {
      return null;
    }
    return pending;
  }

  void _replaceState(AgentConversationModeState next) {
    if (_disposed) {
      return;
    }
    final changed = next != _state;
    _state = next;
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _providerGeneration += 1;
    _threadGeneration += 1;
    _pendingTurn = null;
    super.dispose();
  }
}

final class _PendingTurnMode {
  const _PendingTurnMode({
    required this.threadId,
    required this.threadGeneration,
    required this.selectionRevision,
    required this.selection,
  });

  final String? threadId;
  final int threadGeneration;
  final int selectionRevision;
  final AgentConversationModeSelection selection;
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
