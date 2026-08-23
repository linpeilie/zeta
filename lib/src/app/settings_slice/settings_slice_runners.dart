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

final _log = zetaLoggerFor('zeta.settings.slice_runner');

/// appearance 切片的 effect runner 适配器（app 组合层）。
///
/// 行为逐条对齐现有 `AppearanceSettingsController`：
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

  @override
  void run(AppearanceSettingsSliceEffect effect) {
    switch (effect) {
      case AppearanceSettingsLoadEffect():
        unawaited(_load());
      case AppearanceSettingsPersistEffect():
        unawaited(_persist(effect));
      case AppearanceFontChoiceResolveEffect():
        unawaited(_resolve(effect));
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
    try {
      await _store.save(appearanceSettingsFromSlice(effect.value));
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

/// general 切片的 effect runner 适配器（app 组合层）。
///
/// persist 以单写者串行执行，等价现有 `GeneralSettingsController._enqueue`
/// 队列：落盘顺序与提交顺序一致，失败不阻断后续命令。
final class GeneralSettingsSliceRunnerAdapter
    implements GeneralSettingsSliceEffectRunner {
  GeneralSettingsSliceRunnerAdapter({
    required this._store,
    required this._sliceStore,
  });

  final GeneralSettingsStore _store;
  final GeneralSettingsSliceStore _sliceStore;

  Future<void> _queue = Future<void>.value();
  bool _loaded = false;

  @override
  void run(GeneralSettingsSliceEffect effect) {
    switch (effect) {
      case GeneralSettingsLoadEffect():
        unawaited(_load());
      case GeneralSettingsPersistEffect():
        _enqueue(() => _persist(effect));
    }
  }

  Future<void> _load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      _sliceStore.loaded(await _store.load());
    } catch (error, stackTrace) {
      _log.w(
        'Could not load general settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
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
