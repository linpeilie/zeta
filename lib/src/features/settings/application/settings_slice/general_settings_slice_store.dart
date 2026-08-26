import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_reducer.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 执行 general 切片副作用的端口。
///
/// 实现住在组合层，持有 `GeneralSettingsStore`，并保证 [GeneralSettingsPersistEffect]
/// 以单写者串行执行。
abstract interface class GeneralSettingsSliceEffectRunner {
  void run(GeneralSettingsSliceEffect effect);
}

/// runner 工厂：拿到 store 本身，因此 runner 能直接回流结果。
///
/// 理由同 appearance 切片：把「store ↔ runner」的构造环变成一个普通构造参数，
/// 而不是先造空壳再回填 delegate。
typedef GeneralSettingsSliceEffectRunnerFactory =
    GeneralSettingsSliceEffectRunner Function(GeneralSettingsSliceStore store);

/// 切片诊断计数。
@immutable
final class GeneralSettingsSliceDiagnostics {
  const GeneralSettingsSliceDiagnostics({
    required this.dispatchCount,
    required this.publishCount,
    required this.effectCount,
    required this.staleResultCount,
  });

  final int dispatchCount;
  final int publishCount;
  final int effectCount;
  final int staleResultCount;
}

/// 常规设置切片的薄 store（persist-first）。
///
/// 与 appearance store 同一套骨架：铸造 id、调 reducer、状态变化才发布、
/// effect 交 runner、关闭后拒绝写入；不拥有持久化事实。
final class GeneralSettingsSliceStore {
  GeneralSettingsSliceStore({
    required GeneralSettingsSliceState initialState,
    required GeneralSettingsSliceEffectRunnerFactory effectRunnerFactory,
    bool initiallyLoaded = true,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _loaded = initiallyLoaded,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope)) {
    effectRunner = effectRunnerFactory(this);
  }

