import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 权限选项选择的应用层控制器。
///
/// 只依赖中立 [AgentPermissionPolicyPort] 与 [AgentPermissionOption]；
/// 不持有 [AgentProvider]，不解析 option id 的协议语义。
class AgentConversationPermissionSelectionController {
  /// 创建控制器。
  ///
  /// [persistOptionId] 仅持久化通用 optionId（provider 默认偏好）。
  AgentConversationPermissionSelectionController({
    required Future<void> Function(String optionId) persistOptionId,
  }) : _persistOptionId = persistOptionId;

  /// 持久化 provider 默认 optionId。
  final Future<void> Function(String optionId) _persistOptionId;

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
      _catalog = catalog;
      // 无有效选择时回落 catalog 默认。
      if (_effectiveSelection == null && catalog.defaultOptionId.isNotEmpty) {
        _effectiveSelection = AgentPermissionSelection(
          optionId: catalog.defaultOptionId,
        );
        if (_defaultPreference == null) {
          _defaultPreference = _effectiveSelection;
        }
      }
    } catch (_) {
      if (_disposed ||
          generation != _bindingGeneration ||
          !identical(port, _port)) {
        return;
      }
      // 临时失败保留旧目录，不用空列表覆盖。
      if (_catalog == null) {
        _catalog = null;
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
      final normalized = result.normalizedSelection;
      _lastApplyScope = result.scope;
      _lastApplyWarning = result.warning;

      if (result.scope == AgentPermissionApplyScope.runtime) {
        // Grok runtime-global：同步全部 thread 有效值与默认偏好。
        _defaultPreference = normalized;
        _effectiveSelection = normalized;
        for (final key in _effectiveByThread.keys.toList(growable: false)) {
          _effectiveByThread[key] = normalized;
        }
        if (_boundThreadId != null) {
          _effectiveByThread[_boundThreadId!] = normalized;
        }
      } else {
        _effectiveSelection = normalized;
        if (_boundThreadId != null) {
          _effectiveByThread[_boundThreadId!] = normalized;
        }
        // 产品语义：用户主动选择同时更新后续默认。
        _defaultPreference = normalized;
      }

      try {
        await _persistOptionId(normalized.optionId);
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
      _effectiveSelection = previousEffective;
      _defaultPreference = previousDefault;
      if (_boundThreadId != null) {
        if (previousEffective != null) {
          _effectiveByThread[_boundThreadId!] = previousEffective;
        } else {
          _effectiveByThread.remove(_boundThreadId);
        }
      }
      _lastError = '权限模式切换失败';
      _lastApplyScope = null;
      _lastApplyWarning = null;
    }
  }

  /// 服务端 / 外部将当前 thread 有效选择设为 [selection]（不持久化全局默认）。
  ///
  /// 可选经 port 同步 runtime 内存，失败时回滚 effective。
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
    if (_effectiveSelection?.optionId == next.optionId) {
      return;
    }
    final previous = _effectiveSelection;
    _effectiveSelection = next;
    if (_boundThreadId != null) {
      _effectiveByThread[_boundThreadId!] = next;
    }
    if (!syncPort) {
      return;
    }
    final port = _port;
    final generation = _bindingGeneration;
    if (port == null) {
      return;
    }
    try {
      await port.applyPermissionSelection(next);
      if (_disposed ||
          generation != _bindingGeneration ||
          !identical(port, _port)) {
        return;
      }
    } catch (_) {
      if (_disposed || generation != _bindingGeneration) {
        return;
      }
      _effectiveSelection = previous;
      if (_boundThreadId != null) {
        if (previous != null) {
          _effectiveByThread[_boundThreadId!] = previous;
        } else {
          _effectiveByThread.remove(_boundThreadId);
        }
      }
    }
  }

  /// `thread/settings/updated`：只更新当前 thread 有效 option，不改全局默认。
  Future<void> applyThreadSettings({String? optionId}) async {
    final id = optionId?.trim();
    if (id == null || id.isEmpty) {
      return;
    }
    await applyEffectiveSelection(
      AgentPermissionSelection(optionId: id),
      syncPort: true,
    );
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

  void _restoreEffectiveForBoundThread() {
    final threadId = _boundThreadId;
    if (threadId != null && _effectiveByThread.containsKey(threadId)) {
      _effectiveSelection = _effectiveByThread[threadId];
      return;
    }
    _effectiveSelection = _defaultPreference;
  }
}
