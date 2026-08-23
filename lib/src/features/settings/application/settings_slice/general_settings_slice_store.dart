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
/// 以单写者串行执行（等价现有 controller 的 `_enqueue` 队列）。
abstract interface class GeneralSettingsSliceEffectRunner {
  void run(GeneralSettingsSliceEffect effect);
}

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
    required this.effectRunner,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final GeneralSettingsSliceEffectRunner effectRunner;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};

  /// 监听器列表（同 appearance store：不用 `ChangeNotifier`，§12.5）。
  final List<void Function()> _listeners = <void Function()>[];

  GeneralSettingsSliceState _state;
  bool _closed = false;
  bool _loadRequested = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

  GeneralSettingsSliceState get state => _state;

  bool get isClosed => _closed;

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
    _listeners.clear();
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

  /// 载入持久化设置；重复调用不重复发起（对齐现有 controller 的幂等 load）。
  void load() {
    if (_loadRequested) {
      return;
    }
    _loadRequested = true;
    dispatch(const GeneralSettingsLoadRequested());
  }

  OperationId setMessageSendShortcut(MessageSendShortcut shortcut) {
    final id = _nextOperationId();
    dispatch(MessageSendShortcutSelected(id, shortcut));
    return id;
  }

  OperationId setAppLanguage(AppLanguage language) {
    final id = _nextOperationId();
    dispatch(AppLanguageSelected(id, language));
    return id;
  }

  OperationId setNotificationsEnabled(bool enabled) {
    final id = _nextOperationId();
    dispatch(NotificationsEnabledToggled(id, enabled));
    return id;
  }

  OperationId setTurnTerminalNotificationsEnabled(bool enabled) {
    final id = _nextOperationId();
    dispatch(TurnTerminalNotificationsToggled(id, enabled));
    return id;
  }

  OperationId setActionRequiredNotificationsEnabled(bool enabled) {
    final id = _nextOperationId();
    dispatch(ActionRequiredNotificationsToggled(id, enabled));
    return id;
  }

  // -------------------------------------------------------------------------
  // 结果入口：effect runner 回流
  // -------------------------------------------------------------------------

  void persisted(OperationId operationId, GeneralSettings settings) {
    dispatch(GeneralSettingsPersisted(operationId, settings));
  }

  void persistFailed(OperationId operationId, SettingsPersistFailureKind kind) {
    dispatch(GeneralSettingsPersistFailed(operationId, kind));
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
