import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_reducer.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// 执行 appearance 切片副作用的端口。
///
/// 实现住在组合层（持有 `AppearanceSettingsStore`、`SystemFontCatalogService`
/// 并做 `ThemeMode` 映射）；切片只描述要做什么，不知道怎么做。
abstract interface class AppearanceSettingsSliceEffectRunner {
  /// 执行一个副作用。
  ///
  /// 异步结果必须以 result intent 回流（`fontChoiceResolved` /
  /// `fontChoiceRejected` / `persisted` / `persistFailed`）。
  void run(AppearanceSettingsSliceEffect effect);
}

/// 切片诊断计数，用于回归测试与发布频率断言。
@immutable
final class AppearanceSettingsSliceDiagnostics {
  const AppearanceSettingsSliceDiagnostics({
    required this.dispatchCount,
    required this.publishCount,
    required this.effectCount,
    required this.staleResultCount,
  });

  /// 收到的 intent 数量。
  final int dispatchCount;

  /// 实际对外发布的状态变化次数（状态未变不发布）。
  final int publishCount;

  /// 交给 runner 的副作用数量。
  final int effectCount;

  /// 因在途身份对不上而被丢弃的迟到结果数量。
  final int staleResultCount;
}

/// 外观偏好切片的薄 store。
///
/// 职责与 conversation 切片的 store 相同：铸造 [OperationId]、调 reducer、
/// 状态变化才发布、effect 交给 runner、关闭后拒绝写入。它**不拥有**任何
/// 持久化事实——文件读写全部经 effect 由组合层执行。
final class AppearanceSettingsSliceStore {
  AppearanceSettingsSliceStore({
    required AppearanceSettingsSliceState initialState,
    required this.effectRunner,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final AppearanceSettingsSliceEffectRunner effectRunner;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};

  /// 监听器列表。
  ///
  /// 刻意**不用 `ChangeNotifier`**：application 层禁止 import Flutter
  /// （§12.5）。语义与 `ChangeNotifier` 对齐——通知期间允许增删监听，
  /// 遍历前先复制快照。
  final List<void Function()> _listeners = <void Function()>[];

  AppearanceSettingsSliceState _state;
  bool _closed = false;
  bool _loadRequested = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

  /// 当前切片状态。
  AppearanceSettingsSliceState get state => _state;

  /// store 是否已关闭。
  bool get isClosed => _closed;

  AppearanceSettingsSliceDiagnostics get diagnostics =>
      AppearanceSettingsSliceDiagnostics(
        dispatchCount: _dispatchCount,
        publishCount: _publishCount,
        effectCount: _effectCount,
        staleResultCount: _staleResultCount,
      );

  /// 订阅状态变化；返回取消订阅的回调。
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// 关闭 store：拒绝后续写入并摘掉全部监听（不释放任何 data store——
  /// 它们的生命周期归组合层）。
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _listeners.clear();
  }

  /// 分发意图。状态未变不发布；迟到结果按 stale 计数。
  void dispatch(AppearanceSettingsSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchCount += 1;
    final before = _state;
    final transition = appearanceSettingsSliceReduce(before, intent);

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
  // 命令入口：铸造身份 → dispatch
  // -------------------------------------------------------------------------

  /// 载入持久化偏好。重复调用不重复发起（对齐现有 controller 的
  /// `_loadFuture` 记忆化）。
  void load() {
    if (_loadRequested) {
      return;
    }
    _loadRequested = true;
    dispatch(const AppearanceSettingsLoadRequested());
  }

  OperationId selectThemeMode(ZetaThemeModePreference mode) {
    final id = _nextOperationId(SettingsOperationScopes.appearancePersist);
    dispatch(AppearanceThemeModeSelected(id, mode));
    return id;
  }

  OperationId adjustUiFontSize(double value) {
    final id = _nextOperationId(SettingsOperationScopes.appearancePersist);
    dispatch(AppearanceUiFontSizeAdjusted(id, value));
    return id;
  }

  OperationId adjustCodeFontSize(double value) {
    final id = _nextOperationId(SettingsOperationScopes.appearancePersist);
    dispatch(AppearanceCodeFontSizeAdjusted(id, value));
    return id;
  }

  OperationId selectUiFontChoice(AppearanceFontChoice choice) {
    final id = _nextOperationId(SettingsOperationScopes.appearanceFontChoice);
    dispatch(AppearanceUiFontChoiceSelected(id, choice));
    return id;
  }

  OperationId selectCodeFontChoice(AppearanceFontChoice choice) {
    final id = _nextOperationId(SettingsOperationScopes.appearanceFontChoice);
    dispatch(AppearanceCodeFontChoiceSelected(id, choice));
    return id;
  }

  // -------------------------------------------------------------------------
  // 结果入口：effect runner / ingress 回流
  // -------------------------------------------------------------------------

  void loaded(AppearanceSettingsSlice value) {
    dispatch(AppearanceSettingsLoaded(value));
  }

  void fontChoiceResolved(
    OperationId operationId, {
    required bool forCodeFont,
    required AppearanceFontChoice resolved,
  }) {
    dispatch(
      AppearanceFontChoiceResolved(
        operationId: operationId,
        forCodeFont: forCodeFont,
        resolved: resolved,
      ),
    );
  }

  void fontChoiceRejected(OperationId operationId) {
    dispatch(AppearanceFontChoiceRejected(operationId));
  }

  void persisted(OperationId operationId) {
    dispatch(AppearanceSettingsPersisted(operationId));
  }

  void persistFailed(OperationId operationId) {
    dispatch(AppearanceSettingsPersistFailed(operationId));
  }

  OperationId _nextOperationId(String scope) {
    final generator = _generators.putIfAbsent(
      scope,
      () => _generatorFactory(scope),
    );
    return generator.next();
  }

  /// 字体解析结果对不上两个槽位任一在途身份 → 迟到。
  bool _isStaleResult(
    AppearanceSettingsSliceState before,
    AppearanceSettingsSliceIntent intent,
  ) {
    return switch (intent) {
      AppearanceFontChoiceResolved() =>
        intent.operationId != before.pendingUiFontChoiceOperationId &&
            intent.operationId != before.pendingCodeFontChoiceOperationId,
      AppearanceFontChoiceRejected() =>
        intent.operationId != before.pendingUiFontChoiceOperationId &&
            intent.operationId != before.pendingCodeFontChoiceOperationId,
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
