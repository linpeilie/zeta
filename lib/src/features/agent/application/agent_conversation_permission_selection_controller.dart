import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/application/agent_permission_request_resolver.dart';

/// 权限选项选择的应用层控制器。
///
/// 只依赖中立 [AgentPermissionPolicyPort] 与 [AgentPermissionOption]；
/// 不持有 [AgentProvider]，不解析 option id 的协议语义。
class AgentConversationPermissionSelectionController {
  /// 创建控制器。
  ///
  /// [persistOptionId] 仅持久化通用 optionId（provider 默认偏好）。
  AgentConversationPermissionSelectionController({
    required this.persistOptionId,
  });

  /// 持久化 provider 默认 optionId。
  final Future<void> Function(String optionId) persistOptionId;

  AgentPermissionPolicyPort? _port;
  AgentPermissionCatalog? _catalog;

  /// Provider 级默认偏好（创建新 session / 持久化真源）。
  AgentPermissionSelection? _defaultPreference;

  /// 当前 thread/session 有效选择（UI 展示与本会话 apply 真源）。
  AgentPermissionSelection? _effectiveSelection;

  /// 各 thread 的有效选择缓存（Codex thread-scoped）。
  final Map<String, AgentPermissionSelection> _effectiveByThread =
      <String, AgentPermissionSelection>{};

  String? _boundThreadId;
  int _bindingGeneration = 0;
  bool _disposed = false;

  AgentPermissionApplyScope? _lastApplyScope;
  String? _lastApplyWarning;
  String? _lastError;

  /// 当前绑定的权限 port（测试/诊断）。
  AgentPermissionPolicyPort? get port => _port;

  /// 是否已绑定可用 port。
  bool get hasPort => _port != null;

  /// 当前目录快照（不可修改）。
  List<AgentPermissionOption> get options =>
      _catalog?.options ?? const <AgentPermissionOption>[];

  /// 当前有效 option id。
  String? get selectedOptionId => _effectiveSelection?.optionId;

  /// Provider 默认 option id。
  String? get defaultOptionId => _defaultPreference?.optionId;

  /// 当前有效选择。
  AgentPermissionSelection? get effectiveSelection => _effectiveSelection;

  /// Provider 默认偏好。
  AgentPermissionSelection? get defaultPreference => _defaultPreference;

  /// 当前目录声明的默认选择；目录尚未加载时为空。
  AgentPermissionSelection? get catalogDefault {
    final optionId = _catalog?.defaultOptionId.trim();
    if (optionId == null || optionId.isEmpty) {
      return null;
    }
    return AgentPermissionSelection(optionId: optionId);
  }

  /// 为一次请求冻结权限来源，避免后续 UI/settings 更新改变已开始的异步调用。
  AgentPermissionRequestSnapshot snapshotForRequest({String? threadId}) {
    final normalized = threadId?.trim();
    final effectiveThreadId = normalized == null || normalized.isEmpty
        ? _boundThreadId
        : normalized;
    final threadEffective = effectiveThreadId == null
        ? null
        : _effectiveByThread[effectiveThreadId];
    return AgentPermissionRequestResolver.resolve(
      threadEffective: threadEffective,
      providerDefault: _defaultPreference,
      catalogDefault: catalogDefault,
    );
  }

  /// 最近一次 apply 的生效范围（用于 Composer 紧凑提示）。
  AgentPermissionApplyScope? get lastApplyScope => _lastApplyScope;

  /// 最近一次 apply 的 warning。
  String? get lastApplyWarning => _lastApplyWarning;

  /// 最近一次失败信息。
  String? get lastError => _lastError;

  /// Composer 触发器主文案：优先 catalog label，否则 option id。
  String get displayLabel {
    final optionId = selectedOptionId;
    if (optionId == null || optionId.isEmpty) {
      return 'Permission';
    }
    final option = _catalog?.optionById(optionId);
    if (option != null) {
      return option.label;
    }
    return optionId;
  }

  /// 紧凑 scope 提示；无提示时返回 null。
  String? get applyScopeHint {
    final warning = _lastApplyWarning?.trim();
    if (warning != null && warning.isNotEmpty) {
      return warning;
    }
    return switch (_lastApplyScope) {
      AgentPermissionApplyScope.nextSession => '下次会话生效',
      AgentPermissionApplyScope.currentTurn => '本回合生效',
      AgentPermissionApplyScope.currentSession => null,
      AgentPermissionApplyScope.runtime => null,
      null => null,
    };
  }

  /// 绑定（或重绑）权限 port 与 provider 默认偏好。
  ///
  /// 递增 [bindingGeneration]；清空 catalog；effective 回落为默认偏好。
  void bind({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
  }) {
    if (_disposed) {
      return;
    }
    _bindingGeneration += 1;
    _port = port;
    _catalog = null;
    _lastApplyScope = null;
    _lastApplyWarning = null;
    _lastError = null;
    final trimmed = persistedOptionId?.trim();
    _defaultPreference = (trimmed == null || trimmed.isEmpty)
        ? null
        : AgentPermissionSelection(optionId: trimmed);
    _restoreEffectiveForBoundThread();
  }

