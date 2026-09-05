import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_reducer.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 首次载入结算之前使用的语言兜底值。
///
/// 声明在切片自己这一层，由组合根按宿主环境覆盖（生产是 OS 语言）。默认值必须
/// 安全：它决定了「设置还没读出来」那几帧用哪种语言渲染。
final settingsFallbackLanguageProvider = Provider<AppLanguage>(
  (ref) => AppLanguage.simplifiedChinese,
  name: 'settingsFallbackLanguage',
);

/// 执行 general 切片副作用的端口。
///
/// 实现住在组合层，持有 `GeneralSettingsStore`，并保证 [GeneralSettingsPersistEffect]
/// 以单写者串行执行。
abstract interface class GeneralSettingsSliceEffectRunner {
  void run(GeneralSettingsSliceEffect effect);
}

/// runner 工厂：拿到 notifier 本身，因此 runner 能直接回流结果。
///
/// 把「owner ↔ runner」的构造环变成一个普通构造参数，而不是先造空壳再回填
/// delegate，也不是反向 `ref.read` notifier（那会被判成 `CircularDependencyError`，
/// 工程规范 §3.0）。
typedef GeneralSettingsSliceEffectRunnerFactory =
    GeneralSettingsSliceEffectRunner Function(
      GeneralSettingsSliceNotifier notifier,
    );

/// 组合根必须覆盖的 effect runner 工厂。
///
/// fail-closed：没被覆盖就抛错，而不是静默退化成一个不落盘的 runner——那会让
/// 「设置没保存」变成一个没人发现的哑 failure。
final generalSettingsSliceEffectRunnerFactoryProvider =
    Provider<GeneralSettingsSliceEffectRunnerFactory>(
      (ref) => throw StateError(
        'generalSettingsSliceEffectRunnerFactoryProvider was read before the '
        'composition root overrode it',
      ),
      name: 'generalSettingsSliceEffectRunnerFactory',
    );

/// 常规设置切片的唯一状态 owner。
///
/// **不是 autoDispose。** 设置的载入与落盘跟 app session 走，不能由「当前有没有
/// Widget 在看设置页」决定（工程规范 §3.0）。
///
/// **不声明 `dependencies`。** 它只服务于「把某个 provider 局部 scope 掉」，而本
/// 切片全局唯一、从不被 `ProviderScope` 覆盖；声明了反而会传染——每一个读它的
/// provider（比如 Desktop Attention 的通知设置来源）都得跟着列一遍。
final generalSettingsSliceProvider =
    NotifierProvider<GeneralSettingsSliceNotifier, GeneralSettingsSliceState>(
      GeneralSettingsSliceNotifier.new,
      name: 'generalSettingsSlice',
    );

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

/// 常规设置切片（persist-first）。
///
/// 与 appearance 切片同一套骨架：铸造 id、调 reducer、状态变化才发布、effect 交
/// runner、关闭后拒绝写入；不拥有持久化事实。
final class GeneralSettingsSliceNotifier
    extends Notifier<GeneralSettingsSliceState> {
  GeneralSettingsSliceNotifier({
    bool initiallyLoaded = false,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _loaded = initiallyLoaded,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final ListQueue<GeneralSettingsSliceIntent> _commandQueue =
      ListQueue<GeneralSettingsSliceIntent>();

  /// 首次载入结算的一次性信号。
  ///
  /// 由切片而不是 runner 持有：组合根要等的是「切片已经有可用的设置快照」这个
  /// 切片事实，不是某个 runner 实现的内部进度。runner 换实现不该动到等待方。
  final Completer<GeneralSettings> _initialLoadCompleter =
      Completer<GeneralSettings>();

  late GeneralSettingsSliceEffectRunner _effectRunner;

  /// 已提交的切片状态：这是唯一 owner，[state] 只是它的广播通道。
  ///
  /// 命令入口在同一个同步栈里既要归约又要排干队列（persist-first 的串行语义），
  /// 中间态不该被广播；`build()` 里的自启动 load 也不能同步写 state。因此归约结果
  /// 先落在这里，广播排到 microtask。
  late GeneralSettingsSliceState _working;

  bool _loaded;
  bool _closed = false;
  bool _loadRequested = false;
  bool _drainingCommands = false;
  bool _publishScheduled = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

  @override
  GeneralSettingsSliceState build() {
    // 工厂由组合根一次性覆盖，容器存活期内不再变化。
    _effectRunner = ref.watch(generalSettingsSliceEffectRunnerFactoryProvider)(
      this,
    );
    _working = GeneralSettingsSliceState(
      settings: GeneralSettings(
        appLanguage: ref.watch(settingsFallbackLanguageProvider),
      ),
    );
    ref.onDispose(_handleDispose);
    // 切片自启动：显示语言这条链在等 [initialLoad]，没人再去外面 kick 一次。
    load();
    return _working;
  }

  @override
  GeneralSettingsSliceState get state => _working;

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

  void dispatch(GeneralSettingsSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchCount += 1;
    final before = _working;
    final transition = generalSettingsSliceReduce(before, intent);

    if (transition.state != before) {
      _working = transition.state;
      _publishCount += 1;
      _schedulePublish();
    } else if (_isStaleResult(before, intent)) {
      _staleResultCount += 1;
    }

    for (final effect in transition.effects) {
      _effectCount += 1;
      _effectRunner.run(effect);
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

  void persisted(OperationId operationId, GeneralSettings settings) {
    final accepted = _working.pendingOperationId == operationId;
    dispatch(GeneralSettingsPersisted(operationId, settings));
    if (accepted) {
      _drainCommands();
    }
  }

  void persistFailed(OperationId operationId, SettingsPersistFailureKind kind) {
    final accepted = _working.pendingOperationId == operationId;
    dispatch(GeneralSettingsPersistFailed(operationId, kind));
    if (accepted) {
      _drainCommands();
    }
  }

  void acknowledgeFailure() {
    dispatch(const GeneralSettingsFailureAcknowledged());
  }

  /// 以当前快照结算 [initialLoad]；重复调用无效果。
  void _settleInitialLoad() {
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete(_working.settings);
    }
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
        _working.pendingOperationId != null) {
      return;
    }
    _drainingCommands = true;
    try {
      while (_commandQueue.isNotEmpty && _working.pendingOperationId == null) {
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

  void _handleDispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _commandQueue.clear();
    _settleInitialLoad();
  }

  /// 把已提交状态广播给 Riverpod，同一 microtask 内的多次提交合并成一次。
  void _schedulePublish() {
    if (_publishScheduled || _closed) {
      return;
    }
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      if (_closed) {
        return;
      }
      state = _working;
    });
  }
}