  late final GeneralSettingsSliceEffectRunner effectRunner;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};

  /// 监听器列表（同 appearance store：不用 `ChangeNotifier`，§12.5）。
  final List<void Function()> _listeners = <void Function()>[];
  final ListQueue<GeneralSettingsSliceIntent> _commandQueue =
      ListQueue<GeneralSettingsSliceIntent>();

  /// 首次载入结算的一次性信号。
  ///
  /// 由 store 而不是 runner 持有：组合根要等的是「切片已经有可用的设置快照」这个
  /// 切片事实，不是某个 runner 实现的内部进度。runner 换实现不该动到等待方。
  final Completer<GeneralSettings> _initialLoadCompleter =
      Completer<GeneralSettings>();

  GeneralSettingsSliceState _state;
  bool _loaded;
  bool _closed = false;
  bool _loadRequested = false;
  bool _drainingCommands = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

  GeneralSettingsSliceState get state => _state;

  bool get isClosed => _closed;

  /// 首次载入结算后的设置快照。
  ///
  /// 载入失败时以构造期 fallback 结算，**不会**永远悬空——否则依赖它的
  /// 「等语言加载完再挂有文字的 UI」会把整个窗口卡在空白帧上。
  Future<GeneralSettings> get initialLoad => _initialLoadCompleter.future;

  GeneralSettingsSliceDiagnostics get diagnostics =>
      GeneralSettingsSliceDiagnostics(
        dispatchCount: _dispatchCount,
        publishCount: _publishCount,
        effectCount: _effectCount,
        staleResultCount: _staleResultCount,
      );

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _commandQueue.clear();
    _listeners.clear();
    _settleInitialLoad();
  }

  void dispatch(GeneralSettingsSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchCount += 1;
    final before = _state;
    final transition = generalSettingsSliceReduce(before, intent);

    if (transition.state != before) {
      _state = transition.state;
      _publishCount += 1;
      _notifyListeners();
    } else if (_isStaleResult(before, intent)) {
      _staleResultCount += 1;
    }

    for (final effect in transition.effects) {
      _effectCount += 1;
      effectRunner.run(effect);
    }
  }

  // -------------------------------------------------------------------------
  // 命令入口
  // -------------------------------------------------------------------------

  /// 载入持久化设置；重复调用不重复发起。
  void load() {
    if (_loaded || _loadRequested) {
      return;
    }
    _loadRequested = true;
    dispatch(const GeneralSettingsLoadRequested());
  }

  OperationId setMessageSendShortcut(MessageSendShortcut shortcut) {
    final id = _nextOperationId();
    _submitCommand(MessageSendShortcutSelected(id, shortcut));
    return id;
  }

  OperationId setAppLanguage(AppLanguage language) {
    final id = _nextOperationId();
    _submitCommand(AppLanguageSelected(id, language));
    return id;
  }

  OperationId setNotificationsEnabled(bool enabled) {
    final id = _nextOperationId();
    _submitCommand(NotificationsEnabledToggled(id, enabled));
    return id;
  }

  OperationId setTurnTerminalNotificationsEnabled(bool enabled) {
    final id = _nextOperationId();
    _submitCommand(TurnTerminalNotificationsToggled(id, enabled));
    return id;
  }

  OperationId setActionRequiredNotificationsEnabled(bool enabled) {
    final id = _nextOperationId();
    _submitCommand(ActionRequiredNotificationsToggled(id, enabled));
    return id;
  }

  // -------------------------------------------------------------------------
  // 结果入口：effect runner / ingress 回流
  // -------------------------------------------------------------------------

  void loaded(GeneralSettings settings) {
    _loaded = true;
    dispatch(GeneralSettingsLoaded(settings));
    _settleInitialLoad();
    _drainCommands();
  }

  /// runner 载入失败时使用构造期 fallback 继续结算排队命令。
  void loadFailed() {
    _loaded = true;
    _settleInitialLoad();
    _drainCommands();
  }

  /// 以当前快照结算 [initialLoad]；重复调用无效果。
  void _settleInitialLoad() {
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete(_state.settings);
    }
  }

  void persisted(OperationId operationId, GeneralSettings settings) {
    final accepted = _state.pendingOperationId == operationId;
    dispatch(GeneralSettingsPersisted(operationId, settings));
    if (accepted) {
      _drainCommands();
    }
  }

  void persistFailed(OperationId operationId, SettingsPersistFailureKind kind) {
    final accepted = _state.pendingOperationId == operationId;
    dispatch(GeneralSettingsPersistFailed(operationId, kind));
    if (accepted) {
      _drainCommands();
    }
  }

  void acknowledgeFailure() {
    dispatch(const GeneralSettingsFailureAcknowledged());
  }

  OperationId _nextOperationId() {
    final generator = _generators.putIfAbsent(
      SettingsOperationScopes.generalPersist,
      () => _generatorFactory(SettingsOperationScopes.generalPersist),
    );
    return generator.next();
  }

  /// 命令只在首次 load 结算且前一次 persist 结算后才进 reducer。
  ///
  /// 这保留了 persist-first 的真正串行语义：后续命令从前一次的
  /// 成功或失败结果重新计算，不会把失败修改夹带进后续快照。
  void _submitCommand(GeneralSettingsSliceIntent intent) {
    if (_closed) {
      return;
    }
    _commandQueue.add(intent);
    if (!_loaded) {
      load();
      return;
    }
    _drainCommands();
  }

  void _drainCommands() {
    if (_closed ||
        !_loaded ||
        _drainingCommands ||
        _state.pendingOperationId != null) {
      return;
    }
    _drainingCommands = true;
    try {
      while (_commandQueue.isNotEmpty && _state.pendingOperationId == null) {
        dispatch(_commandQueue.removeFirst());
      }
    } finally {
      _drainingCommands = false;
    }
  }

  /// persist 结果对不上在途身份 → 迟到（已被更新的提交取代）。
  bool _isStaleResult(
    GeneralSettingsSliceState before,
    GeneralSettingsSliceIntent intent,
  ) {
    return switch (intent) {
      GeneralSettingsPersisted() =>
        before.pendingOperationId != intent.operationId,
      GeneralSettingsPersistFailed() =>
        before.pendingOperationId != intent.operationId,
      _ => false,
    };
  }

  void _notifyListeners() {
    final snapshot = List<void Function()>.of(_listeners);
    for (final listener in snapshot) {
      listener();
    }
  }
}