  /// 切换 provider：清空 thread 缓存并重新 bind。
  void resetForProvider({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
  }) {
    if (_disposed) {
      return;
    }
    _boundThreadId = null;
    _effectiveByThread.clear();
    bind(port: port, persistedOptionId: persistedOptionId);
  }

  /// 仅从配置恢复默认偏好（port 尚未就绪时）。
  void seedFromConfig(String? persistedOptionId) {
    if (_disposed) {
      return;
    }
    final trimmed = persistedOptionId?.trim();
    _defaultPreference = (trimmed == null || trimmed.isEmpty)
        ? null
        : AgentPermissionSelection(optionId: trimmed);
    _restoreEffectiveForBoundThread();
  }

  /// 绑定当前 thread；切换时恢复该 thread 的 effective 或回落默认。
  void bindThread(String? threadId) {
    if (_disposed) {
      return;
    }
    final normalized = threadId?.trim();
    final nextId = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
    if (nextId == _boundThreadId) {
      return;
    }
    _boundThreadId = nextId;
    _restoreEffectiveForBoundThread();
  }

  /// 拉取选项目录；旧 generation / 已 dispose 的结果不得回写。
  ///
  /// 临时失败保留旧目录；不用空目录覆盖已有成功目录。
  Future<void> refreshOptions() async {
    if (_disposed) {
      return;
    }
    final port = _port;
    final generation = _bindingGeneration;
    if (port == null) {
      _catalog = null;
      return;
    }
    try {
      final catalog = await port.listPermissionOptions();
      if (_disposed ||
          generation != _bindingGeneration ||
          !identical(port, _port)) {
        return;
      }
      // 不用空目录覆盖已有成功目录。
      if (catalog.options.isEmpty && (_catalog?.options.isNotEmpty ?? false)) {
        return;
      }
      _catalog = catalog;
      // 无有效选择时回落 catalog 默认。
      if (_effectiveSelection == null && catalog.defaultOptionId.isNotEmpty) {
        _effectiveSelection = AgentPermissionSelection(
          optionId: catalog.defaultOptionId,
        );
      }
    } catch (_) {
      // 临时失败 / adapter 上抛：保留旧目录，不用空列表覆盖。
      if (_disposed ||
          generation != _bindingGeneration ||
          !identical(port, _port)) {
        return;
      }
    }
  }

  /// 用户选择一项：经 port apply，成功则更新 effective/default 并持久化默认。
  Future<void> selectOption(AgentPermissionOption option) async {
    if (_disposed || !option.allowed) {
      return;
    }
    final port = _port;
    if (port == null) {
      _lastError = '当前 Provider 不支持权限选择';
      return;
    }
    final generation = _bindingGeneration;
    final previousEffective = _effectiveSelection;
    final previousDefault = _defaultPreference;
    final previousByThread = Map<String, AgentPermissionSelection>.from(
      _effectiveByThread,
    );
    final requested = AgentPermissionSelection(optionId: option.id);
    _lastError = null;
    _lastApplyWarning = null;

    try {
      final result = await port.applyPermissionSelection(requested);
      if (_disposed ||
          generation != _bindingGeneration ||
          !identical(port, _port)) {
        return;
      }
      _commitApplyResult(result, updateDefault: true);

      try {
        await persistOptionId(result.normalizedSelection.optionId);
      } catch (error) {
        // 持久化失败：不伪造 provider 未应用，但报告错误。
        if (!_disposed && generation == _bindingGeneration) {
          _lastError = '权限偏好已应用，但保存失败';
        }
      }
    } catch (_) {
      if (_disposed || generation != _bindingGeneration) {
        return;
      }
      _restoreApplySnapshot(
        effective: previousEffective,
        defaultPreference: previousDefault,
        byThread: previousByThread,
      );
      _lastError = '权限模式切换失败';
      _lastApplyScope = null;
      _lastApplyWarning = null;
    }
  }

  /// 服务端 / 外部将当前 thread 有效选择设为 [selection]（不持久化全局默认）。
  ///
  /// 可选经 port 同步 runtime 内存；成功时提交完整 [AgentPermissionApplyResult]。
  Future<void> applyEffectiveSelection(
    AgentPermissionSelection selection, {
    bool syncPort = true,
  }) async {
    if (_disposed) {
      return;
    }
    final trimmed = selection.optionId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final next = AgentPermissionSelection(optionId: trimmed);

    if (!syncPort) {
      if (_effectiveSelection?.optionId == next.optionId) {
        return;
      }
      _effectiveSelection = next;
      if (_boundThreadId != null) {
        _effectiveByThread[_boundThreadId!] = next;
      }
      return;
    }

    final port = _port;
    final generation = _bindingGeneration;
    if (port == null) {
      if (_effectiveSelection?.optionId == next.optionId) {
        return;
      }
      _effectiveSelection = next;
      if (_boundThreadId != null) {
        _effectiveByThread[_boundThreadId!] = next;
      }
      return;
    }

    final previousEffective = _effectiveSelection;
    final previousDefault = _defaultPreference;
    final previousByThread = Map<String, AgentPermissionSelection>.from(
      _effectiveByThread,
    );

    try {
      final result = await port.applyPermissionSelection(next);
      if (_disposed ||
          generation != _bindingGeneration ||
          !identical(port, _port)) {
        return;
      }
      // 外部/settings 同步：消费完整 result，但不把用户默认偏好改写为本次回写。
      _commitApplyResult(result, updateDefault: false);
    } catch (_) {
      if (_disposed || generation != _bindingGeneration) {
        return;
      }
      _restoreApplySnapshot(
        effective: previousEffective,
        defaultPreference: previousDefault,
        byThread: previousByThread,
      );
      _lastApplyScope = null;
      _lastApplyWarning = null;
    }
  }

