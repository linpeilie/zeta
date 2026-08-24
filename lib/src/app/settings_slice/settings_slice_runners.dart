import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/appearance_font_option.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

final _log = zetaLoggerFor('zeta.settings.slice_runner');

/// appearance 切片的 effect runner 适配器（app 组合层）。
///
/// 行为保持 Phase 3 前的 appearance 设置语义：
/// - 载入后做存储字体的目录校验（不可解析回落默认并尽力回写；目录暂不可用
///   时保留用户设置）；
/// - 字体解析的 kind 规则：界面槽位拒绝 bundled、代码槽位拒绝 systemDefault、
///   代码字体必须等宽；
/// - persist 失败只记日志并回执 `persistFailed`（语义 A：内存值不回滚）。
final class AppearanceSettingsSliceRunnerAdapter
    implements AppearanceSettingsSliceEffectRunner {
  AppearanceSettingsSliceRunnerAdapter({
    required this._store,
    required this._fontCatalog,
    required this._sliceStore,
  });

  final AppearanceSettingsStore _store;
  final SystemFontCatalogService _fontCatalog;
  final AppearanceSettingsSliceStore _sliceStore;
  Future<void> _initialLoad = Future<void>.value();
  Future<void> _writeQueue = Future<void>.value();
  bool _loadStarted = false;

  @override
  void run(AppearanceSettingsSliceEffect effect) {
    switch (effect) {
      case AppearanceSettingsLoadEffect():
        if (!_loadStarted) {
          _loadStarted = true;
          _initialLoad = _load();
        }
      case AppearanceSettingsPersistEffect():
        _enqueueWrite(() async {
          await _initialLoad;
          await _persist(effect);
        });
      case AppearanceFontChoiceResolveEffect():
        unawaited(_initialLoad.then((_) => _resolve(effect)));
      case AppearanceFontCatalogLoadEffect():
        unawaited(_loadCatalog(effect));
    }
  }

  /// 字体目录投影：界面槽位「跟随默认」在前、代码槽位 bundled 在前，
  /// 其余按系统目录——与现有 controller 的选项构造一致。
  /// 失败以空列表回执（弹层显示为空而非报错）。
  Future<void> _loadCatalog(AppearanceFontCatalogLoadEffect effect) async {
    try {
      final families = effect.forCodeFont
          ? await _fontCatalog.codeFontFamilies()
          : await _fontCatalog.uiFontFamilies();
      _sliceStore.fontCatalogLoaded(
        forCodeFont: effect.forCodeFont,
        options: <AppearanceFontOption>[
          if (effect.forCodeFont)
            const AppearanceFontOption.bundledJetBrainsMono()
          else
            const AppearanceFontOption.systemDefault(),
          ...families.map(AppearanceFontOption.system),
        ],
        displayNames: <String, String>{
          for (final family in families)
            family.familyName.toLowerCase(): family.displayName,
        },
      );
    } catch (error, stackTrace) {
      _log.w(
        'Could not load system font catalog via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _sliceStore.fontCatalogLoaded(
        forCodeFont: effect.forCodeFont,
        options: const <AppearanceFontOption>[],
        displayNames: const <String, String>{},
      );
    }
  }

  Future<void> _load() async {
    try {
      final stored = await _store.load();
      final normalized = await _normalizeSettings(stored);
      _sliceStore.loaded(appearanceSliceFromSettings(normalized));
    } catch (error, stackTrace) {
      // 载入异常按现状回落默认值，不阻断启动。
      _log.w(
        'Could not load appearance settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _sliceStore.loaded(const AppearanceSettingsSlice());
    }
  }

  Future<void> _persist(AppearanceSettingsPersistEffect effect) async {
    final merged = _overlayAppearanceChanges(
      base: effect.previousValue,
      desired: effect.value,
      current: _sliceStore.state.value,
    );
    if (merged != _sliceStore.state.value) {
      // load 可能在乐观 intent 后回流；先把用户改动叠加回已加载快照，
      // 再持久化，避免迟到 load 覆盖内存与磁盘。
      _sliceStore.loaded(merged);
    }
    try {
      await _store.save(appearanceSettingsFromSlice(merged));
      _sliceStore.persisted(effect.operationId);
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist appearance settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _sliceStore.persistFailed(effect.operationId);
    }
  }

  void _enqueueWrite(Future<void> Function() action) {
    _writeQueue = _writeQueue.catchError((Object _) {}).then((_) => action());
  }

  Future<void> _resolve(AppearanceFontChoiceResolveEffect effect) async {
    final choice = effect.choice;
    switch (choice.kind) {
      case AppearanceFontChoiceKind.systemDefault:
        if (effect.forCodeFont) {
          _sliceStore.fontChoiceRejected(effect.operationId);
        } else {
          _sliceStore.fontChoiceResolved(
            effect.operationId,
            forCodeFont: false,
            resolved: choice,
          );
        }
      case AppearanceFontChoiceKind.bundledJetBrainsMono:
        if (effect.forCodeFont) {
          _sliceStore.fontChoiceResolved(
            effect.operationId,
            forCodeFont: true,
            resolved: choice,
          );
        } else {
          _sliceStore.fontChoiceRejected(effect.operationId);
        }
      case AppearanceFontChoiceKind.system:
        final resolved = await _tryResolveSystemChoice(
          choice,
          requireMonospace: effect.forCodeFont,
        );
        if (resolved == null) {
          _sliceStore.fontChoiceRejected(effect.operationId);
          return;
        }
        _sliceStore.fontChoiceResolved(
          effect.operationId,
          forCodeFont: effect.forCodeFont,
          resolved: resolved,
        );
    }
  }

  Future<AppearanceSettings> _normalizeSettings(
    AppearanceSettings value,
  ) async {
    var normalized = value;

    final uiChoice = normalized.uiFontChoice;
    if (uiChoice.isSystemFont) {
      final resolved = await _resolveStoredSystemChoice(uiChoice);
      if (resolved == null) {
        normalized = normalized.copyWith(
          uiFontChoice: const AppearanceFontChoice.systemDefault(),
        );
      } else if (resolved != uiChoice) {
        normalized = normalized.copyWith(uiFontChoice: resolved);
      }
    }

    final codeChoice = normalized.codeFontChoice;
    if (codeChoice.isSystemFont) {
      final resolved = await _resolveStoredSystemChoice(
        codeChoice,
        requireMonospace: true,
      );
      if (resolved == null) {
        normalized = normalized.copyWith(
          codeFontChoice: const AppearanceFontChoice.bundledJetBrainsMono(),
        );
      } else if (resolved != codeChoice) {
        normalized = normalized.copyWith(codeFontChoice: resolved);
      }
    }

    if (normalized != value) {
      try {
        await _store.save(normalized);
      } catch (error, stackTrace) {
        _log.w(
          'Could not persist normalized appearance settings via slice',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return normalized;
  }

  Future<AppearanceFontChoice?> _tryResolveSystemChoice(
    AppearanceFontChoice choice, {
    required bool requireMonospace,
  }) async {
    try {
      return await _resolveSystemChoice(
        choice,
        requireMonospace: requireMonospace,
      );
    } catch (error, stackTrace) {
      _log.w(
        'Could not query system font: ${choice.fontFamily}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<AppearanceFontChoice?> _resolveStoredSystemChoice(
    AppearanceFontChoice choice, {
    bool requireMonospace = false,
  }) async {
    try {
      return await _resolveSystemChoice(
        choice,
        requireMonospace: requireMonospace,
      );
    } catch (error, stackTrace) {
      // 原生目录暂时不可用时保留用户设置，避免一次通道故障清空偏好。
      _log.w(
        'Could not normalize stored system font: ${choice.fontFamily}',
        error: error,
        stackTrace: stackTrace,
      );
      return choice;
    }
  }

  Future<AppearanceFontChoice?> _resolveSystemChoice(
    AppearanceFontChoice choice, {
    required bool requireMonospace,
  }) async {
    final family = await _fontCatalog.resolveFontFamily(choice.fontFamily!);
    if (family == null || (requireMonospace && !family.isMonospace)) {
      _log.w('Could not resolve system font: ${choice.fontFamily}');
      return null;
    }
    return AppearanceFontChoice.system(family.familyName);
  }
}

AppearanceSettingsSlice _overlayAppearanceChanges({
  required AppearanceSettingsSlice base,
  required AppearanceSettingsSlice desired,
  required AppearanceSettingsSlice current,
}) {
  return current.copyWith(
    themeMode: desired.themeMode != base.themeMode ? desired.themeMode : null,
    uiFontChoice: desired.uiFontChoice != base.uiFontChoice
        ? desired.uiFontChoice
        : null,
    codeFontChoice: desired.codeFontChoice != base.codeFontChoice
        ? desired.codeFontChoice
        : null,
    uiFontSize: desired.uiFontSize != base.uiFontSize
        ? desired.uiFontSize
        : null,
    codeFontSize: desired.codeFontSize != base.codeFontSize
        ? desired.codeFontSize
        : null,
  );
}

/// general 切片的 effect runner 适配器（app 组合层）。
///
/// persist 以单写者串行执行：落盘顺序与提交顺序一致，失败不阻断
/// 后续命令。
final class GeneralSettingsSliceRunnerAdapter
    implements GeneralSettingsSliceEffectRunner {
  GeneralSettingsSliceRunnerAdapter({
    required this._store,
    required this._sliceStore,
  });

  final GeneralSettingsStore _store;
  final GeneralSettingsSliceStore _sliceStore;

  Future<void> _queue = Future<void>.value();
  Future<void> _initialLoad = Future<void>.value();
  final Completer<GeneralSettings> _loadCompleter =
      Completer<GeneralSettings>();
  bool _loadStarted = false;
  bool _initialLoadSettled = false;

  /// 首次加载完成后的快照；组合根据此决定何时安装依赖 Locale 的运行时。
  Future<GeneralSettings> get loadResult => _loadCompleter.future;

  @override
  void run(GeneralSettingsSliceEffect effect) {
    switch (effect) {
      case GeneralSettingsLoadEffect():
        if (!_loadStarted) {
          _loadStarted = true;
          _initialLoad = _load();
        }
      case GeneralSettingsPersistEffect():
        if (_initialLoadSettled) {
          _enqueue(() => _persist(effect));
        } else {
          _enqueue(() async {
            await _initialLoad;
            await _persist(effect);
          });
        }
    }
  }

  Future<void> _load() async {
    try {
      final settings = await _store.load();
      // 标记必须先于 loaded 回流：store 会在回流栈内同步排出首条命令。
      // 此时数据快照已经拿到，persist 可直接进入串行写队列，无需再多等
      // 一个已完成 Future 的异步轮次。
      _initialLoadSettled = true;
      _sliceStore.loaded(settings);
      _loadCompleter.complete(settings);
    } catch (error, stackTrace) {
      _log.w(
        'Could not load general settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _initialLoadSettled = true;
      _sliceStore.loadFailed();
      _loadCompleter.complete(_sliceStore.state.settings);
    }
  }

  Future<void> _persist(GeneralSettingsPersistEffect effect) async {
    try {
      await _store.save(effect.value);
      _sliceStore.persisted(effect.operationId, effect.value);
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist general settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _sliceStore.persistFailed(
        effect.operationId,
        SettingsPersistFailureKind.persistence,
      );
    }
  }

  void _enqueue(Future<void> Function() action) {
    _queue = _queue.catchError((Object _) {}).then((_) => action());
  }
}