  /// `thread/settings/updated` 服务端事实回写。
  ///
  /// - 只更新 [threadId] 的 effective，不改全局默认、不持久化
  /// - 默认 [syncPort]=false，避免二次 RPC apply
  /// - 事件 thread 与当前绑定不一致时，仅写入 thread 缓存，不污染当前 UI
  Future<void> applyThreadSettings({
    required String threadId,
    AgentPermissionSelection? permissionSelection,
    bool syncPort = false,
  }) async {
    if (_disposed) {
      return;
    }
    final id = permissionSelection?.optionId.trim();
    if (id == null || id.isEmpty) {
      return;
    }
    final normalizedThread = threadId.trim();
    if (normalizedThread.isEmpty) {
      return;
    }
    final next = AgentPermissionSelection(optionId: id);
    _effectiveByThread[normalizedThread] = next;
    if (_boundThreadId != normalizedThread) {
      // 非当前 thread：只缓存，待 bindThread 时恢复。
      return;
    }
    await applyEffectiveSelection(next, syncPort: syncPort);
  }

  /// 读取并清除最近错误（供 UI 一次性 toast）。
  String? takeLastError() {
    final error = _lastError;
    _lastError = null;
    return error;
  }

  /// 读取并清除最近 warning/hint（供 UI 一次性提示）。
  String? takeApplyHint() {
    final hint = applyScopeHint;
    _lastApplyWarning = null;
    // 保留 scope 供状态展示，仅清除一次性 warning 文本后仍可从 scope 推导。
    return hint;
  }

  void dispose() {
    _disposed = true;
    _port = null;
    _catalog = null;
    _effectiveByThread.clear();
  }

  /// 统一提交 port apply 结果：normalized / scope / warning。
  ///
  /// - [updateDefault]：用户主动选择时为 true（同步默认偏好并持久化路径外的内存默认）
  /// - runtime：同步全部 thread + 默认
  /// - currentSession / currentTurn：仅当前 thread effective
  /// - nextSession：更新默认并展示提示；用户选择时同步 UI 选中态
  void _commitApplyResult(
    AgentPermissionApplyResult result, {
    required bool updateDefault,
  }) {
    final normalized = result.normalizedSelection;
    _lastApplyScope = result.scope;
    _lastApplyWarning = result.warning;

    switch (result.scope) {
      case AgentPermissionApplyScope.runtime:
        // Grok runtime-global：同步全部 thread 与默认偏好。
        _defaultPreference = normalized;
        _effectiveSelection = normalized;
        for (final key in _effectiveByThread.keys.toList(growable: false)) {
          _effectiveByThread[key] = normalized;
        }
        if (_boundThreadId != null) {
          _effectiveByThread[_boundThreadId!] = normalized;
        }
      case AgentPermissionApplyScope.nextSession:
        // 下次会话生效：更新默认；用户选择时仍展示为当前选中项。
        _defaultPreference = normalized;
        if (updateDefault) {
          _effectiveSelection = normalized;
          if (_boundThreadId != null) {
            _effectiveByThread[_boundThreadId!] = normalized;
          }
        }
      case AgentPermissionApplyScope.currentSession:
      case AgentPermissionApplyScope.currentTurn:
        _effectiveSelection = normalized;
        if (_boundThreadId != null) {
          _effectiveByThread[_boundThreadId!] = normalized;
        }
        if (updateDefault) {
          _defaultPreference = normalized;
        }
    }
  }

  void _restoreApplySnapshot({
    required AgentPermissionSelection? effective,
    required AgentPermissionSelection? defaultPreference,
    required Map<String, AgentPermissionSelection> byThread,
  }) {
    _effectiveSelection = effective;
    _defaultPreference = defaultPreference;
    _effectiveByThread
      ..clear()
      ..addAll(byThread);
  }

  void _restoreEffectiveForBoundThread() {
    final threadId = _boundThreadId;
    if (threadId != null && _effectiveByThread.containsKey(threadId)) {
      _effectiveSelection = _effectiveByThread[threadId];
      return;
    }
    _effectiveSelection = _defaultPreference ?? catalogDefault;
  }
}
